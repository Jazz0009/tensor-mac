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
     Mapping   : PE(i,j) owns one output element C[i][j] and keeps its running total for the
                 whole tile. Both operands move: a row of A crosses west->east, a column of B
                 falls north->south, and they meet at the PE that needs them.

## 2. Number formats

     Inputs are signed INT8 with range of -2^(w-1):2^(w-1) - 1, for signed w bit number
     Worst case of product is -128x-128 = 16384 which needs 16 bits of storage for multiplication
     then we have K-depth on each so the width required is ACC_W = 16 + [log(base 2)k].
     So now we have designed it robust enough to handle even the worst case and not fail.

## 3. Dataflow

     Pick        : Output-stationary (OS) — each PE owns one C[i][j] and accumulates it in
                   place over all K steps. The running total never moves; both operands do.
     Reason      : the accumulator that stays put is exactly the M11 `mac.sv` I already built,
                   linted and verified (17 checks, signed corners, clear-while-enabled). The
                   array becomes a grid of a block I have already proven, so M13 is wiring and
                   timing rather than new arithmetic. The PE stays small: a MAC plus two
                   pass-through registers, no weight-load path and no wide partial sums in
                   flight.
     Mechanics   : operands enter at two edges and ripple neighbour-to-neighbour, one hop per
                   cycle. A crosses left->right, B falls top->bottom. PE(i,j) sees A[i][k] and
                   B[k][j] on the same cycle and does acc <= acc + A[i][k]*B[k][j]. After K
                   steps every PE holds its finished C[i][j], and the tile is drained out.
     Only 8-bit numbers ever move between PEs. The 24-bit accumulator stays inside its own cell.
     Vs. WS      : weight-stationary instead pins one element of B per PE, loaded once and
                   reused across the whole activation stream, with partial sums flowing down and
                   accumulating as they descend. WS wins when the same weights serve a large
                   batch, because it stops re-fetching B from memory and memory fetches cost far
                   more energy than a neighbour hop. The price is that the thing in motion is the
                   wide (~24-bit) partial sum instead of an 8-bit operand, plus a separate
                   weight-load phase and a PE with no long-lived accumulator (so it cannot reuse
                   `mac.sv`). I am building OS first to get a correct array on a verified cell,
                   and WS second so I can measure the trade instead of just arguing it. See §7.

## 4. Array geometry

     Geometry: N×N grid of identical PEs, PE(i,j) owns tile element C[i][j]; N² MACs, up to N² MACs/cycle.
     Parameters (knobs): N, DW, K.
     Derived (locked): ACC_W = 2·DW + ⌈log₂K⌉ — a localparam, not a parameter: if set
                       independently it could be too small, and the accumulator would silently
                       overflow on the worst-case input (no error, no warning, just a wrong matmul).
     Wire length: every inter-PE wire is one cell long and stays one cell long as N grows. The
                  cost of that is skew — PE(i,j) starts i+j cycles after PE(0,0) — so the array
                  takes a fixed fill time, then produces at full rate.

## 5. Top-level interfaces

Three ready/valid streams — two operands in, results out — plus clock and reset. A "column" is
N elements (one per array row/column), transferred in a single cycle. Both operand streams run
for the whole pass; there is no separate load phase, because nothing is pinned.

| Port          | Dir | Width      | Role |
|---------------|-----|------------|------|
| `clk_i`       | in  | 1          | clock |
| `rst_i`       | in  | 1          | synchronous, active-high reset |
| `a_data_i`    | in  | `N*DW`     | A operand: one column of N INT8 values per cycle, entering the west edge |
| `a_valid_i`   | in  | 1          | sender asserts when an A column is on the bus |
| `a_ready_o`   | out | 1          | accelerator asserts when it can accept an A column |
| `b_data_i`    | in  | `N*DW`     | B operand: one row of N INT8 values per cycle, entering the north edge |
| `b_valid_i`   | in  | 1          | sender asserts when a B row is on the bus |
| `b_ready_o`   | out | 1          | accelerator asserts when it can accept a B row |
| `c_data_o`    | out | `N*ACC_W`  | result data: one column of N ACC_W-bit results per cycle during drain |
| `out_valid_o` | out | 1          | accelerator asserts when a result column is ready |
| `out_ready_i` | in  | 1          | receiver asserts when it can accept a result column |

Widths: operands are DW=8 bits, so an operand bus is `N*DW`. Results are the wide accumulator,
so the result bus is `N*ACC_W` (≈ N*24) — the output stream is the widest port on the block.
Transfer on any stream fires only when its `valid` and `ready` are both high on a clock edge.

Naming note: two symmetric input streams means the house `in_valid_i`/`in_ready_o` pair would be
ambiguous, so the operand streams are prefixed `a_`/`b_`. The output keeps `out_valid_o`/
`out_ready_i`.

## 6. Block diagram

```
                    ┌────────────────┐
   B operand ──────►│  B FEEDER      │──┐   skews B so column j enters j cycles late
  (b_* stream)      │  (skew)        │  │
                    └────────────────┘  │
                                        ▼
 A operand     ┌──────────────┐   ┌──────────────────┐
 (a_* stream) ►│ A FEEDER     │──►│    N×N PE ARRAY  │   output-stationary MACs:
               │ (skew)       │   │ PE(i,j) owns     │   A crosses →, B falls ▼,
               └──────────────┘   │ C[i][j]          │   each PE accumulates in place
                                  └──────────────────┘
                                        │  drain after K steps
                                        ▼
                              ┌────────────────────┐
                              │  RESULT  COLLECTOR │────► results (c_/out_* stream)
                              │   (drain / deskew) │
                              └────────────────────┘

        ┌────────────────┐
        │  CONTROL  FSM  │   stream K steps → drain the tile;
        └────────────────┘   drives the global enable + all ready/valid handshakes
```

- **A feeder** — accepts the `a_*` stream and skews it so row i enters i cycles late, matching
  the diagonal wavefront.
- **B feeder** — same job on the `b_*` stream for the columns.
- **N×N PE array** — the compute core: each PE is one `mac.sv` plus two pass-through registers;
  A crosses west→east, B falls north→south, each PE accumulates its own C[i][j] in place.
- **Result collector** — drains the finished accumulators out of the array and emits the
  `c_*`/`out_*` stream.
- **Control FSM** — sequences stream → drain, generates the global enable and the stream
  handshakes.

## 7. Planned variant — weight-stationary

OS and WS are the two standard dataflows for this array, and they compute the identical C from
the identical inputs. Once the OS design is complete and measured (M16), I intend to build the
WS variant on the same top level and the same golden-model regression:

- `rtl/pe_ws.sv` — one element of B pinned in a weight register with a load path; the incoming
  partial sum from the north gets the local product added and is passed south. No long-lived
  accumulator, so it does not instantiate `mac.sv`.
- A weight-load phase in the control FSM ahead of the streaming phase.
- Results drain off the bottom edge as the partial sums finish descending, rather than being
  read out of the cells.

The point is to report both against the same benchmark — cycles per matmul, utilization, and
gate count from `yosys` — so the OS-vs-WS trade is something this repo measures rather than
something it asserts.
