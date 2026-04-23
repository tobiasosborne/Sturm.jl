# ak2 (spin-j Ry/Rz) Design — Proposer B

## 0. Summary (3-5 lines)

Add `q.θ += δ` and `q.φ += δ` for `QMod{d, K}`. Reuse the existing
`BlochProxy` from `src/types/qbool.jl:67-72` **only at d=2** (single-wire
fast path); for d>2 introduce `QModBlochProxy{d, K}` carrying the full wire
group. At d=2, `QMod{2,1}.θ += δ` re-enters the existing `apply_ry!` /
`apply_rz!` on `wires[1]` — Rule 11 preserved bit-identically. For d>2,
**ship d=2 only in this bead and error loudly on d>2**, deferring the
spin-j multi-qubit decomposition to bead `Sturm.jl-nrs` (the "qubit-encoded
fallback simulator"). The d>2 algorithm sketch (Givens decomposition over
adjacent computational-basis pairs, Bartlett 2002 Eqs. 6–7) is documented
inline so `nrs` can pick it up without re-derivation. Subspace preservation
at d>2 is by design (spin-j rotations close on the (2j+1)-dim irrep), and
the in-subspace Givens decomposition acts trivially on encoded basis states
≥ d. Rule 13 reuse: **all four qubit primitives intact**; d=2 path is a
proxy alias, not a new code path.

## 1. BlochProxy reuse vs new proxy — Q1 answer

**Hybrid: reuse `BlochProxy` at d=2; new `QModBlochProxy{d, K}` at d>2.**

```julia
# At d=2 (K=1): return the existing BlochProxy directly.
@inline function Base.getproperty(q::QMod{2, 1}, s::Symbol)
    if s === :θ
        check_live!(q)
        # Build a non-owning QBool view of the single wire so BlochProxy's
        # `parent::QBool` liveness check still works. No allocation: QBool
        # is a 3-field mutable that the proxy retains via the field.
        view = QBool(getfield(q, :wires)[1], getfield(q, :ctx), false)
        return BlochProxy(getfield(q, :wires)[1], :θ, getfield(q, :ctx), view)
    elseif s === :φ
        check_live!(q)
        view = QBool(getfield(q, :wires)[1], getfield(q, :ctx), false)
        return BlochProxy(getfield(q, :wires)[1], :φ, getfield(q, :ctx), view)
    else
        return getfield(q, s)
    end
end

# At d>2: a distinct proxy that carries the wire group + d.
struct QModBlochProxy{d, K}
    wires::NTuple{K, WireID}
    axis::Symbol         # :θ or :φ
    ctx::AbstractContext
    parent::QMod{d, K}   # liveness check
end

@inline function Base.getproperty(q::QMod{d, K}, s::Symbol) where {d, K}
    if s === :θ
        check_live!(q)
        return QModBlochProxy{d, K}(
            getfield(q, :wires), :θ, getfield(q, :ctx), q,
        )
    elseif s === :φ
        check_live!(q)
        return QModBlochProxy{d, K}(
            getfield(q, :wires), :φ, getfield(q, :ctx), q,
        )
    else
        return getfield(q, s)
    end
end
```

**Trade-off**:
- *d=2 reuses `BlochProxy`*: `q.θ + δ` immediately routes through the
  existing `Base.:+(::BlochProxy, ::Real)` at `src/types/qbool.jl:94-102`,
  which calls `apply_ry!` / `apply_rz!` on the single wire. **Zero new
  code path at d=2.** Rule 11 + Rule 13 honoured.
- *d>2 needs the wire group*: a single `WireID` cannot dispatch a
  multi-qubit decomposition. Promoting `BlochProxy` to hold a tuple
  would break every existing qubit consumer of `BlochProxy` (and the
  `parent::QBool` field would need a Union). Cleaner to introduce a
  parallel `QModBlochProxy{d, K}` and dispatch on it.
