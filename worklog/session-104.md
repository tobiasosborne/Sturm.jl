# Session 104 — 2026-07-27 — session-103 dangling items cleared (F3 ruled into the PRD)

Short session. Tobias: "clear up the dangling stuff from previous session.
take a small step that can land within 30 mins then commit and push."

Session 103 ended with three distillations written but **never committed**, an
85-line worklog addition never committed, and two follow-ups its own text
described as done that were not: a P1 conflict recorded as "(P1, filed)" with
**no bead behind it**, and a distillation gate with no tracker entry. All four
are closed out here.

## The `bd` claim was wrong — check the tracker, not the prose

`worklog/session-103.md` says of the environment-ordering conflict: "⚠ F3 —
environment-ordering conflict (P1, filed)". **It was not filed.** `bd search
"environment ordering"`, `"dilation"`, `"Knill"` all return nothing, and the
newest open bead predates the finding (`42cs`, 2026-07-25). A worklog sentence
in the past tense is not evidence that a bead exists — the finding survived only
because it was written down in prose, which is exactly the failure mode
CLAUDE.md rule 0 exists to prevent. **Cross-check "filed" claims against `bd
list` before trusting them.**

## F3 resolved in place rather than re-filed

The conflict: synthesis S10 pins **environment wires leading (MSB)**,
`Ṽ[i·d + s + 1, t + 1] = Kᵢ[s+1, t+1]`; PRD-v2 §9 line 2281 wrote the isometry
in Watrous's order, `V|ψ⟩ = Σᵢ Kᵢ|ψ⟩|i⟩_E` — **system leading**. Same channel
(they differ by `Y⊗Z → Z⊗Y`, invisible to `Tr_E`), **different matrix**.

S10 is a *ruled* design decision and M11 is unblocked on it, so this is
follow-through on a ruling, not a new decision — filing a bead to re-decide it
would have been churn. Three PRD edits instead:

1. **§4.3 gains a fourth normative bullet on the Stinespring fallback: "The
   environment wires LEAD."** States the transposition of the source's ordering
   *explicitly as a transposition*, gives S10's three reasons (contiguous
   `1:d` env-zero columns ⇒ block read not strided extraction; `apply!`'s
   position-1-is-MSB; `Ctrl`'s leading-wires-are-controls, which in the
   executable tier is the *same* wire — a mixed-unitary dilation IS the
   multiplexed control `Σᵢ|i⟩⟨i|_E ⊗ Uᵢ`), records that Cor. 2.24's freedom
   therefore reads `Ṽ′ = (U ⊗ 1_sys)Ṽ` in Sturm's layout rather than the book's
   `(1_Y ⊗ U)A`, and names the sentinel: **the pin is testable only on a
   non-unital asymmetric channel** — amplitude damping sees the swap, a Pauli
   channel cannot.
2. **§9's Watrous entry gains an ordering warning** so the quoted book-order
   isometry cannot be mistaken for Sturm's layout: *"do not 'correct' the code
   back to the book."* Without this a future agent WILL, and the
   `KRAUS-RECONSTRUCT` contract test — true only in S10's layout — breaks
   silently.
3. **§4.4's stratum-2 theorem now says which of its claims are derived.** All
   three are true; none is quoted verbatim. Cor. 2.23/2.24 give a **unitary on
   a shared index alphabet**, so zero-padding is the trivial reduction *to* that
   hypothesis (Watrous does not take it), and the partial-isometry form is Cor.
   2.24 **plus** an embedding into a common environment (Cor. 2.27(5) + p. 191).
   "Minimal Kraus rank = Choi rank" needs a **two-part** citation: existence
   from Cor. 2.21 / Thm 2.22(5),(7) / Cor. 2.27(4),(6), the converse **only**
   from §3.3.4 p. 191. Both `— forthcoming, §9` markers on Watrous are dropped;
   the Eastin–Knill one correctly stays.

## Distillation gate is now a real edge in the graph — `nms1` blocks `qmpo`

Three of six §9 distillations remain owed (`knill_laflamme_1997_qec_conditions`,
`chiribella_2009_quantum_combs`, `eastin_knill_2009_no_universal_transversal`).
The rule-4 boot lint greps `src/` and asserts every cited `docs/physics/*.md`
resolves, so **M11 slices 5–6 cannot cite them until they exist** — that is a
hard gate, and it is now `bd dep add Sturm.jl-qmpo Sturm.jl-nms1` rather than a
paragraph. Both partial mitigations session 103 found are carried into PRD §9
and the bead so the next agent does not re-derive them: Knill–Laflamme's physics
is already local as **Gottesman §2.3 eq. (2.10)** (necessary *and* sufficient,
attributed — only the projector form belongs to the KL paper, so retargeting is
a normative edit); and combs has a real on-disk locator in **Watrous Exercise
2.6(b)(c) pp. 121–122** (credited to CDP at p. 123) that is **exercise strength,
unproved**, so it cannot substitute without mis-attribution.

§9 entries are now marked ✅/⬜ per file — three landed, three owed.

## I re-derived the repetition-code note rather than trusting it (rule 9)

`repetition_code_effective_noise.md` is an in-repo derivation note, so nothing
external backs it. Independent exact-rational enumeration (`Fraction`, all
`4³ = 64` Pauli patterns, syndrome `f(x) = (x₁⊕x₂, x₂⊕x₃)`, table correction,
logical class `a = majority(x')`, `b = z₁⊕z₂⊕z₃`) reproduces **(P7)–(P9)
exactly** at `p ∈ {1/100, 1/10, 3/10, 1/2, 3/5, 1}`, including the pinned
`p = 1/10` tuple `(6887/8000, 29/8000, 29/8000, 211/1600)` and the endpoint
`depolarizing(1) ↦ (¼,¼,¼,¼)`; `p_L^X = 3p²−2p³` and
`p_L^Z = 3p(1−p)²+p³ = (1−(1−2p)³)/2` also check out (`61/250` at `p = 1/10`,
both `= 1/2` at `p = 1/2` — the break-even crossing). Weights sum to 1 at every
point. The note's own convention warning is real and now restated in PRD §9:
these numbers are **specific to `depolarizing(p) : ρ ↦ (1−p)ρ + p·1/2`** and
every one of them changes under the `(p/3)ΣPρP` convention.

## Gate run

No `src/` change, so the physics-cite lint is untouched by construction. PRD
edits added **no fenced ```julia block**, verified by a standalone parse pass
(13 fences, 0 failures — matching the session-99 pin of 13), so convention 9
holds without paying for a full `Pkg.test()` boot.
