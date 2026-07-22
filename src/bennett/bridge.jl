# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M7 (bead Sturm.jl-7a0v): the Bennett
# bridge — surface construct 7, `oracle(f, x)`, and its accumulate law
# `b ⊻= oracle(f, x)` (D9). This is the CORE half: it names NO Bennett type. The
# `f → Perm` compile lives in `ext/SturmBennettExt.jl` (the weakdep extension);
# core owns the accumulate PHYSICS and the `Base.xor` methods, which are testable
# without Bennett (build an `OracleQuery` by hand from a known `Perm`).
#
# ── WHAT `oracle(f, x)` DENOTES ──────────────────────────────────────────
# Bennett's theorem (logical reversibility — compute/copy/uncompute,
# docs/physics/bennett_1973_logical_reversibility.md) turns an ordinary Julia
# `f : ℤ_{2^W} → ℤ_{2^W}` into a reversible PERMUTATION `P_f` on
# `n = W(input) + W(output) + A(ancilla)` wires acting, on the computational
# basis, as
#       P_f : |x⟩_in |t⟩_out |0⟩_anc  ↦  |x⟩_in |t ⊕ f(x)⟩_out |0⟩_anc      (★)
# for EVERY `t` — input preserved, ancilla restored to |0⟩, output XOR-
# accumulated. `(★)` holds for arbitrary `t` because NO output wire is ever read
# as a control (D9; re-asserted per-circuit in the extension) — XOR-accumulation
# is `t ↦ t ⊕ f(x)` by linearity (Nielsen–Chuang §1.4.4), independent of `t`.
# `P_f` is a phase-free unitary ⇒ it is exactly a kernel `Perm` (kernel/perm.jl).
#
# ── THE KICKBACK LAW IS THE CNOT LAW LIFTED (D9) ─────────────────────────
# `b ⊻= oracle(f, x)` denotes, by (★) with the output block bound to `b`'s wires,
#       |x⟩ |b⟩  ↦  |x⟩ |b ⊕ f(x)⟩
# — the SAME `Base.xor` action family as `a ⊻= b` (surface construct 3): `a ⊻= b`
# is the `W=1, f=id, P_f = CNOT` case (D9: "not a separate construct"). With
# `b = |−⟩` (DJ/BV) this is `(−1)^{f(x)}|x⟩|−⟩` — phase kickback with NO new
# vocabulary. `oracle` (7) PRODUCES the query value; `⊻=` (3) APPLIES it; the
# value itself is never a surface noun (7 produces, 3 consumes).
#
# ── CONTROL-AWARENESS FOR FREE (the M5 IOU, discharged) ──────────────────
# A `when`-wrapped oracle flows through the single `ctrl` choke point unchanged,
# because `ctrl(Perm) = Perm` (kernel/perm.jl closure — the reversible corner is
# closed under control; docs/physics/delorme_control_as_constructor.md). So
# `b ⊻= oracle(f, x)` under a depth-`k` control stack lowers, via the EXISTING
# `_act!` (surface/when.jl), to `ctrl^k(P_f)` — still a `Perm`. M7 writes ZERO
# new ctrl-lowering code. Measurement-based uncompute cannot arise: a `Perm` is
# phase-free-unitary by construction, so the §3.4 MBU-exclusion holds structurally
# (there is nothing MBU-flavoured to construct).
#
# Physics/spec grounding: PRD-v2 §3.4/D9 (accumulate), §3.4 (MBU exclusion),
# §4.2 (ctrl choke point), §7.4/§7.5 (DJ/BV), D14 (circuit-only bridge). Physics:
# docs/physics/bennett_1973_logical_reversibility.md,
# docs/physics/delorme_control_as_constructor.md.

# --- The compiled query value (x-independent) + the bound query -----------