- The proxy types are siblings; both implement the same `+`/`-` API
  (returning `_RotationApplied`). Julia's dispatch picks the right one.

**Rejected: a single proxy holding `Union{WireID, NTuple{K, WireID}}`** —
breaks type stability and forces a runtime check inside the hot path. The
two-proxy design is the same trick `QInt`/`QBool` use (different types,
same operator surface).

**Why method-on-`QMod{2,1}` and not generic `where {d, K}` with an `if d==2`
branch**: type-level dispatch lets Julia constant-fold the d=2 path away
entirely; at d>2 the branch never runs. Same idea as the
`if result >= d` in `Base.Int(::QMod{d, K})` at `src/types/qmod.jl:172-180`
— at power-of-2 d the comparison constant-folds (cf. `qmod.jl:160-161`).

## 2. d=2 specialization — Q2 answer

**Dispatch path for `QMod{2, 1}.θ += δ`** (Julia's `+=` desugaring made
explicit):

```
q.θ += δ
↓ desugar
q.θ = q.θ + δ
↓ getproperty(q::QMod{2,1}, :θ)
BlochProxy(wires[1], :θ, ctx, qbool_view_of_wires[1])
↓ Base.:+(::BlochProxy, ::Real)        [src/types/qbool.jl:94-102]
apply_ry!(ctx, wires[1], δ)            ← EXACTLY the qubit primitive
↓ returns ROTATION_APPLIED
↓ setproperty!(q::QMod{2,1}, :θ, ::_RotationApplied)  [§3 needs to stub]
no-op (rotation already applied)
```

The only new code at d=2 is

  1. `Base.getproperty(::QMod{2, 1}, ::Symbol)` returning `BlochProxy`.
  2. `Base.setproperty!(::QMod{2, 1}, ::Symbol, ::_RotationApplied)` no-op
     mirror of `qbool.jl:108-110`.

**No new context method**, no new ccall, no new gate dispatch — primitive 2
and 3 at d=2 are *literally* the qubit Ry/Rz on `wires[1]`. Verified by the
test "QMod{2}().θ += δ produces same statevector as QBool(0.0).θ += δ"
(see §7).

The QBool view stored in `BlochProxy.parent` is a non-owning alias (same
pattern `QInt._qbool_views` uses at `src/types/qint.jl:45-48`). It exists
purely so the proxy's liveness check still works. The view is not consumed
when the parent `QMod{2}` is consumed; that is fine because `BlochProxy`
only ever calls `check_live!(parent)` — and `check_live!(::QBool)` reads
`q.consumed`, which on the alias starts and stays at `false`. **Subtle but
non-bug**: even if the user mutates a view's consumed flag, the underlying
`QMod{2}.consumed` flag is the source of truth (`getproperty` re-checks it
before building each proxy). For paranoia we *could* override the proxy's
`+`/`-` to also `check_live!` the original `QMod`, but the current
construction already does that at `getproperty` time — re-checking inside
`+` is belt-and-braces and not strictly required.

## 3. d>2 spin-j decomposition — Q3 answer

**Recommendation: option (iii) — defer d>2 decomposition to bead
`Sturm.jl-nrs`.** This bead ships d=2 only and errors loudly at d>2. The
d>2 algorithm sketch is recorded here for the future `nrs` implementer.

### Why deferral

1. **Bead size**. d=2 alone is a ~30-line, self-contained,
   Rule-11-preserving change with a tight test. The d>2 spin-j Givens
   decomposition is its own substantial deliverable: O(d²) controlled
   rotations, multi-controlled gates routed through `_multi_controlled_gate!`
   (`src/context/multi_control.jl:88-111`), and a leakage-aware control
   pattern. Bundling it explodes the diff.
