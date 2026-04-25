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
#     output (t qubits)  |0⟩ ──────── oracle(a^k mod N) ── ptrace!
#
# The ptrace! of the output register is the post-measurement trace that
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
  3. `ptrace!(y)` — trace out output, which collapses `k` onto a coset
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

    ptrace!(y_reg)
    verbose && @info "  after ptrace!(y_reg)" live_qubits=_live_qubits(ctx)

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
#
# The idiom: N&C Box 5.2 / Eq. 5.43 expands the modular exponentiation
#
#     x^z (mod N) = (x^{z_{t-1} 2^{t-1}} mod N) · … · (x^{z_1·2} mod N) · (x^{z_0} mod N)
#
# literally. Rather than invoking a single unitary U(y) = a·y mod N a total
# of 2^{t}−1 times under nested `when()`s (impl B), we precompute
#
#     a_j = a^{2^{j-1}} mod N      (j = 1, …, t)
#
# **classically at compile time** — the "quantum squaring" Box 5.2 describes
# becomes a plain Julia `powermod`. The quantum cost per shot drops from 2^t−1
# mulmod invocations to exactly `t`: one controlled-"multiply-by-a_j-mod-N"
# circuit per counter qubit.
#
# Circuit shape (N&C Fig. 5.4 bottom half, literal):
#
#     counter (t qubits) |0⟩ ─ superpose! ─────────────────── interfere! ─── measure
#                                              │ … │
#                                              │   │
#     y = |1⟩_L ────────────────── M(a_1) ── M(a_2) ── … ── M(a_t) ── discard
#
# where M(a_j) is "multiply y by the classical constant a_j mod N, controlled
# on counter[j]".
#
# ── Realising the controlled mulmod without impl-B's resource blow-up ──
#
# The naïve realisation — wrap `_shor_mulmod_a!` in `when(counter[j])` — produces
# impl B's 25-qubit HWM: every gate inside the QROM becomes multi-controlled via
# the control stack, and the L-qubit ancilla `z` plus the 2·(2^L) QROM rounds stay
# at the same cost as impl B. The only saving (3 calls vs 7) is a 2.3× factor; still
# minutes per shot.
#
# The optimisation that makes this impl a distinct resource datum is to
# **fold the control wire *into* the QROM input**. Instead of emitting a forward
# QROM for `y ↦ a_j·y mod N` under an outer `when(counter[j])`, we build the
# packed table
#
#     f_j(packed)  :  (1+L) bits → L bits
#                     (ctrl=0, y) ↦ y                    (identity)
#                     (ctrl=1, y) ↦ (a_j · y) mod N      (multiply if ctrl=1)
#
# and emit a *single unconditional* QROM on that table — the control is just
# another index bit. Same for the inverse. The compute-copy-uncompute shape is
# preserved (fresh z, forward, XOR-inverse into y, half-swap, free z), but:
#
#   * Every gate runs with an empty control stack — no CCCX unrolling.
#   * The QROM index width grows from L to L+1, so each QROM has
#     2·(2^{L+1}−1) Toffoli vs impl B's 2·(2^L−1). Twice the Toffolis, but
#     each one is a direct Orkan `orkan_ccx!` instead of multi-controlled.
#   * Peak live qubits per call: t + L(y) + L(z) + QROM_tree_flags ≈ 17
#     (vs impl B's 25), matching impl A's 18-qubit HWM.
#
# The "identity on y ≥ N" trick (N&C Eq. 5.36) is baked into the packed table
# so the `(ctrl=1, y≥N) ↦ y` branch keeps every packed `(ctrl, y)` pair a
# bijection on the 2^{1+L}-dim packed space — the circuit is unitary without
# any tail-masking.
#
# ── Why this is still the Box 5.2 idiom, not impl A in disguise ──
#
# Impl A computes the *entire* modular exponential as a single value oracle
# `k ↦ aᵏ mod N` — one table, 2^t entries, t+L input/output wires. The control
# is implicit in the counter's amplitude basis and the QROM's index.
#
# Impl C keeps the **per-qubit cascade structure** from Box 5.2: t separate
# (controlled-mulmod)-on-a-fresh-constant circuits, each multiplying the
# *running* `y` register by `a_j`. The counter qubits stay independent; the
# `y` register threads through a sequence of reversible mulmods. Swap one
# `a_j` out for a different classical constant and you get a different circuit
# without recompiling the whole exponential — exactly the modularity Box 5.2
# exposes.

"""
    _shor_mulmod_packed_circuits(a::Int, N::Int, ::Val{L}) -> Tuple{ReversibleCircuit, ReversibleCircuit}

Build the (forward, inverse) packed-QROM circuits for the controlled
modular-multiplication bijection `(ctrl, y) ↦ (ctrl, ctrl ? a·y mod N : y)`.
The forward circuit reads `[ctrl, y_1, …, y_L]` and XORs `f(ctrl, y)` into
a fresh L-bit output; the inverse does the same with `a⁻¹` in place of `a`.
Circuits are cached by content hash via `_ORACLE_TABLE_CACHE`.

Bit layout (little-endian, matching Sturm's `QInt{W}` convention): the
packed index has `ctrl` at bit L (the MSB of the (1+L)-bit word) and
`y_1..y_L` at bits 0..L−1.

Ref: Nielsen & Chuang §5.3.1, Eq. 5.36 (identity-on-y≥N extension), Box 5.2.
"""
function _shor_mulmod_packed_circuits(a::Int, N::Int, ::Val{L}) where {L}
    gcd(a, N) == 1 || error("_shor_mulmod_packed_circuits: a=$a and N=$N must be coprime")
    (1 << L) >= N || error("_shor_mulmod_packed_circuits: L=$L too small for N=$N")

    ainv = invmod(a, N)
    W_in = 1 + L
    mask_y = (UInt64(1) << L) - UInt64(1)
    mask_o = mask_y

    # Packed tables: index is (ctrl << L) | y for y ∈ [0, 2^L), ctrl ∈ {0, 1}.
    # Output is f(ctrl, y) = (ctrl && y < N) ? (a·y) mod N : y.
    # The `y >= N` identity branch keeps the packed map a bijection.
    data_f = Vector{UInt64}(undef, 1 << W_in)
    data_g = Vector{UInt64}(undef, 1 << W_in)
    @inbounds for packed in 0:((1 << W_in) - 1)
        ctrl = (packed >> L) & 1
        y    = packed & Int(mask_y)
        if ctrl == 1 && y < N
            data_f[packed + 1] = UInt64((a    * y) % N) & mask_o
            data_g[packed + 1] = UInt64((ainv * y) % N) & mask_o
        else
            data_f[packed + 1] = UInt64(y) & mask_o
            data_g[packed + 1] = UInt64(y) & mask_o
        end
    end

    key_f = (hash(data_f), W_in, L)
    key_g = (hash(data_g), W_in, L)

    circuit_f = get!(_ORACLE_TABLE_CACHE, key_f) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, W_in)
        data_out_b  = emit_qrom!(gates, wa, data_f, idx_wires_b, L)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [W_in], [L], Set{Int}())
        bennett(lr)
    end
    circuit_g = get!(_ORACLE_TABLE_CACHE, key_g) do
        wa = WireAllocator()
        gates = ReversibleGate[]
        idx_wires_b = _bennett_wa_allocate!(wa, W_in)
        data_out_b  = emit_qrom!(gates, wa, data_g, idx_wires_b, L)
        lr = LoweringResult(gates, wire_count(wa), idx_wires_b, data_out_b,
                            [W_in], [L], Set{Int}())
        bennett(lr)
    end
    return circuit_f, circuit_g
end