"""
    CompiledOracle

The x-INDEPENDENT compilation of `f` at width `W`: the reversible permutation
`P_f` (a kernel `Perm` on `n_wires`, carrying Bennett's own wire numbering
verbatim) plus the ROLE TABLES that pin which `Perm` wire plays each register
bit. It is a `Perm` + an addressing — the `(★)` denotation, nothing more; it
names no Bennett type (built by the extension, held by core).

Fields:
- `perm`          — `P_f` as MCX generators, `1:n_wires` = Bennett numbering.
- `n_wires`       — total wires of `perm` (input + output + ancilla).
- `in_positions`  — `[reg][bit j MSB-first] → Bennett wire index`; one inner
                    vector per input register (M7 ships a single register).
- `out_positions` — `[bit β LSB-first, 0..W-1] → Bennett wire index`.
- `W`             — the Bennett output/compute width (the `b`-target ceiling).
- `anc_positions` — Bennett ancilla wire indices (return to |0⟩, `(★)`).

The MSB/LSB remap that fills `in_positions`/`out_positions` lives in EXACTLY ONE
function (`_role_tables`, in the extension) — the single-remap discipline that
keeps a silent bit-reversal (wm28 class) out of the gate list.
"""
struct CompiledOracle
    perm::Perm
    n_wires::Int
    in_positions::Vector{Vector{Int}}
    out_positions::Vector{Int}
    W::Int
    anc_positions::Vector{Int}
end

"""
    OracleQuery{Xs<:Tuple}

The opaque query value returned by `oracle(f, x)` (construct 7): a
`CompiledOracle` paired with the LIVE input handle(s) `xs`. `x` stays live and
unchanged after `⊻=` (input preservation, `(★)`), so binding `q = oracle(f, x)`
and applying `q` to several targets reuses the one compiled `Perm` — value-level
reuse is the only caching M7 ships. `public`, never exported, never a surface
noun: users write `oracle(f, x)` and `⊻=` it, never spelling the type.
"""
struct OracleQuery{Xs<:Tuple}
    compiled::CompiledOracle
    xs::Xs
end

# --- The weakdep backend hook (mirrors Bennett's own write-once VM hook) ---

"""
    _BENNETT_BACKEND

Write-once hook (`Ref{Any}`) the `SturmBennettExt` extension fills in its
`__init__` with the `f → CompiledOracle` compiler. Absent the extension it stays
`nothing`, and `oracle` errors loud ("load Bennett"). Mirrors Bennett's own
`_REVERSIBLE_VM_BACKEND` write-once backend registration — the compiler frontend
is behind the weakdep, the lowering vehicle and application are native (keeps
LLVM.jl out of `using Sturm`; CLAUDE.md conv 4).
"""
const _BENNETT_BACKEND = Ref{Any}(nothing)

"""
    oracle(f, x::QInt{W}; kwargs...) -> OracleQuery      # surface construct 7

The Bennett bridge: compile the ordinary Julia function `f` to a reversible
`Perm` (EAGERLY — errors naming `f` surface at THIS call site, not a downstream
`⊻=`) and pair it with the live register `x`. Apply it with `b ⊻= oracle(f, x)`
(the D9 accumulate, `|x⟩|b⟩ ↦ |x⟩|b ⊕ f(x)⟩`); `x` stays live.

`W ∈ 1:64` (Bennett's native ceiling); `f` computes mod `2^W`, matching
`QInt{W}`'s ℤ_{2^W} ring. Compile-time rejections (all loud, at `oracle()`): a
function needing the BennettVM (unbounded loop / dynamic memory) — D14 circuit-
only bridge; a data-dependent loop whose convergence flag cannot be uncomputed;
`W ∉ 1:64`. `kwargs` pass through to `reversible_compile` (e.g. `signed=…`,
`add=:cuccaro`). Any `x` type other than `QInt{W}` is a `MethodError` (no
catch-all on the argument — P9); QBool-input and multi-register `oracle(f, xs…)`
are designed-in but deferred past M7 (follow-on bead).

Physics: docs/physics/bennett_1973_logical_reversibility.md (compute/copy/
uncompute; ancillas return to |0⟩). Worked examples: PRD-v2 §7.4 (Deutsch–Jozsa),
§7.5 (Bernstein–Vazirani).
"""
function oracle(f, x::QInt{W}; kwargs...) where {W}
    _here(x)                                  # fail-fast: bind/verify x's context
    backend = _BENNETT_BACKEND[]
    backend === nothing && error(
        "oracle(f, x): the Bennett backend is not loaded — add `using Bennett` " *
        "alongside `using Sturm` to activate the `SturmBennettExt` extension " *
        "(the reversible-compile frontend is a weak dependency; CLAUDE.md conv 4).")
    compiled::CompiledOracle = backend(f, W, kwargs)
    return OracleQuery(compiled, (x,))
