# Architecture Spec — tensor-mac

A parameterized INT8 systolic-array tensor MAC accelerator. This is the one-page design an
interviewer can walk through cold in ~2 minutes.

---

## 1. The operation

     Operation : C = A x B
     Sizes     : A is M x K, B is K x N, C is M x N
     One pass  : an NxN array produces one NxN tile of C
     Feeds     : N rows of A (each K deep) x N columns of B (each K deep)
     Cost/box  : K multiply-accumulates, summed in one accumulator
     Big matrices : Computed one NxN tile at a time (the "waffle iron in batches")
     Mapping   : A = activations (streamed in); B = weights (loaded once, pinned in the PEs)

## 2. Number formats

     Inputs are signed INT8 with range of -2^(w-1):2^(w-1) - 1, for signed w bit number
     Worst case of product is -128x-128 = 16384 which needs 16 bits of storage for multiplication
     then we have K-depth on each so the width required is ACC_W = 16 + [log(base 2)k].
     So now we have designed it robust enough to handle even the worst case and not fail.

## 3. Dataflow

     Pick        : Weight-stationary (WS) — matches the build plan (M12 weight-load path, M14
                   load→stream→drain) and the TPU-style accelerator this project emulates.
     Reason      : each PE holds one weight, loaded once and reused across the whole activation
                   stream, amortizing weight fetches — the dominant cost for batched inference.
     Mechanics   : weights pinned per PE; activations flow left→right; partial sums flow
                   top→bottom, accumulating as they descend; results drain out the bottom edge.
     Vs. OS      : output-stationary instead pins the wide (~24-bit) accumulator so only 8-bit
                   operands move, and each PE owns one C[i][j] (= one M11 MAC); OS wins for
                   one-off tiles with no weight reuse. WS accepts moving the wide partial sums
                   because weight reuse dominates the energy budget when the same weights serve a
                   large batch — which is the workload a tensor accelerator is built for.

## 4. Array geometry

     Geometry: N×N grid of identical PEs, PE(i,j) owns tile element C[i][j]; N² MACs, up to N² MACs/cycle.
     Parameters (knobs): N, DW, K.
     Derived (locked): ACC_W = 2·DW + ⌈log₂K⌉ — a localparam, not a parameter: if set
                       independently it could be too small, and the accumulator would silently
                       overflow on the worst-case input (no error, no warning, just a wrong matmul).

## 5. Top-level interfaces

Three ready/valid streams — weight-load in, activation in, result out — plus clock and reset.
A "column" is N elements (one per array row/column), transferred in a single cycle.

| Port          | Dir | Width      | Role |
|---------------|-----|------------|------|
| `clk_i`       | in  | 1          | clock |
| `rst_i`       | in  | 1          | synchronous, active-high reset |
| `w_data_i`    | in  | `N*DW`     | weight-load data: one column of N INT8 weights per cycle |
| `w_valid_i`   | in  | 1          | sender asserts when a weight column is on the bus |
| `w_ready_o`   | out | 1          | accelerator asserts when it can accept a weight column |
| `a_data_i`    | in  | `N*DW`     | activation data: one column of N INT8 activations per cycle |
| `in_valid_i`  | in  | 1          | sender asserts when an activation column is valid |
| `in_ready_o`  | out | 1          | accelerator asserts when it can accept activations |
| `c_data_o`    | out | `N*ACC_W`  | result data: one column of N ACC_W-bit results per cycle |
| `out_valid_o` | out | 1          | accelerator asserts when a result column is ready |
| `out_ready_i` | in  | 1          | receiver asserts when it can accept a result column |

Widths: operands are DW=8 bits, so a column is `N*DW`. Results are the wide accumulator, so the
result bus is `N*ACC_W` (≈ N*24) — the output stream is the widest port on the block.
Transfer on any stream fires only when its `valid` and `ready` are both high on a clock edge.

## 6. Block diagram

```
                    ┌────────────────┐
   weights ────────►│ WEIGHT  LOADER │──┐   route weight columns into the array
  (w_* stream)      └────────────────┘  │
                                        ▼
 activations   ┌──────────────┐   ┌──────────────────┐
 (a_/in_*) ───►│ ACTIVATION   │──►│    N×N PE ARRAY  │   weight-stationary MACs:
               │ FEEDER (skew)│   │  (weights pinned)│   activations cross →,
               └──────────────┘   └──────────────────┘   partial sums fall ▼ and accumulate
                                        │  partial sums drain
                                        ▼
                              ┌────────────────────┐
                              │  RESULT  COLLECTOR │────► results (c_/out_* stream)
                              │   (deskew / drain) │
                              └────────────────────┘

        ┌────────────────┐
        │  CONTROL  FSM  │   load-weights → stream → drain;
        └────────────────┘   drives the global enable + all ready/valid handshakes
```

- **Weight loader** — accepts the `w_*` stream, routes weight columns into the PE array to be pinned.
- **Activation feeder** — accepts the `a_*`/`in_*` stream and skews it so the diagonal wavefront aligns.
- **N×N PE array** — the compute core: weight-stationary MACs; activations cross, partial sums descend and accumulate.
- **Result collector** — deskews and drains the partial sums off the bottom, emits the `c_*`/`out_*` stream.
- **Control FSM** — sequences load → stream → drain, generates the global enable and the stream handshakes.