2. **Three sibling beads share the same fallback simulator infra**. `os4`
   (θ₂ quadratic), `mle` (θ₃ cubic), `p38` (SUM at d>2) all need the
   same "controlled rotation on a multi-qubit register" support. Building
   it once in `nrs` and inheriting in 4 beads is a strictly better
   ordering than re-deriving in each bead. WORKLOG Session 53:154–168
   listed `nrs` precisely as the qubit-encoded fallback simulator
   integration bead.
3. **Loud failure now is correct**. A `QMod{3}().θ += δ` that quietly
   does the wrong thing (e.g. acted as `Ry(δ)` on `wires[1]` only, which
   would NOT preserve the d=3 subspace) would silently corrupt every
   downstream computation — Rule 1 forbids it. `error("…d=2 only in
   v0.1; bead Sturm.jl-nrs covers d>2")` is the safe default.

### d>2 algorithm sketch (for `nrs`'s future implementer)

**Physics anchor (Bartlett-deGuise-Sanders 2002,
`docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf`)**:
the qudit is the spin-j irrep with `d = 2j+1`. The number representation
(Bartlett Eqs. 5-7, p.2) defines the computational basis as
`|s⟩ ≡ |j, j-s⟩_z` for `s ∈ {0, …, d-1}`, with `Z_d = exp(2πi(j - Ĵ_z)/d)`
(Eq. 7) and `X_d` as the spin-j rotation `exp(2πiĴ_x/d)` (Eq. 13, with
even-d `exp(-iπ/d)` parity prefactor).

The two primitives we want:

  * `q.θ += δ` ≡ `R_y(δ) = exp(-iδ Ĵ_y)` on the spin-j irrep.
  * `q.φ += δ` ≡ `R_z(δ) = exp(-iδ Ĵ_z)` on the spin-j irrep.

Both are (2j+1)×(2j+1) unitaries. They are the irreducible-rep matrices,
NOT Weyl-Heisenberg operators (cf. survey §3, primitives_survey.md and the
Bartlett Eq. 13 parity flag). Convention is locked at
`qudit_magic_gate_survey.md` §8.2.

**Givens decomposition (the recommended route for `nrs`)**:

`R_z(δ) = exp(-iδ Ĵ_z)` is **diagonal** in the computational basis
(Bartlett Eq. 7 — `Ĵ_z|j, j-s⟩_z = (j - s)|j, j-s⟩_z`). Implementation:
for `s ∈ {0, …, d-1}`, apply phase `exp(-iδ(j - s))` to qubit basis state
`|s⟩` (binary K-bit encoding of `s`). Encoded basis states ≥ d get **no
phase** — the loop simply doesn't iterate over them, leaving them at
amplitude zero (which they are by the prep + subspace-preservation
invariant; if a buggy upstream primitive put amplitude there, this
implementation does not propagate it). Concretely: for each `s ∈ {0, …,
d-1}`, push the K-bit binary mask of `s` as a control pattern (using
`_multi_controlled_gate!` at `src/context/multi_control.jl:88-111` with
appropriate X-gate negations on zero-control bits, then strip after), and
apply a single-qubit `Rz` of angle `2δ(j - s)` to a freshly-allocated
ancilla, *or* — much cheaper — emit a multi-controlled global-phase gate
which Sturm currently realises as `apply_rz!` on a target prepared at |0⟩
(global phase becomes a controlled relative phase). **Open subproblem**:
Sturm has no native "controlled global-phase" primitive; the workaround is
the standard one (Nielsen-Chuang §4.3 p.184: controlled-`exp(iα)` =
`Rz(2α)·X·Rz(-2α)·X` on a fresh |0⟩ ancilla, modulo phase). Defer this
to `nrs`.

`R_y(δ) = exp(-iδ Ĵ_y)` is **block-tridiagonal** in the computational basis
(Bartlett Eq. 6 ladder structure: `J_± = J_x ± iJ_y` couple `|j, m⟩` to
`|j, m±1⟩`). Standard Givens decomposition (Brennen-Bullock-O'Leary 2005
quant-ph/0509161 §4 Eq. 14, also Wang-Hu-Sanders-Kais 2020 Eq. 4) writes

