# Session 95 — 2026-07-10 — M0 shipped + M1 distillations + 3+1 kernel round launched (orchestrated)

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
