# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M9 (bead Sturm.jl-8oo9, design
# `docs/design/m9-addq-inplace-perm-design.md` §3): the IN-PLACE-`Perm` COMPILER
# CONTRACT. Where M7's `oracle(f, x)` accumulates `f(x)` into a SEPARATE target
# (`|x⟩|t⟩ ↦ |x⟩|t⊕f(x)⟩`, input preserved — the `(★)` form), a registered
# library action such as `mulmod!` transforms its register IN PLACE:
# `|x⟩ ↦ |f(x)⟩` on the data block itself.
#
# THE MECHANISM (Bennett's Table 2 input-erasure pattern, specialised to
# compute/swap/uncompute-with-the-inverse; docs/physics/
# bennett_1973_logical_reversibility.md "Inverse-assisted in-place permutation",
# eq (3)). Given `f` and a SEPARATELY COMPILED `f⁻¹` (both through the EXISTING
# `_BENNETT_BACKEND` accumulate bridge — NOT `oracle`, which binds a live `x`):
#
#     |x⟩_D |0⟩_B |0⟩_A  --U_f-->   |x⟩_D    |f(x)⟩_B       |0⟩_A
#                        --SWAP-->  |f(x)⟩_D |x⟩_B          |0⟩_A
#                        --U_g-->   |f(x)⟩_D |x ⊕ g(f(x))⟩_B |0⟩_A            (3)
#
# `B` returns to |0⟩ for every `x` IFF `g∘f = id` on the FULL padded space `S_W`;
# then `C = U_g ∘ SWAP ∘ U_f` is a clean in-place `Perm` on `2W + max(A_f,A_g)`
# wires (shared ancilla pool — legal because `U_f` returns its ancillas to |0⟩
# before `U_g` runs). Using `adjoint(U_f)` after the swap would accumulate `f(f(x))`,
# not `f⁻¹(f(x)) = x` — the SEPARATELY COMPILED inverse is load-bearing (wm28 guard).
#
# VERIFICATION IS TIERED and happens BEFORE any quantum action (design §3.3, Δ1):
#   • Tier E (`W ≤ PERM_EQ_MAXW`): replay EACH compiled `Perm` classically on all
#     `2^W` inputs — check input preservation, ancilla-|0⟩, and BOTH directions of
#     the inverse (3-inv) exactly. Then replay the COMPOSITE (embedding tripwire).
#     No `isapprox`, no sampling.
#   • Tier P (any `W`): a CLOSED, compiler-owned structural proof
#     (`AbstractInplaceProof`; the modular family's `FullSpaceMulProof{N,W}` lives
#     in `src/library/modular.jl`) supplies inverse agreement analytically; faithful
#     compilation rests on the shipped M7 Bennett contract. A GENERIC pair at
#     `W > PERM_EQ_MAXW` is REJECTED loudly — finite probes are not a certificate.
#
# THE ARTIFACT is one frozen kernel `Perm`; it carries a `PermClean` certificate
# whose declared clean ports are the copy block `B` ∪ the shared ancilla pool `A`
# (PRD-v2 §4.1a, the second combinator route `compile_inplace_perm ⇒ PermClean`).
# MBU is excluded by construction (a `Perm` has no measurement node), so
# `ctrl^k(Perm) = Perm` in every context, `when` body, and control stack.
#
# CONSTRUCTION CHOKE POINT (mechanically enforced, like `_ctrl`): the ONLY
# constructor of a `CompiledInplacePerm` is the private `_compiled_inplace_perm`,
# and a boot lint (test/runtests.jl) asserts it appears in `src/` ONLY here.
#
# Physics/spec grounding: docs/physics/bennett_1973_logical_reversibility.md
# ("Inverse-assisted in-place permutation", eq (3)/(3-inv)); PRD-v2 §3.4 (the
# in-place action paragraph), §4.1a (the `PermClean` two-theorem bullet).

# --- Exceptions (fail-loud, named; thrown BEFORE any quantum action) -------