```
R_y(δ) = ∏_{s=0}^{d-2} G_{s, s+1}(α_s, β_s)
```

where `G_{s, s+1}` is a 2×2 SU(2) rotation acting on the `{|s⟩, |s+1⟩}`
adjacent-basis pair, identity elsewhere. The angles `(α_s, β_s)` come from
the spin-j Wigner d-matrix `d^j_{m', m}(δ)` (e.g. Sakurai-Napolitano Modern
QM §3.8 Eq. 3.8.33 / Bartlett ref [10] Vourdas), computable in closed form
for fixed d but cumbersome. Each `G_{s, s+1}` is implemented as a
multi-controlled single-qubit Ry on the *one* qubit wire that distinguishes
the binary encodings of `s` and `s+1`, with the other K-1 wires used as
controls (binary-mask conditioned on the bits they share). This is
precisely the existing `_multi_controlled_gate!` pattern; no new
infrastructure needed beyond Sturm-side code-gen of the angle table.

The encoded basis states ≥ d are NEVER in the active control pattern (the
loop only iterates `s ∈ {0, …, d-2}`), so they remain in their initial
state (ideally |0⟩-amplitude) — see §4 / §5.

**Cost sketch for d=3 (K=2)**: 2 Givens blocks (for the pairs (0,1) and
(1,2)), each one `apply_ry!` on the differing wire with the shared wire as
a control — i.e. 2 × `_controlled_ry!` = 8 single-qubit Ry + 4 CX, plus
some X-gate negation flips (since e.g. (0,1) shares MSB=0 → control on
"MSB=0" needs the MSB negated for the duration of the Givens). Manageable.

**Why not option (ii) `oracle_table`**: as the brief notes,
`oracle_table` / `qrom_lookup_xor!` lower a *classical* function via QROM,
not an arbitrary unitary — they cannot encode an Ry rotation. Not
applicable.

**Bartlett equation references** (these ARE cited even though we defer the
Bartlett decomposition itself):
  * Eq. 5 (basis labelling `|s⟩ ≡ |j, j-s⟩_z`) — sets the convention so
    that `R_z(2π/d)` matches `Z_d` up to the global phase from Eq. 7.
  * Eq. 6 (ladder-operator matrix elements) — the source of the Wigner
    d-matrix coefficients for the Ry Givens decomposition.
  * Eq. 7 (`Z_d = exp(2πi(j - Ĵ_z)/d)`) — relates `R_z` to the
    Weyl-Heisenberg `Z_d` clock operator; the `j - Ĵ_z` shift is why
    "root-of-unity recovery" requires angle `2π/d` AND a global-phase
    correction at half-integer j.
  * Eq. 13 (`X_d = exp(2πi Ĵ_x/d)` for odd d, `exp(-iπ/d)·exp(2πi Ĵ_x/d)`
    for even d) — the parity factor that forces the §8.4 "controlled-X
    differs from displacement-X at even d" test (see §7 Test 6).

## 4. Subspace preservation — Q4 answer

**Choice: (a) trust the decomposition, document the proof, NO runtime
projection. Optional (b) leakage check guarded by a TLS flag, default-off.**

### Mathematical proof (paper-side, what the docstring will cite)

Spin-j R_y(δ) and R_z(δ) are matrix exponentials of `Ĵ_y` and `Ĵ_z`
respectively. `Ĵ_y` and `Ĵ_z` are operators *on the (2j+1)-dim spin-j
irrep* — they map the irrep to itself by definition of "irrep". Therefore
R_y(δ) and R_z(δ) preserve `span{|0⟩, …, |d-1⟩}` setwise. This is not a
property of a particular decomposition; it is a property of the
Hamiltonian. Reference: any QM textbook treatment of SU(2)
representations (Sakurai-Napolitano Modern QM Ch. 3.5; or Bartlett 2002
p.2: "the d-dimensional irreducible representation of SU(2)").