end

# --- The `Base.xor` application methods (return-value discipline) ---------
#
# Following actions.jl's "THE RETURN-VALUE DISCIPLINE IS THE WHOLE GAME": every
# method MUTATES and RETURNS ITS FIRST HANDLE, so `b = xor(b, q)` (what `b ⊻= q`
# lowers to) is a true in-place no-op rebind; `x` stays live. There is NO
# `xor(::OracleQuery, ::AbstractQubit)` — the query is always the RHS; a swapped
# call is a `MethodError` (fail-loud, no catch-all — P9).

"""
    xor(b::AbstractQubit, q::OracleQuery) -> b       # `b ⊻= oracle(f, x)`, Wb = 1

The 1-bit target case (DJ/BV): `f`'s value `f(x) ∈ {0,1}` accumulates into `b`'s
single wire; the high `W−1` output bits go to fresh scratch asserted |0⟩ (the
zero-tail witness — an under-sized target for a value `≥ 2` is a LOUD error, not
a silent decohere). With `b = |−⟩` this is the `(−1)^{f(x)}` phase kick (§7.4).
Returns `b` (the in-place rebind no-op); `x` stays live.
"""
function Base.xor(b::AbstractQubit, q::OracleQuery)
    ctx = _here(b)
    _apply_oracle!(ctx, q, (b.wire,))
    return b
end

"""
    xor(b::QInt{Wb}, q::OracleQuery) -> b            # `y ⊻= oracle(f, x)`, Wb bits

The multi-bit target case: the low `Wb` output bits of `f(x)` accumulate into
`b` (MSB-first), the high `W−Wb` tail goes to fresh scratch asserted |0⟩. `Wb`
must be `≤ W` (the Bennett output width) — a wider target is a loud error.
`Wb == W` is the modular-arithmetic case (no tail, no witness cost). Returns `b`;
`x` stays live.
"""
function Base.xor(b::QInt{Wb}, q::OracleQuery) where {Wb}
    ctx = _here(b)
    W = q.compiled.W
    Wb ≤ W || error(
        "oracle target too wide: target is QInt{$Wb} but `f` produces a $W-bit " *
        "output block (its compute width). A target wider than the oracle output " *
        "is a bug — narrow `b`, or widen the oracle's input width `W`.")
    _apply_oracle!(ctx, q, b.wires)
    return b
end

# --- The wire-allocation choreography (the whole mechanism) ---------------

