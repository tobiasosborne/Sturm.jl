# Session 95 — 2026-07-10 — M0 through M6 SHIPPED (orchestrated)

## M6 SHIPPED (80g6) — 14,711 tests green; ALL FOUR SIGN PINS PASS

QInt{W} (wire1=MSB, AbstractQubit supertype + WireRef borrow slices),
QFT kernel node (ctrl(P(θ)) through the existing choke point — zero new
lowering code; F†=conj(F), same ladder, negated angles), two-world
arithmetic (the dispatch fact: += on the view mutates-returns-self =
modulation D₋ₐ; += on the bare register allocates fresh = the lost-
binding trap), strict-mode detector completed WITH escape tracking
(returned handles now survive region exit — an improvement), D2 suite
(dual(x)[i] throws with the corrected CSW wording). Sign pins: add!(0,1)
→ 1 ✓; superpose!; x̂+=a; Int(dual(x))==a ✓ (wrong sign reads −a);
dual(dual(x))===x zero-ops ✓ vs QFT² → 2^W−n ✓ (the normative
integer-negation signature — M4's blind-pinned conjugation direction now
empirically verified).

Also this round: CSW distillation found + I fixed a RESIDUAL r6 citation
inversion in PRD D2 prose (maximality → Tyson/Nielsen; CSW = small-core).

### M6 gotchas
1. apply!(X) leaves a global −i per set bit (ker Ad drops φ) — invisible
   physically, breaks raw-amplitude test compares; test tooling preps via
   _emit_x!. 2. Strict lost-binding is undecidable at region granularity
   without ESCAPE TRACKING (return-value handles marked survivors);
   s=x+a;return s is genuinely indistinguishable from x=x+a;return x —
   only parent-consumed/parent-returned are reliable negatives. 3. Two
   consecutive docstrings = "cannot document expression" precompile trap.
   4. Julia ≥1.11: public symbols appear in names(M) — test exportedness
   via Base.isexported. 5. QFT adjoint needs no ladder reversal (H/SWAP
   real, F symmetric).

---

# (earlier: M0–M5 + audit)

## M5 SHIPPED (o5yh) — 13,822 tests green; §8.1 CLOSED; deferred teleport one-run Choi PASSES

First genuine 3+1 architectural split: A = control-choke inside apply!;
B = `_act!` ABOVE apply! (action family only; preps + view sandwiches
uncontrolled). RULED FOR B — Delorme Eq 16 licenses the uncontrolled
sandwich (both = C(VWV†); 3 vs ~10 emissions), uncontrolled prep = §3.9
alloc=|e_G⟩ clean-ancilla entry, zero edits to frozen apply!/ad.jl.
Adopted from A: three-funnel guardrail completeness proof (embedded as
the 11-entry table in when.jl) + clean-ancilla necessity/sufficiency.

Gate: `choi(teleport_deferred,1) ≈ J(id)` ONE DM run, J[1,4]=0.5
(coherent — wm28-diagonal ruled out structurally). Guardrails live:
cast/ptrace under control = loud error (the §8.1 NAMED regression);
guard-externality sees through views both sides; clean-ancilla witness =
FULL |1⟩ marginal (implementer deviation, CORRECT — A's proof was full-
marginal; strictly safer, catches uncontrolled non-|0⟩ prep in the
control-0 branch); when opens its own region so body ancillas get the
witness while the control is still stacked.

### M5 gotchas
1. The 6 lint-reserved tokens (`Ctrl(`, `_ctrl(`, `\bcontrolled\b`,
   `orkan_cx`, `ccall`, `single_from_mat`) fire in COMMENT PROSE too —
   "uncontrolled" is safe (no word boundary), " controlled" is not.
2. `_act!` closes the §8.1 fusion hole BY CONSTRUCTION (ctrl-wrap before
   apply! ⇒ always ≥2 wires ⇒ never the 1q fusion path under control).
3. ptrace! has no QBool method (WireID only) — future surface wiring note.
4. Double-throw masking accepted (body error hidden by witness error in
   finally; both fail-loud).
5. Guardrail messages differentiate naturally: Bool(control) hits G1 at
   the cast; not!(control) hits G2 in _act! — no special-casing.
6. IOUs: M7 must prove MBU-exclusion-under-ctrl + when-controlled oracle;
   M8 must wire cases/noise into _assert_no_control + the streaming≡
   materialized law test (hooks + comments in place).

