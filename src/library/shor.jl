# Shor's algorithm — order-finding and factoring.
#
# Ground truth: Nielsen & Chuang §5.3 (docs/physics/nielsen_chuang_5.3.md).
# Test matrix: N=15, all 7 coprime bases a ∈ {2, 4, 7, 8, 11, 13, 14}.
#
# This file hosts the three independent Sturm.jl implementations
# (value-oracle lift, phase-estimation HOF, controlled-U^{2^j} cascade)
# plus their shared classical post-processing (continued-fraction
# convergents, period extraction, reduction to factors). Classical helpers
# are module-private (`_shor_*` prefix).

# ═══════════════════════════════════════════════════════════════════════════
# Classical helpers (shared by all three implementations)
# ═══════════════════════════════════════════════════════════════════════════

"""
    _shor_convergents(num::Integer, den::Integer) -> Vector{Rational{Int}}

Continued-fraction convergents of `num/den`. Returns the finite sequence
[p₀/q₀, p₁/q₁, …, p_M/q_M] where p_k/q_k = [a₀; a₁, …, a_k] and
[a₀; a₁, …, a_M] is the CF expansion of `num/den`. The last convergent is
always exactly `num/den` (in lowest terms).

Ref: Nielsen & Chuang §5.3.1 Box 5.3, Eq. (5.49) ff.
"""
function _shor_convergents(num::Integer, den::Integer)::Vector{Rational{Int}}
    den > 0 || error("_shor_convergents: denominator must be positive, got $den")
    num >= 0 || error("_shor_convergents: numerator must be non-negative, got $num")

    if num == 0
        return Rational{Int}[0 // 1]
    end

    # CF coefficients: num/den = [a₀; a₁, a₂, …].
    a, b = Int(num), Int(den)
    coeffs = Int[]
    while b != 0
        q, r = divrem(a, b)
        push!(coeffs, q)
        a, b = b, r
    end

    # Convergents via the standard recurrence:
    #   p_k = a_k · p_{k−1} + p_{k−2},  with p_{−1}=1, p_{−2}=0
    #   q_k = a_k · q_{k−1} + q_{k−2},  with q_{−1}=0, q_{−2}=1
    h_m2, h_m1 = 0, 1
    k_m2, k_m1 = 1, 0
    convs = Rational{Int}[]
    for c in coeffs
        h = c * h_m1 + h_m2
        k = c * k_m1 + k_m2
        push!(convs, h // k)
        h_m2, h_m1 = h_m1, h
        k_m2, k_m1 = k_m1, k
    end
    return convs
end

"""
    _shor_period_from_phase(y_tilde::Integer, t::Integer, N::Integer) -> Int

Given the counting-register measurement `ỹ ∈ [0, 2ᵗ)` and the modulus `N`,
extract the candidate period `r`. Uses continued-fraction convergents of
`ỹ / 2ᵗ` (Theorem 5.1, Eq. 5.48) and returns the denominator of the
largest convergent with `1 < denominator < N`. The trivial outcome
`ỹ = 0` returns `r = 1` so callers see it as a no-op that must be retried.
"""
function _shor_period_from_phase(y_tilde::Integer, t::Integer, N::Integer)::Int
    y_tilde == 0 && return 1
    two_t = 1 << Int(t)
    convs = _shor_convergents(y_tilde, two_t)

    r_candidate = 1
    for c in convs
        d = denominator(c)
        if 1 < d < N
            r_candidate = Int(d)
        elseif d >= N
            break
        end
    end
    return r_candidate
end

"""
    _shor_factor_from_order(a::Integer, r::Integer, N::Integer) -> Vector{Int}

Reduction step of §5.3.2 (step 5): given candidate order `r` of `a` mod
`N`, return a non-trivial factorisation `[p, q]` of `N` with `p*q = N`
and `1 < p, q < N`, or `Int[]` if the reduction fails (odd r, r=0, or
`a^{r/2} ≡ ±1 mod N` per Theorem 5.3).
"""
function _shor_factor_from_order(a::Integer, r::Integer, N::Integer)::Vector{Int}
    r <= 0 && return Int[]
    isodd(r) && return Int[]

    half = powermod(Int(a), Int(r) ÷ 2, Int(N))
    (half == 1 || half == N - 1) && return Int[]

    for candidate in (gcd(half - 1, N), gcd(half + 1, N))
        if 1 < candidate < N
            return sort!([Int(candidate), Int(N) ÷ Int(candidate)])
        end
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Implementation A — value-oracle lift (N&C Exercise 5.14 / Eq. 5.47)
# ═══════════════════════════════════════════════════════════════════════════
#
# The idiom: write modular exponentiation as plain Julia `powermod(a, k, N)`
# and hand it to `oracle(f, k)` from the Bennett bridge. The second register
# starts at |0⟩ (not |1⟩ as in §5.3.1) per Exercise 5.14 — Bennett's reversible
# construction is already compute-copy-uncompute, so the "into |0⟩" form drops
# out naturally.
#
# Circuit shape:
#     counter (t qubits) |0⟩ ─ superpose! ─┬──────────── interfere! ── measure
#                                         │
#     output (t qubits)  |0⟩ ──────── oracle(a^k mod N) ── discard!
#
# The discard! of the output register is the post-measurement trace that
# collapses `k` onto the coset `{k : a^k mod N = f₀}` for some random f₀;
# inverse QFT + measurement then samples `s/r` to precision 2^{−t}.

"""
    shor_order_A(a::Int, N::Int; t::Int=4) -> Int
    shor_order_A(a::Int, N::Int, ::Val{t}) where {t}

Order of `a` modulo `N` via the "maximal Julia lift" idiom. The modular
exponential `k ↦ aᵏ mod N` is a plain Julia closure handed to
[`oracle_table`](@ref), which classically tabulates 2ᵗ values and emits
them via Babbush-Gidney QROM.

Why `oracle_table` and not `oracle`? `powermod`'s LLVM IR contains
control flow and stdlib call edges that Bennett's symbolic lowering
cannot resolve (Session 24: "Undefined SSA variable: %__v2"). For small
`t`, classical evaluation + QROM is strictly cheaper than any symbolic
path — `O(2ᵗ)` Toffoli, T-count independent of output width — so this is
the idiomatic choice, not a workaround.

Algorithm (N&C §5.3.1, Exercise 5.14 / Eq. 5.47):
  1. Prepare counter `k` = |0⟩ on `t` qubits; `superpose!` → uniform.
  2. `y = oracle_table(k -> powermod(a, k, N), k, Val(L))` — fresh
     output register; a single controlled table lookup.
  3. `discard!(y)` — trace out output, which collapses `k` onto a coset
     of the period `r`.
  4. `interfere!(k)` — inverse QFT on the counter.
  5. `ỹ = Int(k)`; continued-fractions → candidate period.

`t` counter qubits, `L = ⌈log₂ N⌉` output qubits. For `N = 15`, `L = 4`;
`t = 4` resolves peaks at `{0, 4, 8, 12}` for `r = 4` and `{0, 8}` for
`r = 2` exactly.

Ref: Nielsen & Chuang §5.3.1, Exercise 5.14, Eq. 5.47, Box 5.4.
See `docs/physics/nielsen_chuang_5.3.md`.
"""
function shor_order_A(a::Int, N::Int, ::Val{t}; verbose::Bool=false) where {t}
    gcd(a, N) == 1 || error("shor_order_A: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_A: a=$a must satisfy 1 ≤ a < N=$N")
    L = max(1, ceil(Int, log2(N)))

    ctx = current_context()
    verbose && @info "shor_order_A: a=$a, N=$N, t=$t, L=$L" live_qubits=_live_qubits(ctx)

    k_reg = QInt{t}(0)
    superpose!(k_reg)
    verbose && @info "  after superpose!(k_reg)" live_qubits=_live_qubits(ctx)

    y_reg = oracle_table(k -> powermod(a, k, N), k_reg, Val(L))
    verbose && @info "  after oracle_table (peak)" live_qubits=_live_qubits(ctx) total_allocated=ctx.n_qubits

    discard!(y_reg)
    verbose && @info "  after discard!(y_reg)" live_qubits=_live_qubits(ctx)

    interfere!(k_reg)
    y_tilde = Int(k_reg)
    verbose && @info "  measured ỹ=$y_tilde after interfere!" live_qubits=_live_qubits(ctx)

    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && @info "  continued-fraction decode" ỹ=y_tilde φ=(y_tilde//(1<<t)) r=r
    return r
end

shor_order_A(a::Int, N::Int; t::Int=4, verbose::Bool=false) =
    shor_order_A(a, N, Val(t); verbose=verbose)

"""
    _live_qubits(ctx::AbstractContext) -> Int

Count live qubits on an EagerContext (n_qubits − length(free_slots)). Returns
-1 for non-Eager contexts so verbose logging stays non-fatal on Tracing/Density.
"""
_live_qubits(ctx::EagerContext) = ctx.n_qubits - length(ctx.free_slots)
_live_qubits(::AbstractContext) = -1

"""
    shor_factor_A(N::Int; max_attempts::Int=16) -> Vector{Int}

Factor composite `N` using order-finding implementation A. Returns
`[p, q]` with `p · q = N` and `1 < p ≤ q < N`, or `Int[]` if every
attempt hits the Theorem 5.3 failure case (`a^{r/2} ≡ ±1 mod N`) or a
trivial-period outcome.

Implements the classical reduction of N&C §5.3.2:
  1. If `N` is even, return `[2, N÷2]`.
  2. (Perfect-power check skipped — `N = 15` passes trivially.)
  3. Random `a ∈ [2, N−1]`; if `gcd(a, N) > 1`, return the factor.
  4. `r ← shor_order_A(a, N)`.
  5. If `r` is even and `a^{r/2} ≢ ±1 mod N`, return
     `gcd(a^{r/2} ± 1, N)`; else retry.
"""
function shor_factor_A(N::Int; max_attempts::Int=16)
    N >= 2 || error("shor_factor_A: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_A(a, N)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Implementation B — phase-estimation higher-order (§5.3.1 verbatim)
# ═══════════════════════════════════════════════════════════════════════════
#
# Lifts Nielsen & Chuang §5.3.1 directly: write the modular-multiplication
# unitary U|y⟩ = |a·y mod N⟩ (Eq. 5.36) as a plain Julia subroutine and hand
# it to `phase_estimate(U!, |1⟩_L, Val(t))`. The HOF already handles the
# controlled-U^{2^j} cascade (Fig. 5.4 / Eqs. 5.40–5.43) by invoking `U!`
# exactly `2^{j-1}` times under each counter-qubit's control — that control
# stack auto-propagates through `when(ctrl)` into every gate the mulmod emits
# (QROM + CNOTs), so we never write an explicit controlled gate.
#
# The |1⟩_L initial state is the §5.3.1 trick (Eq. 5.44):
#
#     (1/√r) Σ_s |u_s⟩ = |1⟩_L,
#
# so phase estimation samples s uniform in {0, …, r−1}. The classical
# continued-fractions decoder (shared with impl A) extracts r.
#
# ── _shor_mulmod_a!: reversible "multiply by a mod N" on a QInt{L} register ──
#
# The tricky bit is realising U reversibly *in-place* — i.e. leaving the
# caller's register handle holding the transformed value on the same physical
# wires. N&C Eq. 5.36 treats U as identity on y ∈ {N, …, 2^L−1}, which makes
# y ↦ a·y mod N (augmented with identity outside {0, …, N−1}) a bijection on
# the full 2^L-dimensional space and therefore unitary.
#
# Construction (compute-copy-uncompute with swap-through):
#
#   Let f(y) = (y < N) ? (a·y mod N) : y               (forward, bijection)
#   Let g(z) = (z < N) ? (a⁻¹·z mod N) : z             (inverse, g ∘ f = id)
#
#   1. Allocate fresh |0⟩^L register z.
#   2. QROM(f): z ⊻= f(y), giving state |y⟩|f(y)⟩.
#   3. QROM(g): y ⊻= g(z) = g(f(y)) = y, giving state |0⟩|f(y)⟩.
#   4. Half-swap wires z ↔ y_reg via 2L CNOTs (source known-zero, so full
#      3-CNOT swap is unnecessary): state |f(y)⟩|0⟩ on (y_reg, z).
#   5. Deallocate z (now |0⟩, guaranteed by step 4).
#
# Per call: L fresh ancillae momentarily (steps 1–4), 2L CNOTs for the
# half-swap, plus the two QROM circuits (O(2^L) Toffoli each via
# Babbush–Gidney unary iteration). Circuits are content-hash-cached in
# `_ORACLE_TABLE_CACHE` so the 2^t − 1 invocations during phase estimation
# compile them exactly twice (once f, once g).
#
# Auto-controls inside `when(ctrl) do … end`: every gate the QROM and the
# CNOT half-swap emit goes through `apply_cx!`/`apply_ccx!` on the context,
# which consults `ctx.control_stack`. The phase_estimate caller never
# constructs a controlled gate explicitly; the control is a *side-effect* of
# the surrounding `when` block.

"""
    _shor_mulmod_circuits(a::Int, N::Int, ::Val{L}) -> Tuple{ReversibleCircuit, ReversibleCircuit}

Build (forward, inverse) QROM circuits for the `L`-bit modular-multiplication
bijection `y ↦ a·y mod N` (identity on `y ≥ N`, per N&C Eq. 5.36) and its
inverse `z ↦ a⁻¹·z mod N`. Circuits are cached by content hash via
`_ORACLE_TABLE_CACHE` (see `src/bennett/bridge.jl`) — a second invocation
with the same `(a, N, L)` returns the already-compiled circuits.
"""
function _shor_mulmod_circuits(a::Int, N::Int, ::Val{L}) where {L}
    gcd(a, N) == 1 || error("_shor_mulmod_circuits: a=$a and N=$N must be coprime")
    (1 << L) >= N || error("_shor_mulmod_circuits: L=$L too small for N=$N (need 2^L ≥ N)")

    ainv = invmod(a, N)
    mask = (UInt64(1) << L) - UInt64(1)

    # Forward table: f(y) = y < N ? (a*y) % N : y (identity on the high tail).
    data_f = Vector{UInt64}(undef, 1 << L)
    data_g = Vector{UInt64}(undef, 1 << L)
    @inbounds for y in 0:((1 << L) - 1)
        data_f[y + 1] = (y < N ? UInt64((a * y) % N) : UInt64(y)) & mask
        data_g[y + 1] = (y < N ? UInt64((ainv * y) % N) : UInt64(y)) & mask
    end

    key_f = (hash(data_f), L, L)
    key_g = (hash(data_g), L, L)

    circuit_f = get!(_ORACLE_TABLE_CACHE, key_f) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, L)
        data_out_b  = emit_qrom!(gates, wa, data_f, idx_wires_b, L)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [L], [L], Set{Int}())
        bennett(lr)
    end
    circuit_g = get!(_ORACLE_TABLE_CACHE, key_g) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, L)
        data_out_b  = emit_qrom!(gates, wa, data_g, idx_wires_b, L)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [L], [L], Set{Int}())
        bennett(lr)
    end
    return circuit_f, circuit_g
