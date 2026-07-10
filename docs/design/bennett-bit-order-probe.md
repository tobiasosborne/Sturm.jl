# Bennett.jl bit-order empirical probe — Sturm.jl-rnzk

Empirical follow-up to `docs/design/bennett-v2-compat-audit.md` Q1/Q2
impedance 1. That audit was read-only (no Julia executed) and explicitly
flagged the MSB/LSB bit-order question as **the single biggest M7 risk**,
to be resolved by probing, never by assumption. This document is the
probe: what was run, the raw output, and the unambiguous conclusion.

Probe script: `/tmp/claude-1000/-home-tobias-Projects-Sturm-jl/a7a3c681-9231-44e5-98bf-c7471dee7b4f/scratchpad/bennett_bitorder_probe.jl`
(scratch — not committed; reproducible from this doc). Run with:

```
julia --project=/home/tobias/Projects/Bennett.jl bennett_bitorder_probe.jl
```

## 0. Health check

```
$ julia --project=/home/tobias/Projects/Bennett.jl -e 'using Bennett; println(VERSION)'
1.12.5
```

`Bennett.jl` (`v0.5.0`, HEAD as audited) loads cleanly on the installed
Julia 1.12.5 — no precompilation failures. Two of Bennett's own small unit
test files (`test/test_increment.jl`, `test/test_bitwise.jl`, 257
exhaustive-`Int8` cases each) were run standalone as a suite sanity check
and both pass:

```
Increment: f(x::Int8) = x + Int8(3)  |  257  257  Pass  6.7s
Bitwise: h(x::Int8) = (x&0x0f)|(x>>2) |  257  257  Pass  2.3s
```