### Implementation proof (qubit-side, the part that actually needs care)

The Givens decomposition (§3) has every gate `G_{s, s+1}` confined to the
2-level subspace `span{|s⟩, |s+1⟩}` for `s ∈ {0, …, d-2}`. None of these
2-level subspaces touches an encoded basis state `|m⟩` with `m ≥ d`. So
the implementation acts as identity on `|m⟩` for `m ≥ d`. If the upstream
state has zero amplitude on those levels (the prep + invariant is layer 1
of `qmod.jl:30-46`), it stays zero.

**This is option (a)**. No projection, no per-gate amplitude check.

### Optional debug check (option (b), filed for `nrs`)

Same TLS-toggled mechanism Session 52 WORKLOG suggested
(`:sturm_qmod_check_leakage`, default false). The check sums |amp|² over
qubit-basis indices whose K-bit encoding decodes to ≥ d; tolerance 1e-12;
errors loudly. Mechanism: zero-FFI sweep via `unsafe_wrap` (the same idiom
`measure!` uses at `src/context/eager.jl:230`). In this bead's d=2 path
the check is statically unreachable and trivially elided. **Recommendation**:
**this bead does NOT ship the optional check** — option (a) suffices for
d=2 (no leakage states exist), and the check infrastructure is
fallback-simulator concern owned by `nrs`. Filed for `nrs`.

### Rejected: option (c) project at the boundary

Changes channel semantics (turns a unitary into a non-trace-preserving
projection). Wrong by Rule 14/P1.

## 5. Leakage in the gate decomposition — Q5 answer