"""
    InverseContractError(W, x, img, back, direction)

The supplied `(f, finv)` pair is NOT a two-sided inverse on the full padded space
`S_W` (eq 3-inv): at input `x`, one direction's forward image `img` mapped back to
`back ≠ x`. No clean in-place `Perm` exists (eq 3 would leave the copy block dirty).
Raised by Tier-E verification BEFORE any allocation or application. `direction` is
`:g_after_f` (`finv∘f ≠ id`) or `:f_after_g` (`f∘finv ≠ id`).
"""
struct InverseContractError <: Exception
    W::Int
    x::Int
    img::Int
    back::Int
    direction::Symbol
end
Base.showerror(io::IO, e::InverseContractError) = print(io,
    "InverseContractError(W=$(e.W), direction=$(e.direction)): the supplied inverse " *
    "is not a two-sided inverse on the padded space S_W — at x=$(e.x), the forward " *
    "image $(e.img) maps back to $(e.back) ≠ $(e.x) (eq 3-inv). No clean in-place " *
    "Perm exists; verified BEFORE any quantum action.")

# --- Registered structural proofs (closed set; Tier P) ---------------------

"""
    AbstractInplaceProof

Supertype of the CLOSED set of registered, compiler-owned structural proofs that
discharge inverse agreement (eq 3-inv) ANALYTICALLY for `W > PERM_EQ_MAXW`, where
exhaustive replay is intractable (design §3.3, Tier P). "Registered" means: a
proof is NOT attachable to an arbitrary user closure through a keyword — each
concrete subtype generates BOTH callables from one immutable spec and validates
them by number theory. The modular family's `FullSpaceMulProof{N,W}` lives in
`src/library/modular.jl`. `public`, not exported.
"""
abstract type AbstractInplaceProof end

"""
    _validate_inplace_proof(proof, ::Val{W})

Validate a registered structural proof at width `W`, or fail loud. The fallback
rejects any object that is not a registered `AbstractInplaceProof` — an arbitrary
value cannot masquerade as a certificate (§3.4, no `check=false`). Concrete
subtypes add their own method (e.g. `FullSpaceMulProof`, `modular.jl`).
"""
_validate_inplace_proof(proof, ::Val{W}) where {W} = error(
    "verify_inverse_pair: object of type $(typeof(proof)) is not a registered " *
    "in-place inverse proof (AbstractInplaceProof). Above PERM_EQ_MAXW only a " *
    "closed structural proof is admissible — no sampling, no `check=false`.")

# --- Single-basis-state classical replay (gated by DATA width, not 2^n) ----

"""
    _replay_perm_basis(p::Perm, b) -> Int

Forward-replay `p`'s `MCX` generators on ONE computational-basis index `b`
(wire 1 = MSB: wire `c` holds bit `(b >> (n-c)) & 1`), returning the image index.
This is the inner loop of `denoted_permutation` for a single input — so it costs
`O(#gates)` and is gated by the DATA width `W` (we call it `2^W` times), NEVER by
`2^n` (which would blow up on the wide composite). The Tier-E budget (design §3.3).
"""
function _replay_perm_basis(p::Perm, b::Integer)
    n = p.n
    s = Int(b)
    @inbounds for g in p.gates
        fire = true
        for c in g.controls
            if ((s >> (n - c)) & 1) == 0
                fire = false
                break
            end
        end
        fire && (s ⊻= (1 << (n - g.target)))
    end
    return s
end

"""
    _oracle_image(c::CompiledOracle, x) -> (val, input_preserved, anc_clean)

The realized image `f(x)` a compiled accumulate oracle induces, read at the
PERMUTATION level (never a marginal — wm28): build the clean basis input
(input=`x` MSB-first via `in_positions`, output=0, ancilla=0), replay `c.perm`,
and extract the LSB-first output value plus the `(★)` witnesses (input preserved,
ancilla returned to |0⟩). The ground truth for Tier-E checks.
"""
function _oracle_image(c::CompiledOracle, x::Integer)
    n = c.n_wires
    inpos = c.in_positions[1]
    Wx = length(inpos)
    b = 0
    @inbounds for j in 1:Wx
        ((x >> (Wx - j)) & 1) == 1 && (b |= (1 << (n - inpos[j])))   # MSB-first bit j
    end
    img = _replay_perm_basis(c.perm, b)
    getbit(bb, wire) = (bb >> (n - wire)) & 1
    val = 0
    @inbounds for β in 0:(c.W - 1)
        val |= Int(getbit(img, c.out_positions[β + 1])) << β          # output LSB-first
    end
    xin = 0
    @inbounds for j in 1:Wx
        xin |= Int(getbit(img, inpos[j])) << (Wx - j)                 # input preserved?
    end
    anc_clean = all(getbit(img, a) == 0 for a in c.anc_positions)
    return (val = val, input_preserved = (xin == x), anc_clean = anc_clean)