(Full ~688k-case suite was NOT run — out of scope for this probe per the
task; the audit's Q5 already recorded the pinned-validation record.)

## 1. Protocol

Bennett's `ReversibleCircuit` (`src/gates.jl`) is a permutation on
`n_wires` boolean wires, built from `NOTGate(target)`,
`CNOTGate(control,target)`, `ToffoliGate(control1,control2,target)`
(introspected via `fieldnames()`, not assumed — matches the audit's
recorded field names exactly). Two independent evidence paths were used:

1. **Source-code ground truth.** Bennett's own `simulate`/`_simulate`
   (`src/simulator.jl`) encodes the input/output packing convention
   directly:
   - input packing (`simulator.jl:186-193`):
     `bits[circuit.input_wires[offset + i]] = (v >> (i-1)) & 1 == 1`
     for `i in 1:w` — **position `i` of `input_wires` (1-based) is bit
     `(i-1)` of the Julia value**, i.e. position 1 = bit 0 = LSB.
   - output unpacking (`simulator.jl:424-429`, `_read_int`):
     `raw |= UInt64(bits[wires[start+i]]) << i` for `i in 0:width-1` —
     same convention, position 1 (`start+0`) = bit 0 = LSB.
2. **Independent hand-rolled black-box simulator**, written fresh in the
   probe script (not reusing Bennett's `simulate` internals) that applies
   `NOTGate`/`CNOTGate`/`ToffoliGate` directly to a `Vector{Bool}` state,
   used to drive single-hot-bit inputs through compiled circuits and read
   which positional wire lit up — a cross-check independent of (1).

Circuits probed, all via `reversible_compile(f, UInt8)` (note: the
`(f, (UInt8,))` tuple-literal form from the task brief does **not**
dispatch — Bennett's `reversible_compile(f, arg_types::Type{<:Tuple})`
wants either the splatted-types form `reversible_compile(f, UInt8)` or an
explicit `Tuple{UInt8}` type; this was discovered by MethodError and
corrected):

- `x -> x` (identity) — single-hot-bit input/output correspondence.
- `x -> x + 0x01` (increment) — carry-chain direction, the unambiguous
  arithmetic signature.
- `x -> x << 1` (shift) — compiles fine; shift-direction signature.
- `x -> (x, x)` (two-output tuple) — output block-packing convention.
- `x -> x + 0x03` — ancilla-cleanliness sweep.
- statically-bounded loop (`for i in 1:3; acc += x; end`) — expect empty
  `loop_check_wires`.
- data-dependent loop (countdown-with-max_loop_iterations, modeled on
  Bennett's own `test/test_s0tn_loop_overflow.jl` `countdown` pattern,
  **with `optimize=false`**) — expect non-empty `loop_check_wires` and a
  convergence-flag semantics, not a clean-ancilla semantics.

## 2. Raw results

### 2a. Identity — single-hot-bit correspondence

```
n_wires=17
input_wires  = [1, 2, 3, 4, 5, 6, 7, 8]
output_wires = [10, 11, 12, 13, 14, 15, 16, 17]
ancilla_wires = [9]
gates: NOTGate(9), CNOTGate(1,10), CNOTGate(2,11), ..., CNOTGate(8,17), NOTGate(9)
```

Driving `x=0x01` (`0b00000001`, only bit 0 set) with the candidate rule
"input_wires position `i` = bit `(i-1)`":
```
hot input position:  [1]
hot output position: [1]
```
Driving `x=0x80` (`0b10000000`, only bit 7 set):
```
hot input position:  [8]
hot output position: [8]
```
Self-consistent: position 1 tracks bit 0 through the identity gate chain
(`CNOTGate(1,10)`), position 8 tracks bit 7 (`CNOTGate(8,17)`).

### 2b. Increment (`x -> x + 0x01`) — carry-chain direction, the decisive signature

```
input_wires=[1,2,3,4,5,6,7,8]  output_wires=[34,35,36,37,38,39,40,41]
simulate(c_inc, 1) = 2      (expected 2)
simulate(c_inc, 2) = 3      (expected 3)
simulate(c_inc, 128) = 129  (expected 129)
simulate(c_inc, 255) = 0    (expected 0, 8-bit wraparound)
simulate(c_inc, 127) = 128  (expected 128)
```
Wire-level (hand-rolled simulator, position-1-based, candidate rule
`position i ↔ bit (i-1)`):
```
x=1   (0b00000001): input hot [1]    -> output hot [2]        (1+1=2=0b00000010: bit1 set, i.e. position 2)
x=2   (0b00000010): input hot [2]    -> output hot [1,2]      (2+1=3=0b00000011: bits 0,1 set, positions 1,2)
x=128 (0b10000000): input hot [8]    -> output hot [1,8]      (128+1=129=0b10000001: bits 0,7 set, positions 1,8)
```
This is the unambiguous cross-check: incrementing a value whose only set
bit is at **position 8** (0x80) produces a carry that also lights
**position 1** (the 129 = 0b10000001 result) — carries propagate from
low positions toward high positions, and position 1 is where the
"+1" LSB increment enters. **Position 1 = LSB, position 8 = MSB.**

### 2b-ii. Shift (`x -> x << 1`) — confirms direction, does compile

```
simulate(c_shl,1)=2  simulate(c_shl,2)=4  simulate(c_shl,64)=128  simulate(c_shl,128)=0
x=1 (0b00000001): input hot [1] -> output hot [2]   (1<<1=2=0b00000010, bit1=position2)
```
Shifting left moves the hot bit from position 1 to position 2 — i.e.
"left shift" (toward higher significance) moves toward **higher**
positional index. Consistent with 2a/2b: position index counts up with
bit significance (position `i` = value `2^(i-1)`), the opposite of
Sturm's convention.

### 2c. Two-output tuple (`x -> (x, x)`)

```
input_wires=[1..8]
output_wires=[58..73]  (16 wires)
output_elem_widths=[8,8]
simulate(c_dup, 0x80) = (0x80, 0x80)
simulate(c_dup, 0x01) = (0x01, 0x01)
```
`output_wires` is simply the two 8-wire blocks concatenated
(`output_wires[1:8]` = first tuple element, `output_wires[9:16]` =
second), each block internally using the *same* position-`i`-=-bit-`(i-1)`
convention as the single-output case (per `_read_int`'s `start`/`width`
walk in `simulator.jl:414-421`). No change of convention between blocks
or between input/output.

### 2d. Ancilla cleanliness (`x -> x + 0x03`, 25 ancilla wires)

```
x=0x00: ancilla all zero? true
x=0x01: ancilla all zero? true
x=0x80: ancilla all zero? true
x=0xFD: ancilla all zero? true
x=0xFF: ancilla all zero? true
ASSERT PASSED: all ancilla wires returned to |0> for every tested input
```
Confirms the audit's Q2-impedance-2 assumption empirically: ancilla wires
genuinely return to `|0⟩` for every tested input, for a real
arithmetic-with-carries circuit (not just the identity's single-ancilla
sign-bit gate pair).

### 2e. Statically-bounded loop (`for i in 1:3; acc += x; end`)

```
n_wires=225, n_gates=220
loop_check_wires = LoopGuard[]   (EMPTY, as expected)
```
A loop whose trip count is a compile-time constant is fully unrolled by
Bennett's IR walker with no convergence-guard machinery — no fourth wire
class appears.

### 2e-ii. Data-dependent loop — non-empty `loop_check_wires`, and it is NOT a clean ancilla

First attempt (a naive `while acc != 0; acc -= 1; count += 1; end`
countdown, default `optimize=true`) produced `n_wires=17, n_gates=10` —
essentially the same size as the identity circuit, with **empty**
`loop_check_wires`. Root cause (confirmed by reading Bennett's own
`test/test_s0tn_loop_overflow.jl` comment, Bennett-s0tn): LLVM's default
optimizer recognizes a simple countdown as a closed form (`acc = x`) and
eliminates the loop entirely before Bennett's IR walker ever sees a
back-edge. **`optimize=false` is required to force genuine per-iteration
unrolling** — noted here because a bridge-side test suite that doesn't
know this will silently test the wrong code path.

Re-run with `optimize=false, max_loop_iterations=6`:
```
n_wires=749, n_gates=1733
loop_check_wires = [LoopGuard(wire=749, header_label=:L2, K=6)]

simulate(x=0) = 0   (converged, K=6 >= 0)
simulate(x=1) = 1   (converged)
simulate(x=5) = 5   (converged)
simulate(x=6) = 6   (converged, exactly at K)
simulate(x=7) THREW: "data-dependent loop ... did not converge within
  max_iterations=6 for this input ((0x07,))... Recompile with a larger
  max_loop_iterations (e.g. max_loop_iterations=12)."
simulate(x=255) THREW: same class of error.
```
Raw wire value of the `LoopGuard`'s wire (read via the hand-rolled
simulator, which does not throw on non-convergence):
```
x=3   (converges within K=6):  loop_check wire value = true   (1)
x=200 (needs 200 > K=6 steps): loop_check wire value = false  (0)
```
**Confirms the audit's Q2-impedance-3 warning empirically**: the
loop-check wire is a **convergence flag**, `1` iff converged and `0`
otherwise — it is data-dependent on whether the *input itself* stays
within the unrolled bound, not a scratch value that always returns to a
fixed pin. It is categorically different from `ancilla_wires`, which
returned to `false` for every tested input in 2d regardless of the input
value. A bridge that treated `loop_check_wires` as ordinary clean ancilla
would be silently wrong for any out-of-bound input under a `when` body.

## 3. Conclusion — stated unambiguously

**`input_wires[k]` and `output_wires[k]` (Bennett's 1-based positional
index into those vectors) carry bit `(k-1)` of the corresponding Julia
integer value — i.e. positional index 1 = LSB, positional index `W` =
MSB. Bennett is little-endian, positionally, on both its input and
output wire-order vectors, and the convention is identical across
input/output and across multi-element tuple output blocks.** This
matches Bennett's `simulator.jl` source directly (`(v >> (i-1)) & 1`
packing, `<< i` for `i in 0:width-1` unpacking) and was independently
reproduced with a from-scratch black-box gate simulator via single-hot-
bit and carry-chain probes (§2a, §2b). The v0.1 bridge's little-endian
assumption for Bennett was **correct**, but was asserted without proof
at the time — this probe supplies the proof empirically rather than
carrying the assumption forward unverified, per the audit's directive.