**At d=2 (this bead's actual scope): no leakage states exist.** K=1, every
qubit basis state encodes a valid d-level label. The question is moot;
constant-folded away.

**At d=3, K=2, encoded basis state `|11⟩_qubit` represents label 3 ≥ d
(forbidden)**. The Givens decomposition (§3) iterates `s ∈ {0, 1}`, applying
`G_{0,1}` on `{|00⟩, |01⟩}` and `G_{1,2}` on `{|01⟩, |10⟩}`. Neither block
touches `|11⟩`. Concretely:
  * `G_{0,1}` on `{|00⟩, |01⟩}`: differing wire = LSB; control: MSB == 0.
    Acts as identity when MSB=1, i.e. on `|10⟩` and `|11⟩`. ✓
  * `G_{1,2}` on `{|01⟩, |10⟩}`: differing wires are *both* (this is a
    Hamming-distance-2 pair), so it's a 2-qubit Givens, not a single-bit
    flip with a control. Realised as a sequence of CXs that move the LSB
    out of the way, then a controlled rotation, then unmove. Crucially:
    the gates only fire when `(MSB, LSB) ∈ {(0, 1), (1, 0)}` — never on
    `(1, 1)`. ✓

So the decomposition acts trivially on `|11⟩`, leaving any (presumably
zero) amplitude there untouched. **Recommendation**: each Givens block in
the future `nrs` implementation must include in its docstring an explicit
"acts as identity on basis states |m⟩ with m ∉ {s, s+1}" assertion, plus a
unit test verifying `|11⟩ → |11⟩` for the d=3 case. Same proof obligation
gets reused for d=5,6,7,… in `nrs`.

**At d=4, K=2**: every K-bit pattern is in-range, no leakage states. The
Givens decomposition runs without any "skip" logic.

**At d=5 (K=3) and beyond**: encoded patterns 5, 6, 7 are forbidden.
Same per-block argument applies.

## 6. File location — Q6 answer

**`src/types/qmod.jl` (extend the existing file)**.

Reasoning:
  1. The d=2 path is ~30 lines (getproperty + setproperty! mirrors of
     `qbool.jl:74-110`). It belongs *with* the `QMod` type definition,
     just as `BlochProxy` lives in `qbool.jl:67-111` immediately after
     the `QBool` type.
  2. The d>2 path in this bead is just a single `error()` stub. Trivial.
  3. A future `src/types/qmod_rotations.jl` split is fine if `os4`/`mle`
     accumulate enough code to warrant it, but YAGNI for now — `qint.jl`
     keeps adder + xor + shifts all inline, and `qbool.jl` keeps the
     proxy + xor + measurement together. Same style.
  4. `src/library/qudit_gates.jl` is for *library* gates (composed, like
     `H_d!`, `T_d!`). Primitives 2 and 3 are primitives, not library
     gates — they belong with the type definition.

Files touched:
  * `src/types/qmod.jl` — extend with proxy + getproperty/setproperty!
    + Base.:+ / Base.:- on `QModBlochProxy`.
  * `test/test_qmod.jl` — extend the existing 21-testset file with the
    new ak2-specific tests.

No edits to: `src/context/eager.jl`, `src/context/multi_control.jl`,
`src/Sturm.jl` (BlochProxy is already exported indirectly via the public
qbool surface; `QModBlochProxy` is internal — no export needed).

## 7. Test sketch — Q7 answer

```julia
# test/test_qmod.jl — appended to existing testsets

@testset "QMod{2}.θ += δ matches QBool .θ += δ on underlying wire" begin
    # The Rule-11 contract: at d=2, primitives 2/3 are bit-identical to
    # the qubit Ry/Rz primitives. Verify by running both on fresh contexts
    # with the same seed / prep and comparing the raw amplitude vector.
    using Sturm: orkan_state_get
    for δ in (0.0, π/7, π/3, π, 2π - 0.01, -π/4)
        # Path A: QBool primitive
        amps_qbool = @context EagerContext() begin
            q = QBool(0.0)        # fresh |0⟩
            q.θ += δ
            ctx = current_context()
            dim = 1 << ctx.n_qubits
            [orkan_state_get(ctx.orkan.raw, i) for i in 0:dim-1]
        end

        # Path B: QMod{2} primitive
        amps_qmod = @context EagerContext() begin
            q = QMod{2}()         # fresh |0⟩_d at d=2
            q.θ += δ
            ctx = current_context()
            dim = 1 << ctx.n_qubits
            [orkan_state_get(ctx.orkan.raw, i) for i in 0:dim-1]
        end

        @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
    end
end

@testset "QMod{2}.φ += δ matches QBool .φ += δ on underlying wire" begin
    using Sturm: orkan_state_get
    for δ in (0.0, π/3, π, -π/2)
        amps_qbool = @context EagerContext() begin
            q = QBool(0.0); q.θ += π/3   # non-trivial start state
            q.φ += δ
            ctx = current_context()
            [orkan_state_get(ctx.orkan.raw, i) for i in 0:(1 << ctx.n_qubits)-1]
        end
        amps_qmod = @context EagerContext() begin
            q = QMod{2}(); q.θ += π/3
            q.φ += δ
            ctx = current_context()
            [orkan_state_get(ctx.orkan.raw, i) for i in 0:(1 << ctx.n_qubits)-1]
        end
        @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
    end
end

@testset "QMod{2} Bloch chain QBool/QMod parity over a 4-gate sequence" begin
    # End-to-end identity: a sequence of θ and φ rotations on QMod{2}
    # produces the same statevector as the same sequence on QBool.
    using Sturm: orkan_state_get
    seq = [(:θ, 0.4), (:φ, 1.1), (:θ, -0.3), (:φ, π/2)]
    amps_qbool = @context EagerContext() begin
        q = QBool(0.0)
        for (ax, δ) in seq
            ax === :θ ? (q.θ += δ) : (q.φ += δ)
        end
        ctx = current_context()
        [orkan_state_get(ctx.orkan.raw, i) for i in 0:(1 << ctx.n_qubits)-1]
    end
    amps_qmod = @context EagerContext() begin
        q = QMod{2}()
        for (ax, δ) in seq
            ax === :θ ? (q.θ += δ) : (q.φ += δ)
        end
        ctx = current_context()
        [orkan_state_get(ctx.orkan.raw, i) for i in 0:(1 << ctx.n_qubits)-1]
    end
    @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
end

@testset "QMod{d>2}.θ += δ errors loudly (deferral to nrs)" begin
    @context EagerContext() begin
        q = QMod{3}()
        @test_throws ErrorException q.θ += π/3
    end
    @context EagerContext() begin
        q = QMod{5}()
        @test_throws ErrorException q.φ += π/5
    end
end

# ── Tests below are written but @test_skip-pinned, ready for nrs ────────
# Listed here for completeness so nrs's implementer has the scaffold.

@testset "QMod{3}.θ += π/3 measurement distribution (nrs)" begin
    @test_skip begin
        # Spin-j=1 R_y(π/3) on |0⟩_d=3 gives a known distribution.
        # Compute Wigner d-matrix d^1(π/3); compare measurement marginals
        # over N=4000 samples with tolerance 0.03.
        false
    end
end

@testset "QMod{3}.φ += δ is diagonal in computational basis (nrs)" begin
    @test_skip begin
        # Prep |0⟩_d, apply φ rotation, measure → still 0 with prob 1.
        true
    end
end

@testset "QMod{3} root-of-unity φ recovery (nrs)" begin
    # Bartlett Eq. 7: R_z(2π/d) = Z_d up to a global phase.
    # Test by sandwiching with a QFT (when QFT_d! lands in nrs).
    @test_skip true
end

@testset "QMod{d>2} subspace preservation (nrs, statistical)" begin
    # After random sequences of θ/φ rotations, measure ≥ d never returns.
    @test_skip true
end

@testset "Bartlett Eq. 13 parity factor at d=4 (nrs)" begin
    # Even-d global phase difference: spin-j X built from R_y(2π/d) is
    # exp(-iπ/d) times the Weyl-Heisenberg X_d. This is observable when
    # the X gate is wrapped in `when()` — verify the controlled-phase
    # discrepancy. Locked behaviour, qudit_magic_gate_survey.md §8.4.
    @test_skip true
end
```

## 8. Open questions / risks — Q8 answer

### Open questions

1. **Should the d=2 BlochProxy alias also be created via a thin
   `_qbool_view` helper for symmetry with `QInt._qbool_views`
   (`src/types/qint.jl:45-48`)?** The 3-arg `QBool(wire, ctx, false)`
   call is a sharp edge — easy to forget the trailing `false` for
   "consumed". Recommendation: extract `_qbool_view(wire, ctx) =
   QBool(wire, ctx, false)` into `qbool.jl`; reuse it in `qmod.jl`
   and `qint.jl`. Out of scope here, but worth a follow-on.

2. **Does `apply_ry!`'s recursive control stack (`src/context/eager.jl:141-151`)
   correctly handle a `QMod{2}` rotation called inside a `when(::QBool)`?**
   Yes — at d=2, the rotation hits the existing qubit fast path with the
   QBool's wire on the control stack. No new dispatch logic. Verify with
   one extra @testset in the bead.

3. **Convention sanity (orchestrator's call)**: Bartlett Eq. 5 puts
   `|s⟩ = |j, j - s⟩_z`, so `Ĵ_z|s⟩ = (j - s)|s⟩`. At d=2 (j=1/2): `|0⟩
   → m = 1/2`, `|1⟩ → m = -1/2`. So `R_z(δ) = exp(-iδ Ĵ_z)` puts a phase
   `exp(-iδ/2)` on `|0⟩` and `exp(+iδ/2)` on `|1⟩`. This is **exactly**
   what Sturm's qubit `apply_rz!(ctx, wire, δ)` does (orkan
   convention). ✓ At d>2 the convention is `Ĵ_z|s⟩ = (j - s)|s⟩`, NOT
   `Ĵ_z|s⟩ = -s|s⟩` — flag in `nrs`'s docstring.

### Risks

1. **`QModBlochProxy{d, K}` collides with future `QInt{W, d}`'s own
   proxy** — when `dj3` lands and `QInt{W, d}` digits are `QMod{d, K}`,
   `q.θ` on a `QInt{W, d}` should mean *something* (per-digit
   rotation? whole-register rotation?). Recommendation: defer; `dj3`'s
   designer must consult this bead. Filed as a potential follow-on
   issue ("QInt{W,d} per-digit Bloch proxy semantics").

2. **`BlochProxy.parent::QBool` field type**: at d=2 we are passing a
   non-owning view, which is safe under the current `check_live!`
   contract but only because the view's `consumed` flag is never read
   after the proxy's construction (the only reader is in `Base.:+` /
   `Base.:-`, which calls `check_live!(proxy.parent)` and reads the
   alias). If a future change makes `Base.:-` actually mutate the
   parent (e.g. some "consume on rotation" idea — there is no such
   idea), the view aliases would silently diverge. **Mitigation**:
   add a comment in `qmod.jl`'s d=2 getproperty pointing this out;
   add a TLS-free unit test that runs 2 successive rotations and
   verifies neither marks the parent consumed.