end

# --- The verified inverse pair (two-phase API; design §1 Δ2) ----------------

"""
    VerifiedInversePair{W}

The proof-carrying result of `verify_inverse_pair`: the callables `f`/`finv`, the
Bennett-`kwargs`, the verification `tier` (`:exhaustive` or `:proof`), and — for
Tier E — the two already-compiled `CompiledOracle`s (`cf`/`cg`, reused by
`compile_inplace_perm` so the artifact is compiled once). Tier P defers
compilation (`cf === cg === nothing`) and carries the structural `proof`. `public`,
not exported; NOT a surface construct — reached only through registered library
actions such as `mulmod!`.
"""
struct VerifiedInversePair{W}
    f::Any
    finv::Any
    cf::Union{Nothing,CompiledOracle}
    cg::Union{Nothing,CompiledOracle}
    kw::Any
    tier::Symbol
    proof::Any
end

"""
    verify_inverse_pair(f, finv, ::Val{W}; proof=nothing, kwargs...) -> VerifiedInversePair{W}

Verify that `finv` is a two-sided inverse of `f` on the full padded space
`S_W = {0,…,2^W-1}` (eq 3-inv), BEFORE any quantum action, choosing the tier by
width (design §3.3):

- `W ≤ PERM_EQ_MAXW`: **Tier E** — Bennett-compile both callables through the
  existing `_BENNETT_BACKEND`, replay each compiled `Perm` on all `2^W` inputs,
  and check input preservation, ancilla-|0⟩, and BOTH inverse directions exactly.
  First counterexample → `InverseContractError`. No sampling, no `isapprox`.
- `W > PERM_EQ_MAXW`: **Tier P** — a registered structural `proof` is REQUIRED
  (a generic pair is rejected loudly, `proof=nothing` → error); it is validated
  analytically and compilation is deferred to `compile_inplace_perm`.

`kwargs` pass identically to both compilations (`auto_self_reversing=false` is
forced by the backend). `public`, not exported.
"""
function verify_inverse_pair(f, finv, ::Val{W}; proof = nothing, kwargs...) where {W}
    W ≥ 1 || throw(ArgumentError("verify_inverse_pair: width W=$W must be ≥ 1."))
    kw = kwargs
    if W ≤ PERM_EQ_MAXW
        backend = _BENNETT_BACKEND[]
        backend === nothing && error(
            "verify_inverse_pair: the Bennett backend is not loaded — add " *
            "`using Bennett` (the reversible-compile frontend is a weak dependency).")
        cf::CompiledOracle = backend(f, W, kw)
        cg::CompiledOracle = backend(finv, W, kw)
        _tier_e_check(cf, cg, W)
        return VerifiedInversePair{W}(f, finv, cf, cg, kw, :exhaustive, proof)
    else
        proof === nothing && error(
            "verify_inverse_pair: width W=$W exceeds PERM_EQ_MAXW=$PERM_EQ_MAXW, so " *
            "exhaustive inverse verification is intractable and NO registered proof " *
            "was supplied. A generic inverse pair at W>$PERM_EQ_MAXW is REJECTED — " *
            "finite probes are not a certificate (§3.4). Supply a closed structural " *
            "proof (e.g. `FullSpaceMulProof`).")
        _validate_inplace_proof(proof, Val(W))
        return VerifiedInversePair{W}(f, finv, nothing, nothing, kw, :proof, proof)
    end
end