---

# (earlier: M0–M4 + audit)

## M4 SHIPPED (3nld) — 13,772 tests green; TELEPORTATION WORKS

**The wm28 bug class is dead.** §7.1 teleport (zero gates: casts + ⊻= +
dual + Julia-Bool corrections) transcribed verbatim; Eager statistical
full-channel gate over {|0⟩,|1⟩,|+⟩,|−⟩,|i⟩}, N=1024 each: PERFECT
recovery on every probe — the |i⟩ Y-basis probe reads 1024/1024 where a
diagonal-only (wm28) teleport reads ≈512. CZ symmetry + X↔Z swap verified
at Choi level (harness extended to nin=2).

3+1 highlights: both proposers converged (two nominal wrapper types, zero
kernel edits, _conj(V,g)=adjoint(V)∘g∘V via M1 ∘, |+⟩↦false free);
RATIFIED teleport split — M4 = Eager statistical probes, M5 = one-run
Choi(teleport_deferred) §7.1b (DM Bool throws by M3 design; no M4 path).

### M4 gotchas (spec-grade)
1. **Immutable-struct `===` is structural in Julia — the adjtrans pattern
   does NOT deliver `dual(q) !== dual(q)`** (Base's transpose(A)===transpose(A)
   is true!). Honoring §3.3's normative identity claim requires
   `mutable struct DualView`; field never reassigned, mutability purely
   for identity. ALL future register views (x[i], QInt duals, M6) must be
   mutable for the same reason. PRD §3.3's "adjtrans pattern" wording
   conflates the two — flag for Tobias / next PRD pass.
2. The `\bcontrolled\b` choke-point lint fires on lowercase prose in
   surface docstrings — reword to "CZ"/"ctrl(…)"; the word is reserved
   under kernel/+orkan/.
3. `_conj(H,X)` lands on exactly Z (phase and all) → ctrl(Z) hits the
   native cz fast path: the conjugation route emits ONE Orkan call.
4. Implementer added `_here` cross-context guard to the action family
   (proposals had missed it — same hole QBool.ctx exists to close).
5. Teleport gate asserts hits==N exactly (recovery is exact) — stronger
   than the directive's ±3σ.

---

# (earlier: M0–M3 + audit)

## M3 SHIPPED (77m2) — 13,711 tests green, ~25s

Full 3+1. Both proposers INDEPENDENTLY put the P2 warning on
`Base.convert(Bool, ::QBool)` (the compiler-inserted path) with explicit
`Bool(q)` silent — and B proved `if q` is a TypeError in Julia, never an
auto-cast, so convert IS the implicit site. Adjudication: B's handle shape
(QBool stores ctx — WireIDs are per-context monotone, bare-id handles
would silently cross contexts), B's prep-by-composition (Rz(φ)∘Ry(2asin√p)
via the fuzz-tested M1 ∘, A's analytic column as the test oracle), A's
exact-X for QBool(::Bool) (not Ry(π) — latent-phase trap), and the big
one: **DM Bool(q) THROWS** (A's trajectory-sample position REJECTED —
DM-executes-channels is r6 doctrine; scalar-on-channel-context is the D3
token problem, M8). First surface exports: QBool, plus, minus, magic_T.

The wm28 gate is now a live test: `choi(pinch)` on the COHERENT Bell
probe is diagonal AND ≉ choi(identity) — the class of test that v0.1's
Z-marginal teleportation test could never be.

### M3 gotchas
1. QBool NOT parametrized on context (QBool{C} would metastasize into
   QInt{W,C}); ctx is an abstract field — handles are never hot-loop.
2. `_measure_wire!` must `_flush_all!` (not flush-one-wire) before
   collapse — same conservative path as the M2 trace.
3. Test files using `public`-but-unexported names (eager/density) must
   import them explicitly — passing only via an earlier include's imports
   is a trap (made M3 tests self-sufficient).
4. Choi partial-trace endianness pinned in ONE function (_ptrace_keep,
   keep[1]=MSB); analytic references written to the same ordering.
5. P2 warning deliberately NOT maxlog-deduped: collapse is a physical
   event; per-site dedup also makes @test_logs non-deterministic.
6. choi harness cap = 2·nin+2 (a channel that allocates its output before
   consuming its input needs the headroom).

---

# (earlier: M0 + M1 + M2 + audit)

## M2 SHIPPED (dc6i) — 13,573 tests green, ~20s

