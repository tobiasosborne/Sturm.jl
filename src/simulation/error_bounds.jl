# Trotter error bounds with commutator scaling.
#
# Two levels of bounds for ‖S^r(t/r) - exp(-iHt)‖:
#
# 1. Naive 1-norm bound (Lemma 6, Eq. 18):
#      error ≤ O((λt)^{p+1} / r^p)    where λ = Σ|hⱼ|
#      → r = O((λt)^{1+1/p} / ε^{1/p})
#
# 2. Commutator-scaling bound (Theorem p.5, Eq. 2):
#      error ≤ O(α̃_comm · t^{p+1} / r^p)
#      → r = O(α̃_comm^{1/p} · t^{1+1/p} / ε^{1/p})
#
# where α̃_comm = Σ_{γ1,...,γp+1} ‖[H_{γp+1}, ...[H_{γ2}, H_{γ1}]...]‖
# is the nested commutator norm. For Pauli Hamiltonians, this is computable
# exactly because [P_a, P_b] = 0 (commute) or 2i·P_c (anticommute).
#
# Ref: Childs, Su, Tran, Wiebe, Zhu (2021), "Theory of Trotter Error with
#      Commutator Scaling", Phys. Rev. X 11, 011020.
#      arXiv:1912.08854
#      Local PDF: docs/literature/quantum_simulation/product_formulas/1912.08854.pdf

# ── Pauli commutation algebra ───────────────────────────────────────────────
# Two single-qubit Paulis anticommute iff both are non-I and different.
# Multi-qubit: anticommute iff odd number of anticommuting positions.
# Product (ignoring phase): PauliOp XOR (since {I,X,Y,Z} ≅ Z₂×Z₂).

"""Check if two single-qubit Paulis anticommute."""
@inline function _single_anticommutes(a::PauliOp, b::PauliOp)
    a != pauli_I && b != pauli_I && a != b
end

"""
    _pauli_anticommutes(ops_a, ops_b) -> Bool

Check if two N-qubit Pauli strings anticommute.
They anticommute iff they differ on an odd number of non-identity positions.
"""
@inline function _pauli_anticommutes(ops_a::NTuple{N,PauliOp},
                                     ops_b::NTuple{N,PauliOp}) where {N}
    count = 0
    @inbounds for k in 1:N
        count += _single_anticommutes(ops_a[k], ops_b[k])
    end
    isodd(count)
end

"""
    _pauli_product(ops_a, ops_b) -> NTuple{N,PauliOp}

Compute the product Pauli string P_a · P_b (ignoring global phase).
Per-qubit: σ_a · σ_b has Pauli part = a ⊻ b (Klein four-group).
"""
@inline function _pauli_product(ops_a::NTuple{N,PauliOp},
                                ops_b::NTuple{N,PauliOp}) where {N}
    ntuple(k -> PauliOp(UInt8(ops_a[k]) ⊻ UInt8(ops_b[k])), Val(N))
end

# ── Nested commutator norm α̃_comm ──────────────────────────────────────────

"""
    alpha_comm(H::PauliHamiltonian{N}, p::Int) -> Float64

Nested commutator norm [Childs et al. 2021, Eq. 2]:
    α̃_comm = Σ_{γ1,...,γp+1} ‖[H_{γp+1}, ...[H_{γ2}, H_{γ1}]...]‖

For Pauli Hamiltonians, ‖[P_a, P_b]‖ = 2 if anticommute, 0 if commute.
Each nesting level contributes a factor of 2 when nonzero.

Complexity: O(L^{p+1}) where L = number of terms. Feasible for p ≤ 2
and L ≤ ~100. For p ≥ 3, use `alpha_comm_naive` as upper bound.

# Arguments
- `p::Int`: formula order (1 for Trotter1, 2 for Trotter2, etc.)
"""
function alpha_comm(H::PauliHamiltonian{N}, p::Int) where {N}
    p >= 1 || error("alpha_comm: p must be >= 1, got $p")
    L = length(H.terms)

    if p == 1
        return _alpha_comm_p1(H)
    elseif p == 2
        return _alpha_comm_p2(H)
    else
        # For p ≥ 3, exact computation is O(L^{p+1}). Fall back to
        # recursive estimation. For now, use the naive upper bound.
        return _alpha_comm_naive(H, p)
    end
end

"""First-order commutator norm (p=1): α̃ = 2 Σ_{anticommuting pairs} |h_a||h_b|."""
function _alpha_comm_p1(H::PauliHamiltonian{N}) where {N}
    terms = H.terms
    L = length(terms)
    total = 0.0
    @inbounds for i in 1:L
        for j in 1:L
            if _pauli_anticommutes(terms[i].ops, terms[j].ops)
                total += abs(terms[i].coeff) * abs(terms[j].coeff) * 2.0
            end
        end
    end
    total