end

"""
    _shor_mulmod_a!(y_reg::QInt{L}, circuit_f, circuit_g)

Apply the in-place modular-multiplication unitary U : |y⟩ ↦ |a·y mod N⟩ on the
L-qubit register `y_reg`, using the pre-compiled (forward, inverse) QROM
circuits from `_shor_mulmod_circuits`. The register's WireIDs are preserved
(same physical wires before and after), so calling this inside a `when(ctrl)`
block and/or passing it to `phase_estimate` composes naturally.

Ref: Nielsen & Chuang §5.3.1, Eq. 5.36, Fig. 5.4. The compute-copy-uncompute
structure is Bennett-standard (cf. Markov & Saeedi 2012, Beauregard 2003).
"""
function _shor_mulmod_a!(y_reg::QInt{L},
                         circuit_f::ReversibleCircuit,
                         circuit_g::ReversibleCircuit) where {L}
    check_live!(y_reg)
    ctx = y_reg.ctx

    # Fresh |0⟩ ancilla register z
    z_wires = WireID[allocate!(ctx) for _ in 1:L]
    y_wires = WireID[y_reg.wires[i] for i in 1:L]

    # Step A: z ⊻= f(y)  ⇒  z = f(y)   (y preserved)
    wm_f = build_wire_map(circuit_f, y_wires, z_wires)
    apply_reversible!(ctx, circuit_f, wm_f)

    # Step B: y ⊻= g(z) = g(f(y)) = y  ⇒  y = 0   (z preserved)
    wm_g = build_wire_map(circuit_g, z_wires, y_wires)
    apply_reversible!(ctx, circuit_g, wm_g)

    # Step C: half-swap y_reg ↔ z (source known-zero, 2L CNOTs).
    #   y ⊻= z  ⇒  y = f(y);   z ⊻= y  ⇒  z = 0.
    for i in 1:L
        apply_cx!(ctx, z_wires[i], y_wires[i])
    end
    for i in 1:L
        apply_cx!(ctx, y_wires[i], z_wires[i])
    end

    # Step D: deallocate z (guaranteed |0⟩)
    for w in z_wires
        deallocate!(ctx, w)
    end
    return y_reg