Sturm's kernel convention (`src/types/qint.jl:11`, "THE ENDIANNESS PIN"):
register position `j` (1-based, wire 1 = MSB) carries bit `(W-j)`, i.e.
`n = Σ_j x_j · 2^(W-j)`. This is the **opposite** direction from
Bennett's positional convention. **A bridge that copies `WireIndex`
values 1:1 between the two systems produces a silent bit-reversal** —
exactly the wm28-class bug the audit warned about, and it would pass any
marginal/round-trip test that itself uses the same (wrong) convention on
both sides.

## 4. The exact remap formula

For a single scalar input/output of width `W` (the common oracle case,
`length(c.input_widths) == 1`):

```
sturm_wire(j)  :=  c.input_wires[W - j + 1]     for input register position j = 1..W
sturm_wire(j)  :=  c.output_wires[W - j + 1]    for output register position j = 1..W
```
where `j = 1` is Sturm's MSB (kernel convention) and `W - j + 1` is
Bennett's positional index carrying that same bit (`bit (W-j)` in both
conventions — Bennett position `i` carries bit `(i-1)`, so setting
`i = W - j + 1` gives bit `(W-j)`, matching Sturm's `bit (W-j)` for
register position `j`). Equivalently, walking Bennett's own positional
index `i`, it lands at Sturm register position `j = W - i + 1`.

