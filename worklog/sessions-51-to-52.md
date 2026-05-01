## 2026-04-22 — Session 52: `goi-type` (Sturm.jl-9aa) — 3+1 proposer round, implementer deferred

Claimed `Sturm.jl-9aa` (QMod{d} type + EagerContext prep primitive — the
foundational brick of the qudit epic). This is a core-type change, so
CLAUDE.md Rule 2 (3+1 protocol) applies: 2 independent proposer subagents
dispatched in parallel, neither seeing the other's output. Session
stopped after proposers reported — implementer runs in next session per
user instruction.

### Proposers converged hard

Both designs land at `/tmp/qmod_design_A.md` (596 lines) and
`/tmp/qmod_design_B.md` (548 lines); copied to `docs/design/
qmod_design_proposer_{a,b}.md` for durability (/tmp won't survive).

**Wire layout**: both picked `mutable struct QMod{d, K} <: Quantum`
holding `wires::NTuple{K, WireID}` where `K = ⌈log₂ d⌉` is a **derived
hidden second type parameter** (same pattern QCoset uses at
`src/types/qcoset.jl:45-50` with its `{W, Cpad, Wtot}` trick — user
only writes `QMod{d}`, Julia figures K from d via an inner constructor).
At d=2 this collapses to K=1 (single wire), recovering the QBool shape
exactly — Rule 11 preserved.

**Context-d strategy**: both picked **compile-time d via the type
parameter**, no `wire_dims::Dict` on any context, no new
`allocate_group!` on AbstractContext. Mixed-d operations (`QMod{3} ⊻=
QMod{5}`) error at Julia dispatch time rather than runtime dict lookup —
loud-fail is structural, matches Rule 1.

**Leakage strategy**: both picked a 3-layer approach:
  1. **Trust prep** — fresh wires from `allocate!` are always |0⟩, always
     in-subspace. No runtime check at prep time.
  2. **Proof obligation on primitive authors** — each primitive
     (Ry, Rz, θ₂, θ₃, SUM in later beads) must preserve the d-level
     subspace by construction. Documented as a TODO header in the 9aa
     type file; referenced in each primitive bead.
  3. **Unconditional check at measurement** — inside `Int(::QMod{d})`,
     if the observed bitstring is ≥ d, fail loud with a clear message.
     Optional amplitude-buffer sweep behind a `:sturm_qmod_check_leakage`
     TLS flag (mirrors `with_silent_casts` / `with_orkan_*` precedents).

This convergence across two independent agents is strong evidence the
design is right. The implementer can lift it directly.

### Two tradeoffs flagged (implementer's call, but my leans below)

**R1. `Base.Bool(::QMod{2})` interop — does it exist?**
  * Proposer A's lean: NO — strict non-interop matches survey §8.5
    ("QBool and QMod{2} are distinct types by design, same reason Julia
    keeps `Bool` and `Mod{2}` separate — logical vs. arithmetic API").
  * Cost of NO: `Int(q) == 1` at every measurement site of a `QMod{2}`.
  * My lean: agree with A, no interop. Add a docstring pointing users to
    `QBool` if they want logical ops at d=2.

**R2. Leakage-guard default — on or off?**
  * Proposer B's flag: default-off keeps tight-loop performance clean
    (no O(2^n) amp sweep per measurement); default-on catches silently-
    buggy primitives during prototyping but hurts hot paths (Shor
    iterations, QFT loops).
  * My lean: **default-off + easy TLS toggle**. Mirror `with_silent_
    casts`. Primitives are supposed to be correct by construction (layer
    2 above); the sweep is for debugging. `with_qmod_leakage_checks(do
    ... end)` wraps the block.

### Bikeshed: K vs W naming for derived type param

Proposer A chose `K`, Proposer B chose `W`. Both work. **Implementer
should use `K`**: rationale is that `W` will be reused with a DIFFERENT
meaning in the future `QInt{W, d}` bead (Sturm.jl-dj3 — where W = number
of digits, not qubits-per-digit). Using K for QMod{d} avoids a name
collision when QInt{W,d} composes QMod wires as
`NTuple{W, QMod{d, K}}`. Also: K is the first letter of Kubit-encoding
storage width, a weak mnemonic.

### What the implementer needs to do (next session's brief)

Scope:
  * `src/types/qmod.jl` (new) — the type + prep + Bool/Int measurement.
  * `src/types/quantum.jl` — update the "future QDit{D}" comment at
    `src/types/quantum.jl:4-5` to `QMod{d}`.
  * `src/Sturm.jl` — export `QMod`.
  * `test/test_qmod.jl` (new) — TDD FIRST, implement SECOND.
  * Possibly `src/context/eager.jl` if either proposer's design needs a
    context-side hook (check both designs — if neither requires it,
    skip).

TDD tests to write FIRST (per Rule 10):
  1. `QMod{3}(ctx)` constructs, type-checks, is live, deallocates on
     ptrace.
  2. `Int(QMod{3}(ctx)) == 0` — prep'd at |0⟩, measurement returns 0.
  3. `QMod{4}(ctx)` — d=4 power-of-2, K=2, no leakage states.
  4. `QMod{3}(ctx)` — d=3 in 2 qubits (K=2), leakage check catches a
     synthetic |11⟩ corruption.
  5. Backwards-compat: full `test_types_qbool.jl` (or equivalent)
     passes unchanged. All `test_qint_*` pass unchanged.
  6. `@context EagerContext() begin q = QMod{3}() end` — TLS context.
  7. `ptrace!` / `discard!` work on QMod{3}.
  8. `Base.convert(::Type{Int}, q::QMod{3})` emits the P2 implicit-cast
     warning exactly once per source location.

Rules to honour:
  * Rule 0 — update WORKLOG when you finish.
  * Rule 1 — fail fast on leakage, fail fast on mixed-d (even though SUM
    is a later bead, the error site should be tight-scoped).
  * Rule 5 — docstrings: WHAT / WHY / WHICH reference.
  * Rule 10 — tests before code.
  * Rule 14 P5 — QMod{d} is user-facing; no raw wire manipulation in
    public API.

### Tradeoff the implementer should NOT resolve

**P9 / Bennett compatibility (classical_type for QMod{d}).** Both
proposers flagged this honestly: Bennett currently compiles against
power-of-2 integer types, not modular arithmetic for arbitrary d. This
is a real gap (`oracle(f, q::QMod{3})` wouldn't Just Work). Implementer
should stub `classical_type(::Type{QMod{d}}) where {d}` with a clear
`error("Bennett compilation not yet supported for QMod{d>2}; see bead
...")` — file a follow-on bead "QMod Bennett interop — modular
arithmetic in reversible IR" for later scope.

### Files for next session

Before writing code, the implementer reads:
  * `docs/design/qmod_design_proposer_a.md` (596 lines, NTuple + compile-
    time d + 3-layer leakage)
  * `docs/design/qmod_design_proposer_b.md` (548 lines, same but different
    leakage-default wording)
  * `docs/physics/qudit_magic_gate_survey.md` §8 (locked design decisions)
  * `src/types/qbool.jl` + `src/types/qint.jl` + `src/types/qcoset.jl`
    (templates — QCoset's hidden-type-param trick is the key pattern)

### `bd dolt push` STILL BLOCKED

Secret-scanning on a historical OAuth blob (same token across multiple
dolt blobs). This session's `bd dolt push` attempt failed with the
same unblock URL pointing at commit `2ebc38db890ec54c54cc64bc73024eff7c5e4ce3`
path `vfupa118n12u09cfs5ppi791p43sh6s0.darc:7715`. User action required
at `https://github.com/tobiasosborne/Sturm.jl/security/secret-scanning/
unblock-secret/3CitIms2IwRs2Ixan0CiUzUFuLk`.

Until unblocked, beads are local-only. Before starting 9aa implementation
in the next session, the implementer should re-attempt `bd dolt push`
(in case user cleared the block) and verify via `git ls-remote origin
'refs/dolt/*'` that the remote ref updates.

### Files touched this session

  * `docs/design/qmod_design_proposer_a.md` (new, 596 lines)
  * `docs/design/qmod_design_proposer_b.md` (new, 548 lines)
  * `WORKLOG.md` — this entry
  * `Sturm.jl-9aa` bead claimed (local dolt, not synced to remote)

---

## 2026-04-22 — Session 51: `goi` qudit research rounds 1+2 — primitives + T-gate / MSD

Claim `Sturm.jl-goi` (P7 dimension lift, qudit d>2 support). Pure-research
pass — no Sturm source code touched. Two ground-truth survey rounds
produce the locked 6-primitive hybrid-B + cubic-phase design.

### Round 1: primitive choice (`docs/physics/qudit_primitives_survey.md`)

Three candidate continuous 1-parameter families for `q.θ` / `q.φ`
evaluated across 7 axes (d=2 recovery, root-of-unity → Weyl-Heisenberg,
1-qudit universality, CV limit, P9/Bennett compatibility, count, Sturm
idiom fit). 11 PDFs downloaded (Gottesman 1998 quant-ph/9802007 anchor,
Brylinski² universality theorem, Bartlett-deGuise-Sanders, Brennen-
Bullock-O'Leary ×3, Muthukrishnan-Stroud, Howard-Vala, Farinholt, Wang
review, de Beaudrap). Luo-Wang 2014 has no arxiv preprint, not a blocker.

**Decision**: hybrid spin-$j$ $su(2)$ (Candidate B) for continuous
primitives. Cleanest d=2 match (exact Ry/Rz), cleanest CV limit via
Holstein-Primakoff $\hat J_\pm \to \hat x \pm i\hat p$. Three continuous
primitives: `q.θ` ($\hat J_y$), `q.φ` ($\hat J_z$), `q.θ₂` ($\hat J_z^2$
squeezing). SUM as 4th primitive (`a ⊻= b` at d=2 → CNOT, at d>2 →
Gottesman Eq. G12). 5 primitives total.

### Round 2: T-gate / magic state distillation (`docs/physics/qudit_magic_gate_survey.md`)

User flagged: "I don't know what is the natural analogue of the T gate
for qudits." Second research round dispatched. 7 more PDFs downloaded
(Campbell 2014 canonical form, Campbell-Anwar-Browne, Anwar-Campbell-
Browne, Watson 2015, Beverland et al., Krishna-Tillich, Prakash 2020
ternary Golay, Veitch resource theory).

**Key finding — and the redirect this session made**: the Howard-Vala
qudit π/8 is **cubic** in the computational-basis label, not quadratic.
Campbell 2014 Eq. 1 gives the canonical form $M_\mu = \omega^{\mu
\hat n^3}$ at prime $d \ge 5$. Three independent proofs that our locked
$q.\theta_2$ (quadratic $\hat J_z^2$) cannot realise it:
  1. Distinct eigenvalue count at d=3: 2 vs 3
  2. Parity symmetry: quadratic is parity-symmetric, cubic is not
  3. Polynomial degree invariance under linear relabelling

And `q.φ + q.θ₂` together give exactly the Clifford diagonal group
$\omega^{\alpha \hat n + \beta \hat n^2}$ (Campbell 2014 $\mathcal Z_{
\alpha,\beta}$) — Clifford-complete, magic-incomplete. To reach
universal unitaries on qudits, something has to give.

**Decision**: add **6th primitive** `q.θ₃ += δ` ($\exp(-i\delta \hat n^3)$,
cubic phase). At $\delta = -2\pi/d$ (prime $d \ge 5$) this is Campbell's
$M_1$, the canonical magic gate.

**The pleasant surprise**: at d=2, primitives 4 and 5 collapse naturally:
  - $\hat n^2 = \hat n$ on {0,1}, so `q.θ₂` becomes global phase (trivial)
  - $\hat n^3 = \hat n$ on {0,1}, so `q.θ₃` collapses to Rz-equivalent
The 6-primitive qudit set reduces **exactly** to the 4-primitive qubit
set at d=2. Rule 11 (CLAUDE.md: 4 primitives ONLY) is preserved at the
qubit specialisation; the two extra primitives are d>2-only.

**CV-limit sanity (P7)**: $\hat J_z^3$ in the Holstein-Primakoff limit
gives $\hat n^3$; conjugated by Ry(π/2) it becomes $\hat J_x^3 \sim
\hat x^3$ at large j — the canonical **GKP cubic-phase gate**, the
textbook non-Gaussian resource for universal CV (Gottesman-Kitaev-Preskill
2001). The qudit cubic primitive is precisely the right non-Gaussian
resource in the CV limit. P7 is enhanced, not strained.

**Level-structured design**: primitives stratify by Clifford hierarchy
level — Ry/Rz at level 1, $\hat n^2$ at level 2 (Clifford diagonal),
$\hat n^3$ at level 3 (magic). Higher levels don't form groups, so the
set is complete at 3 levels. This is a structural argument for stopping
at 6 primitives.

### Non-prime d gotcha

Watson 2015 Eq. 7 explicitly excludes d ∈ {2, 3, 6} from the clean
$\omega^{\hat n^3}$ form:
  - prime d ≥ 5: $M_1 = \omega^{\hat n^3}$, $\omega = e^{2\pi i/d}$
  - d = 3: $T_3 = \gamma^{\hat n^3}$, $\gamma = e^{2\pi i / 9}$ (Watson Eq. 7)
  - d = 2: standard qubit T = Rz(π/4)
  - d ∈ {4, 6, 8, 9, …}: open in literature. Filed as lit-gap bead.

### Orkan impact — feature request, not PR

User decision: Orkan-side native d-level statevector is a feature
request, not an immediate PR. Memory-bound, deep, subtle. Prepared PR
plan at `/home/tobiasosborne/Projects/orkan/docs/qudit-support-pr-plan.md`
(334 lines) + feature-request body at `/home/tobiasosborne/Projects/orkan/
ISSUES/qudit-support.md` — push to GH when `gh` re-authenticated.
Sturm v0.1 qudit ships on qubit-encoded fallback simulator.

### Beads filed

Epic `Sturm.jl-goi` description rewritten with locked-design summary. 15
new beads:

  * Lit-gap (P3, non-blocking v0.1):
    - `Sturm.jl-dcv` non-prime d magic gate
    - `Sturm.jl-egh` prime-power d via Galois F_{p^k}
    - `Sturm.jl-kba` composite-d MSD
    - `Sturm.jl-b9r` CV-limit formal derivation (Holstein-Primakoff → GKP)

  * Implementation spine (P2):
    - `Sturm.jl-9aa` QMod{d} type + prep primitive (renamed from QDit{d,W}
      post-session per user preference — see 'Naming: QDit → QMod' below)
    - `Sturm.jl-ak2` spin-j Ry/Rz primitives (q.θ, q.φ)
    - `Sturm.jl-os4` squeezing primitive (q.θ₂)
    - `Sturm.jl-mle` cubic-phase magic primitive (q.θ₃)
    - `Sturm.jl-p38` SUM entangler (a ⊻= b at d>2)
    - `Sturm.jl-nrs` qubit-encoded fallback simulator
    - `Sturm.jl-u2n` library gates: X_d!, Z_d!, F_d! QFT
    - `Sturm.jl-tws` library gate T_d! (per-d branch)
    - `Sturm.jl-70a` library gate QuditToffoli!
    - `Sturm.jl-csw` full-pipeline tests at d=3, d=5 (v0.1 acceptance)
    - `Sturm.jl-dhn` QECC prime-d trait (P3)

29 dep edges inserted via direct dolt SQL — **bd bug found**: `bd dep
add` and `bd blocked` query `wisp_dependencies` but the table is named
`dependencies` in the embedded Dolt install. Worked around; filed as a
known-issue for the next bd upgrade. Edges verified via join query.

### Dolt push blocked by GH secret scanning

`bd dolt push` fails because a historical blob (commit `5bf30ae` in dolt
blobstore) contains an OAuth token. Pre-existing issue, not caused by
this session. Unblock URL: `https://github.com/tobiasosborne/Sturm.jl/
security/secret-scanning/unblock-secret/3CitIms2IwRs2Ixan0CiUzUFuLk`.
User decision required (security judgement).

### Files touched this session

Surveys + downloads (`docs/physics/`):
  * `qudit_primitives_survey.md` (round 1, 343 lines + decisions pointer)
  * `qudit_magic_gate_survey.md` (round 2, with §8 locked decisions)
  * 20 new PDFs: Gottesman, Brylinski², Bartlett-deGuise-Sanders,
    Brennen-Bullock-O'Leary ×3, Muthukrishnan-Stroud, Howard-Vala,
    Farinholt, Wang review, de Beaudrap, Campbell 2014, Campbell-Anwar-
    Browne, Anwar-Campbell-Browne, Watson, Beverland et al., Krishna-
    Tillich, Prakash 2020 ×2, Veitch.

Orkan (separate repo, feature request):
  * `docs/qudit-support-pr-plan.md` (PR design doc, 334 lines)
  * `ISSUES/qudit-support.md` (GH issue body)

`WORKLOG.md`: this entry.

### Naming: QDit → QMod (late-session correction)

Initial survey + child beads used `QDit{d,W}` following the etymology of
"qudit" (qu + dit, a d-ary digit). User rejected this mid-session: the Q-
prefix convention parallels the **classical type name**, as in
QBool / `Bool` and QInt / `Int` — not the information-theoretic unit.

Rename: **`QDit{d,W}` → `QMod{d}`** for the single d-level wire, with
classical counterpart `Mod{d}` (from Julia's `Mods.jl`, representing
$\mathbb{Z}/d\mathbb{Z}$). The modular-arithmetic API matches SUM
semantics exactly.

The W parameter drops: single-wire primitives don't need a width. Where
registers of multiple qudits are wanted, the existing `QInt` type
extends to **`QInt{W,d}`** with d=2 default — d=2 recovers the existing
qubit `QInt{W}`, d>2 gives a W-digit base-d integer register with
mod-d ripple-carry arithmetic. **`QInt{W,d}` is deliberately not v0.1
qudit scope** (the acceptance suite `goi-tests-d35` uses single-qudit
gates + 2-qudit SUM only); filed as new P2 bead `goi-qint-d`.

`QBool` stays its own type at d=2 (not `QMod{2}`), same reason
Julia keeps `Bool` and `Mod{2}` separate — the logical API (`!`, `&&`,
`||`) differs from the arithmetic API (`+ mod 2`).

All survey docs, Orkan PR plan + ISSUE body, WORKLOG, and 6 goi-* beads
updated. No code changes — nothing had been implemented yet.

---