"""
    _shor_mulmod_controlled!(ctx, ctrl::WireID, y::QInt{L}, circuit_f, circuit_g)

In-place controlled modular multiplication on the register `y`:

    (ctrl, y) ↦ (ctrl, ctrl ? (a_j · y) mod N : y)

Implements the compute-copy-uncompute pattern of [`_shor_mulmod_a!`](@ref)
but with the `ctrl` wire **packed into the QROM input** (it becomes the MSB of
the (1+L)-bit index), so every gate in the two QROMs runs at the empty control
stack rather than being individually multi-controlled. The caller must supply
the `(circuit_f, circuit_g)` pair from
[`_shor_mulmod_packed_circuits`](@ref).

Execution (ancilla `z` is fresh |0⟩^L, deallocated on exit):

  1. Forward packed QROM:   `z ⊻= f(ctrl, y)`  ⇒  `z = f(ctrl, y)` (y preserved)
  2. Inverse packed QROM:   `y ⊻= g(ctrl, z) = g(ctrl, f(ctrl, y)) = y`  ⇒  `y = 0`
  3. Half-swap y ↔ z via 2L CNOTs (y side is known-zero after step 2):
       first y ⊻= z  (y ← f(ctrl, y), z unchanged),
       then  z ⊻= y  (z ← 0).
  4. Deallocate z (guaranteed |0⟩).

Preserves `y`'s WireIDs — the register handle passed in still points at the
same physical wires on exit, now carrying the post-multiplication value.

Ref: Nielsen & Chuang §5.3.1 Eq. 5.36, Box 5.2, and the Bennett-standard
compute-copy-uncompute construction (Bennett 1973).
"""
function _shor_mulmod_controlled!(ctx::AbstractContext, ctrl_wire::WireID,
                                  y_reg::QInt{L},
                                  circuit_f::ReversibleCircuit,
                                  circuit_g::ReversibleCircuit) where {L}
    check_live!(y_reg)

    # Sub-stage instrumentation — each step flushes to stderr so a stall
    # inside a QROM apply is visible at the last printed line. This adds
    # four log lines per mulmod call; at `t=3` that's 12 extra lines per
    # shot — trivial compared to the information value when debugging.
    LOG(msg) = (println(stderr, "  [mulmod ctrl=", ctrl_wire, "] ", msg); flush(stderr))

    z_wires = WireID[allocate!(ctx) for _ in 1:L]
    y_wires = WireID[y_reg.wires[i] for i in 1:L]
    LOG("allocated z ($(L) wires), live=$(_live_qubits(ctx))")

    packed_input_wires = WireID[ctrl_wire; y_wires]
    packed_input_for_g = WireID[ctrl_wire; z_wires]

    # Run at the empty control stack — `ctrl` is already folded into the QROM
    # index so an outer `when(...)` would only add spurious controls.
    with_empty_controls(ctx) do
        LOG("enter QROM_f (packed forward mulmod)")
        wm_f = build_wire_map(circuit_f, packed_input_wires, z_wires)
        apply_reversible!(ctx, circuit_f, wm_f)
        LOG("exit  QROM_f, live=$(_live_qubits(ctx))")

        LOG("enter QROM_g (packed inverse, uncomputes y to 0)")
        wm_g = build_wire_map(circuit_g, packed_input_for_g, y_wires)
        apply_reversible!(ctx, circuit_g, wm_g)
        LOG("exit  QROM_g, live=$(_live_qubits(ctx))")

        LOG("half-swap via 2L=$(2L) CNOTs")
        for i in 1:L
            apply_cx!(ctx, z_wires[i], y_wires[i])
        end
        for i in 1:L
            apply_cx!(ctx, y_wires[i], z_wires[i])
        end
    end

    for w in z_wires
        deallocate!(ctx, w)
    end
    LOG("dealloc z, live=$(_live_qubits(ctx))")
    return y_reg
end

"""
    shor_order_C(a::Int, N::Int; t::Int=3, verbose::Bool=false) -> Int
    shor_order_C(a::Int, N::Int, ::Val{t}) where {t}

Order of `a` modulo `N` via the "controlled-U^{2^j} cascade" idiom — the
literal reading of Nielsen & Chuang Box 5.2 / Eq. 5.43. Rather than invoking
a single modular-multiplication unitary `2^t − 1` times under nested
controls (impl B), we precompute the `t` classical constants

    a_j = a^{2^{j-1}} mod N,     j = 1, …, t

and emit **one** controlled-"multiply by a_j mod N" circuit per counter
qubit. The quantum squaring Box 5.2 describes is replaced by a plain
`powermod` at compile time.

Algorithm (N&C §5.3.1, Box 5.2, Eqs. 5.40–5.43):
  1. Counter `c = QInt{t}(0)` → `superpose!` → uniform.
  2. `y = QInt{L}(1)` — Eq. 5.44 eigenstate, shared by all stages.
  3. For j = 1, …, t:
       * classical: `a_j = a^{2^{j-1}} mod N`
       * quantum:   controlled-mulmod on `y` by `a_j`, control = `c.wires[j]`.
  4. `interfere!(c)` — inverse QFT on the counter.
  5. `ptrace!(y)`; `ỹ = Int(c)`; continued-fractions → candidate period.

Resource profile (N = 15, L = 4, t = 3):
  * Peak live qubits per mulmod call: `t + 2L + O(log L) ≈ 17` (cf. impl B's 25)
  * Packed QROM table size: `2^{1+L} = 32` entries (cf. impl B's 16).
  * Unconditional QROM gates — no control-stack expansion (cf. impl B's CCCX).
  * `t` mulmod calls per shot (cf. impl B's `2^t − 1`).
  * Matches impl A's HWM envelope; retains the Box 5.2 per-qubit cascade.

Ref: Nielsen & Chuang §5.3.1, Box 5.2 (modular-exponentiation expansion),
Eq. 5.36 (identity-on-y≥N extension), Box 5.4 (N=15 worked example).
See `docs/physics/nielsen_chuang_5.3.md`.
"""
# Fail-fast logger: every line reaches stderr immediately, no Julia buffering.
# `@info` has macro-level overhead and buffers in some environments; a plain
# println+flush always hits the terminal within milliseconds so a user can
# kill the process the instant a stage stalls.
@inline function _shor_log(msg::AbstractString)
    println(stderr, msg)
    flush(stderr)
end

function shor_order_C(a::Int, N::Int, ::Val{t}; verbose::Bool=true) where {t}
    gcd(a, N) == 1 || error("shor_order_C: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_C: a=$a must satisfy 1 ≤ a < N=$N")
    L = max(1, ceil(Int, log2(N)))

    ctx = current_context()
    t0 = time_ns()
    lq() = _live_qubits(ctx)
    ms() = round((time_ns() - t0) / 1e6, digits=1)
    verbose && _shor_log("[shor_C t=+0.0ms] start a=$a N=$N t=$t L=$L  live=$(lq())")

    # Classical precompute — N&C Box 5.2 replaces each quantum squaring with a
    # plain powermod. For a=7, N=15, t=3: a_j = {7, 4, 1}.
    a_js = [powermod(a, 1 << (j - 1), N) for j in 1:t]
    verbose && _shor_log("[shor_C t=+$(ms())ms] classical a_j=$(a_js)")

    # Build + cache (forward, inverse) packed circuits, one pair per a_j.
    circuits = [_shor_mulmod_packed_circuits(a_j, N, Val(L)) for a_j in a_js]
    verbose && _shor_log("[shor_C t=+$(ms())ms] packed circuits ready ($(length(circuits)) pairs)  live=$(lq())")

    c_reg = QInt{t}(0)
    superpose!(c_reg)
    verbose && _shor_log("[shor_C t=+$(ms())ms] superpose!(c_reg)                live=$(lq()) cap=$(ctx.capacity)")

    y_reg = QInt{L}(ctx, 1)
    verbose && _shor_log("[shor_C t=+$(ms())ms] y = QInt{$L}(1) eigenstate      live=$(lq()) cap=$(ctx.capacity)")

    # Box 5.2 cascade: t controlled mulmods, one per counter qubit.
    # Log BEFORE + AFTER each stage so a stall inside the mulmod is visible at
    # the last "enter" line (no need to wait for exit to know something is
    # happening, or to know WHERE it's stuck).
    for j in 1:t
        ctrl_wire = c_reg.wires[j]
        cf, cg = circuits[j]
        verbose && _shor_log("[shor_C t=+$(ms())ms] ENTER mulby a_$j=$(a_js[j]) mod $N  live=$(lq()) cap=$(ctx.capacity)")
        t_stage = time_ns()
        _shor_mulmod_controlled!(ctx, ctrl_wire, y_reg, cf, cg)
        stage_ms = round((time_ns() - t_stage) / 1e6, digits=1)
        verbose && _shor_log("[shor_C t=+$(ms())ms] EXIT  mulby a_$j done in $(stage_ms)ms  live=$(lq()) hwm=$(ctx.n_qubits) cap=$(ctx.capacity)")
    end

    interfere!(c_reg)
    verbose && _shor_log("[shor_C t=+$(ms())ms] interfere!(c_reg)                live=$(lq())")

    ptrace!(y_reg)
    verbose && _shor_log("[shor_C t=+$(ms())ms] ptrace!(y_reg)                  live=$(lq())")

    y_tilde = Int(c_reg)
    verbose && _shor_log("[shor_C t=+$(ms())ms] measured ỹ=$y_tilde                    live=$(lq())")

    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && _shor_log("[shor_C t=+$(ms())ms] decoded φ=$(y_tilde)/$(1<<t) r=$r   (total=$(ms())ms)")
    return r
