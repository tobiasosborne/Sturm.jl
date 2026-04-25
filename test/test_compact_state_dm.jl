# test_compact_state_dm.jl — Stage A1 of bead Sturm.jl-amc.
#
# Red tests for `compact_state!(ctx::DensityMatrixContext)`: the density-matrix
# mirror of the EagerContext compaction primitive (bead Sturm.jl-059). Remaps
# live wires to compact slots `0..k-1` and shrinks the MIXED_PACKED packed
# buffer from `2^old_n × 2^old_n` to `2^k × 2^k` (lower-triangle stored).
#
# Soundness assumption: every slot in `ctx.free_slots` was freed via
# `_blessed_measure!` and is therefore in |0⟩ on both row AND column indices.
# Stronger than the pure-state precondition because off-diagonal coherences in
# freed rows/cols must also be zero.
#
# Layout: MIXED_PACKED is LAPACK 'L' lower-triangle column-major packed.
# Length = `dim*(dim+1)/2`. Element `(r, c)` with `r ≥ c` is at packed index
# `c*(2*dim - c + 1)/2 + (r - c)`. Upper triangle returned as conj(lower).
#
# The tests are organised under these @testsets, mirroring test_compact_state.jl:
#   1. CONTRACT      — public API behaviour
#   2. STATE         — preservation of density-matrix entries / correlations
#   3. SOUNDNESS     — precondition fires; off-diagonal violations caught
#   4. ATOMICITY     — failed compact leaves ctx unchanged
#   5. AUTO-TRIGGER  — deallocate fires compact at threshold; ping-pong bounded
#   6. PRE-FLIGHT    — each error path fires loud
#   7. GROW          — _grow_density_state! correctness under bulk migration

using Test
using Sturm
using Sturm: DensityMatrixContext, QBool, ptrace!, when
using Sturm: allocate!, deallocate!, _blessed_measure!

# ── Helpers ──────────────────────────────────────────────────────────────────

# Zero-copy view of the MIXED_PACKED lower-triangle buffer. Uses capacity
# (NOT n_qubits) because Orkan's packed layout is keyed off `state->qubits =
# capacity`. The live block lives in the [0, 2^n_qubits)² subregion of the
# lower triangle, addressed via `_dm_col_off(2^capacity, c)`.
function _dm_packed_view(ctx::DensityMatrixContext)
    cap = ctx.capacity
    cap_dim = 1 << cap
    buf_len = (cap_dim * (cap_dim + 1)) ÷ 2
    return unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, buf_len)
end

# Materialise the full dim×dim Hermitian density matrix as a Julia 2D array
# (uses orkan_state_get, which handles upper-triangle conjugation). Used in
# tests that need to compare entries directly.
function _dm_full(ctx::DensityMatrixContext)
    n = ctx.n_qubits
    dim = 1 << n
    rho = zeros(ComplexF64, dim, dim)
    for r in 0:dim - 1
        for c in 0:dim - 1
            rho[r + 1, c + 1] = ctx.orkan[r, c]
        end
    end
    return rho
end

# Residual norm² over freed rows/cols — DM analogue of the eager helper.
# Sums |ρ[r,c]|² over the stored lower triangle of the LIVE block where
# the freed mask hits the row OR column. Symmetric upper-triangle violations
# have equal modulus and are not double-counted (we scan the stored lower
# triangle once). Packed indices use `cap_dim = 2^capacity`, NOT n_qubits.
function _dm_residual_norm_sq(ctx::DensityMatrixContext, freed_slots::Vector{Int})
    isempty(freed_slots) && return 0.0
    cap_dim = 1 << ctx.capacity
    live_dim = 1 << ctx.n_qubits
    mask = UInt64(0)
    for s in freed_slots; mask |= UInt64(1) << s; end
    buf = _dm_packed_view(ctx)
    acc = 0.0
    @inbounds for c in 0:live_dim - 1
        col_off = (c * (2 * cap_dim - c + 1)) ÷ 2
        for offset in 0:(live_dim - c - 1)
            r = c + offset
            if (UInt64(r) & mask) != 0 || (UInt64(c) & mask) != 0
                acc += abs2(buf[col_off + offset + 1])
            end
        end
    end
    return acc
end

