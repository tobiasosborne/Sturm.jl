# test_compact_state_logical.jl — bead Sturm.jl-pw9
#
# `compact_state_logical!` is the in-place variant of `compact_state!`:
# same wire-remap and amplitude projection, but mutates the existing
# Orkan buffer rather than allocating a new one. Used by
# `apply_reversible!` after Bennett ancilla cleanup so sub-threshold
# bursts (3–7 ancillae, below deallocate's 2*GROW_STEP=8 trigger) don't
# leave `n_qubits` stuck at the burst peak — every subsequent gate would
# otherwise pay `2^peak` cost on a buffer mostly full of zeros.

using Test
using Random
using Sturm
using Sturm: EagerContext, allocate!, ptrace!, apply_ry!, apply_rz!, apply_cx!,
             compact_state!, compact_state_logical!, _compact_plan,
             _compact_scatter!, _compact_scatter_inplace!, _bump_orkan_qubits!

@testset "compact_state_logical! (Sturm.jl-pw9)" begin

    @testset "no-op when free_slots is empty" begin
        @context EagerContext(capacity=8) begin
            ctx = current_context()
            a = allocate!(ctx); b = allocate!(ctx); c = allocate!(ctx)
            apply_ry!(ctx, a, π/3)
            apply_cx!(ctx, a, b)
            n_before = ctx.n_qubits
            cap_before = ctx.capacity
            orkan_qubits_before = Int(ctx.orkan.raw.qubits)
            compact_state_logical!(ctx)
            @test ctx.n_qubits == n_before
            @test ctx.capacity == cap_before
            @test Int(ctx.orkan.raw.qubits) == orkan_qubits_before
        end
    end

    @testset "post-compact contract: n_qubits drops, capacity unchanged" begin
        @context EagerContext(capacity=8) begin
            ctx = current_context()
            # Allocate 6 wires, deallocate 4 of them at non-contiguous slots.
            ws = [allocate!(ctx) for _ in 1:6]
            cap_before = ctx.capacity
            orkan_buffer_ptr_before = ctx.orkan.raw.data
            ptrace!(Sturm.QBool(ws[1], ctx, false))
            ptrace!(Sturm.QBool(ws[3], ctx, false))
            ptrace!(Sturm.QBool(ws[5], ctx, false))
            ptrace!(Sturm.QBool(ws[6], ctx, false))
            # Bypass the deallocate-trigger logic that may have run
            # compact_state! if capacity is small. We want to test pw9 directly.
            # If free_slots is empty (compact_state! already fired), prep more.
            if isempty(ctx.free_slots)
                # rebuild the scenario at a higher count so threshold isn't hit
                w_extra = allocate!(ctx)
                ptrace!(Sturm.QBool(w_extra, ctx, false))
            end
            @test !isempty(ctx.free_slots)
            n_before_compact = ctx.n_qubits
            cap_before_compact = ctx.capacity
            buffer_before = ctx.orkan.raw.data
            n_live = length(ctx.wire_to_qubit)

            compact_state_logical!(ctx)

            @test ctx.n_qubits == n_live
            @test Int(ctx.orkan.raw.qubits) == n_live
            @test ctx.capacity == cap_before_compact   # capacity UNCHANGED — pw9's whole point
            @test ctx.orkan.raw.data == buffer_before  # SAME orkan buffer — no realloc
            @test isempty(ctx.free_slots)
            # Live wires now contiguous at slots 0..n_live-1
            for w in keys(ctx.wire_to_qubit)
                @test 0 <= ctx.wire_to_qubit[w] < n_live
            end
            slots = sort!(collect(values(ctx.wire_to_qubit)))
            @test slots == collect(0:n_live - 1)
        end
    end

    @testset "amplitudes match buffer-shrinking compact_state!" begin
        # Same circuit + same dealloc pattern: the live amplitudes after
        # compact_state_logical! must equal those after compact_state!
        # (only the FIRST 2^new_n entries — positions beyond may differ
        # since logical leaves stale data there, gates ignore via state.qubits).
        function build_state!(ctx)
            ws = [allocate!(ctx) for _ in 1:5]
            apply_ry!(ctx, ws[1], 0.7)
            apply_ry!(ctx, ws[2], 1.1)
            apply_cx!(ctx, ws[1], ws[3])
            apply_rz!(ctx, ws[4], 0.4)
            apply_cx!(ctx, ws[2], ws[4])
            apply_ry!(ctx, ws[5], 0.5)
            # Discard wires 3, 4, 5 → free_slots gets non-contiguous slots
            ptrace!(Sturm.QBool(ws[3], ctx, false))
            ptrace!(Sturm.QBool(ws[5], ctx, false))
            ptrace!(Sturm.QBool(ws[4], ctx, false))
            return ws
        end

        # build_state! includes ptraces (measurement) — non-deterministic post-state.
        # Pin RNG so the reference and logical paths land on the same outcomes.
        # Reference path: compact_state! (allocates new orkan)
        ctx_ref = EagerContext(capacity=12)
        local ref_amps
        Random.seed!(42)
        @context ctx_ref begin
            build_state!(ctx_ref)
            # If the deallocate trigger already fired compact_state!, free_slots
            # is empty and there's nothing to compare. Force a fresh non-empty
            # free_slots if needed.
            if isempty(ctx_ref.free_slots)
                w = allocate!(ctx_ref)
                ptrace!(Sturm.QBool(w, ctx_ref, false))
            end
            compact_state!(ctx_ref)
            # After compact_state!, ctx_ref runs at small capacity. Snapshot
            # the live-region amplitudes (first 2^n_live entries).
            n_live = ctx_ref.n_qubits
            new_dim = 1 << n_live
            ref_amps = unsafe_wrap(Array{ComplexF64,1}, ctx_ref.orkan.raw.data, new_dim) |> copy
        end

        # Logical path: compact_state_logical! (in-place) — same seed.
        ctx_log = EagerContext(capacity=12)
        local n_live_log, log_amps, cap_after_log, ptr_before, ptr_after
        Random.seed!(42)
        @context ctx_log begin
            build_state!(ctx_log)
            if isempty(ctx_log.free_slots)
                w = allocate!(ctx_log)
                ptrace!(Sturm.QBool(w, ctx_log, false))
            end
            cap_before = ctx_log.capacity
            ptr_before = ctx_log.orkan.raw.data
            compact_state_logical!(ctx_log)
            cap_after_log = ctx_log.capacity
            ptr_after = ctx_log.orkan.raw.data
            n_live_log = ctx_log.n_qubits
            new_dim = 1 << n_live_log
            log_amps = unsafe_wrap(Array{ComplexF64,1}, ctx_log.orkan.raw.data, new_dim) |> copy
            @test cap_after_log == cap_before
            @test ptr_after == ptr_before
        end

        n_live = length(ref_amps) |> n -> Int(log2(n))
        @test n_live_log == n_live
        @test log_amps ≈ ref_amps atol=1e-12
    end

    @testset "subsequent allocate! correctly bumps orkan.qubits" begin
        # After logical compact, allocate! must restore orkan.raw.qubits
        # so gates address the new slot. Without this, the ccall would
        # see a stale dim and refuse / silently miss the slot.
        @context EagerContext(capacity=12) begin
            ctx = current_context()
            ws = [allocate!(ctx) for _ in 1:5]
            ptrace!(Sturm.QBool(ws[2], ctx, false))
            ptrace!(Sturm.QBool(ws[4], ctx, false))
            if isempty(ctx.free_slots)
                w = allocate!(ctx)
                ptrace!(Sturm.QBool(w, ctx, false))
            end
            compact_state_logical!(ctx)
            n_after_compact = ctx.n_qubits
            orkan_qubits_after_compact = Int(ctx.orkan.raw.qubits)
            @test n_after_compact == orkan_qubits_after_compact
            # Allocate a fresh wire — n_qubits goes up; orkan.raw.qubits must follow.
            w_new = allocate!(ctx)
            @test ctx.n_qubits == n_after_compact + 1
            @test Int(ctx.orkan.raw.qubits) == n_after_compact + 1
            # Gate on the new wire must work without error (would crash if
            # orkan saw qubit_idx ≥ state.qubits).
            apply_ry!(ctx, w_new, π/4)
        end
    end

    @testset "Bennett path: apply_reversible! drops n_qubits after burst" begin
        # The bead's headline acceptance: post-Bennett-call, ctx.n_qubits is
        # bounded by the live set (input + output wires), not the burst peak.
        @context EagerContext(capacity=12) begin
            ctx = current_context()
            x = Sturm.QInt{2}(2)
            n_qubits_before = ctx.n_qubits
            cap_before = ctx.capacity
            # Use oracle_table: triggers a Bennett ancilla burst inside
            # apply_reversible!. After return, the apply_reversible! finally
            # block calls compact_state_logical! → n_qubits should be at most
            # input_W + output_W = 4 (typical burst peak before this fix
            # was ~7-9 wires).
            y = Sturm.oracle_table(k -> 2k + 1, x, Val(2))
            n_qubits_after = ctx.n_qubits
            cap_after = ctx.capacity
            @test n_qubits_after <= 4   # x: W=2 + y: W=2; ancillae freed
            @test Int(ctx.orkan.raw.qubits) == n_qubits_after
            # Capacity must NOT have shrunk via realloc (that's compact_state!,
            # not the logical variant). It might still grow if the burst pushed
            # past the initial capacity — that's fine, just not shrunk-by-realloc.
            @test cap_after >= cap_before
            @test Int(y) == 1   # 2*0+1 mask 3 ≠ 0 — at least exercise correctness
        end
    end

    @testset "_compact_scatter_inplace! matches _compact_scatter! amplitude-by-amplitude" begin
        # Direct unit test of the in-place scatter against the reference
        # out-of-place version on a contrived plan, using a hand-built
        # amplitude buffer.
        using Sturm: CompactPlan, OrkanState, ORKAN_PURE
        # n=4, live_slots=[0, 2], freed=[1, 3]. new_n=2, new_dim=4.
        old_n = 4; new_n = 2
        old_dim = 1 << old_n
        plan = CompactPlan(
            old_n, new_n, 4,
            [Sturm.WireID(UInt32(101)), Sturm.WireID(UInt32(102))],
            [0, 2],
            UInt64(0b1010),  # bits 1 and 3 freed
        )
        # Test buffer: arbitrary amplitudes; precondition |0⟩ on freed
        # bits is NOT enforced by _compact_scatter_inplace! (the upstream
        # _compact_verify_freed_zero owns that — we're unit-testing scatter).
        ref_amps = ComplexF64[i + 0im for i in 1:old_dim]

        # Reference: out-of-place scatter into a fresh new-dim buffer.
        new_dim = 1 << new_n
        new_orkan_ref = OrkanState(ORKAN_PURE, new_n)
        old_orkan_ref = OrkanState(ORKAN_PURE, old_n)
        old_view_ref = unsafe_wrap(Array{ComplexF64,1}, old_orkan_ref.raw.data, old_dim)
        copyto!(old_view_ref, ref_amps)
        _compact_scatter!(new_orkan_ref, old_orkan_ref, plan)
        new_view_ref = unsafe_wrap(Array{ComplexF64,1}, new_orkan_ref.raw.data, new_dim) |> copy

        # In-place: scatter on a fresh single buffer.
        orkan_inp = OrkanState(ORKAN_PURE, old_n)
        view_inp = unsafe_wrap(Array{ComplexF64,1}, orkan_inp.raw.data, old_dim)
        copyto!(view_inp, ref_amps)
        _compact_scatter_inplace!(orkan_inp, plan)
        new_view_inp = view_inp[1:new_dim]

        @test new_view_inp ≈ new_view_ref atol=1e-12
    end
end