end

shor_order_C(a::Int, N::Int; t::Int=3, verbose::Bool=true) =
    shor_order_C(a, N, Val(t); verbose=verbose)

"""
    shor_factor_C(N::Int; max_attempts::Int=16) -> Vector{Int}

Factor composite `N` using order-finding implementation C. Identical
classical reduction (N&C §5.3.2) to [`shor_factor_A`](@ref) and
[`shor_factor_B`](@ref); differs only in the quantum order-finding
subroutine — the controlled-`U^{2^j}` cascade from Box 5.2.
"""
function shor_factor_C(N::Int; max_attempts::Int=16)
    N >= 2 || error("shor_factor_C: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_C(a, N)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Implementation D — Beauregard arithmetic mulmod (polynomial in L)
# ═══════════════════════════════════════════════════════════════════════════
#
# Same Box 5.2 cascade structure as impl C, but the controlled mulmod is
# [`mulmod_beauregard!`](@ref) (Beauregard 2003 Fig. 7, c-U_a) instead of a
# packed-QROM table. The physics difference matters:
#
#   * Impl C pays `2·2^{L+1} Toffoli` per mulmod (two packed QROMs) plus a
#     QROM ancilla tree growing as `O(L)`. At L=14 / t=28 the measured DAG
#     was 47M gates and the single-shot simulation blew past Orkan's 30-qubit
#     statevector cap — untestable.
#
#   * Impl D pays Beauregard's `O(L² · k_max)` gates per mulmod call
#     (Beauregard 2003 §3 p.11), depth `O(L²)`, and uses only **2n+3 wires
#     total** for the whole order-finding run (paper headline). No QROM
#     ancilla tree; no `L+1`-wide packed index. The L+1-qubit Fourier
#     accumulator `b` and the 1-qubit modadd flag `anc` are allocated
#     *inside* each `mulmod_beauregard!` call and returned to |0⟩ before
#     deallocation, so the peak live-qubit count is independent of how
#     many mulmods have already run.
#
# Expected scaling (Beauregard §3 Eq. p.11 with exact QFT, `k_max = L`):
#
#     cost per c-U_a          = 2 · L · (doubly-controlled φADD(a)MOD(N))
#                              = 2 · L · O(L²)
#                              = O(L³)
#     cost for full order-find = t · c-U_a = 2L · O(L³) = O(L^4)
#
# At L=14 / t=28 the projection is ~50k gates vs impl C's measured 47M —
# about **1000× reduction**. More importantly it is *polynomial* rather
# than exponential, so L=100 stays constructible (~10^8 gates) and L=1024
# (useful crypto) stays around ~10^12 gates, matching Gidney-Ekerå 2021's
# surface-code Toffoli estimate for RSA-2048.
#
# Control-depth optimisation inherited from Sturm.jl-uf4. Because
# `mulmod_beauregard!` already takes its own `ctrl::QBool` argument and
# pushes `(ctrl, x_j)` into modadd's `ctrls` kwarg, wrapping the call in
# `when(counter_qubit_j) do … end` is **NOT** what we want — that would
# push three controls on the stack for every primitive inside modadd,
# triggering the `_multi_controlled_gate!` cascade and undoing the uf4
# fix.  Instead we pass `counter_qubit_j` *as* the `ctrl` argument. The
# max control depth inside modadd stays at 2 (on the three φADD(a) gates)
# and 1 elsewhere — Sturm inline-HotNode fast path throughout.
#
# ── Fig. 7 c-U_a: (x, 0) ↦ (a·x mod N, 0)                    ──────────────
# ── Eq. 5.43 cascade: Π_j c-U_{a^{2^j}} on |1⟩_L              ──────────────

# ═══════════════════════════════════════════════════════════════════════════
# Impl E — Gidney-Ekerå 2021 windowed arithmetic  (Sturm.jl-6oc Phase B step 2)
#
# Ground truth: Gidney 2019 "Windowed quantum arithmetic" arXiv:1905.07682 §3.4
#   Fig 6, and Gidney-Ekerå 2021 arXiv:1905.09749 §2.5.
#   docs/physics/gidney_2019_windowed_arithmetic.pdf
#   docs/physics/gidney_ekera_2021_rsa2048.pdf
#
# Controlled modular multiplication on a coset-encoded target, via the
# cmult-swap-cmult⁻¹ pattern (Fig 6):
#   1. b := 0_coset                                       (fresh scratch QCoset)
#   2. b += a · x  (mod N)    [controlled by ctrl]        — plus_equal_product_mod!
#   3. SWAP(x, b)             [controlled by ctrl]        — 3 Toffoli / wire
#   4. b -= a⁻¹ · x  (mod N)  [controlled by ctrl]        — plus_equal_product_mod!
#   5. free b                                              — clean |0⟩ on both branches
#
# Control flow:
#   ctrl = |1⟩:  after step 2, b = a·r.  After step 3, x = a·r, b = r.
#                after step 4, b = r - a⁻¹·(a·r) = 0.  Final: x = a·r. ✓
#   ctrl = |0⟩:  every step is a no-op.  b stays |0⟩, x unchanged. ✓
#
# This is NOT the Beauregard structure (which uses an unconditional QFT
# sandwich and doubly-controlled modadds). Here the when(ctrl) wrapper
# around each plus_equal_product_mod! forces controlled QFTs inside —
# correct but higher Toffoli cost. Optimising to hoist the QFT out of
# the ctrl wrapper is tracked as a Phase C follow-on.
# ═══════════════════════════════════════════════════════════════════════════

"""
    _shor_mulmod_E_controlled!(target::QCoset{W, Cpad, Wtot}, a::Integer,
                                ctrl::QBool; c_mul::Int=2) -> target

Controlled modular multiplication on a coset-encoded register:
`target ← (a · target) mod N` when `ctrl = |1⟩`, identity when `ctrl = |0⟩`.
`N = target.modulus`.

# Preconditions
  * `gcd(a, N) == 1` (so `a⁻¹ mod N` exists).
  * `target.reg.ctx === ctrl.ctx`.

# Cost
Each of the two `plus_equal_product_mod!` sweeps fires ⌈Wtot/c_mul⌉ lookup-
adds. Each lookup emits a Babbush-Gidney QROM (2^c_mul − 1 Toffoli forward,
same backward in Phase A — √L measurement-based uncompute is Phase C).
Controlled-SWAP costs 3 Toffoli per wire × (Wtot + Cpad) wires.

# References
  Gidney (2019) arXiv:1905.07682 §3.4 Fig 6.
  Gidney-Ekerå (2021) arXiv:1905.09749 §2.5.
"""
function _shor_mulmod_E_controlled!(target::QCoset{W, Cpad, Wtot},
                                     a::Integer, ctrl::QBool;
                                     c_mul::Int=2,
                                     mbu::Bool=false,
                                     mbu_compute::Bool=false) where {W, Cpad, Wtot}
    check_live!(target); check_live!(ctrl)
    target.reg.ctx === ctrl.ctx ||
        error("_shor_mulmod_E_controlled!: target and ctrl must share a context")
    N = Int(target.modulus)
    a_mod = mod(Int(a), N)
    gcd(a_mod, N) == 1 ||
        error("_shor_mulmod_E_controlled!: need gcd(a, N)=1, got gcd($(a_mod), $N)=$(gcd(a_mod, N))")
    a_inv = invmod(a_mod, N)
    ctx = target.reg.ctx

    # Fresh |0⟩ coset for the scratch accumulator b.
    b = QCoset{W, Cpad}(ctx, 0, N)

    # Step 1: b += a · target  (controlled via `ctrls=(ctrl,)`).
    # The `ctrls` kwarg pushes control only onto the add step inside
    # plus_equal_product_mod! — the QROM/QFT surroundings run unconditionally
    # and self-cancel on the ctrl=|0⟩ branch. Same correctness as
    # `when(ctrl) do plus_equal_product_mod!(...) end` but without cascading
    # the control onto QROM Toffolis (which would force _multi_controlled_cx!
    # workspace ancillae past Orkan's 30-qubit cap at N=15, c_mul=2).
    # `mbu=true` enables Berry et al. 2019 measurement-based QROM uncompute
    # inside each plus_equal_product_mod! iteration (bead Sturm.jl-9ij):
    # reverse-lookup cost drops from 2^c_mul − 1 to ⌈2^c_mul/k⌉ + k Toffoli.
    # `mbu_compute=true` additionally swaps the FORWARD QROM for Berry App B
    # Theorem 2 clean-ancilla forward (bead Sturm.jl-vbz). Forward cost drops
    # from 4·(2^c_mul − 1) to 4·(2^Whi − 1) + Wtot·(k_b − 1) at k_b=2.
    plus_equal_product_mod!(b, a_mod, target.reg;
                              window=c_mul, ctrls=(ctrl,),
                              mbu=mbu, mbu_compute=mbu_compute)

    # Step 2: controlled-SWAP(target, b) — still needs full when(ctrl) because
    # SWAP has no self-inverse structure (it's CNOT³, each of which needs the
    # control). Depth-1 ctrl on each CNOT → native Toffoli, no cascade.
    when(ctrl) do
        for j in 1:Wtot
            swap!(QBool(target.reg.wires[j], ctx, false),
                  QBool(b.reg.wires[j],      ctx, false))
        end
        for j in 1:Cpad
            swap!(QBool(target.pad_anc[j], ctx, false),
                  QBool(b.pad_anc[j],      ctx, false))
        end
    end

    # Step 3: b -= a⁻¹ · target  (same ctrls pattern as step 1).
    minus_a_inv = mod(N - a_inv, N)
    plus_equal_product_mod!(b, minus_a_inv, target.reg;
                              window=c_mul, ctrls=(ctrl,),
                              mbu=mbu, mbu_compute=mbu_compute)

    # b is now |0⟩ coset on both ctrl branches — free it.
    ptrace!(b)

    return target
end

"""
    shor_order_D(a::Int, N::Int; t::Int=3, verbose::Bool=true) -> Int
    shor_order_D(a::Int, N::Int, ::Val{t}) where {t}

Order of `a` modulo `N` via the "controlled-U^{2^j} cascade" idiom (Box
5.2 / Eq. 5.43), lifting **arithmetic** modular multiplication
([`mulmod_beauregard!`](@ref), Beauregard 2003 Fig. 7) instead of a
QROM-packed table (contrast [`shor_order_C`](@ref)).

This is the fourth independent Sturm.jl implementation of Shor order-
finding. Algorithm body is identical to impl C — the `t` classical
constants `a_j = a^{2^{j-1}} mod N` precomputed via `powermod`, one
controlled-multiply-by-`a_j` per counter qubit — but each multiply is
realised with 2·L doubly-controlled φADD(a) modular additions in the
Fourier basis, running entirely on Sturm's 4 primitives and
`mulmod_beauregard!`'s own `L+1`-qubit Fourier accumulator.

Scaling (Beauregard 2003 §3, Eq. p.11):
  * **Gates per c-U_a:**        `O(L² · k_max) = O(L³)`  with exact QFT
  * **Gates total order-find:** `O(t · L³) = O(L^4)`     at `t = 2L`
  * **Peak wires:**             `t + 2L + O(1)` (counter + y + b + anc)
  * **Max control depth:**      2 on φADD(a), 1 elsewhere (uf4 invariant)

Algorithm (N&C §5.3.1 Box 5.2, Eqs. 5.40–5.43, with Beauregard 2003
Fig. 7 replacing the abstract c-U_a):
  1. Counter `c = QInt{t}(0)` → `superpose!` → uniform.
  2. `y = QInt{L}(1)` — Eq. 5.44 eigenstate, shared by all stages.
  3. For j = 1, …, t:
       classical: `a_j = a^{2^{j-1}} mod N`
       quantum:   `mulmod_beauregard!(y, a_j, N, c.wires[j])`
       (skip `a_j == 1` — identity, saves 2L modadds)
  4. `interfere!(c)` — inverse QFT on the counter.
  5. `ptrace!(y)`; `ỹ = Int(c)`; continued-fractions → candidate period.

Ref: Nielsen & Chuang §5.3.1, Box 5.2, Eqs. 5.40–5.43, 5.44.
     Beauregard 2003, §2.3 Fig. 6/7, Eq. 3, Eq. 4.
     `docs/physics/nielsen_chuang_5.3.md` and
     `docs/physics/beauregard_2003_2n3_shor.pdf`.
"""
function shor_order_D(a::Int, N::Int, ::Val{t}; verbose::Bool=true) where {t}
    gcd(a, N) == 1 || error("shor_order_D: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_D: a=$a must satisfy 1 ≤ a < N=$N")
    L = max(1, ceil(Int, log2(N)))

    ctx = current_context()
    t0 = time_ns()
    lq() = _live_qubits(ctx)
    ms() = round((time_ns() - t0) / 1e6, digits=1)
    verbose && _shor_log("[shor_D t=+0.0ms] start a=$a N=$N t=$t L=$L  live=$(lq())")

    # Classical precompute. For a=7, N=15, t=3: a_j = {7, 4, 1}.  (The
    # j=3 entry is 1 here, which we skip as a no-op — mulmod by 1 is
    # identity but still issues 2L·modadd calls; skipping saves O(L²).)
    a_js = [powermod(a, 1 << (j - 1), N) for j in 1:t]
    verbose && _shor_log("[shor_D t=+$(ms())ms] classical a_j=$(a_js)")

    c_reg = QInt{t}(0)
    superpose!(c_reg)
    verbose && _shor_log("[shor_D t=+$(ms())ms] superpose!(c_reg)                live=$(lq()) cap=$(ctx.capacity)")

    y_reg = QInt{L}(ctx, 1)
    verbose && _shor_log("[shor_D t=+$(ms())ms] y = QInt{$L}(1) eigenstate      live=$(lq()) cap=$(ctx.capacity)")

    # Box 5.2 cascade: one controlled-mulmod per counter qubit. Each call's
    # internal modadd routing uses ctrls=(ctrl, x_j) — depth 2 max, fast path.
    for j in 1:t
        a_j = a_js[j]
        if a_j == 1
            verbose && _shor_log("[shor_D t=+$(ms())ms] SKIP mulby a_$j=1 (identity)")
            continue
        end
        ctrl = QBool(c_reg.wires[j], ctx, false)
        verbose && _shor_log("[shor_D t=+$(ms())ms] ENTER mulby a_$j=$(a_j) mod $N  live=$(lq()) cap=$(ctx.capacity)")
        t_stage = time_ns()
        mulmod_beauregard!(y_reg, a_j, N, ctrl)
        stage_ms = round((time_ns() - t_stage) / 1e6, digits=1)
        verbose && _shor_log("[shor_D t=+$(ms())ms] EXIT  mulby a_$j done in $(stage_ms)ms  live=$(lq()) hwm=$(ctx.n_qubits) cap=$(ctx.capacity)")
    end

    interfere!(c_reg)
    verbose && _shor_log("[shor_D t=+$(ms())ms] interfere!(c_reg)                live=$(lq())")

    ptrace!(y_reg)
    verbose && _shor_log("[shor_D t=+$(ms())ms] ptrace!(y_reg)                  live=$(lq())")

    y_tilde = Int(c_reg)
    verbose && _shor_log("[shor_D t=+$(ms())ms] measured ỹ=$y_tilde                    live=$(lq())")

    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && _shor_log("[shor_D t=+$(ms())ms] decoded φ=$(y_tilde)/$(1<<t) r=$r   (total=$(ms())ms)")
    return r
end

shor_order_D(a::Int, N::Int; t::Int=3, verbose::Bool=true) =
    shor_order_D(a, N, Val(t); verbose=verbose)

"""
    shor_factor_D(N::Int; max_attempts::Int=16) -> Vector{Int}

Factor composite `N` using order-finding implementation D. Identical
classical reduction (N&C §5.3.2) to [`shor_factor_A`](@ref) /
[`shor_factor_B`](@ref) / [`shor_factor_C`](@ref); differs only in the
quantum order-finding subroutine — Beauregard 2003 arithmetic mulmod.
"""
function shor_factor_D(N::Int; max_attempts::Int=16)
    N >= 2 || error("shor_factor_D: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_D(a, N)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Implementation D-semi — single-qubit recycled counter (Beauregard §2.4 Fig. 8)
# ═══════════════════════════════════════════════════════════════════════════
#
# The `shor_order_D` implementation uses `t` counter qubits + `2L+2` arithmetic
# qubits, total `t + 2L + 2`. At `t = 2L` that's `4L + 2` — Beauregard's
# §2.3 peak. §2.4 (p. 8) sharpens this to `2L + 3` by observing:
#
#   1. All `c-U_{a^{2^j}}` gates commute (they all act on the same y register,
#      each conditional on a different counter qubit).
#   2. The inverse QFT on the counter register can be applied **semi-
#      classically** — one counter qubit at a time, with the Rz corrections
#      for cross-terms computed from *measurement outcomes* of previously-
#      measured counter qubits.
#
# Combining (1) + (2): process the counter one qubit at a time, recycling the
# same physical qubit. At iteration `i = 1, …, t`:
#
#   a. Fresh `c = QBool(0)`, H to |+⟩.
#   b. Classical phase correction `Rz(θ_i)` using bits measured at iterations
#      `1 … i−1` — the Griffiths-Niu / Parker-Plenio 2000 formula
#         θ_i  =  −2π · Σ_{j<i, bit_j = 1}  2^{-(i − j + 1)}
#      (equivalent to the cross-term `R_{2i}` phase rotations that would have
#      been applied between counter qubits in a non-measured iQFT circuit).
#   c. `mulmod_beauregard!(y, a^{2^(t-i)}, N, c)` — controlled-U with the
#      HIGHEST remaining power. Iter 1 uses `2^(t-1)`, iter t uses `2^0`.
#      With this order, iter i's counter phase (on |1⟩) is exactly
#      `2π · ỹ / 2^i` where `ỹ` is the t-bit PE output — the top bit of
#      ỹ shows up as a π phase at iter 1 (clean measurement of bit_0 = LSB)
#      and successive iters extract progressively higher bits after the
#      cross-term correction from `b` has removed the lower-bit contributions.
#   d. H then `Bool(c)` — measure bit `m_i` (= bit `i−1` of ỹ).
#
# After all `t` iterations, `ỹ = Σ m_i · 2^{i−1}` (little-endian — iteration
# 1 produces the LSB), passed through the same continued-fractions post-
# processing as every other impl.
#
# # Peak wires
#
# Counter region: 1 (reused across t iterations).
# y register (eigenstate): L.
# `mulmod_beauregard!` interior: L+1 (b) + 1 (anc), per uf4/6kx.
# Cascade workspace (doubly-controlled Rz inside modadd's φADD(a) calls):
#   nc=2 in EagerContext goes through `_multi_controlled_gate!` with
#   1 workspace ancilla, allocated/freed per primitive. Charges +1 live
#   qubit at cascade time (concurrent with the other live qubits).
#
# Total peak = 1 + L + (L+1) + 1 + 1 = **2L + 4**, independent of `t`.
# Matches Beauregard's "2n+3" bound plus the 1-workspace cascade cost
# introduced by Sturm's multi-controlled Rz lowering — see
# `src/context/multi_control.jl`. At L=13 that's 30 wires (Orkan's
# statevector cap); at L=14 it's 32 wires, tracing-only. DAG-level
# tracing remains unconstrained.
#
# # Reference
#   Beauregard 2003 §2.4 (p. 8) Fig. 8 — the "one controlling-qubit trick".
#   Griffiths & Niu 1996 (quant-ph/9511007) — original semi-classical iQFT
#   Parker & Plenio 2000 (quant-ph/0001104) §II — efficient factoring with
#   few qubits, concrete Rz phase correction formula.
#   `docs/physics/beauregard_2003_2n3_shor.pdf`.

"""
    shor_order_D_semi(a::Int, N::Int; t::Int=3, verbose::Bool=false) -> Int
    shor_order_D_semi(a::Int, N::Int, ::Val{t}) where {t}

Order of `a` modulo `N` via the Beauregard §2.4 (Fig. 8) "one controlling
qubit" trick — identical outer cascade to [`shor_order_D`](@ref) but with
the `t`-wide counter register collapsed to a single recycled `QBool` via
semi-classical inverse QFT. Same post-processing (continued fractions)
returns the candidate period.

Total live wires at peak: **`2L + 4`**, independent of `t`. Matches
Beauregard's "2n+3 qubits" bound plus a 1-workspace charge from
Sturm's doubly-controlled Rz Toffoli-cascade lowering.

Arguments are as in [`shor_order_D`](@ref). See there for the definition
of `L`, the choice of `t`, and the correctness regime.
"""
function shor_order_D_semi(a::Int, N::Int, ::Val{t}; verbose::Bool=false) where {t}
    gcd(a, N) == 1 || error("shor_order_D_semi: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_D_semi: a=$a must satisfy 1 ≤ a < N=$N")
    L = max(1, ceil(Int, log2(N)))

    ctx = current_context()
    t0 = time_ns()
    lq() = _live_qubits(ctx)
    ms() = round((time_ns() - t0) / 1e6, digits=1)
    verbose && _shor_log("[shor_D_semi t=+0.0ms] start a=$a N=$N t=$t L=$L  live=$(lq())")

    # Parker-Plenio 2000 §II: measure LSB-first, using c-U^{2^(t-i)} at iter
    # i. So iter 1 uses the *highest* power 2^(t-1), iter t uses 2^0.
    # Pre-compute in the order we'll consume them: a_js[i] = a^{2^(t-i)}.
    a_js = [powermod(a, 1 << (t - i), N) for i in 1:t]
    verbose && _shor_log("[shor_D_semi t=+$(ms())ms] classical a_j=$(a_js)")

    # Shared eigenstate across all t stages — |1⟩_L is Eq. 5.44 of N&C §5.3.1.
    y_reg = QInt{L}(ctx, 1)
    verbose && _shor_log("[shor_D_semi t=+$(ms())ms] y = QInt{$L}(1) eigenstate   live=$(lq())")

    bits = Bool[]
    sizehint!(bits, t)
    for i in 1:t
        a_j = a_js[i]

        # (a) Fresh counter qubit, H → |+⟩.
        c = QBool(0)
        H!(c)

        # (b) Classical phase correction from prior-measured bits.
        #     θ_i = -2π · Σ_{j<i, bits[j]} 2^{-(i-j+1)}
        corr = 0.0
        for j in 1:(i - 1)
            if bits[j]
                corr -= 2π / (1 << (i - j + 1))
            end
        end
        if corr != 0.0
            c.φ += corr
        end

        # (c) Skip the mulmod if a_j == 1 — identity, 2L modadds saved.
        #     The Rz correction and H/measure still fire (they commute
        #     with identity on y so the measurement statistics are preserved).
        if a_j != 1
            verbose && _shor_log("[shor_D_semi t=+$(ms())ms] iter $i: mulby a_$i=$a_j  live=$(lq()) cap=$(ctx.capacity)")
            t_stage = time_ns()
            mulmod_beauregard!(y_reg, a_j, N, c)
            stage_ms = round((time_ns() - t_stage) / 1e6, digits=1)
            verbose && _shor_log("[shor_D_semi t=+$(ms())ms] iter $i: mulmod done in $(stage_ms)ms  live=$(lq())")
        else
            verbose && _shor_log("[shor_D_semi t=+$(ms())ms] iter $i: SKIP mulby a_$i=1 (identity)")
        end

        # (d) H then measure → bit m_i.
        H!(c)
        m_i = Bool(c)
        push!(bits, m_i)
        verbose && _shor_log("[shor_D_semi t=+$(ms())ms] iter $i: m_$i = $(m_i)")
    end

    # Reconstruct ỹ with iter-i bit at position 2^{i-1} (LSB-first convention).
    y_tilde = 0
    for (idx, b) in enumerate(bits)
        b && (y_tilde |= (1 << (idx - 1)))
    end
    verbose && _shor_log("[shor_D_semi t=+$(ms())ms] ỹ = $(y_tilde) (bits = $(bits))")

    ptrace!(y_reg)
    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && _shor_log("[shor_D_semi t=+$(ms())ms] decoded φ=$y_tilde/$(1<<t) r=$r   (total=$(ms())ms)")
    return r
end

shor_order_D_semi(a::Int, N::Int; t::Int=3, verbose::Bool=false) =
    shor_order_D_semi(a, N, Val(t); verbose=verbose)

"""
    shor_factor_D_semi(N::Int; max_attempts::Int=16) -> Vector{Int}

Factor composite `N` using the Beauregard 2003 `2n+3`-qubit pipeline
([`shor_order_D_semi`](@ref)). Identical classical post-processing to
[`shor_factor_D`](@ref).
"""
function shor_factor_D_semi(N::Int; max_attempts::Int=16)
    N >= 2 || error("shor_factor_D_semi: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_D_semi(a, N)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Impl E — Gidney-Ekerå 2021 windowed arithmetic
#
# Same outer shape as shor_order_D_semi (Parker-Plenio semi-classical QFT,
# single recycled counter qubit). The only structural change is the target:
# a QCoset{W, Cpad} encoding |1⟩ mod N (coset representation, GE21 §2.4).
# Controlled modular multiplication uses _shor_mulmod_E_controlled! from
# Phase B step 2 — windowed arithmetic via QROM lookup-adds.
#
# Parameters (exposed as kwargs):
#   cpad  — coset padding qubits. ↑cpad → ↓deviation, ↑qubit count.
#           Total deviation over t stages bounded by ~(t·Wtot/c_mul)·2^-cpad.
#   c_mul — multiplication window size. ↑c_mul → ↓multiplication count
#           (folded into QROM lookups), ↑table size 2^c_mul entries.
#
# Acceptance (bead Sturm.jl-6oc):
#   shor_order_E(7, 15, Val(3)) r=4 hit rate ≥ 30% over 50 shots
#   shor_factor_E(15) → {3, 5} ≥ 50% over 20 shots
# ═══════════════════════════════════════════════════════════════════════════

"""
    shor_order_E(a::Int, N::Int, ::Val{t}; cpad::Int=1, c_mul::Int=2,
                  verbose::Bool=false) where {t} -> Int
    shor_order_E(a::Int, N::Int; t::Int=3, kw...) -> Int

Order of `a` mod `N` via Gidney-Ekerå 2021 windowed arithmetic on a coset-
encoded eigenstate. Same Parker-Plenio semi-classical cascade as
[`shor_order_D_semi`](@ref), with `mulmod_beauregard!` replaced by
[`_shor_mulmod_E_controlled!`](@ref) — windowed modular multiplication
with QROM lookup-adds (Gidney 2019 §3.4 Fig 6).

# Parameters
  * `t`     — exponent register width (counter recycled across `t` stages).
  * `cpad`  — coset padding qubits (Gidney 1905.08488 Thm 3.2). Per-op
              deviation ≤ `2^{-cpad}`; accumulated over `t · Wtot / c_mul`
              lookup-adds per mulmod × `t` mulmods.
  * `c_mul` — multiplication window size. 2^c_mul entries per lookup table.
              Larger c_mul → fewer lookups, bigger tables.

# Live-qubit budget (peak, during a single mulmod stage)
  `3·W + 5·cpad + 1 + c_mul`  — target (W+2·cpad) + b (W+2·cpad) + ctrl + scratch (W+cpad) + qrom_anc.

# References
  * Gidney-Ekerå (2021) arXiv:1905.09749 §2.5, Fig 2.
  * Parker & Plenio (2000) arXiv:quant-ph/0002014 (semi-classical iQFT).
  * Ground truth PDFs under `docs/physics/`.
"""
function shor_order_E(a::Int, N::Int, ::Val{t}; cpad::Int=1, c_mul::Int=2,
                      verbose::Bool=false) where {t}
    gcd(a, N) == 1 || error("shor_order_E: a=$a and N=$N must be coprime")
    1 <= a < N || error("shor_order_E: a=$a must satisfy 1 ≤ a < N=$N")
    # Choose W such that N < 2^W strictly (QCoset invariant).
    W = max(2, ceil(Int, log2(N + 1)))
    N < (1 << W) || error("shor_order_E: internal W=$W does not satisfy N<2^W; N=$N")

    ctx = current_context()
    t0 = time_ns()
    lq() = _live_qubits(ctx)
    ms() = round((time_ns() - t0) / 1e6, digits=1)
    verbose && _shor_log("[shor_E t=+0.0ms] start a=$a N=$N t=$t W=$W cpad=$cpad c_mul=$c_mul  live=$(lq())")

    # Parker-Plenio 2000: LSB-first measurement; iter i consumes a^{2^(t-i)}.
    a_js = [powermod(a, 1 << (t - i), N) for i in 1:t]
    verbose && _shor_log("[shor_E t=+$(ms())ms] classical a_j=$(a_js)")

    # Shared coset-encoded eigenstate |1⟩ mod N across all t stages.
    # Boxing W at runtime via Val then dispatch — the underlying QCoset
    # constructor takes type parameters.
    target_coset = _alloc_shor_E_target(ctx, 1, N, W, cpad)
    verbose && _shor_log("[shor_E t=+$(ms())ms] target = QCoset{$W,$cpad}(1, $N) eigenstate  live=$(lq())")

    bits = Bool[]
    sizehint!(bits, t)
    for i in 1:t
        a_j = a_js[i]

        # (a) Fresh counter qubit, H → |+⟩.
        c = QBool(0)
        H!(c)

        # (b) Classical phase correction from prior-measured bits.
        corr = 0.0
        for j in 1:(i - 1)
            if bits[j]
                corr -= 2π / (1 << (i - j + 1))
            end
        end
        if corr != 0.0
            c.φ += corr
        end

        # (c) Skip the mulmod if a_j == 1 (identity).
        if a_j != 1
            verbose && _shor_log("[shor_E t=+$(ms())ms] iter $i: mulby a_$i=$a_j  live=$(lq())")
            t_stage = time_ns()
            _shor_mulmod_E_controlled!(target_coset, a_j, c; c_mul=c_mul)
            stage_ms = round((time_ns() - t_stage) / 1e6, digits=1)
            verbose && _shor_log("[shor_E t=+$(ms())ms] iter $i: mulmod done in $(stage_ms)ms  live=$(lq())")
        else
            verbose && _shor_log("[shor_E t=+$(ms())ms] iter $i: SKIP mulby a_$i=1")
        end

        # (d) H then measure → bit m_i.
        H!(c)
        m_i = Bool(c)
        push!(bits, m_i)
        verbose && _shor_log("[shor_E t=+$(ms())ms] iter $i: m_$i = $(m_i)")
    end

    # Reconstruct ỹ LSB-first and decode period via continued fractions.
    y_tilde = 0
    for (idx, b) in enumerate(bits)
        b && (y_tilde |= (1 << (idx - 1)))
    end
    verbose && _shor_log("[shor_E t=+$(ms())ms] ỹ = $(y_tilde) (bits = $(bits))")

    ptrace!(target_coset)
    r = _shor_period_from_phase(y_tilde, t, N)
    verbose && _shor_log("[shor_E t=+$(ms())ms] decoded φ=$y_tilde/$(1<<t) r=$r  (total=$(ms())ms)")
    return r
end

shor_order_E(a::Int, N::Int; t::Int=3, kw...) = shor_order_E(a, N, Val(t); kw...)

"""
    _alloc_shor_E_target(ctx, k, N, W, cpad) -> QCoset

Runtime-dispatched QCoset allocator: picks the right type-parameterised
QCoset based on the values of W and cpad (which come from `shor_order_E`'s
kwargs, not the caller's dispatch). Uses a @generated-style value-type
trick via `Val`.

# Why not a single call
`QCoset{W,cpad}(...)` requires W and cpad to be compile-time constants.
`shor_order_E` takes them as Integer kwargs, which are runtime values, so
we need an explicit dispatch point.
"""
function _alloc_shor_E_target(ctx::AbstractContext, k::Integer, N::Integer,
                               W::Int, cpad::Int)
    return QCoset{W, cpad}(ctx, k, N)
end

"""
    shor_factor_E(N::Int; max_attempts::Int=16, cpad::Int=1, c_mul::Int=2) -> Vector{Int}

Factor composite `N` via [`shor_order_E`](@ref). Identical classical
post-processing (continued fractions + gcd) to [`shor_factor_D_semi`](@ref).
"""
function shor_factor_E(N::Int; max_attempts::Int=16, cpad::Int=1, c_mul::Int=2)
    N >= 2 || error("shor_factor_E: N=$N must be ≥ 2")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    for _ in 1:max_attempts
        a = rand(2:(N - 1))
        g = gcd(a, N)
        if g > 1
            return sort!([g, N ÷ g])
        end

        r = shor_order_E(a, N; cpad=cpad, c_mul=c_mul)
        fs = _shor_factor_from_order(a, r, N)
        !isempty(fs) && return fs
    end
    return Int[]
end

# ═══════════════════════════════════════════════════════════════════════════
# Impl EH — Ekerå-Håstad 2017 short-DLP derivative
#
# Ground truth: Ekerå & Håstad, "Quantum algorithms for computing short
# discrete logarithms and factoring RSA integers", arXiv:1702.00249
# (2017-02-01).  Local PDF: docs/physics/ekera_2017_short_dlp.pdf
#
# Unlike the A/B/C/D impls which find the ORDER of `a mod N` and reduce to
# factors via gcd(a^{r/2} ± 1, N), impl EH recasts factoring as a short
# discrete log problem (EH17 §5.2) and gives a ~1.5n exponent instead of
# Shor's 2n — asymptotically fewer controlled modular multiplications.
#
# For RSA integer N = pq (EH17 normalisation, §5.2.2):
#   y = g^((N-1)/2) mod N  ≡  g^((p+q-2)/2)  (since (N-1)/2 ≡ (p+q-2)/2 mod
#                                             ord(g) when ord(g) | φ(N))
#   d = (p+q-2)/2         — the short discrete log, 0 < d < 2^(n_prime+1)
#   Recover (p, q) from x² - (2d+2)x + N = 0 via the quadratic formula.
#
# Quantum step (EH17 §4.3, s=1 parameterisation):
#   Two exponent registers of sizes (ℓ+m) and ℓ, working reg |1⟩_L.
#   Prepare both in |+⟩ (uniform).  Compute g^a · y^(-b) mod N on working
#   reg via controlled mulmod cascades.  Inverse QFT each register.
#   Measure → (j, k).  The pair (j, k) is "good" (Def 1) with high
#   probability: |{d·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2).
#
# Classical post-processing (EH17 §4.4, s=1):
#   The 2D lattice L = Z-span of rows [[j, 1], [2^(ℓ+m), 0]], target
#   v = ({-2^m·k}_{2^(ℓ+m)}, 0).  Search for u ∈ L with
#   |u - v| < sqrt(s/4+1)·2^m = sqrt(5)/2·2^m; last coordinate of u is d.
#   For s=1 and small m this reduces to brute force over d ∈ (0, 2^m),
#   testing the residual |{d·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2) bound.
#   ~20 lines pure Julia (mirrors _shor_convergents).
#
# Toy-N caveat (N=15, 21, 35):
#   EH17's analysis (§4.3) requires ord(g) ≥ 2^(ℓ+m) + 2^ℓ·d.  For small
#   N the multiplicative group is too small (ord ≤ 4 at N=15).  The
#   algorithm still yields biased output because the phase structure
#   survives partial wrap-around; empirical hit rate at N=15 is 50-90%.
# ═══════════════════════════════════════════════════════════════════════════

"""
    _eh_recover_d_candidates(j::Int, k::Int, m::Int, ell::Int) -> Vector{Int}

Classical post-processing for the Ekerå-Håstad short-DLP algorithm
(s=1 parameterisation).  Given a quantum measurement outcome `(j, k)` and
the register sizes `m` (short-DLP bit-width) and `ell` (second register),
return the sorted list of all candidate `d ∈ (0, 2^m)` satisfying the
good-pair residual bound

    |{d·j + 2^m·k}_{2^(ℓ+m)}| ≤ 2^(m-2)        (EH17 Def 1)

where `{·}_M` is the centred residue on `[-M/2, M/2)`.  Sorted by
increasing absolute residual (best candidate first).  Empty if `(j, k)`
is not a good pair for any `d`.

Note on spurious candidates (EH17 §4.4, Lemma 3): at small `m`, the 2D
lattice may contain multiple short vectors, so several `d` may pass the
bound.  The caller must verify each via `_eh_factors_from_d` or by
recomputing `g^d mod N`.  For s>1 the lattice `L` has `s+1`
dimensions and the probability of spurious short vectors drops to
`2^{-s-1}`.

# Reference
  Ekerå-Håstad 2017 (arXiv:1702.00249), §4.4;
  `docs/physics/ekera_2017_short_dlp.pdf`.
"""
function _eh_recover_d_candidates(j::Int, k::Int, m::Int, ell::Int)::Vector{Int}
    m >= 1   || error("_eh_recover_d_candidates: m=$m must be ≥ 1")
    ell >= 1 || error("_eh_recover_d_candidates: ell=$ell must be ≥ 1")
    j >= 0   || error("_eh_recover_d_candidates: j=$j must be ≥ 0")
    k >= 0   || error("_eh_recover_d_candidates: k=$k must be ≥ 0")

    M = 1 << (ell + m)
    twom = 1 << m
    bound = m >= 2 ? (1 << (m - 2)) : 0    # 2^(m-2); at m=1 bound=0 (trivial)
    half = M ÷ 2

    pairs = Tuple{Int, Int}[]              # (|residual|, d)
    for d in 1:(twom - 1)
        r = mod(d * j + twom * k, M)
        r = r >= half ? r - M : r
        ar = abs(r)
        if ar <= bound
            push!(pairs, (ar, d))
        end
    end
    sort!(pairs)
    return Int[p[2] for p in pairs]
end

"""
    _eh_factors_from_d(d::Integer, N::Integer) -> Union{Tuple{Int,Int}, Nothing}

Factor recovery for the Ekerå-Håstad algorithm (EH17 §5.2.2, EH normalisation).
Given the short discrete log `d = (p+q-2)/2`, solves the quadratic

    x² - (2d+2)·x + N = 0

whose roots are `x = (d+1) ± √((d+1)² - N)`.

Returns `(p, q)` with `p ≤ q`, `p·q = N`, and `1 < p, q < N`; or `nothing`
if the discriminant is negative or not a perfect square, or if the roots
do not genuinely factor `N`.
"""
function _eh_factors_from_d(d::Integer, N::Integer)::Union{Tuple{Int,Int}, Nothing}
    d >= 1 || return nothing
    N_i = Int(N)
    c = Int(d) + 1
    disc = c * c - N_i
    disc < 0 && return nothing
    sr = isqrt(disc)
    sr * sr == disc || return nothing
    p = c - sr
    q = c + sr
    (p > 1 && q > 1 && p * q == N_i) || return nothing
    return (Int(p), Int(q))
end

"""
    _eh_short_dlp(g::Int, y::Int, N::Int, ::Val{m}, ::Val{ell}, ::Val{L}) -> (j, k)

Quantum step of the Ekerå-Håstad 2017 short-DLP algorithm (§4.3, s=1).
Given a generator `g` and `y = [d]g = g^d mod N` with `0 < d < 2^m`,
runs the two-register phase estimation and returns the measured outcome
`(j, k)` with `j ∈ [0, 2^(ℓ+m))`, `k ∈ [0, 2^ℓ)`.

# Circuit

Three registers:
  * `first_reg :: QInt{ell+m}` — exponent register for `a`.
  * `second_reg :: QInt{ell}`  — exponent register for `b`.
  * `y_reg :: QInt{L}`         — working register, initial state `|1⟩`.

Four phases:
  1. Prepare `first_reg` and `second_reg` in `|+⟩` (via `superpose!(|0⟩)`).
  2. Controlled cascade: for each bit `i` of `first_reg`, apply
     `mulmod_beauregard!(y_reg, g^{2^(i-1)} mod N, N, first_reg[i])`.
     Net effect: `y_reg ← y_reg · g^a mod N`.
  3. Controlled cascade: for each bit `i` of `second_reg`, apply
     `mulmod_beauregard!(y_reg, y_inv^{2^(i-1)} mod N, N, second_reg[i])`
     where `y_inv = invmod(y, N)`.  Net: `y_reg ← y_reg · y^(-b) mod N`.
  4. Inverse QFT on each exponent register, measure → `(j, k)`.

The working register factors out of the final measurement (paper
§4.3 step 4: the measurement of the third register gives `[e]g` but is
discarded — only `(j, k)` feeds classical post-processing).

# Peak qubit budget (per EH17 §4.3, Sturm.jl allocation)

  * `(ell + m) + ell + L` steady-state live wires.
  * `+ L + 1` transient ancilla for each `mulmod_beauregard!` call.
  * For N=15 (`m = ell = 3`, `L = 4`): peak `6 + 3 + 4 + 5 = 18` wires.

# Reference
  Ekerå-Håstad 2017 (arXiv:1702.00249), §4.3;
  `docs/physics/ekera_2017_short_dlp.pdf`.
"""
function _eh_short_dlp(g::Int, y::Int, N::Int,
                      ::Val{m}, ::Val{ell}, ::Val{L};
                      verbose::Bool=false) where {m, ell, L}
    gcd(g, N) == 1 || error("_eh_short_dlp: gcd(g=$g, N=$N) must be 1")
    gcd(y, N) == 1 || error("_eh_short_dlp: gcd(y=$y, N=$N) must be 1")
    N < (1 << L)   || error("_eh_short_dlp: N=$N must fit in L=$L bits")

    ctx = current_context()
    W1 = ell + m
    t0 = time_ns()
    ms() = round((time_ns() - t0) / 1e6, digits=1)
    lq() = _live_qubits(ctx)
    function log(msg::AbstractString)
        verbose || return
        print(stderr, "[eh_dlp +", ms(), "ms live=", lq(), "] ", msg, "\n")
        flush(stderr)
    end

    log("ENTER g=$g y=$y N=$N m=$m ell=$ell L=$L W1=$W1")

    # Exponent registers: start at |0⟩, then put in |+⟩ via superpose! (= QFT).
    # QFT|0⟩ = (1/√2^W)·Σ|k⟩ = |+⟩^W, which is what step 1 of §4.3 calls for.
    first_reg  = QInt{W1}(ctx, 0)
    log("alloc first_reg[W1=$W1]")
    second_reg = QInt{ell}(ctx, 0)
    log("alloc second_reg[ell=$ell]")
    superpose!(first_reg)
    log("superpose!(first_reg) → |+⟩^$W1")
    superpose!(second_reg)
    log("superpose!(second_reg) → |+⟩^$ell")

    # Working register in eigenstate-style init |1⟩ (§4.3 step 2 acts on |0⟩
    # then prepends |1⟩ via the ⊙ group operation; initialising to |1⟩
    # directly is equivalent and avoids an extra mulby-1).
    y_reg = QInt{L}(ctx, 1)
    log("alloc y_reg[L=$L] = |1⟩")

    # Phase 2 — y_reg ← y_reg · g^a mod N, bit-controlled from first_reg.
    for i in 1:W1
        pow = powermod(g, 1 << (i - 1), N)
        if pow == 1
            log("first_reg[$i]: pow=g^$(1<<(i-1)) mod $N = 1 → SKIP (identity)")
            continue                        # identity: skip
        end
        log("first_reg[$i]: ENTER mulmod_beauregard!(y_reg, $pow, $N)")
        mulmod_beauregard!(y_reg, pow, N, first_reg[i])
        log("first_reg[$i]: EXIT  mulmod_beauregard!")
    end

    # Phase 3 — y_reg ← y_reg · y^(-b) mod N, bit-controlled from second_reg.
    y_inv = invmod(y, N)
    log("y_inv = invmod($y, $N) = $y_inv")
    for i in 1:ell
        pow = powermod(y_inv, 1 << (i - 1), N)
        if pow == 1
            log("second_reg[$i]: pow=y_inv^$(1<<(i-1)) mod $N = 1 → SKIP")
            continue
        end
        log("second_reg[$i]: ENTER mulmod_beauregard!(y_reg, $pow, $N)")
        mulmod_beauregard!(y_reg, pow, N, second_reg[i])
        log("second_reg[$i]: EXIT  mulmod_beauregard!")
    end

    # Phase 4 — inverse QFT on each exponent register, then measure.
    # (Paper §4.3 step 3 writes QFT; inverse QFT gives the same |·|² peak
    #  structure, matches Sturm's existing Shor A/B/C convention, and
    #  keeps j, k in the "continued-fractions compatible" orientation.)
    log("interfere!(first_reg)")
    interfere!(first_reg)
    log("interfere!(second_reg)")
    interfere!(second_reg)

    log("measure first_reg + second_reg")
    j = Int(first_reg)
    k = Int(second_reg)
    ptrace!(y_reg)
    log("EXIT  j=$j k=$k")
    return j, k
end

"""
    shor_factor_EH(N::Int; max_attempts::Int=16, verbose::Bool=false) -> Vector{Int}

Factor composite `N = p·q` via the Ekerå-Håstad 2017 short-DLP derivative
of Shor's algorithm (EH17 §5.2).  Returns `sort([p, q])` on success,
`Int[]` after exhausting attempts.

For an `n`-bit semiprime the EH17 exponent-register width is
`2ℓ + m ≈ 1.5n` bits (single-shot `s=1` parameterisation), compared to
Shor's `2n`.  At small `N` the asymptotic savings do not apply — see
the "toy-N caveat" in the comment block above.

# Parameter selection

Default heuristic: `n_N = ceil(log2(N+1))`, `m = max(3, (n_N+1)÷2 + 1)`,
`ell = m` (s = 1), `L = max(1, ceil(log2(N)))`.  For N=15 (`n_N=4`):
`m = ell = 3`, `L = 4`.

When the caller has tight qubit-budget constraints and knows a smaller
`m` suffices (e.g. `d` is known to fit), pass `m` and `ell` explicitly.
Peak live wires = `2·ell + m + 2·L + 3`.

# Reference
  Ekerå-Håstad 2017 (arXiv:1702.00249) §5.2;
  `docs/physics/ekera_2017_short_dlp.pdf`.
  Gidney-Ekerå 2021 §2.1 (use as an optimisation stage in Shor pipeline).
"""
function shor_factor_EH(N::Int;
                        m::Union{Int, Nothing}=nothing,
                        ell::Union{Int, Nothing}=nothing,
                        max_attempts::Int=16, verbose::Bool=false)
    N >= 4 || error("shor_factor_EH: N=$N must be ≥ 4")
    N % 2 == 0 && return sort!([2, N ÷ 2])

    # Parameter selection for EH17 s=1 normalisation (§5.2.4).
    # Default heuristic guarantees d < 2^m for any allowable (p, q) with
    # similarly-sized primes.  Caller may override via `m` / `ell` kwargs
    # to squeeze qubit budget when (p, q) are known smaller.
    n_N = ceil(Int, log2(N + 1))
    m_val   = m === nothing   ? max(3, (n_N + 1) ÷ 2 + 1) : m
    ell_val = ell === nothing ? m_val : ell              # s = 1 default
    L_val   = max(1, ceil(Int, log2(N)))                 # working register
    m_val   >= 1 || error("shor_factor_EH: m=$m_val must be ≥ 1")
    ell_val >= 1 || error("shor_factor_EH: ell=$ell_val must be ≥ 1")

    for attempt in 1:max_attempts
        g = rand(2:(N - 1))
        gcd_gN = gcd(g, N)
        if gcd_gN > 1
            # Lucky draw: g shares a factor with N.  Return it without
            # invoking the quantum step.
            return sort!([gcd_gN, N ÷ gcd_gN])
        end

        # y = g^((N-1)/2) mod N (EH17 §5.2.2 normalisation).  Retry if y == 1,
        # which happens when g is in a subgroup too small to encode d.
        y = powermod(g, (N - 1) ÷ 2, N)
        y == 1 && continue

        # Quantum step — returns the two QFT outcomes.
        j, k = _eh_short_dlp(g, y, N, Val(m_val), Val(ell_val), Val(L_val);
                             verbose=verbose)

        # Classical post-processing — iterate lattice candidates, verify
        # each via the quadratic recovery + multiplication check.
        cands = _eh_recover_d_candidates(j, k, m_val, ell_val)
        for d in cands
            fs = _eh_factors_from_d(d, N)
            fs === nothing && continue
            p, q = fs
            if 1 < p < N && 1 < q < N && p * q == N
                return sort!([p, q])
            end
        end
    end
    return Int[]
end