@testset "compact_state! — DensityMatrixContext (Sturm.jl-amc)" begin

    # ── 1. CONTRACT ────────────────────────────────────────────────────────

    @testset "contract" begin

        @testset "no-op when free_slots empty" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0.5)
                b = QBool(0)
                old_n = ctx.n_qubits
                old_cap = ctx.capacity
                old_w2q = copy(ctx.wire_to_qubit)
                Sturm.compact_state!(ctx)
                @test ctx.n_qubits == old_n
                @test ctx.capacity == old_cap
                @test ctx.wire_to_qubit == old_w2q
                @test isempty(ctx.free_slots)
                ptrace!(a); ptrace!(b)
            end
        end

        @testset "returns the context (chain-friendly)" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                ptrace!(b); ptrace!(c)
                @test Sturm.compact_state!(ctx) === ctx
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "alloc 4, ptrace 2, compact → n_qubits=2, free_slots=[]" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                ptrace!(b); ptrace!(c)
                @test ctx.n_qubits == 4
                @test length(ctx.free_slots) == 2
                Sturm.compact_state!(ctx)
                @test ctx.n_qubits == 2
                @test isempty(ctx.free_slots)
                live_slots = sort!(collect(values(ctx.wire_to_qubit)))
                @test live_slots == [0, 1]
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "live wires retain their identity after compact" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                a_id = a.wire; d_id = d.wire
                ptrace!(b); ptrace!(c)
                Sturm.compact_state!(ctx)
                @test haskey(ctx.wire_to_qubit, a_id)
                @test haskey(ctx.wire_to_qubit, d_id)
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "consumed wires stay consumed after compact" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0)
                b_id = b.wire
                ptrace!(b)
                @test b_id in ctx.consumed
                Sturm.compact_state!(ctx)
                @test b_id in ctx.consumed
                @test !haskey(ctx.wire_to_qubit, b_id)
                ptrace!(a)
            end
        end
    end

    # ── 2. STATE PRESERVATION ──────────────────────────────────────────────

    @testset "state preservation" begin

        @testset "compact preserves single-qubit ρ entries" begin
            # Allocate scratch first (slot 0). Allocate `a` second (slot 1)
            # and prepare a non-trivial state with both diagonal AND off-
            # diagonal density-matrix entries: Ry(θ)|0⟩ = cos(θ/2)|0⟩+sin(θ/2)|1⟩
            # gives ρ_a with cross-terms. Discard scratch, compact, verify
            # the surviving 2×2 ρ matches the 2×2 marginal of the pre-compact
            # ρ.
            @context DensityMatrixContext() begin
                ctx = current_context()
                scratch = QBool(0)            # slot 0
                a = QBool(0)                   # slot 1, preparing |0⟩
                a.θ += π / 3                  # Ry(π/3): puts a in superposition
                a.φ += π / 4                  # Rz(π/4): adds a phase
                # Pre-compact: 4-dim ρ. The slot-0 (scratch) is in |0⟩, so the
                # only non-zero block is rows/cols where bit 0 = 0; entries
                # are at indices {0, 2}.
                pre_full = _dm_full(ctx)
                @test pre_full[1 + 0, 1 + 0] ≈ cos(π / 6)^2 atol=1e-12      # |α|²
                @test pre_full[1 + 2, 1 + 2] ≈ sin(π / 6)^2 atol=1e-12      # |β|²
                # |ψ_a⟩ = Rz(π/4) Ry(π/3) |0⟩ = cos(π/6) e^(-iπ/8) |0⟩ + sin(π/6) e^(+iπ/8) |1⟩
                # ρ_a[1,0] = β α* = sin(π/6) cos(π/6) · e^(+iπ/8) · e^(+iπ/8) = sin(π/6) cos(π/6) e^(+iπ/4)
                # In joint indices (slot 0 scratch in |0⟩, slot 1 = a):
                # ρ_joint[2, 0] = ρ_a[1, 0] · ρ_scratch[0, 0] = cos(π/6) sin(π/6) e^(+iπ/4)
                expected_off = cos(π / 6) * sin(π / 6) * cis(+π / 4)
                @test pre_full[1 + 2, 1 + 0] ≈ expected_off atol=1e-12
                # Discard scratch, compact.
                ptrace!(scratch)
                Sturm.compact_state!(ctx)
                @test ctx.n_qubits == 1
                # Post-compact: 2-dim ρ on `a` only. Should equal the
                # marginal of pre_full over scratch (= entries at indices
                # {0, 2} of pre_full reindexed to {0, 1}).
                post_full = _dm_full(ctx)
                @test size(post_full) == (2, 2)
                @test post_full[1, 1] ≈ pre_full[1 + 0, 1 + 0] atol=1e-12
                @test post_full[2, 2] ≈ pre_full[1 + 2, 1 + 2] atol=1e-12
                @test post_full[2, 1] ≈ pre_full[1 + 2, 1 + 0] atol=1e-12
                @test post_full[1, 2] ≈ pre_full[1 + 0, 1 + 2] atol=1e-12
                # Trace preserved.
                @test real(post_full[1, 1] + post_full[2, 2]) ≈ 1.0 atol=1e-12
                ptrace!(a)
            end
        end

        @testset "compact preserves Bell-pair correlations" begin
            results = (Bool[], Bool[])
            for _ in 1:200
                @context DensityMatrixContext() begin
                    ctx = current_context()
                    junk = QBool(0)        # slot 0
                    a = QBool(0.5)          # slot 1
                    b = QBool(0)            # slot 2
                    b ⊻= a                  # entangle
                    ptrace!(junk)
                    Sturm.compact_state!(ctx)
                    @test ctx.n_qubits == 2
                    push!(results[1], Bool(a))
                    push!(results[2], Bool(b))
                end
            end
            @test results[1] == results[2]
        end

        @testset "compact then more gates yields same state as no-compact" begin
            # Identical computations, with vs without a mid-circuit compact.
            # Compare the marginal density matrix on the 2 surviving qubits.
            function run_with_compact(do_compact::Bool)
                @context DensityMatrixContext() begin
                    ctx = current_context()
                    junk = QBool(0)       # slot 0
                    a = QBool(0.5)         # slot 1
                    b = QBool(0)           # slot 2
                    b ⊻= a                  # Bell
                    ptrace!(junk)
                    if do_compact
                        Sturm.compact_state!(ctx)
                    end
                    a.φ += π / 3
                    when(a) do
                        b.φ += π / 5
                    end
                    return _dm_full(ctx), ctx.n_qubits
                end
            end
            rho_no, n_no = run_with_compact(false)
            rho_cp, n_cp = run_with_compact(true)
            @test n_cp <= n_no
            # Marginalise rho_no over junk (slot 0): for each (r_live, c_live)
            # in [0, 4) the marginal is rho_no[2*r_live + 0 + 1, 2*c_live + 0 + 1]
            # since junk is at bit 0 and is in |0⟩ — only the bit0=0 block
            # has non-zero entries.
            @test n_no == n_cp + 1
            dim_cp = 1 << n_cp
            for r in 0:dim_cp - 1
                for c in 0:dim_cp - 1
                    @test rho_cp[r + 1, c + 1] ≈ rho_no[(r << 1) + 1, (c << 1) + 1] atol=1e-12
                end
            end
        end

        @testset "stress: random alloc/ptrace at moderate scale" begin
            for trial in 1:5
                @context DensityMatrixContext() begin
                    ctx = current_context()
                    qs = [QBool(rand(Bool) ? 1.0 : 0.0) for _ in 1:6]
                    for i in 1:5
                        if rand(Bool); qs[i + 1] ⊻= qs[i]; end
                    end
                    to_ptrace = sort(collect(rand(1:6, 3)) |> unique, rev=true)
                    survivors = QBool[]
                    for i in 1:6
                        if i in to_ptrace
                            ptrace!(qs[i])
                        else
                            push!(survivors, qs[i])
                        end
                    end
                    Sturm.compact_state!(ctx)
                    @test ctx.n_qubits == length(survivors)
                    @test isempty(ctx.free_slots)
                    @test sort(collect(values(ctx.wire_to_qubit))) ==
                          collect(0:length(survivors) - 1)
                    # Trace must be 1.
                    full = _dm_full(ctx)
                    @test sum(real(full[i, i]) for i in 1:size(full, 1)) ≈ 1.0 atol=1e-10
                    for q in survivors
                        q.φ += π / 6
                    end
                    for q in survivors; ptrace!(q); end
                end
            end
        end
    end

    # ── 3. SOUNDNESS ASSERTION ─────────────────────────────────────────────

    @testset "soundness: error loud if freed slot is not |0⟩" begin
        # Bell pair, then forcibly free a slot WITHOUT measuring. The DM
        # has non-zero entries in BOTH the diagonal (|11⟩⟨11|) AND the
        # off-diagonal (|11⟩⟨00|, |00⟩⟨11|) of the freed-slot direction.
        # Both must contribute to the residual.
        @context DensityMatrixContext() begin
            ctx = current_context()
            a = QBool(0.5)         # slot 0
            b = QBool(0)            # slot 1
            b ⊻= a                  # Bell pair: ρ has 1/2 at (00,00),(00,11),(11,00),(11,11)
            # Forcibly free b's slot WITHOUT measuring.
            b_slot = ctx.wire_to_qubit[b.wire]
            delete!(ctx.wire_to_qubit, b.wire)
            push!(ctx.consumed, b.wire)
            push!(ctx.free_slots, b_slot)
            b.consumed = true
            # Residual over freed rows/cols:
            #   stored lower-triangle entries with (r|c) & freed_mask != 0 :
            #   (3,0) = 1/2 → contributes 1/4 (off-diagonal coherence!)
            #   (3,3) = 1/2 → contributes 1/4 (diagonal population)
            # Total = 0.5.
            @test _dm_residual_norm_sq(ctx, ctx.free_slots) ≈ 0.5 atol=1e-12
            # compact_state! must error loud.
            @test_throws ErrorException Sturm.compact_state!(ctx)
            ptrace!(a)
        end
    end

    @testset "soundness: scan covers off-diagonal coherences" begin
        # Pin that the DM precondition scan picks up off-diagonal (coherence)
        # violations, not just diagonal (population) violations. A naive
        # port of the pure-state residual formula would only sum diagonal
        # entries indexed by `(r & freed_mask) != 0`, missing the
        # off-diagonal contribution. (For a valid Hermitian PSD ρ the two
        # always co-occur — Cauchy-Schwarz forces |ρ[r,c]|² ≤ ρ[r,r]·ρ[c,c]
        # — but the implementation must tally BOTH so the residual gap
        # to the floating-point tolerance is unambiguous.)
        @context DensityMatrixContext() begin
            ctx = current_context()
            a = QBool(0.5)          # slot 0: |+⟩ — has off-diagonal in ρ_a
            b = QBool(0)             # slot 1: |0⟩
            # ρ_total = ρ_a ⊗ |0⟩⟨0|_b. In joint indices (bit 0 = a, bit 1 = b)
            # the live block r,c ∈ {0,1} all hold 1/2:
            #   ρ[0,0] = ρ[0,1] = ρ[1,0] = ρ[1,1] = 1/2.
            # Forcibly free a (freed_mask = 1). Lower-triangle violations:
            #   (1, 0): off-diagonal coherence, |1/2|² = 0.25
            #   (1, 1): diagonal population,    |1/2|² = 0.25
            # Total residual = 0.5; off-diagonal alone is 0.25.
            a_slot = ctx.wire_to_qubit[a.wire]
            delete!(ctx.wire_to_qubit, a.wire)
            push!(ctx.consumed, a.wire)
            push!(ctx.free_slots, a_slot)
            a.consumed = true
            res = _dm_residual_norm_sq(ctx, ctx.free_slots)
            @test res ≈ 0.5 atol=1e-12
            # If the implementation summed only diagonals it would return
            # 0.25, not 0.5. Pinning 0.5 fails any diagonals-only regression.
            @test_throws ErrorException Sturm.compact_state!(ctx)
            ptrace!(b)
        end
    end

    # ── 4. ATOMICITY UNDER EXCEPTION ───────────────────────────────────────

    @testset "atomicity: failed compact leaves ctx unchanged" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
            ptrace!(b); ptrace!(c)
            push!(ctx.free_slots, ctx.free_slots[1])
            old_n = ctx.n_qubits
            old_cap = ctx.capacity
            old_w2q = copy(ctx.wire_to_qubit)
            old_consumed = copy(ctx.consumed)
            old_free = copy(ctx.free_slots)
            old_count = ctx._compact_count
            old_orkan_data = ctx.orkan.raw.data
            @test_throws ErrorException Sturm.compact_state!(ctx)
            @test ctx.n_qubits == old_n
            @test ctx.capacity == old_cap
            @test ctx.wire_to_qubit == old_w2q
            @test ctx.consumed == old_consumed
            @test ctx.free_slots == old_free
            @test ctx._compact_count == old_count
            @test ctx.orkan.raw.data == old_orkan_data
            unique!(ctx.free_slots)
            Sturm.compact_state!(ctx)
            @test ctx.n_qubits == 2
            @test ctx._compact_count == old_count + 1
            ptrace!(a); ptrace!(d)
        end
    end

    # ── 5. AUTO-TRIGGER (deallocate! threshold) ────────────────────────────

    @testset "auto-trigger: deallocate fires compact at threshold" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            qs = [QBool(0) for _ in 1:12]
            @test ctx._compact_count == 0
            for i in 1:7
                ptrace!(qs[i])
            end
            @test ctx._compact_count == 0
            @test length(ctx.free_slots) == 7
            ptrace!(qs[8])
            @test ctx._compact_count == 1
            @test isempty(ctx.free_slots)
            @test ctx.n_qubits == 4
            for i in 9:12; ptrace!(qs[i]); end
        end
    end

    @testset "auto-trigger: ping-pong stays bounded" begin
        @context DensityMatrixContext() begin
            ctx = current_context()
            base = [QBool(0) for _ in 1:4]
            peak = ctx.n_qubits
            for round in 1:10
                burst = [QBool(0) for _ in 1:8]
                peak = max(peak, ctx.n_qubits)
                for q in burst; ptrace!(q); end
            end
            @test peak <= 16
            for q in base; ptrace!(q); end
        end
    end

    # ── 6. PRE-FLIGHT VALIDATION ───────────────────────────────────────────

    @testset "pre-flight validation errors" begin
        @testset "free_slots out-of-range" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0)
                ptrace!(b)
                push!(ctx.free_slots, 99)
                err = try; Sturm.compact_state!(ctx); nothing; catch e; e; end
                @test err isa ErrorException
                @test occursin("out-of-range", err.msg)
                pop!(ctx.free_slots)
                ptrace!(a)
            end
        end

        @testset "free_slots duplicates" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0)
                ptrace!(b); ptrace!(c)
                push!(ctx.free_slots, ctx.free_slots[1])
                err = try; Sturm.compact_state!(ctx); nothing; catch e; e; end
                @test err isa ErrorException
                @test occursin("duplicates", err.msg)
                unique!(ctx.free_slots)
                ptrace!(a)
            end
        end

        @testset "live and freed slot sets overlap" begin
            @context DensityMatrixContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0)
                ptrace!(b)
                live_slot = first(values(ctx.wire_to_qubit))
                push!(ctx.free_slots, live_slot)
                err = try; Sturm.compact_state!(ctx); nothing; catch e; e; end
                @test err isa ErrorException
                @test occursin("BOTH free_slots and wire_to_qubit", err.msg)
                pop!(ctx.free_slots)
                ptrace!(a)
            end
        end
    end

    # ── 7. _grow_density_state! correctness under bulk migration ──────────
    #
    # The bead also asks us to migrate `_grow_density_state!` from per-element
    # FFI to bulk `unsafe_wrap` + per-column `unsafe_copyto!`. Per-column is
    # mandatory: `col_off(dim, c)` depends on `dim`, so a single bulk copy of
    # the old packed buffer into the new one would misroute every column
    # except column 0. These tests pin that invariant.

    @testset "growth preserves arbitrary ρ" begin
        # Allocate a small set, bake a non-trivial ρ, then force growth by
        # allocating past the initial capacity. The post-growth ρ must
        # restrict to the original on the [0, old_dim) × [0, old_dim) block,
        # and must be zero outside.
        @context DensityMatrixContext(capacity=2) begin
            ctx = current_context()
            # Initial capacity 2 → forces a grow when we allocate the 3rd qubit.
            a = QBool(0)
            b = QBool(0)
            a.θ += π / 3   # Ry(π/3) on a
            b ⊻= a          # entangle a, b
            pre_full = _dm_full(ctx)
            @test ctx.capacity == 2
            # Force growth: allocate a third qubit (calls _grow_density_state!).
            c = QBool(0)
            @test ctx.capacity > 2     # grew
            post_full = _dm_full(ctx)
            old_dim = 1 << 2
            new_dim = 1 << ctx.n_qubits
            # The [0, old_dim) × [0, old_dim) block of post must equal pre.
            for r in 0:old_dim - 1
                for col in 0:old_dim - 1
                    @test post_full[r + 1, col + 1] ≈ pre_full[r + 1, col + 1] atol=1e-12
                end
            end
            # Entries outside the old block (i.e., where any new qubit bit
            # is set, in either row or col) must be zero — the new qubit is
            # in |0⟩⟨0| by construction.
            new_bits_mask = (1 << ctx.n_qubits) - old_dim   # mask for bits >= old_n
            for r in 0:new_dim - 1
                for col in 0:new_dim - 1
                    if (r & new_bits_mask) != 0 || (col & new_bits_mask) != 0
                        @test abs2(post_full[r + 1, col + 1]) < 1e-20
                    end
                end
            end
            # Trace preserved.
            @test sum(real(post_full[i, i]) for i in 1:new_dim) ≈ 1.0 atol=1e-12
            ptrace!(a); ptrace!(b); ptrace!(c)
        end
    end

    @testset "growth + measurement still gives Bell correlations" begin
        # Force at least one growth event mid-circuit by starting with low
        # capacity, then run Bell. Post-grow Bell correlations must hold.
        @context DensityMatrixContext(capacity=2) begin
            for _ in 1:50
                a = QBool(0.5)
                b = QBool(0)        # forces grow
                b ⊻= a
                @test Bool(a) == Bool(b)
            end
        end
    end
end
