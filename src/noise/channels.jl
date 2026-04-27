# Noise channel implementations using Kraus operators via Orkan.
# All noise channels require DensityMatrixContext.
#
# DELIBERATE ABI EXCEPTION: The Kraus operators below are constructed as
# explicit 2×2 matrices (I, X, Y, Z) and passed to Orkan's kraus_to_superop
# C function. This bypasses the 4-primitive DSL (q.θ, q.φ, ⊻=, QBool).
# This is unavoidable: density matrix channel application requires the matrix
# form for the Orkan superoperator ABI. The DSL primitives apply gates to
# state vectors; Kraus operators act on density matrices via ρ → Σ K_i ρ K_i†.
#
# Ref: Nielsen & Chuang, §8.3 "Quantum noise and quantum operations"
# Depolarising: Eq. (8.102), Dephasing: Eq. (8.96), Amplitude damping: Eq. (8.91)

function _require_density_matrix(ctx::AbstractContext)
    ctx isa DensityMatrixContext || error(
        "Noise channels require DensityMatrixContext, got $(typeof(ctx))"
    )
end

"""
    _apply_kraus!(ctx::DensityMatrixContext, qubit::UInt8, matrices::Vector{Matrix{ComplexF64}})

Apply a quantum channel defined by Kraus operators to a single qubit.
Uses Orkan's kraus_to_superop + channel_1q pipeline.
"""
function _apply_kraus!(ctx::DensityMatrixContext, qubit::UInt8, matrices::Vector{Matrix{ComplexF64}})
    n_terms = length(matrices)
    # Flatten Kraus matrices into contiguous array: [K1[1,1], K1[2,1], K1[1,2], K1[2,2], K2[1,1], ...]
    # Orkan expects column-major 2x2 matrices packed sequentially
    data = Vector{ComplexF64}(undef, 4 * n_terms)
    for (k, M) in enumerate(matrices)
        offset = (k - 1) * 4
        data[offset + 1] = M[1, 1]
        data[offset + 2] = M[2, 1]  # column-major
        data[offset + 3] = M[1, 2]
        data[offset + 4] = M[2, 2]
    end

    # GC.@preserve must span pointer(data) AND the ccall that consumes it.
    # The OrkanKrausRaw struct stores only the raw Ptr, so the GC has no way to
    # see that `data` is still live during orkan_kraus_to_superop — without the
    # anchor, a GC pass between pointer-take and ccall could move/free `data`.
    # Bead Sturm.jl-twv. After kraus_to_superop returns, `sop` owns its own
    # buffer and `data` is no longer needed.
    local sop
    GC.@preserve data begin
        kraus = OrkanKrausRaw(UInt8(1), ntuple(_ -> UInt8(0), 7), UInt64(n_terms), pointer(data))
        sop = orkan_kraus_to_superop(kraus)
    end
    try
        orkan_channel_1q!(ctx.orkan.raw, sop, qubit)
    finally
        orkan_superop_free!(sop)
    end
end

# ── Depolarising channel ─────────────────────────────────────────────────────

"""
    depolarise!(q::QBool, p::Real)

Apply the depolarising channel with probability p.
Kraus operators: {√(1-p)·I, √(p/3)·X, √(p/3)·Y, √(p/3)·Z}

p=0: no effect. p=1: fully depolarised (maximally mixed state ρ = I/2).

Ref: Nielsen & Chuang, Eq. (8.102).
"""
function depolarise!(q::QBool, p::Real)
    check_live!(q)
    _require_density_matrix(q.ctx)
    ctx = q.ctx::DensityMatrixContext
    qubit = _resolve(ctx, q.wire)

    # Standard parameterization: E(ρ) = (1-p)ρ + p·I/2
    # Kraus: {√(1-3p/4)·I, √(p/4)·X, √(p/4)·Y, √(p/4)·Z}
    # Verify: (1-3p/4)ρ + (p/4)(XρX+YρY+ZρZ) = (1-3p/4)ρ + (p/4)(2I-ρ) = (1-p)ρ + p·I/2
    I2 = ComplexF64[1 0; 0 1]
    X2 = ComplexF64[0 1; 1 0]
    Y2 = ComplexF64[0 -im; im 0]
    Z2 = ComplexF64[1 0; 0 -1]

    kraus = Matrix{ComplexF64}[
        sqrt(1 - 3p/4) * I2,
        sqrt(p / 4) * X2,
        sqrt(p / 4) * Y2,
        sqrt(p / 4) * Z2,
    ]
    _apply_kraus!(ctx, qubit, kraus)
end

# ── Dephasing channel ────────────────────────────────────────────────────────

"""
    dephase!(q::QBool, p::Real)

Apply the dephasing (phase-damping) channel with probability p.
Kraus operators: {√(1-p)·I, √p·Z}

p=0: no effect. p=1: full dephasing (off-diagonal elements zeroed).

Ref: Nielsen & Chuang, Eq. (8.96).
"""
function dephase!(q::QBool, p::Real)
    check_live!(q)
    _require_density_matrix(q.ctx)
    ctx = q.ctx::DensityMatrixContext
    qubit = _resolve(ctx, q.wire)

    I2 = ComplexF64[1 0; 0 1]
    Z2 = ComplexF64[1 0; 0 -1]

    kraus = Matrix{ComplexF64}[sqrt(1 - p) * I2, sqrt(p) * Z2]
    _apply_kraus!(ctx, qubit, kraus)
end

# ── Amplitude damping channel ────────────────────────────────────────────────

"""
    amplitude_damp!(q::QBool, γ::Real)

Apply the amplitude damping channel with damping parameter γ.
Models energy relaxation (T1 decay): |1⟩ decays to |0⟩ with probability γ.

Kraus operators: K0 = [[1,0],[0,√(1-γ)]], K1 = [[0,√γ],[0,0]]

γ=0: no effect. γ=1: fully damped (qubit decays to |0⟩).

Ref: Nielsen & Chuang, Eq. (8.91).
"""
function amplitude_damp!(q::QBool, γ::Real)
    check_live!(q)
    _require_density_matrix(q.ctx)
    ctx = q.ctx::DensityMatrixContext
    qubit = _resolve(ctx, q.wire)

    K0 = ComplexF64[1 0; 0 sqrt(1 - γ)]
    K1 = ComplexF64[0 sqrt(γ); 0 0]

    kraus = Matrix{ComplexF64}[K0, K1]
    _apply_kraus!(ctx, qubit, kraus)
end