For multi-input or multi-output (tuple) circuits, apply the same formula
per element using Bennett's own offset/`start` accumulation
(`simulator.jl:186-193` for inputs — `offset += w` per element in
`input_widths` order; `simulator.jl:414-421` for outputs — `starts[k]`
accumulated over `output_elem_widths` in order), i.e. for input element
`e` with local width `w_e` and base offset `offset_e` (sum of widths of
preceding elements):
```
sturm_wire(e, j)  :=  c.input_wires[offset_e + (w_e - j + 1)]   for j = 1..w_e
```
and symmetrically for `output_elem_widths`/`output_wires` using
`starts[e]` in place of `offset_e + 1`.

`ancilla_wires` and every `LoopGuard.wire` in `loop_check_wires` are
**not** part of any register and carry no MSB/LSB significance — they
only need a *consistent* (arbitrary) placement into whatever remaining
wire slots the target `Perm(n_wires, gates)` uses, applied identically to
every gate's `control`/`control1`/`control2`/`target` field so the overall
map `Bennett WireIndex -> Sturm Perm wire index` is a single bijection
over `1:n_wires` used uniformly across the whole gate list.

**Operational consequence for `loop_check_wires`:** per the audit's Q2
impedance 3, any `ReversibleCircuit` with non-empty `loop_check_wires`
must be rejected loud by the bridge when applied under a nonzero control
stack (inside a `when` body) — confirmed here that the wire genuinely
carries input-dependent 0/1 state, not a clean-ancilla constant, so it
cannot be treated as scratch that vanishes under superposed control.

## 5. Summary for the bridge implementer

- Health check: **PASS** — Bennett.jl v0.5.0 loads and runs cleanly on
  Julia 1.12.5; two representative unit test files pass in full
  (257/257 each, exhaustive over `Int8`).
- Bit order: **Bennett is positionally little-endian** (`input_wires[1]`
  / `output_wires[1]` = LSB); Sturm is MSB-first (`wire 1 = MSB`). The
  bridge must reverse the positional index within each register block:
  `sturm_position(j) = Bennett_position(W - j + 1)` (or symmetrically,
  `Bennett_position(i) = Sturm_position(W - i + 1)`) — a plain
  end-to-end reversal per register block, not a bit-twiddle on wire
  values.
- Ancilla wires: **genuinely clean** — return to `|0⟩` for every tested
  input on both the trivial (1-ancilla identity) and non-trivial
  (25-ancilla `x+3`) circuits.
- `loop_check_wires`: **empty for loop-free/statically-bounded code**;
  **non-empty and input-dependent (not clean) for genuine data-dependent
  loops** — confirmed the wire holds a real 0/1 convergence flag, and that
  `simulate` itself throws loud on overflow. `optimize=false` is required
  to observe this path at all; the default optimizer eliminates simple
  countdown-style loops into closed form before any loop guard is ever
  emitted, which will fool a naive bridge-side test into believing loop
  guards "never happen."
- Gate/struct field names, as introspected (not assumed):
  `NOTGate.target`, `CNOTGate.(control,target)`,
  `ToffoliGate.(control1,control2,target)`,
  `LoopGuard.(wire,header_label,K)`,
  `ReversibleCircuit.(n_wires,gates,input_wires,output_wires,
  ancilla_wires,input_widths,output_elem_widths,loop_check_wires)`.

---

## Re-validation against Bennett.jl HEAD `b6f13802` (2026-07-10, orchestrator)

The probe above ran against Bennett.jl `051f5402` (the audited SHA); the
user pulled to HEAD `b6f13802` minutes later. Verified by the orchestrator:

- `git diff 051f5402..b6f13802 -- src/gates.jl src/simulator.jl
  src/bennett_strategies.jl` is **empty** — artifact shape, simulator
  bit-packing, and strategy set are byte-identical. The ~30 new commits
  are compiler front-end work (CW-D/`ptr_cells`/fdict cluster: which
  functions compile, not what the artifact looks like). `Project.toml`
  drift is JET test-tooling commentary only.
- The full probe script was **re-run against HEAD `b6f13802`**: identical
  results, including the loop-guard section (LoopGuard flag `true` on
  convergence / `false` on overflow; `simulate` throws a loud, actionable
  error for inputs exceeding `max_loop_iterations`).

**All conclusions in this document hold at HEAD `b6f13802`.** BennettVM.jl
also advanced (CW-D blocker commits, HEAD `36f8af2`) — irrelevant to M7
under the D14 ruling (circuit-only bridge; `VMProgram` never crosses).