end

"""
    shor_order_B(a::Int, N::Int; t::Int=4, verbose::Bool=false) -> Int

Order of `a` modulo `N` via the "phase-estimation higher-order" idiom
(N&C §5.3.1 verbatim). Constructs the modular-multiplication unitary
`U|y⟩ = |a·y mod N⟩` (Eq. 5.36) as a closure over `(a, N)` and hands it to
[`phase_estimate`](@ref) with `|1⟩_L` as eigenstate (Eq. 5.44).

The HOF fabricates the controlled-`U^{2^j}` cascade by invoking `U!`
`2^{j-1}` times under each counter qubit's control; the control stack
auto-propagates into every QROM gate emitted by `_shor_mulmod_a!`.

Algorithm (N&C §5.3.1, Eqs. 5.36–5.44, Fig. 5.4):
  1. Allocate `y = QInt{L}(1)` — Eq. 5.44 eigenstate.
  2. `ỹ = phase_estimate(U!, y, Val(t))` where `U!` is `_shor_mulmod_a!`.
  3. Continued-fractions decode of `ỹ / 2ᵗ` → candidate period.

`t` counter qubits, `L = ⌈log₂ N⌉` register qubits. For `N = 15`, `L = 4`;
`t = 3` resolves peaks at `{0, 2, 4, 6}` for `r = 4` and `{0, 4}` for `r = 2`.

Ref: Nielsen & Chuang §5.3.1, Eqs. 5.36, 5.40–5.44, Fig. 5.4, Box 5.4.
See `docs/physics/nielsen_chuang_5.3.md`.
"""
function shor_order_B(a::Int, N::Int, ::Val{t}; verbose::Bool=false) where {t}
    gcd(a, N) == 1 || error("shor_order_B: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_B: a=$a must satisfy 1 ≤ a < N=$N")
    L = max(1, ceil(Int, log2(N)))

    ctx = current_context()
    verbose && @info "shor_order_B: a=$a, N=$N, t=$t, L=$L" live_qubits=_live_qubits(ctx)

    # Precompile the forward + inverse QROM circuits once (cached in
    # _ORACLE_TABLE_CACHE — subsequent shots reuse both circuits).
    circuit_f, circuit_g = _shor_mulmod_circuits(a, N, Val(L))
    verbose && @info "  after _shor_mulmod_circuits (compiled/cached)" live_qubits=_live_qubits(ctx)

    # Eq. 5.44 initial state |1⟩_L — phase_estimate handles the counter register
    # internally (allocate, superpose, controlled-U^{2^j}, interfere, measure).
    y = QInt{L}(ctx, 1)
    verbose && @info "  after QInt{$L}(1) (eigenstate |1⟩)" live_qubits=_live_qubits(ctx)

    # Wrap the mulmod in a closure that takes a QInt{L}. `phase_estimate`
    # invokes this 1 + 2 + 4 + … + 2^{t-1} = 2^t − 1 times inside `when(ctrl)`
    # blocks; each call momentarily allocates L ancillae (z), deallocates on
    # exit, so the live-qubit HWM for the mulmod cascade stays at t + 2L.
    U! = reg -> _shor_mulmod_a!(reg, circuit_f, circuit_g)
    y_tilde = phase_estimate(U!, y, Val(t))
    verbose && @info "  measured ỹ=$y_tilde after phase_estimate" live_qubits=_live_qubits(ctx) peak_allocated=ctx.n_qubits capacity=ctx.capacity

    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && @info "  continued-fraction decode" ỹ=y_tilde φ=(y_tilde//(1<<t)) r=r
    return r
end

shor_order_B(a::Int, N::Int; t::Int=4, verbose::Bool=false) =
    shor_order_B(a, N, Val(t); verbose=verbose)

"""
    shor_factor_B(N::Int; max_attempts::Int=16) -> Vector{Int}

Factor composite `N` using order-finding implementation B. Identical
classical reduction (N&C §5.3.2) to [`shor_factor_A`](@ref); differs only
in the quantum order-finding subroutine.
"""
function shor_factor_B(N::Int; max_attempts::Int=16)
    N >= 2 || error("shor_factor_B: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_B(a, N)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Implementation C — controlled-U^{2^j} cascade (Box 5.2 literal)
# ═══════════════════════════════════════════════════════════════════════════
# (landed by Opus proposer subagent #2)