"""
    _apply_oracle!(ctx, q::OracleQuery, targets::NTuple{Wb,WireID}) -> ctx

Assemble the length-`n_wires` apply-list from the role tables (input slots → `x`,
low output slots → `targets`, high output tail + ancilla → fresh |0⟩ scratch),
apply `q.compiled.perm` through the control-aware `_act!` choke point, then free
the scratch with `_free_clean!` (assert-|0⟩-then-drop-slot, NEVER measure). The
scratch is born and dies inside a `region()`, so an error mid-apply cannot leak
slots (its region-exit trace cleans/collapses them).

Fail-loud order: input liveness/context (`_here`/`_assert_live`), then the
register-level b∩x disjointness check (front-running `apply!`'s generic aliasing
backstop with a b-vs-x message, §8.4). The kickback target must be a DISTINCT
register from `x` (else the output would alias the input, `(★)` broken).

Physics: docs/physics/bennett_1973_logical_reversibility.md (input preservation
P3, clean ancilla). Control-awareness inherited: `_act!` builds `ctrl^k(Perm) =
Perm` (docs/physics/delorme_control_as_constructor.md) — the M5 `when`-oracle IOU.
"""
function _apply_oracle!(ctx::AbstractContext, q::OracleQuery, targets::NTuple{Wb,WireID}) where {Wb}
    c = q.compiled
    # Input liveness + context (a consumed/dead `x` is a loud error BEFORE any op).
    xwires = Set{WireID}()
    for x in q.xs
        _here(x)
        for w in x.wires
            _assert_live(ctx, w)
            push!(xwires, w)
        end
    end
    # b ⊄ x: the kickback target must be a DISTINCT register (else output aliases input).
    for t in targets
        t in xwires && error(
            "oracle target aliases its input register: wire $t is shared between " *
            "the `⊻=` target `b` and the oracle input `x`. The kickback target must " *
            "be a DISTINCT register (D9, §8.4) — the output block cannot overlap the " *
            "preserved input block.")
    end
    Wb ≤ c.W || error("oracle target width $Wb exceeds output width $(c.W)")  # backstop
    tail = c.W - Wb
    region() do                                   # scratch is born and dies here (§3.9)
        nanc = length(c.anc_positions)
        scratch = WireID[allocate!(ctx) for _ in 1:(nanc + tail)]   # fresh |0⟩, uncontrolled
        wt = Vector{WireID}(undef, c.n_wires)
        # Input block: MSB-first bit j of register `reg` → its remapped Bennett slot.
        for (positions, x) in zip(c.in_positions, q.xs)
            @inbounds for j in eachindex(positions)
                wt[positions[j]] = x.wires[j]
            end
        end
        # Output block: low `Wb` bits → `b` (MSB-first), high tail → scratch.
        si = 0
        @inbounds for β in 0:(c.W - 1)
            bslot = c.out_positions[β + 1]
            if β < Wb
                wt[bslot] = targets[Wb - β]       # LSB-index β ↔ MSB-first wire (Wb − β)
            else
                si += 1
                wt[bslot] = scratch[si]
            end
        end
        # Ancilla block → fresh scratch.
        @inbounds for a in c.anc_positions
            si += 1
            wt[a] = scratch[si]
        end
        # THE CHOKE POINT (control-aware): empty stack ⇒ apply!; depth k ⇒
        # ctrl^k(Perm) = Perm, controls prepended. Vector-typed seam (A §4).
        _act!(ctx, c.perm, wt)
        # Free scratch cleanest-possible: assert |0⟩ then drop slot (NO measurement).
        # The tail wires are the zero-tail witness (under-sized `b`); the ancilla
        # wires are the Bennett-clean witness. Both LOUD if dirty (wm28 guard).
        for w in scratch
            _free_clean!(ctx, w)
        end
    end
    return ctx
end

"""
    _free_clean!(ctx, w::WireID)

Free a scratch wire the cleanest way: ASSERT it is a disentangled |0⟩ (the M5
`_clean_ancilla_assert!` full-|1⟩-marginal witness, control-agnostic), then drop
its slot back to the allocator. It NEVER measures — a `deallocate!` outside a
control stack would measure-and-discard, spending an RNG draw and, on a wrongly
DIRTY wire (an under-sized `b`, a broken Bennett ancilla), SILENTLY collapsing an
`x`-entangled superposition (wm28 class). A dirty wire here is LOUD, uniform under
and outside `when`. The already-freed wire is skipped by the enclosing region's
exit trace (it checks `haskey(wire_to_slot, ·)`), so no double-free.
"""
function _free_clean!(ctx::AbstractContext, w::WireID)
    _clean_ancilla_assert!(ctx, w)                # LOUD if the |1⟩-marginal ≥ CLEAN_EPS
    core = _core(ctx)
    # M8 tee-tracing (design §5): if this Bennett-clean scratch is freed inside a
    # `when` body, record its release with a `PermClean` cert so the body-exit seal
    # matches the recorded `AllocN` and trusts Bennett's `(★)` (structural, not the
    # marginal above). Zero-overhead outside `when`.
    if !isempty(core.when_frames)
        frame = core.when_frames[end]
        haskey(frame.w2pid, w) && _tee_record_trace!(ctx, w, PermClean((frame.w2pid[w],)))
    end
    slot = core.wire_to_slot[w]
    delete!(core.wire_to_slot, w)
    _return_slot!(core, slot)
    nothing
end