"""
    _tier_e_check(cf, cg, W)

Tier-E obligation (design §3.3): each compiled `Perm` faithfully realizes its
spec (input preserved, ancilla clean, full-width output) AND the two realized
maps are two-sided inverses on all of `S_W`. Exact integer semantics; first
counterexample → `InverseContractError`.
"""
function _tier_e_check(cf::CompiledOracle, cg::CompiledOracle, W::Int)
    cf.W == W || error(
        "verify_inverse_pair: forward oracle output width $(cf.W) ≠ W=$W — the " *
        "in-place contract admits only full-width accumulated outputs (§3.4).")
    cg.W == W || error(
        "verify_inverse_pair: inverse oracle output width $(cg.W) ≠ W=$W.")
    N = 1 << W
    imgf = Vector{Int}(undef, N)
    imgg = Vector{Int}(undef, N)
    for x in 0:(N - 1)
        rf = _oracle_image(cf, x)
        rf.input_preserved || error("verify_inverse_pair: forward oracle does not preserve input at x=$x.")
        rf.anc_clean       || error("verify_inverse_pair: forward oracle leaves a dirty ancilla at x=$x (not |0⟩).")
        imgf[x + 1] = rf.val
        rg = _oracle_image(cg, x)
        rg.input_preserved || error("verify_inverse_pair: inverse oracle does not preserve input at x=$x.")
        rg.anc_clean       || error("verify_inverse_pair: inverse oracle leaves a dirty ancilla at x=$x (not |0⟩).")
        imgg[x + 1] = rg.val
    end
    for x in 0:(N - 1)
        gf = imgg[imgf[x + 1] + 1]
        gf == x || throw(InverseContractError(W, x, imgf[x + 1], gf, :g_after_f))
        fg = imgf[imgg[x + 1] + 1]
        fg == x || throw(InverseContractError(W, x, imgg[x + 1], fg, :f_after_g))
    end
    return nothing
end

# --- The compiled artifact + its PRIVATE construction choke point -----------

"""
    CompiledInplacePerm{W}

The frozen in-place-permutation artifact: one composite kernel `Perm` on
`2W + max(A_f,A_g)` wires realizing `|x⟩_D ↦ |f(x)⟩_D` with the copy block `B` and
ancilla pool `A` returned to |0⟩ (eq 3). `scratch_width = W + max(A_f,A_g)` is the
number of fresh |0⟩ wires `_apply_inplace_perm!` allocates (`B ∪ A`);
`clean_ports` are the declared clean positions `{W+1 : 2W+A}` (the `PermClean`
justification, §4.1a). Deeply immutable (M8/TR5 — its `Perm` is a frozen tuple).
Minted ONLY through the private `_compiled_inplace_perm` (boot-lint gated to this
file, like `_ctrl`). `public`, not exported, NOT a surface construct.
"""
struct CompiledInplacePerm{W}
    perm::Perm
    scratch_width::Int
    clean_ports::Vector{Int}

    # PRIVATE constructor — the choke point. `compile_inplace_perm` is the only caller.
    global _compiled_inplace_perm(::Val{W}, perm::Perm, sw::Integer,
                                  cp::AbstractVector{<:Integer}) where {W} =
        new{W}(perm, Int(sw), Int[Int(c) for c in cp])
end

nwires(c::CompiledInplacePerm) = nwires(c.perm)

"""
    permclean_cert(c::CompiledInplacePerm) -> PermClean

The `PermClean` certificate the artifact carries (design §4.1a, the second
combinator route): its declared clean ports are the copy block ∪ the shared
ancilla pool (`c.clean_ports`, as `PortID`s), justified by the inverse-pair
compute/swap/uncompute theorem (eq 3), NOT Bennett's input-preserving `(★)`. No
new `CleanCert` variant. `public`.
"""
permclean_cert(c::CompiledInplacePerm) = PermClean(Tuple(PortID(p) for p in c.clean_ports))

# --- Composite assembly: embed U_f, width-W swap, embed U_g -----------------

