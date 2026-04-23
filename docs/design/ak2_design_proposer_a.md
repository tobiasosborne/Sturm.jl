# ak2 (spin-j Ry/Rz) Design — Proposer A

## 0. Summary (3-5 lines)

Ship `q.θ += δ` and `q.φ += δ` on `QMod{d, K}` as **spin-j rotations**
$\exp(-i\delta \hat J_y)$ and $\exp(-i\delta \hat J_z)$ on the
$(2j+1)$-dimensional irrep of $SU(2)$, $j = (d-1)/2$. **Reuse the existing
`BlochProxy` only at d=2** (where K=1, single wire, identity routing to
`apply_ry!`/`apply_rz!`); at d>2 introduce a new `QModBlochProxy{d, K}`
that holds the full `NTuple{K, WireID}` and dispatches on d. **At v0.1
we ship d=2 fully and d>2 as an explicit `error("…deferred to bead
Sturm.jl-nrs…")` with the proxy plumbing in place** — the spin-j Givens
decomposition is non-trivial enough (controlled multi-qubit rotations
restricted to in-subspace pairs) that landing it cleanly is a separate
bead. Subspace preservation for the d=2 path is trivial; the d>2 follow-on
bead carries the proof obligation.

## 1. BlochProxy reuse vs new proxy — Q1 answer

**Two-method dispatch on `getproperty(q::QMod{d, K}, :θ|:φ)`**: at d=2
(K=1) return the existing `BlochProxy` (`src/types/qbool.jl:67-72`) bound
to `q.wires[1]`; at d>2 return a new `QModBlochProxy{d, K}` that holds
the full wire group.

```julia
struct QModBlochProxy{d, K}
    wires::NTuple{K, WireID}
    axis::Symbol           # :θ or :φ
    ctx::AbstractContext
    parent::QMod{d, K}     # for check_live!
end
```

Dispatch in `Base.getproperty(q::QMod{d, K}, s::Symbol)`:

```julia
@inline function Base.getproperty(q::QMod{d, K}, s::Symbol) where {d, K}
    if s === :θ || s === :φ
        check_live!(q)
        if d == 2
            return BlochProxy(getfield(q, :wires)[1], s,
                              getfield(q, :ctx), QBool(getfield(q, :wires)[1],
                                                       getfield(q, :ctx), false))
        else
            return QModBlochProxy{d, K}(getfield(q, :wires), s,
                                         getfield(q, :ctx), q)
        end
    else
        return getfield(q, s)
    end
end
```

**Justification.** Two competing options, ruled out:

* *Single new proxy for both d=2 and d>2.* Tempting (uniform code path),
  but at d=2 the existing `BlochProxy + Real` overload already does the
  right thing (`src/types/qbool.jl:94-102`) and routes to bare
  `apply_ry!`/`apply_rz!` — bit-identical to a `QBool` rotation, which
  is what Rule 11 requires (the 4-primitive qubit set is preserved). A
  new proxy would mean a parallel `+` overload and a parallel test for
  bit-identity at d=2.
* *Always use the existing `BlochProxy`.* It carries a single `WireID`
  and a `parent::QBool` (`src/types/qbool.jl:67-72`). Lossy at d>2 —
  there is no way to recover `wires[2:K]` or `d` for the multi-qubit
  spin-j decomposition.

The two-method dispatch keeps the d=2 path identical to today (the
qubit-set tests in `test_qbool.jl` / `test_primitives.jl` are the
oracle), and `QModBlochProxy` cleanly carries the extra information the
d>2 decomposition needs. **The `BlochProxy.parent::QBool` field accepts
a freshly-constructed non-owning `QBool` view of `wires[1]`** — the
same trick `_qbool_views` uses on `QInt` (`src/types/qint.jl:45-48`)
and `superpose!` uses for QFT controlled-phases
(`src/library/patterns.jl:36-41`). The view's `consumed=false` flag is
fine because the QMod's `check_live!` already fired in `getproperty`.

## 2. d=2 specialization — Q2 answer

Concrete dispatch trace for `q.θ += δ` on `q::QMod{2, 1}`:

1. Julia desugars `q.θ += δ` → `q.θ = q.θ + δ`.
2. `q.θ` calls `Base.getproperty(q::QMod{2,1}, :θ)` (the method shown
   in §1). The d==2 branch fires; returns
   `BlochProxy(q.wires[1], :θ, q.ctx, QBool(q.wires[1], q.ctx, false))`.
3. The BlochProxy is added to δ via the existing
   `Base.:+(::BlochProxy, ::Real)` (`src/types/qbool.jl:94-102`),
   which calls `apply_ry!(proxy.ctx, proxy.wire, δ)` — identical to
   what `QBool(...).θ += δ` does.
4. `Base.:+` returns `ROTATION_APPLIED` sentinel
   (`src/types/qbool.jl:91-92`).
5. `q.θ = ROTATION_APPLIED` calls
   `Base.setproperty!(::QMod{d,K}, ::Symbol, ::_RotationApplied)` —
   needs to be added in this bead, no-op (mirror
   `src/types/qbool.jl:108-111`).

**Zero new context methods.** The dispatch reaches
`apply_ry!(ctx, wire, δ)` exactly once, on the single underlying wire,
identical in every observable way to `QBool(0).θ += δ`. Rule 11 holds:
no 5th primitive at the qubit layer. The Givens decomposition machinery
only fires at d>2.

`q.φ += δ` is symmetric: same path, axis `:φ`, routes to `apply_rz!`.

## 3. d>2 spin-j decomposition — Q3 answer (CITE BARTLETT EQ NUMBERS)

**Recommendation: ship deferral (option iii) at v0.1; design the
mechanism (option i) explicitly so the follow-on bead is a drop-in.**

### Physics anchor (Bartlett deGuise Sanders 2002)

The qudit is the spin-j irrep of SU(2) with $d = 2j+1$ (Bartlett Eq. 5,
p.2: "$|s\rangle \equiv |j, j-s\rangle_z$, $s = 0, 1, \ldots, d-1$").
The continuous primitives are the $SU(2)$ generators:

* $\hat J_z |j, m\rangle_z = m |j, m\rangle_z$ (Bartlett, between Eqs. 5
  and 6).