3. **Spin-j Wigner d-matrix angle table size at large d** — the d>2
   Givens decomposition for `R_y(δ)` needs `O(d²)` gate angles, each
   computed from the Wigner d-matrix `d^j_{m', m}(δ)`. At d=11,
   K=4: ~110 controlled rotations per `q.θ += δ` call, all routed
   through `_multi_controlled_gate!`. Performance acceptable for v0.1
   prototyping; flag for `nrs`.

4. **Ĵ_z convention drift**: Bartlett 2002 uses `|j, j-s⟩_z` (Eq. 5),
   while Howard-Vala 2012 and Campbell 2014 use `Ĵ_z = diag(j, j-1, …,
   -j)` directly with no `j - s` relabelling. The two are equivalent
   *up to a basis permutation*. `nrs`'s implementer must pick ONE and
   document; the v0.1 lock at `qudit_magic_gate_survey.md` §8.2 is
   "use `n̂` (computational-basis label) for `θ₂, θ₃`" but `θ, φ` are
   in `Ĵ_y / Ĵ_z` (locked §8.1 + §8.2 second paragraph). At d=2 these
   collapse and the tension does not bite — that is what enables this
   bead to ship without resolving it.

## 9. Files to touch (paths + line counts)

| File | Action | Line count |
|---|---|---|
| `/home/tobias/Projects/Sturm.jl/src/types/qmod.jl` | extend (add `Base.getproperty(::QMod{2,1}, ...)`, `Base.getproperty(::QMod{d,K}, ...)`, `Base.setproperty!(::QMod{2,1}, ...)`, `QModBlochProxy{d,K}`, `Base.:+`/`Base.:-` on the new proxy with `error()` stub for d>2, plus literate docstrings citing Bartlett Eqs. 5-7, 13) | ~50-70 lines added (188 → ~245) |
| `/home/tobias/Projects/Sturm.jl/test/test_qmod.jl` | extend (add 4 active testsets + 5 `@test_skip` scaffolds for `nrs`) | ~120 lines added (244 → ~365) |
| `/home/tobias/Projects/Sturm.jl/WORKLOG.md` | append Session 54 entry per Rule 0 | ~40-60 lines appended |

No edits to `src/Sturm.jl`, `src/context/*`, or `src/types/qbool.jl`.
`QModBlochProxy` is internal — no export needed. The `BlochProxy`
return at d=2 reuses an already-public type and operator surface.