end

"""Second-order commutator norm (p=2): nested 3-fold commutator.
α̃ = Σ_{γ1,γ2,γ3} ‖[H_{γ3}, [H_{γ2}, H_{γ1}]]‖
For each (γ1,γ2) that anticommute, compute P_C = P_{γ2}·P_{γ1}, then check
if P_{γ3} anticommutes with P_C. Norm = 4|h1||h2||h3| when nonzero."""
function _alpha_comm_p2(H::PauliHamiltonian{N}) where {N}
    terms = H.terms
    L = length(terms)
    total = 0.0
    @inbounds for i in 1:L
        for j in 1:L
            _pauli_anticommutes(terms[j].ops, terms[i].ops) || continue
            # Inner commutator nonzero: P_C = product(P_j, P_i)
            P_C = _pauli_product(terms[j].ops, terms[i].ops)
            coeff_ij = abs(terms[i].coeff) * abs(terms[j].coeff)
            for k in 1:L
                if _pauli_anticommutes(terms[k].ops, P_C)
                    total += coeff_ij * abs(terms[k].coeff) * 4.0
                end
            end
        end
    end
    total
end

"""Naive upper bound on α̃_comm: 2^p · λ^{p+1}, valid for any p.
This is the triangle inequality bound — always larger than the exact value."""
function _alpha_comm_naive(H::PauliHamiltonian, p::Int)
    λ = lambda(H)
    (2.0^p) * λ^(p + 1)
end

# ── Trotter error bounds ────────────────────────────────────────────────────

"""
    trotter_error(H::PauliHamiltonian, t::Real, order::Int;
                  method::Symbol=:comm) -> Float64

Upper bound on ‖S^r(t/r) - exp(-iHt)‖ for ONE Trotter step (r=1).

Methods:
- `:naive` — 1-norm bound [Eq. 18]: O((λt)^{p+1})
- `:comm`  — commutator-scaling [Eq. 2]: O(α̃_comm · t^{p+1})

The `order` parameter is the formula order p (1, 2, 4, 6, ...).

NOTE: These are asymptotic bounds (the O() constant is not explicit in the
general case). They are useful for comparing methods and scaling analysis,
not as tight numerical bounds. See Childs et al. 2021, Section 5 for
tight prefactors at p=1,2.

Ref: Childs et al. (2021), arXiv:1912.08854, Theorem (p.5), Lemma 6 (Eq.18).
"""
function trotter_error(H::PauliHamiltonian, t::Real, order::Int;
                       method::Symbol=:comm)
    order >= 1 || error("trotter_error: order must be >= 1, got $order")
    t >= 0 || error("trotter_error: t must be >= 0, got $t")
    p = order
    if method == :naive
        λ = lambda(H)
        return (λ * t)^(p + 1)
    elseif method == :comm
        α = alpha_comm(H, p)
        return α * t^(p + 1)
    else
        error("trotter_error: unknown method :$method. Use :naive or :comm.")
    end
end

"""
    trotter_steps(H::PauliHamiltonian, t::Real, epsilon::Real, order::Int;
                  method::Symbol=:comm) -> Int

Estimate the number of Trotter steps r needed for error ≤ ε.

From ‖S^r(t/r) - exp(-iHt)‖ ≤ error_per_step · t^{p+1} / r^p ≤ ε:
    r ≥ (error_per_step · t^{p+1} / ε)^{1/p}

Methods:
- `:naive` — r = ⌈(λt)^{1+1/p} / ε^{1/p}⌉  [Corollary 7, Eq. 25]
- `:comm`  — r = ⌈(α̃_comm)^{1/p} · t^{1+1/p} / ε^{1/p}⌉

Ref: Childs et al. (2021), arXiv:1912.08854, Corollary 7.
"""
function trotter_steps(H::PauliHamiltonian, t::Real, epsilon::Real, order::Int;
                       method::Symbol=:comm)
    order >= 1 || error("trotter_steps: order must be >= 1, got $order")
    t >= 0 || error("trotter_steps: t must be >= 0, got $t")
    epsilon > 0 || error("trotter_steps: epsilon must be > 0, got $epsilon")
    t == 0 && return 1
    p = order
    if method == :naive
        λ = lambda(H)
        return ceil(Int, (λ * t)^(1 + 1/p) / epsilon^(1/p))
    elseif method == :comm
        α = alpha_comm(H, p)
        return ceil(Int, α^(1/p) * t^(1 + 1/p) / epsilon^(1/p))
    else
        error("trotter_steps: unknown method :$method. Use :naive or :comm.")
    end
end