* $X_d \mapsto \sum_{m=-j}^{j} |j,m\rangle_z (j, m+1|$ (Bartlett Eq. 6,
  cyclic shift expressed in the spin basis).
* $Z_d \mapsto \exp(2\pi i (j - \hat J_z)/d)$ (Bartlett Eq. 7).
* For the "phase representation" basis Bartlett Eq. 12 (p.3):
  $X_d \mapsto \exp(2\pi i \hat J_x / d)$ (d odd) or
  $\exp(-i\pi/d)\exp(2\pi i \hat J_x / d)$ (d even) — **Eq. 13**.
  The even-d $\exp(-i\pi/d)$ prefactor is the parity factor §8.4 of the
  magic-gate survey commits us to honouring (it becomes observable
  inside `when()`).

Our `q.θ += δ` is therefore:

$$
R_y(\delta) := \exp(-i\delta \hat J_y), \qquad
\hat J_y = \frac{\hat J_+ - \hat J_-}{2i}
$$

with $\hat J_\pm$ from the standard ladder (Bartlett, after Eq. 5):
$\hat J_\pm = \hat J_x \pm i \hat J_y$, and matrix elements
$(\hat J_\pm)_{m', m} = \sqrt{j(j+1) - m(m \pm 1)} \delta_{m', m \pm 1}$
(Edmonds 1957, Wigner; cited identity, also referenced in Sakurai §3.5.39
— **NOT in Bartlett directly**; we add this to `docs/physics/wigner_jpm.md`
as a derivation note for Rule 4 grounding before merging the d>2 bead).
The $(2j+1) \times (2j+1)$ matrix is the spin-j Wigner small-d matrix
$d^j_{m', m}(\delta)$ (Sakurai Eq. 3.10.16); explicit formulas live in
§3.4 of `qudit_primitives_survey.md`.

### Decomposition algorithm (Givens / two-level rotations)

Spin-j $R_y(\delta)$ is dense in the $\{|0\rangle, \ldots, |d-1\rangle\}$
subspace — no obvious sparsity. Two routes:

* **(i) Givens decomposition into $d-1$ Wigner-pair rotations.** Any
  $SU(d)$ matrix factors into $\binom{d}{2}$ two-level $SU(2)$ rotations
  on adjacent computational pairs $(|k\rangle, |k+1\rangle)$ — this is
  the Reck-Zeilinger / Murnaghan factorisation. For spin-j $R_y(\delta)$
  specifically, Wigner small-d provides closed-form matrix elements;
  decomposition reduces to applying $d-1$ controlled-Ry rotations on
  pairs of computational basis states, each implemented as a
  multi-controlled-rotation on the K-qubit encoding (controls fire only
  on basis states $< d$). This is option (i) from the brief.
* **(ii) `oracle_table` / `qrom_lookup_xor!`.** Doesn't apply: those
  pre-compile classical lookup tables (Bennett-style reversible boolean
  functions, see exports at `src/Sturm.jl:127`), not arbitrary unitaries.
* **(iii) Defer to bead `Sturm.jl-nrs` (qubit-encoded fallback simulator
  integration).** Ship d=2 only here; at d>2, error loudly with a clear
  message pointing to the follow-on bead.

**Recommend (iii) for THIS bead, scaffold (i) for next.** Reasoning:

1. **Cost/benefit at v0.1.** The 3+1 protocol (Rule 2) only kicks in
   for *core changes*. The d>2 Givens decomposition is core: it adds a
   multi-controlled spin-j rotation primitive (the controls fire on
   computational labels k, not on bit values, which means the controls
   themselves are k-encoded — a different beast from the existing
   `_multi_controlled_gate!` cascade at
   `src/context/multi_control.jl:88-111`). Folding that into ak2 doubles
   the bead's surface area and pushes the test matrix from O(d=2) to
   O(d ∈ {2, 3, 4, 5} × leakage tests).
2. **Locked plan already files this.** WORKLOG Session 53 lists
   `Sturm.jl-nrs` ("qubit-encoded fallback simulator integration") as
   one of the next beads. The natural home for the spin-j decomposition
   is `nrs`, not `ak2`.
3. **Honesty over ambition (Rule 1).** A half-implemented spin-j
   decomposition that mostly works but leaks at edge cases (e.g.
   d=3 K=2 with a sign error in the |11⟩-region rotation) is exactly
   the "quantum bug invisible until amplification" Rule 6 warns
   against. Ship the d=2 path the tests can fully verify; let `nrs`
   carry the d>2 decomposition with proper Bartlett Eq. 6/7 grounding
   tests.
4. **The proxy split costs us nothing.** §1's design already routes
   d>2 to a separate proxy that can dispatch a `_apply_qmod_ry!` /
   `_apply_qmod_rz!` helper. In ak2, those helpers just `error(...)`;
   `nrs` fills them in. Zero refactor cost.

### What ak2 SHIPS at d>2

```julia
@inline function Base.:+(proxy::QModBlochProxy{d, K}, δ::Real) where {d, K}
    check_live!(proxy.parent)
    if d == 2
        # unreachable — d=2 routes through BlochProxy in §1
        error("internal: d=2 reached QModBlochProxy")
    elseif ispow2(d)  # d ∈ {4, 8, 16, ...}
        _apply_spin_j_rotation!(proxy.ctx, proxy.wires, proxy.axis, δ, Val(d))
    else              # d ∈ {3, 5, 6, 7, ...}
        _apply_spin_j_rotation!(proxy.ctx, proxy.wires, proxy.axis, δ, Val(d))
    end
    return ROTATION_APPLIED
end

# Stub — implemented by bead Sturm.jl-nrs.
function _apply_spin_j_rotation!(ctx, wires::NTuple{K, WireID},
                                  axis::Symbol, δ::Real, ::Val{d}) where {K, d}
    error(
        "spin-j $(axis) rotation on QMod{$d} not yet implemented. " *
        "The Givens / Wigner-small-d decomposition into multi-controlled " *
        "qubit rotations is filed as bead Sturm.jl-nrs (qubit-encoded " *
        "fallback simulator integration). Use d=2 for v0.1, or wait."
    )
end
```

The `Val(d)` dispatch lets `nrs` add specialised `Val{3}`, `Val{4}`, …
methods or a generic `where {d}` Givens loop without changing call sites.

## 4. Subspace preservation — Q4 answer

**(a) Trust the decomposition; per-primitive proof obligation.**

The spin-j irrep IS the $(2j+1)$-dim invariant subspace of
$U(2^K) \cap \text{span}\{|0\rangle, \ldots, |d-1\rangle\}$ (Bartlett
Eq. 6 for $X_d$; same for any $\exp(-i\delta \hat J_a)$ since $\hat J_a$
acts on the irrep, not on the encoded bits). At d=2 there is nothing
to preserve (K=1, all bit patterns are in-subspace). At d>2, the
primitive's *implementation* (controlled multi-qubit rotations whose
controls fire only on basis states $< d$) is what carries the proof —
that proof is the whole content of bead `nrs`, NOT this bead.

For ak2 the discipline is:

1. **At d=2: trivially preserved.** K=1, $2^K = d$.
2. **At ispow2(d) > 2: trivially preserved structurally.** Every K-bit
   pattern is in-subspace; nothing to preserve. (Still error in this
   bead — the spin-j math doesn't live here yet.)
3. **At non-pow2 d (d ∈ {3, 5, 6, 7, …}): proof obligation moves with
   the implementation.** ak2 errors loudly; `nrs` carries the proof and
   the test ("after any sequence of `q.θ += δ_i`, `q.φ += δ_j`,
   measurement never returns ≥ d" — Q7 test 5 below).

**Why not (b) leakage check after each rotation.** Cost is O(2^n) per
rotation across the *full* state — disastrous in QFT/Shor loops. Worth
keeping as a TLS-toggled debug knob but NOT default-on. Mirrors the
already-deferred `with_qmod_leakage_checks` (Session 52 WORKLOG).

**Why not (c) project at the boundary.** Changes the channel semantics
silently — kills off amplitude that should have been a Rule-1 error and
papers over real bugs. Rejected by the QMod docstring (`src/types/qmod.jl:36-46`).

The unconditional measurement-time check in `Base.Int(::QMod{d})` at
`src/types/qmod.jl:172-180` is the safety net (layer 3). It already
ships from bead 9aa.

## 5. Leakage in the gate decomposition — Q5 answer

For ak2's d=2 implementation: trivially no leakage (K=1, no |11⟩ to
leak into).

For the deferred d>2 implementation (`nrs`): the Givens decomposition
restricts every two-level rotation to an *in-subspace* pair
$(|k\rangle, |k+1\rangle)$ with $k+1 < d$. The multi-controlled
encoding of "fire only when the K-bit register equals $k$" means the
control pattern explicitly excludes bit-strings $k \ge d$. So |11⟩ at
d=3, K=2 is acted upon by *zero* of the d-1 Givens rotations and stays
at amplitude zero (assuming it started there — guaranteed by 9aa's prep
and the layer-1 / layer-2 invariants).

Concrete: the d=3 spin-j $R_y(\delta)$ acts on the $(|0\rangle,
|1\rangle, |2\rangle)$ triplet via two Wigner pair rotations:
$(|0\rangle, |1\rangle)$ with angle $\delta_a(\delta)$ and
$(|1\rangle, |2\rangle)$ with angle $\delta_b(\delta)$. Each pair
rotation, lifted to qubit space, is "controlled-Ry on wires[2] when
wires[1] = something specific". The control patterns for $k \in \{0, 1\}$
(pair 0-1) are $(\text{wires}[1]=0, \text{wires}[2]=0)$ and
$(\text{wires}[1]=1, \text{wires}[2]=0)$ — neither matches $|11\rangle$
($\text{wires}=[1,1]$). The control pattern for pair 1-2 fires on
$\text{wires}=[1,0]$ and rotates wires[2] from 0→1 (giving label 2).
$|11\rangle$ never appears as a control match, so its amplitude is
multiplied by 1.

(That control-pattern argument is the entire proof obligation `nrs`
will discharge; ak2 just files it as the test "after spin-j Ry/Rz
sequences, |11⟩ amplitude stays at zero".)

## 6. File location — Q6 answer

**Extend `src/types/qmod.jl`** for the proxy + getproperty/setproperty!
glue (BlochProxy reuse at d=2, QModBlochProxy struct + dispatch at
d>2). Put the `_apply_spin_j_rotation!` stub in the same file —
trivial 5-line `error(...)` for ak2. When `nrs` lands, it can either
expand the implementation in qmod.jl or move it to a new
`src/types/qmod_rotations.jl` (clear seam for the larger
multi-qubit decomposition). For now, one-file = simpler test surface.

**NOT** `src/library/qudit_gates.jl`: ak2's primitives 2 and 3 ARE
primitives (Rule 11 column "Syntax", §8.1 of the magic-gate survey),
not library gates. Library gates (`X_d!`, `H_d!`, `T_d!`, …) build
*on* primitives 2 and 3 and live in a future qudit-gates file.

**NOT** `src/primitives/`: that directory does not exist (verified via
`ls src/`); the existing pattern is "type files own their syntax-sugar
primitives" — `BlochProxy` lives in `qbool.jl`, `Base.:+` for QInt
lives in `qint.jl`. Follow precedent.

## 7. Test sketch — Q7 answer (Julia code blocks, runnable)

New file `test/test_qmod_rotations.jl`. Registered after `test_qmod.jl`
in `test/runtests.jl`.

### Testset 1 — d=2 reduces to bare Ry/Rz on the underlying wire

```julia
using Sturm
using Test

@testset "QMod{2}.θ += δ matches QBool.θ += δ on the underlying wire" begin
    δ = π/3
    # Pull amplitude vectors out for direct comparison.
    amps_qmod = @context EagerContext() begin
        q = QMod{2}()
        q.θ += δ
        # Snapshot before measurement
        ctx = current_context()
        amps = [Sturm.orkan_state_get(ctx.orkan.raw, UInt(i)) for i in 0:1]
        ptrace!(q)
        amps
    end
    amps_qbool = @context EagerContext() begin
        q = QBool(0.0)
        q.θ += δ
        ctx = current_context()
        amps = [Sturm.orkan_state_get(ctx.orkan.raw, UInt(i)) for i in 0:1]
        ptrace!(q)
        amps
    end
    @test amps_qmod ≈ amps_qbool atol=1e-12
end
```

(Note: `orkan_state_get` is in `src/orkan/ffi.jl`; if not exported, qualify
as `Sturm.orkan_state_get` exactly as Session 53 did with `Sturm.apply_ry!`.)

### Testset 2 — d=2 .φ symmetric

```julia
@testset "QMod{2}.φ += δ matches QBool.φ += δ" begin
    δ = π/4
    # Same pattern as above with apply_rz!. Expected: amplitude vectors equal up to
    # numerical noise. Rz on |0⟩ is just a global phase (e^{-iδ/2}) — verify amplitude
    # of |0⟩ is e^{-iδ/2}, |1⟩ stays 0.
    @context EagerContext() begin
        q = QMod{2}()
        q.φ += δ
        ctx = current_context()
        a0 = Sturm.orkan_state_get(ctx.orkan.raw, UInt(0))
        a1 = Sturm.orkan_state_get(ctx.orkan.raw, UInt(1))
        @test a0 ≈ exp(-im*δ/2) atol=1e-12
        @test abs(a1) < 1e-12
        ptrace!(q)
    end
end
```

### Testset 3 — d=2 statistics: q.θ += π/3 measurement distribution

```julia
@testset "QMod{2}.θ += π/3 produces correct measurement statistics" begin
    # P(|1⟩) after Ry(π/3) on |0⟩ = sin²(π/6) = 0.25
    counts = [0, 0]
    for _ in 1:5000
        @context EagerContext() begin
            q = QMod{2}()
            q.θ += π/3
            counts[Int(q) + 1] += 1
        end
    end
    p1 = counts[2] / 5000
    @test isapprox(p1, 0.25; atol=0.02)  # 5000 samples → ~σ = √(0.1875/5000) ≈ 0.006
end
```

### Testset 4 — d>2 errors loudly (deferred)

```julia
@testset "QMod{d>2}.θ errors with deferral message" begin
    @context EagerContext() begin
        q = QMod{3}()
        @test_throws ErrorException q.θ += π/3
        # Test the error mentions the follow-on bead
        try
            q.θ += π/3
        catch e
            @test occursin("Sturm.jl-nrs", e.msg)
            @test occursin("not yet implemented", e.msg)
        end
        ptrace!(q)
    end
end

@testset "QMod{d>2}.φ errors with deferral message" begin
    # symmetric to the .θ test
    @context EagerContext() begin
        q = QMod{5}()
        @test_throws ErrorException q.φ += π/4
        ptrace!(q)
    end
end
```

### Testset 5 — d=2 inside `when()` (controlled rotation reuse)

```julia
@testset "when(::QBool) { qm::QMod{2}.θ += δ } routes through control stack" begin
    # Build a Bell-shaped state: H on ctrl, then controlled-Ry(π) on QMod{2} target.
    # P(ctrl=1, target=1) = 0.5; P(ctrl=0, target=0) = 0.5.
    counts = Dict((0,0) => 0, (0,1) => 0, (1,0) => 0, (1,1) => 0)
    for _ in 1:5000
        @context EagerContext() begin
            ctrl = QBool(0.5)
            qm = QMod{2}()
            when(ctrl) do
                qm.θ += π
            end
            # Note: Ry(π) at d=2 is the Y channel, not X — see gates.jl:26-31.
            # Expected pattern: when ctrl=0 → qm stays |0⟩; when ctrl=1 → qm flips to |1⟩.
            c = Bool(ctrl) ? 1 : 0
            t = Int(qm)
            counts[(c, t)] += 1
        end
    end
    @test counts[(0, 0)] > 2000   # ~2500 expected
    @test counts[(0, 1)] < 50     # ~0 expected
    @test counts[(1, 0)] < 50     # ~0 expected
    @test counts[(1, 1)] > 2000   # ~2500 expected
end
```

### Testset 6 — d=2 compose with .θ and .φ (parity sanity)

```julia
@testset "QMod{2} composes θ and φ correctly (Hadamard-like)" begin
    # H! = q.φ += π; q.θ += π/2 (gates.jl:24).
    # Apply that pattern to QMod{2}; resulting state should match a QBool H!.
    @context EagerContext() begin
        q = QMod{2}()
        q.φ += π
        q.θ += π/2
        ctx = current_context()
        a0 = Sturm.orkan_state_get(ctx.orkan.raw, UInt(0))
        a1 = Sturm.orkan_state_get(ctx.orkan.raw, UInt(1))
        @test abs(abs(a0) - 1/sqrt(2)) < 1e-12
        @test abs(abs(a1) - 1/sqrt(2)) < 1e-12
        ptrace!(q)
    end
end
```

### Testset 7 — DEFERRED to bead nrs: d=3 spin-j sanity (documented placeholder)

```julia
@testset "QMod{3} spin-j Ry/Rz statistics — deferred to Sturm.jl-nrs" begin
    @test_skip "QMod{3}.θ += π/3 statistical match against Wigner small-d at j=1"
    @test_skip "QMod{3}.φ += δ is diagonal in computational basis (probabilities unchanged)"
    @test_skip "QMod{3}.φ += 2π/3 * k root-of-unity test against Bartlett Eq. 7"
    @test_skip "QMod{3} subspace preservation: P(measure ≥ d) == 0 over 1000 random sequences"
    @test_skip "QMod{4} controlled-X built from spin-j Ry/Rz vs. Bartlett Eq. 13 parity factor"
end
```

These are the Q7 brief items 2-6; written as `@test_skip` so they
appear in the test report and `nrs` can flip them to `@test`. **The
brief explicitly allows "at least a docstring reference if the test
is heavy" for the Bartlett Eq. 13 parity test** — fine to leave as
@test_skip with a paper reference comment.

### Testset 8 — proxy plumbing tests (white-box)

```julia
@testset "QMod{2}.θ returns BlochProxy; QMod{3}.θ returns QModBlochProxy" begin
    @context EagerContext() begin
        q2 = QMod{2}()
        @test getproperty(q2, :θ) isa Sturm.BlochProxy
        ptrace!(q2)

        q3 = QMod{3}()
        @test getproperty(q3, :θ) isa Sturm.QModBlochProxy{3, 2}
        ptrace!(q3)
    end
end
```

### Test count estimate

~8 testsets, ~25 assertions, sub-second wall (5000-sample stat tests
are the bottleneck at ~100ms each).

## 8. Open questions / risks — Q8 answer

**R1. `_RotationApplied` sentinel type — shared with QBool.** §1's
`Base.:+(::QModBlochProxy, ::Real)` and `Base.setproperty!(::QMod, …,
::_RotationApplied)` reuse the existing
sentinel/no-op-setproperty machinery. We need to verify
`_RotationApplied` is internal-but-importable from qmod.jl (it is —
defined at `src/types/qbool.jl:91-92`, both files are in the same
module). No risk.

**R2. `Val(d)` specialisation overhead at d>2 stub.** `_apply_spin_j_rotation!`
takes `::Val{d}` for future dispatch; at the stub it just routes to
`error(...)`. Julia compiles a separate stub method per d the user
calls — at d=3, 5, 7, … the world will see one method each. Tiny;
not a concern. Future `nrs` work can collapse via `where {d}` if it
ships a single generic implementation.

**R3. d=2 BlochProxy fabricates a `parent::QBool` with `consumed=false`.**
The `BlochProxy` struct's `parent` field is checked on `+` via
`check_live!(proxy.parent)` (`src/types/qbool.jl:95`). Our fake
`QBool(wires[1], ctx, false)` view is always live (we just made it),
so the check is vacuous but harmless. If the QMod gets consumed
*after* `q.θ` is evaluated but *before* `+δ` runs (extreme
pathological case), the BlochProxy's view will still report live. This
is identical to the existing `_qbool_views` pattern in QInt
(`src/types/qint.jl:45-48`). Acceptable, matches precedent. Document
in the proxy method's docstring.

**R4. Setproperty! method on QMod{d}.** Need to add
`Base.setproperty!(q::QMod{d, K}, s::Symbol, val::_RotationApplied)`
mirroring `src/types/qbool.jl:108-111`. The existing setproperty
fall-through (default Julia field assignment) would error on `:θ`
since QMod has no `θ` field. This is plumbing, not physics — the
implementer must remember it.

**R5. Tracing context.** Under `TracingContext`, `apply_ry!`/`apply_rz!`
emit RyNode/RzNode (`src/context/multi_control.jl` comments at
:11-14). At d=2 our path is identical to QBool, so tracing emits the
same nodes — no DAG change. At d>2 (when `nrs` lands), the spin-j
decomposition expands into many controlled-rotations, which the DAG
will see as RyNode/RzNode/CXNode under push/pop_control. CHANNEL IR
note (CLAUDE.md "Channel IR vs Unitary Methods"): no measurement
nodes inside the decomposition, so unitary optimizations are safe to
apply across the spin-j sub-block. NOT a problem.

**R6. CV / infinite-d foreclosure (P7).** The proxy split `if d == 2`
is a runtime branch on the type parameter, constant-folded by Julia's
specialiser. It does NOT foreclose future infinite-d. A
`QMod{:infinite, K_or_other}` could add a third proxy variant or
overload on a Symbol type-parameter — design-space-open. Bartlett's
Holstein-Primakoff CV limit (`qudit_primitives_survey.md` §3.4) maps
$\hat J_y / \hat J_z$ to $\hat x / \hat p$ on $L^2(\mathbb{R})$; the
proxy's role would be the same (carry the wire group + the dimension
witness), the dispatch would route to a CV simulator. Nothing in this
bead blocks that path.

**R7. Bennett interop (P9).** Untouched. `classical_type(::QMod)` is
intentionally absent (Session 53 WORKLOG entry on bead `Sturm.jl-jba`).
Calls like `oracle(f, q::QMod{d})` will MethodError. ak2 doesn't
change this. Auto-control of plain Julia functions inside `when()`
(P9 path) is unaffected at d=2 (rides the existing QBool catch-all);
at d>2 it's blocked at the `oracle` boundary, not at our primitives.

**R8. Wigner small-d derivation note (Rule 4).** Bartlett provides
the SU(2) framework but cites Edmonds / Wigner / standard QM textbooks
for the explicit small-d matrix elements of $\exp(-i\delta \hat J_y)$.
For Rule 4 strict compliance, the d>2 follow-on bead should add
`docs/physics/wigner_small_d.md` deriving $d^j_{m', m}(\delta)$ from
the ladder-operator commutation relations and citing Sakurai
*Modern Quantum Mechanics* §3.10 (or Edmonds *Angular Momentum* Ch. 4).
NOT a blocker for ak2 (which only ships d=2, where Sakurai §3.2
directly gives $R_y(\delta)$ from $\sigma_y$).

**R9. The `Sturm.jl-nrs` bead description in WORKLOG Session 53 says
"qubit-encoded fallback simulator integration" — slightly different
framing from "spin-j Ry/Rz at d>2".** The two are the same work:
`nrs` will land the spin-j decomposition AS the qubit-encoded fallback
(every `QMod{d>2}` gate decomposes to qubit gates that Orkan can
execute). Worth a bead-description tweak when the orchestrator picks
this design up — explicit "implements the d>2 path of ak2's spin-j
proxy" line.

## 9. Files to touch (paths + line counts)

* **Edit: `src/types/qmod.jl`** (current 188 lines → ~290 lines, +~100)
  * Add `struct QModBlochProxy{d, K}` (~10 lines).
  * Add `Base.getproperty(::QMod{d, K}, ::Symbol)` for `:θ`/`:φ`,
    branching on d==2 (~15 lines).
  * Add `Base.:+(::QModBlochProxy{d, K}, ::Real)` and `-` (~15 lines).
  * Add `Base.setproperty!(::QMod{d, K}, ::Symbol, ::_RotationApplied)`
    (~5 lines, mirror qbool.jl:108-111).
  * Add `_apply_spin_j_rotation!` stub with deferral error (~15 lines
    docstring + 5 lines body).
  * Update QMod docstring to mention rotations (~10 lines extension to
    the existing leakage section).
  * Comments / blank lines / docstrings: ~30 lines.

* **Edit: `src/Sturm.jl`** (current 184 lines, no count change)
  * `QModBlochProxy` is internal — NOT exported. No edit needed unless
    a future bead wants the proxy publicly visible (none planned).

* **New: `test/test_qmod_rotations.jl`** (~140 lines)
  * 8 testsets per §7 above.

* **Edit: `test/runtests.jl`** (+1 line)
  * `include("test_qmod_rotations.jl")` after `include("test_qmod.jl")`.

* **DO NOT TOUCH:**
  * `src/types/qbool.jl` — Rule 11, the qubit primitives stay frozen.
  * `src/context/eager.jl` / `density.jl` / `tracing.jl` — no new
    apply_* methods (Q2 dispatch trace shows we reach existing
    `apply_ry!`/`apply_rz!` only).
  * `src/context/multi_control.jl` — the multi-controlled cascade is
    untouched at d=2; the d>2 cascade is `nrs`'s problem.
  * `src/orkan/ffi.jl` — no new ccall (Q3 deferral defers Orkan-side
    work too; spin-j-on-qubit-encoding compiles to existing qubit
    primitives).

* **Follow-on bead update:** `Sturm.jl-nrs` description should be
  amended to call out "implements `_apply_spin_j_rotation!` for d>2;
  unblocks the deferred testsets in test_qmod_rotations.jl".

---

Design doc written to /tmp/ak2_design_A.md