"""
    _embed_map(c::CompiledOracle, W) -> Vector{Int}

The renumbering `Bennett wire → composite slot` for embedding a compiled accumulate
oracle into the in-place layout (D=`1:W`, B=`W+1:2W`, A=`2W+1:…`), with input = D
and output = B: input bit `j` (MSB-first) → slot `j`; output bit `β` (LSB-first) →
copy-block slot `2W-β` (so equal bit-index D/B wires align for the swap); ancilla
`i` → shared-pool slot `2W+i`. The `Perm` keeps Bennett's own numbering — this
map only renumbers positions into the composite; there is NO second bit reversal
(the M7 `_role_tables` remains the ONLY MSB/LSB remap — wm28 guard).
"""
function _embed_map(c::CompiledOracle, W::Int)
    c.W == W || error("in-place embed: oracle output width $(c.W) ≠ W=$W.")
    n = c.n_wires
    m = Vector{Int}(undef, n)
    inpos = c.in_positions[1]
    length(inpos) == W || error("in-place embed: oracle input width $(length(inpos)) ≠ W=$W.")
    @inbounds for j in 1:W
        m[inpos[j]] = j                       # D slot j (MSB-first)
    end
    @inbounds for β in 0:(W - 1)
        m[c.out_positions[β + 1]] = 2W - β     # B slot for bit β
    end
    @inbounds for (i, a) in enumerate(c.anc_positions)
        m[a] = 2W + i                          # shared ancilla pool
    end
    return m
end

"""
    _embed_gates!(dst, c::CompiledOracle, W)

Push `c`'s `MCX` generators, renumbered by `_embed_map`, onto `dst`.
"""
function _embed_gates!(dst::Vector{MCX}, c::CompiledOracle, W::Int)
    m = _embed_map(c, W)
    for g in c.perm.gates
        push!(dst, MCX(Int[m[ci] for ci in g.controls], m[g.target]))
    end
    return dst
end

"""
    _append_swap!(dst, W)

Append the genuine width-`W` bitwise swap of D (`1:W`) and B (`W+1:2W`) — three
`MCX` (CNOTs) per bit position, so the data physically ends in the declared D
ports (design §3.4). Equal bit-index wires are `s` (D) and `s+W` (B).
"""
function _append_swap!(dst::Vector{MCX}, W::Int)
    for s in 1:W
        push!(dst, MCX(Int[s], s + W))
        push!(dst, MCX(Int[s + W], s))
        push!(dst, MCX(Int[s], s + W))
    end
    return dst
end

"""
    _compiled_oracles(pair) -> (cf, cg)

The two `CompiledOracle`s for the composite: reused from Tier-E verification when
present, else compiled now (Tier P — the deferred case, `W > PERM_EQ_MAXW`).
"""
function _compiled_oracles(pair::VerifiedInversePair{W}) where {W}
    pair.cf !== nothing && return (pair.cf::CompiledOracle, pair.cg::CompiledOracle)
    backend = _BENNETT_BACKEND[]
    backend === nothing && error("compile_inplace_perm: the Bennett backend is not loaded.")
    return (backend(pair.f, W, pair.kw)::CompiledOracle, backend(pair.finv, W, pair.kw)::CompiledOracle)
end

"""
    compile_inplace_perm(pair::VerifiedInversePair{W}) -> CompiledInplacePerm{W}

Compose the verified `(f, f⁻¹)` into ONE frozen kernel `Perm` by
compute/swap/uncompute (eq 3): embedded `U_f` (D→B), a genuine width-`W` swap of
D and B, then embedded `U_g` (D→B). Shared ancilla pool of size `max(A_f,A_g)`
(legal because `U_f` cleans its ancilla before `U_g` runs). For `W ≤ PERM_EQ_MAXW`
a composite self-check replays the assembled `Perm` on all `2^W` clean inputs,
asserting `D=f(x)`, `B=0`, `A=0` — the embedding/swap tripwire (wm28 class).
Minted through the private `_compiled_inplace_perm` choke point. `public`.
"""
function compile_inplace_perm(pair::VerifiedInversePair{W}) where {W}
    cf, cg = _compiled_oracles(pair)
    (cf.W == W && cg.W == W) || error(
        "compile_inplace_perm: oracle output widths ($(cf.W), $(cg.W)) ≠ W=$W — the " *
        "in-place contract admits only full-width accumulated outputs (§3.4).")
    A = max(length(cf.anc_positions), length(cg.anc_positions))
    n = 2W + A
    gates = MCX[]
    _embed_gates!(gates, cf, W)     # 1. U_f: D → B
    _append_swap!(gates, W)         # 2. genuine width-W swap of D, B
    _embed_gates!(gates, cg, W)     # 3. U_g = U_{f⁻¹}: D → B  (cleans B iff g∘f=id)
    perm = Perm(n, gates)
    clean_ports = collect((W + 1):n)        # copy block B ∪ ancilla pool A
    scratch_width = W + A                    # B (W) + pool (A)
    compiled = _compiled_inplace_perm(Val(W), perm, scratch_width, clean_ports)
    W ≤ PERM_EQ_MAXW && _composite_selfcheck(perm, cf, W, n)
    return compiled
