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

     Inputs are signed DW-bit, range -2^(DW-1) : 2^(DW-1) - 1.
     Worst case product is (-2^(DW-1)) x (-2^(DW-1)) = 2^(2·DW-2) — both operands at their most
     negative. That is the largest magnitude a signed multiply can produce, and it needs 2·DW
     bits, because one bit of each operand is spent on sign.
     Accumulating K of them, the running total is bounded by

         |acc| <= K · 2^(2·DW-2)

     and a signed register of width W holds up to 2^(W-1), so it is enough that

         2^(ACC_W-1) >= K · 2^(2·DW-2)   =>   ACC_W >= 2·DW + log2(K)

     giving the locked width  ACC_W = 2·DW + ⌈log₂K⌉.
     At DW=8, K=8: the worst product is 16384, the worst sum is 8 × 16384 = 131072, and
     ACC_W = 16 + 3 = 19 bits (signed range -262144 : 262143). It fits, with margin.
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
     Only 8-bit numbers ever move between PEs. The ACC_W-bit accumulator (19 bits at DW=8,
     K=8) stays inside its own cell.
     Vs. WS      : weight-stationary instead pins one element of B per PE, loaded once and
                   reused across the whole activation stream, with partial sums flowing down and
                   accumulating as they descend. WS wins when the same weights serve a large
                   batch, because it stops re-fetching B from memory and memory fetches cost far
                   more energy than a neighbour hop. The price is that the thing in motion is the
                   wide (ACC_W-bit) partial sum instead of an 8-bit operand, plus a separate
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
so the result bus is `N*ACC_W` (N*19 at DW=8, K=8) — the output stream is the widest port on
the block, and it grows with K while the operand buses do not.
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

## 8. Control FSM (M14)

The array free-runs in lockstep on a global enable — there is no ready/valid *inside* it,
because the skew makes every operand's arrival time known at design time. The controller's job
is to sequence one tile through its phases and hold the enable for exactly the right span; the
handshakes it drives live only at the edge, where the outside world's timing is still unknown.

### 8.1 Interface

| Port        | Dir | Width | Role |
|-------------|-----|-------|------|
| `clk_i`     | in  | 1     | clock |
| `rst_i`     | in  | 1     | synchronous, active-high reset |
| `start_i`   | in  | 1     | pulse: begin one NxN tile |
| `clear_o`   | out | 1     | zero the PE accumulators before a fresh tile (drives `clear_i` on the PE) |
| `en_o`      | out | 1     | global PE enable — the array's lockstep clock-gate |
| `feed_en_o` | out | 1     | feeders may source operands this cycle (high in FEED, low in DRAIN) |
| `done_o`    | out | 1     | tile complete, C is settled and readable |

### 8.2 State diagram

```
        start_i                cnt = N+K-1            cnt = 2(N-1)+K
  IDLE ─────────► FEED ──────────────────► DRAIN ──────────────────► DONE
   ▲   (clear)   en=1                       en=1                      en=0
   │             feed_en=1                  feed_en=0                 done=1
   │                                                                   │
   └───────────────────────────────────────────────────────────────┘
                         (consumer takes result / next start)
```

### 8.3 Cycle contract

`cnt` counts cycles since leaving IDLE; the first FEED cycle is `cnt = 0`.

     Fill/wavefront : PE(i,j) begins accumulating at cnt = i+j (when its skewed operands arrive)
                      and needs K accumulate edges, finishing after cnt = i+j+K.
     Last operand   : row N-1 starts feeding at cnt = N-1 and pushes K values on consecutive
                      cycles, so the last real operand enters at
                          (N-1) + (K-1) = N + K - 2.
     Last accumulate: the corner PE(N-1,N-1) commits its K-th MAC on the edge entering
                          cnt = 2(N-1) + K,
                      i.e. its last accumulate cycle is cnt = 2(N-1)+K - 1.
     Done           : the corner result is settled at cnt = 2(N-1)+K — the exact cycle M13's
                      test sampled at (LATENCY = 2(N-1)+K).

Phase boundaries that follow:

| Phase | cnt range              | `en_o` | `feed_en_o` | `done_o` |
|-------|------------------------|--------|-------------|----------|
| FEED  | `0 … N+K-2`            | 1      | 1           | 0        |
| DRAIN | `N+K-1 … 2(N-1)+K - 1` | 1      | 0           | 0        |
| DONE  | `2(N-1)+K`             | 0      | 0           | 1        |

DRAIN is exactly `N-1` cycles — the time for the last operand to travel from the edge to the
far corner: `(2(N-1)+K - 1) - (N+K-1) + 1 = N-1`. A clean consistency check.

Worked timeline, N=2, K=2 (so N+K-2 = 2, 2(N-1)+K = 4):

| cnt | phase | `en_o` | `feed_en_o` | `done_o` | note |
|-----|-------|--------|-------------|----------|------|
| 0   | FEED  | 1 | 1 | 0 | A[0][0], B[0][0] enter; PE(0,0) starts |
| 1   | FEED  | 1 | 1 | 0 | A[0][1], A[1][0], … enter |
| 2   | FEED  | 1 | 1 | 0 | last operands A[1][1], B[1][1] enter |
| 3   | DRAIN | 1 | 0 | 0 | feeders idle; corner PE finishing |
| 4   | DONE  | 0 | 0 | 1 | C settled, readable |

`cnt` width: `$clog2(2(N-1)+K + 1)` — enough to hold the max count `2(N-1)+K`.

### 8.4 Open design point — clear timing

`clear_o` must zero the accumulators before the first accumulate, but M12's PE gives `clear_i`
priority over accumulate (a `clear & en` cycle writes 0, not the product). So asserting `clear_o`
*during* `cnt = 0` would discard PE(0,0)'s first product. The controller must therefore clear on
a cycle before any real accumulate — e.g. held in IDLE, or one dedicated cycle on the
IDLE→FEED transition. Settled in RTL against M12's clear-vs-accumulate priority.