Full 3+1: 2 Opus proposers (semantics-first / systems-first, heavy
convergence: identical ZYZ formulas, ABC+p(φ), one state_t per context,
no single_from_mat) → synthesis → Opus implementer → orchestrator review
(hand-probed β≈π fold, sqrt_u2 half-angle, native-fast-path soundness,
k≥3 clean-ancilla phase placement — no defects). Barenco 1995 distilled
FIRST (rule 4): real lemma numbering is ABC = 4.3+5.1+5.2+Cor 5.3; the
"iff W ∈ SU(2)" hinge of Lemma 5.1 IS the v0.1 phase-bug mechanism;
clean-vs-borrowed ancilla split (phase-carrying MCU needs clean |0⟩ —
Lemma 7.11; borrowed OK for SU(2)/Perm — Cor 7.4).

Shipped: src/types/wire.jl (minimal WireID), src/orkan/{ffi,state,ad}.jl,
src/context/{abstract,eager,density,regions}.jl; exports @context/region/
ptrace!; new boot lints (ccall only under src/orkan/, single_from_mat
NOWHERE, Ctrl( construction only in kernel/ctrl.jl). Phase-exactness
verified at denotation level for k∈{1,2,3} incl. gphase and NEG_I≠I2.
ccall counts: U2=3 (ZYZ), k=1 ctrl-U2=10, k=2=32 (sqrt-V), k=3=14 (ladder).

### M2 gotchas (implementer, verbatim-worthy)

1. **`state_init` ZERO-allocates — does NOT set |0…0⟩**; must state_set(0,0,1).
   Centralized in `_state_new`. DM likewise needs ρ[0,0]=1.
2. **ccall library slot cannot be a local variable** — use a global
   `const Ref{String}` directly: `@ccall LIBORKAN[].f(...)`; set in __init__.
3. Orkan is little-endian (qubit j = bit j); q(ctx,wire) is a plain slot
   map, no reversal; X-on-MSB→high-bit regression pins it.
4. **The choke-point grep-lints read comments too** — the word "controlled"
   in prose trips them outside kernel/+orkan/; emitters moved into ad.jl
   and three comments reworded. Feature, not bug (lint = no discussion of
   controlled lowering outside the sanctioned files).
5. **Proposal A's β≈π ZYZ fold order was BACKWARDS** (rz;ry) — correct
   time-order is ry(π);rz(α) (= matrix Rz(α)·Ry(π)); caught by implementer,
   verified by orchestrator by hand. 3+1 works.
6. sqrt_u2 free-axis branch must trigger ONLY at essentially-exact −I
   ((w+1)²+|v|² < CHART_EPS²), else V∘V≈u fails near the pole.
7. `using LinearAlgebra` in tests passes under include() but fails under
   Pkg.test()'s clean env until declared in [extras]/[targets].
8. ctx.rng is an untyped field (::Any): AbstractRNG lives in Random which
   src/ may not depend on; nothing → Base rand().
9. DM exact ptrace implemented as the reset channel (Kraus {|0⟩⟨0|,|0⟩⟨1|})
   via channel_1q — survivors' reduced state is the exact partial trace.

---

# (earlier: M0 + M1 + audit)

## M1 kernel SHIPPED (c52g + puig) — 12,752 tests green

Full 3+1 round: 2 independent Opus proposers → orchestrator adjudication →
Opus implementer → orchestrator review (1 real defect found + fixed).

**Design synthesis** (proposals preserved at `docs/design/m1-kernel-proposal-{A,B}.md`):
base = A (laws-first: denoted matrix IS the semantics, fast paths are
fuzz-anchored optimizations; largest-magnitude sign pivot; circdist;
renorm inside ∘ at 2^-40; checked ctor + unchecked `_u2`), from B:
same-k `Ctrl∘Ctrl` fusion (§4.2 homomorphism made executable), **NO ctrl
catch-all** (a generic fallback would silently wrap future non-unitary
channel nodes — P4 forbids control-on-measurement; MethodError is correct),
plain `Matrix{ComplexF64}` (no Mat2, no StaticArrays). Both proposers
independently derived IDENTICAL gate-constant tables and independently
chose flat-count `Ctrl{V}` + variable-arity MCX ({X,CX,CCX} is NOT closed
under ctrl — plan baseline was wrong there).

**Orchestrator review catch (the +1 earning its keep):** the fast
quaternion-level `≈` had a rare FALSE NEGATIVE — two float representations
of the same element whose top-two quaternion components are nearly tied
with opposite signs can pick different `_signfix` pivots and land in
different ℤ₂ representatives (e.g. `(c+δ, −(c−δ),0,0,0.2)` vs its mirror
`(−(c−δ), c+δ,0,0,0.2+π)`, c=1/√2: verdict was `false`). Fix: fall back to
denoted-matrix comparison when the fast path rejects (sound fast path +
exact fallback = complete predicate). Regression test `T-canon-tie`;
pre-fix failure verified empirically. Random fuzz would essentially never
hit this — constructed adversarial cases are load-bearing.

**Implementer gotchas (verbatim-worthy):**
1. Julia 1.12.5 Base provides matrix `*`, `kron`, `isapprox(::AbstractArray)`
   WITHOUT LinearAlgebra — only identity (`I`) needs it; hand-rolled `_eye`
   keeps src/ dependency-free.
2. Include-order vs choke-point-lint collision: `ctrl(::Tensor)/(::Seq)`
   must live in ctrl.jl (they call `_ctrl`), so `Tensor`/`Seq` STRUCTS are
   defined in u2.jl, methods in algebra.jl.
3. `rem2pi(Float64(π), RoundNearest)` may return ±π; both denote −I and
   circdist absorbs it — never assume +π.
4. The `|φ|≤2π` invariant lets ∘ use one conditional subtract
   (`_foldphase`) instead of rem2pi (Payne–Hanek, too slow per-product);
   rem2pi confined to circdist + public ctor.
5. `@allocated` at global scope reports phantom ~96B for `U2∘U2`; inside a
   typed function the 10^6-compose chain is 0 bytes (isbits).

## M2 pre-step: Orkan ABI audit DONE (qmes → docs/design/orkan-abi-audit-m2.md)

- **D7 answered:** pure statevector path has NO general-1q entry — ZYZ
  (rz;ry;rz + p, 3 ccalls) is forced; the θ≈0/π singularity branch lives at
  the FFI boundary exactly as §4.1/D7 mandate. `single_from_mat` exists but
  is HEADER-PRIVATE + tiled-DM-only + coupled to compile-time LOG_TILE_DIM
  — DO NOT BIND (no header diff would reveal its drift).
- **24/24 v0.1 ccalls VERIFIED-STILL-CURRENT** (0 drifted, 0 removed);
  struct layouts byte-identical. v0.1 FFI shapes re-portable as-is.
- **Controlled ops: only CX/CY/CZ/CCX native** — all Ctrl{U2}/MCX/MCU
  decomposition is kernel-side (confirms single-choke-point architecture;
  no Orkan shortcut exists).
- **Orkan errors are fatal exit()** (qs_error_t is decorative) — every
  wrapper MUST validate Julia-side pre-ccall or a bad index kills the
  process. No C-side RNG/measurement — sampling stays Julia-side (prefer
  bulk unsafe_wrap over per-amplitude state_get). Threading env-var-only
  (OMP_NUM_THREADS, ceiling 16 on this device).

---

# (earlier the same session)

Orchestrated session: main agent coordinating subagents (1 implementer for
M0, 4 researchers for distillations, then 2 independent proposers + 1
implementer for the M1 3+1 round).

## M0 scaffold SHIPPED (23o1 + 2o0y)

- `Project.toml` (uuid fcbab5b2-…, v0.2.0-dev, julia = "1.11", zero deps,
  Test in extras), `src/Sturm.jl` (module skeleton, commented export/public
  stanzas per convention 8), `test/runtests.jl` (physics-cite lint) +
  `test/test_prd_examples.jl` (PRD doctest lint). All AGPL-headed.
- `Pkg.test()` green: 16 pass / 16 total on Julia **1.12.5**. ⚠ Compat
  floor 1.11 NOT verified locally (only 1.12.5 installed) — CI gap, carry
  to the CI bead when one exists.
- **Doctest lint: 11/11 julia-tagged PRD blocks parse AND lower**, count
  pinned (`@test length(blocks) == 11` — bump deliberately when the PRD
  gains examples).

### Gotchas (implementer + orchestrator review)

1. **`Meta.lower` does not throw on most lowering errors** — it returns
   `Expr(:error, msg)`, possibly nested in `:toplevel`. Only
   undefined-macro errors throw. A lint checking only "did it throw" is
   blind to B1-class bugs (invalid assignment targets). The lint walks the
   lowered tree for buried `:error` nodes. Verified empirically:
   `Meta.lower(Main, Meta.parse("dual(q) ⊻= r"))` → `Expr(:error,
   "invalid assignment location …")`, no exception.
2. **Orchestrator review catch:** implementer shipped `@test nrefs == 0`
   in the physics-cite lint — fires on ANY citation, valid or dangling;
   would have broken the first M1 commit with a *valid* citation. Replaced
   with `@info` reporting; the real lint is the per-reference `isfile`
   @test.
3. Stale untracked v0.1 `Manifest.toml` at repo root deleted; regenerated
   Manifest references only stdlibs (no-deps constraint confirmed).
4. The invalid-Julia traps (`dual(q) ⊻= r` etc.) appear only in prose /
   non-julia fences in the PRD — extraction lints exactly ```julia fences.
5. Combining-diacritic identifiers (`x̂`, `q̂`) parse+lower fine on 1.12.

## M1 distillations SHIPPED (kvtb) — 4 papers → docs/physics/

All four with PDFs obtained (incl. Stuelpnagel via the public-domain NASA
reprint, Internet Archive item `nasa_techdoc_19640008534`). Key findings a
future implementer MUST read before touching the kernel:

1. **`wharton_koch_quaternion_bloch.md`** — PINS the operator convention
   `(i,j,k) ↔ −i(σx,σy,σz)`, i.e. `U(q) = w·I − i(xσx+yσy+zσz)`.
   ⚠ **TRAP:** the paper's own Table 1 / Eq. 6 use an idiosyncratic
   spinor-map axis relabeling (`X↔k, Y↔−j, Z↔i`) — do NOT transcribe
   those labels into the operator representation. X=i (φ=π/2), Y=j, Z=k,
   H=(i+k)/√2; verified `q_H² = −1_quat` so H∘H lands on the −q
   representative of +I — matches §4.1 exactly.
2. **`delorme_control_as_constructor.md`** (CaaC 2508.21756) — grounds
   ctrl functoriality (`C(g∘f)=C(g)∘C(f)`), dagger compat, and Eq. 16 IS
   the §4.2 reassociation law. ⚠ `C(f⊗g) ≠ C(f)⊗C(g)` — ctrl does NOT
   distribute over ⊗. ⚠ Do NOT cite this paper for the black-box no-go
   (that stays Bădescu–Panangaden / Gavorová).
3. **`tang_wright_2025_controlled_unitaries.md`** — Thm 1.1 is the formal
   "control makes global phase physical" statement (PRD §4.2 citation
   checked: accurate). Nuance: it's a negative result (decontrolling);
   Sturm uses the contrapositive. Not a source for quaternion mechanics.
4. **`stuelpnagel_1964_rotation_parametrization.md`** — Thm 2
   (no global nonsingular 3-chart of SO(3), Brouwer invariance-of-domain)
   grounds quaternion-IR + ZYZ-only-at-Orkan-boundary (D7); Thm 1 grounds
   the double cover. ⚠ Pagination cited by NASA reprint pages, not SIAM
   pp. 422–430. ⚠ Euler singularity LOCATION is convention-dependent
   (paper: roll/pitch/yaw θ=±π/2; Sturm ZYZ: θ≈0/π) — existence is the
   theorem, location is ours.

## Beads/dolt sync surgery

- Remote `refs/dolt/data` was ahead (session 94 pushed enriched beads from
  another machine); local dolt merge hit ONE row conflict (23o1: remote
  enriched description vs local claim). Resolved `--theirs` + re-claimed.
  Procedure: `cd .beads/embeddeddolt/Sturm_jl && dolt pull origin main`
  (bd's own `bd dolt pull` can't pass a branch and errors), resolve,
  commit, `dolt push origin main`.
- `hn90` (remote, parse-only spec) superseded by `2o0y` (parse+lower).
- Stranded v0.1 QSVT beads `4ceh`/`5lu4`/`grq5` moved in_progress → open
  with STRANDED-BY-REBOOT notes (they return via reimport gates, M12+).

## M1 3+1 round LAUNCHED (c52g)

Two independent Opus proposers running (angles: algebraic-laws-first vs
mechanical-sympathy/API-seams), both required to adopt the Wharton–Koch
pinned convention and the ⊗-non-distributivity caveat. Implementer next.