end

"""
    _composite_selfcheck(perm, cf, W, n)

Embedding tripwire (Tier E): replay the composite `Perm` on every clean input
`|x⟩_D|0⟩_B|0⟩_A`, asserting the data block ends in `f(x)` and `B ∪ A` return to
|0⟩. Single-basis replay (`2^W` calls, gated by DATA width `W`, never `2^n`).
"""
function _composite_selfcheck(perm::Perm, cf::CompiledOracle, W::Int, n::Int)
    for x in 0:((1 << W) - 1)
        b = 0
        @inbounds for j in 1:W
            ((x >> (W - j)) & 1) == 1 && (b |= (1 << (n - j)))     # D slot j (MSB)
        end
        img = _replay_perm_basis(perm, b)
        d = 0
        @inbounds for j in 1:W
            d |= Int((img >> (n - j)) & 1) << (W - j)
        end
        fx = _oracle_image(cf, x).val
        d == fx || error(
            "compile_inplace_perm: composite realizes $d at x=$x, expected f(x)=$fx " *
            "— embedding/swap bug (wm28 class).")
        @inbounds for s in (W + 1):n
            ((img >> (n - s)) & 1) == 0 || error(
                "compile_inplace_perm: composite leaves dirty scratch (slot $s) at " *
                "x=$x — the copy block/ancilla pool B∪A did not return to |0⟩.")
        end
    end
    return nothing
end

# --- Application (the whole mechanism; mirrors `_apply_oracle!`) -------------

"""
    _apply_inplace_perm!(ctx, data::NTuple{W,WireID}, compiled::CompiledInplacePerm{W}) -> ctx

Apply the in-place permutation to `data`: allocate `compiled.scratch_width` fresh
|0⟩ wires (the copy block `B` then the ancilla pool `A`, uncontrolled), assemble
the length-`2W+A` apply-list (`data` = D = slots `1:W`, scratch = slots `W+1:…`),
apply the composite `Perm` through the control-aware `_act!` choke point
(`ctrl^k(Perm) = Perm`), then free the scratch with `_free_clean!` (assert-|0⟩,
NEVER measure). The scratch is born and dies inside a `region()`, so an error
mid-apply cannot leak slots. Under `when` the non-firing branch leaves scratch
|0⟩; the firing branch cleans it by eq (3) — release is valid in both.
"""
function _apply_inplace_perm!(ctx::AbstractContext, data::NTuple{W,WireID},
                              compiled::CompiledInplacePerm{W}) where {W}
    for w in data
        _assert_live(ctx, w)
    end
    n = nwires(compiled.perm)
    region() do
        scratch = WireID[allocate!(ctx) for _ in 1:compiled.scratch_width]  # B (W) + pool (A)
        wt = Vector{WireID}(undef, n)
        @inbounds for j in 1:W
            wt[j] = data[j]
        end
        @inbounds for j in 1:compiled.scratch_width
            wt[W + j] = scratch[j]
        end
        _act!(ctx, compiled.perm, wt)                # ctrl^k(Perm) = Perm (control-aware)
        for w in scratch
            _free_clean!(ctx, w)                     # assert-|0⟩-then-drop; PermClean under when
        end
    end
    return ctx
end
