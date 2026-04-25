# test_compact_state.jl — Stage A1 of bead Sturm.jl-059.
#
# Red tests for `compact_state!(ctx::EagerContext)`: a primitive that
# remaps live wires to compact slots 0..k-1 and shrinks the Orkan state
# from 2^old_n to 2^k. After A2 lands, all tests here go green.
#
# Soundness assumption (validated empirically by probe_compact_precond.jl,
# Stage A0): every slot in `ctx.free_slots` was freed via `_blessed_measure!`
# and is therefore deterministically in |0⟩. `compact_state!` projects onto
# that |0⟩ branch and errors loud if the assumption is violated.
#
# The tests are organised under three @testsets:
#   1. CONTRACT  — public API behaviour (no-op, semantics, return value).
#   2. STATE     — preservation of amplitudes/statistics across compaction.
#   3. SOUNDNESS — the precondition assertion fires when violated.

using Test
using Sturm
using Sturm: EagerContext, QBool, QInt, QCoset, ptrace!, when
using Sturm: allocate!, deallocate!, _blessed_measure!

# `compact_state!` doesn't exist yet — A1 (this file) is the red gate;
# A2 (the implementation) flips it green. Until A2 lands the testsets
# below fail at the first call site with `UndefVarError: compact_state!`.
# That is the intended red.

# Helper: snapshot amplitudes of a live context (zero-copy via unsafe_wrap).
function _amps_view(ctx::EagerContext)
    dim = 1 << ctx.n_qubits
    return unsafe_wrap(Array{ComplexF64,1}, ctx.orkan.raw.data, dim)
end

# Helper: residual norm² over freed slots (mirror of probe_compact_precond).
function _residual_norm_sq(ctx::EagerContext, freed_slots::Vector{Int})
    isempty(freed_slots) && return 0.0
    dim = 1 << ctx.n_qubits
    mask = 0
    for s in freed_slots; mask |= (1 << s); end
    amps = _amps_view(ctx)
    acc = 0.0
    @inbounds for i in 0:dim-1
        if (i & mask) != 0; acc += abs2(amps[i + 1]); end
    end
    return acc
end

@testset "compact_state! (Sturm.jl-059)" begin

    # ── 1. CONTRACT ────────────────────────────────────────────────────────

    @testset "contract" begin

        @testset "no-op when free_slots empty" begin
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0.5)
                b = QBool(0)
                # snapshot
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
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                ptrace!(b); ptrace!(c)
                @test Sturm.compact_state!(ctx) === ctx
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "alloc 4, ptrace 2, compact → n_qubits=2, free_slots=[]" begin
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                ptrace!(b); ptrace!(c)
                @test ctx.n_qubits == 4
                @test length(ctx.free_slots) == 2
                Sturm.compact_state!(ctx)
                @test ctx.n_qubits == 2
                @test isempty(ctx.free_slots)
                # Both surviving wires must map to compact slots {0, 1}.
                live_slots = sort!(collect(values(ctx.wire_to_qubit)))
                @test live_slots == [0, 1]
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "live wires retain their identity after compact" begin
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
                a_id = a.wire; d_id = d.wire
                ptrace!(b); ptrace!(c)
                Sturm.compact_state!(ctx)
                # a and d must still be valid handles after compact —
                # their WireIDs are stable, only the slot index changes.
                @test haskey(ctx.wire_to_qubit, a_id)
                @test haskey(ctx.wire_to_qubit, d_id)
                ptrace!(a); ptrace!(d)
            end
        end

        @testset "consumed wires stay consumed after compact" begin
            @context EagerContext() begin
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

        @testset "compact preserves single-qubit amplitudes" begin
            @context EagerContext() begin
                ctx = current_context()
                # Allocate scratch first so it ends up at slot 0
                scratch = QBool(0)
                a = QBool(0.3)        # P(|1⟩) = 0.3 → amplitude √0.7 + √0.3
                a.φ += π / 4          # add a phase
                ptrace!(scratch)
                # Snapshot amps before compact (a's slot is now 1, scratch
                # was at 0 and is freed).
                pre = copy(_amps_view(ctx))
                Sturm.compact_state!(ctx)
                post = copy(_amps_view(ctx))
                # After compact: a is at slot 0, only 2 amplitudes total.
                # The pre-compact amplitudes at indices where scratch=0
                # (i.e., even indices 0, 2 of the 4-amp state) must equal
                # the post-compact amplitudes [1, 2] (1-indexed).
                @test length(post) == 2
                @test post[1] ≈ pre[1] atol=1e-12
                @test post[2] ≈ pre[3] atol=1e-12
                ptrace!(a)
            end
        end

        @testset "compact preserves Bell-pair correlations" begin
            # Allocate ancilla first, ptrace it, compact, then run Bell on
            # the survivors. Bell correlations must be intact.
            results = (Bool[], Bool[])
            for _ in 1:200
                @context EagerContext() begin
                    ctx = current_context()
                    junk = QBool(0)        # slot 0
                    a = QBool(0.5)          # slot 1
                    b = QBool(0)            # slot 2
                    b ⊻= a                 # entangle a and b
                    ptrace!(junk)
                    Sturm.compact_state!(ctx)
                    @test ctx.n_qubits == 2
                    push!(results[1], Bool(a))
                    push!(results[2], Bool(b))
                end
            end
            # Bell pair: outcomes must be perfectly correlated.
            @test results[1] == results[2]
        end

        @testset "compact then more gates yields same state as no-compact" begin
            # Identical computations, with vs without a mid-circuit compact.
            # Final amplitudes must agree.
            function run_with_compact(do_compact::Bool)
                @context EagerContext() begin
                    ctx = current_context()
                    junk = QBool(0)
                    a = QBool(0.5)
                    b = QBool(0)
                    b ⊻= a              # Bell
                    ptrace!(junk)
                    if do_compact
                        Sturm.compact_state!(ctx)
                    end
                    # Apply additional gates after the (potential) compact.
                    a.φ += π / 3
                    when(a) do
                        b.φ += π / 5
                    end
                    # Snapshot the live amps — but in different layouts,
                    # so we measure outcome distribution instead.
                    return abs2.(copy(_amps_view(ctx))), ctx.n_qubits
                end
            end
            amps_no, n_no = run_with_compact(false)
            amps_cp, n_cp = run_with_compact(true)
            @test n_cp <= n_no
            # Compute the marginal over the 2 live qubits in the no-compact
            # layout: with-compact has dim=4, no-compact has dim=8 (junk slot
            # in |0⟩, doubles the dim). Marginal-over-junk should match.
            marginal_no = zeros(Float64, 1 << n_cp)
            for i in 0:(1 << n_no - 1)
                # junk is at slot 0 in no-compact, |0⟩-only — bit 0 must be 0
                if (i & 1) == 0
                    j = i >> 1   # drop the junk bit, remaining bits form
                                  # the live-qubit index in compact order
                    marginal_no[j + 1] = amps_no[i + 1]
                end
            end
            for k in 1:length(amps_cp)
                @test amps_cp[k] ≈ marginal_no[k] atol=1e-12
            end
        end

        @testset "stress: random alloc/ptrace pattern at moderate scale" begin
            # 8 wires, randomly ptrace 4, compact, run gates, ptrace rest.
            # No assertion on final value beyond well-formedness.
            for trial in 1:5
                @context EagerContext() begin
                    ctx = current_context()
                    qs = [QBool(rand(Bool) ? 1.0 : 0.0) for _ in 1:8]
                    # randomise some entanglement
                    for i in 1:7
                        if rand(Bool)
                            qs[i+1] ⊻= qs[i]
                        end
                    end
                    # ptrace 4 random qubits
                    to_ptrace = sort(collect(rand(1:8, 4)) |> unique, rev=true)
                    survivors = QBool[]
                    for i in 1:8
                        if i in to_ptrace
                            ptrace!(qs[i])
                        else
                            push!(survivors, qs[i])
                        end
                    end
                    # compact & verify well-formed
                    Sturm.compact_state!(ctx)
                    @test ctx.n_qubits == length(survivors)
                    @test isempty(ctx.free_slots)
                    @test sort(collect(values(ctx.wire_to_qubit))) ==
                          collect(0:length(survivors) - 1)
                    # apply more gates and consume
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
        # Construct an "unsafe-released" slot manually: we entangle two
        # qubits, then forcibly remove one from wire_to_qubit and push its
        # slot index to free_slots WITHOUT going through measure!. The
        # amplitude in the |1⟩ branch of that slot is non-zero, so
        # compact_state! must detect the violation and error.
        @context EagerContext() begin
            ctx = current_context()
            a = QBool(0.5)
            b = QBool(0)
            b ⊻= a    # Bell pair: amps[(00)] = amps[(11)] = 1/√2
            # Forcibly free b's slot WITHOUT measuring.
            b_slot = ctx.wire_to_qubit[b.wire]
            delete!(ctx.wire_to_qubit, b.wire)
            push!(ctx.consumed, b.wire)
            push!(ctx.free_slots, b_slot)
            b.consumed = true   # so check_live! doesn't fire later
            # The free_slots entry has non-zero amp in its |1⟩ branch.
            @test _residual_norm_sq(ctx, ctx.free_slots) ≈ 0.5 atol=1e-12
            # compact_state! must now error loud.
            @test_throws ErrorException Sturm.compact_state!(ctx)
            ptrace!(a)
        end
    end

    # ── 4. ATOMICITY UNDER EXCEPTION ───────────────────────────────────────

    @testset "atomicity: failed compact leaves ctx unchanged" begin
        # Trip an input-validation error in the middle of an otherwise-valid
        # context, then assert that EVERY context field is exactly the same
        # as before the call. The compact_state! design guarantees compute-
        # then-commit: any throw before the commit phase leaves ctx fully
        # in its old state. (See `_compact_plan` in src/context/eager.jl.)
        @context EagerContext() begin
            ctx = current_context()
            a = QBool(0); b = QBool(0); c = QBool(0); d = QBool(0)
            ptrace!(b); ptrace!(c)
            # Corrupt invariant: inject a duplicate slot index into
            # free_slots. compact_state! pre-flight must catch this.
            push!(ctx.free_slots, ctx.free_slots[1])
            old_n = ctx.n_qubits
            old_cap = ctx.capacity
            old_w2q = copy(ctx.wire_to_qubit)
            old_consumed = copy(ctx.consumed)
            old_free = copy(ctx.free_slots)
            old_count = ctx._compact_count
            old_orkan_data = ctx.orkan.raw.data
            @test_throws ErrorException Sturm.compact_state!(ctx)
            # Ctx must be EXACTLY as before — compute-then-commit invariant.
            @test ctx.n_qubits == old_n
            @test ctx.capacity == old_cap
            @test ctx.wire_to_qubit == old_w2q
            @test ctx.consumed == old_consumed
            @test ctx.free_slots == old_free
            @test ctx._compact_count == old_count
            @test ctx.orkan.raw.data == old_orkan_data  # same OrkanState
            # Heal the corruption and confirm ctx is still usable.
            unique!(ctx.free_slots)
            Sturm.compact_state!(ctx)   # now succeeds
            @test ctx.n_qubits == 2
            @test ctx._compact_count == old_count + 1
            ptrace!(a); ptrace!(d)
        end
    end

    # ── 5. AUTO-TRIGGER (deallocate! threshold) ────────────────────────────

    @testset "auto-trigger: deallocate fires compact at threshold" begin
        # Threshold is 2 * GROW_STEP = 8. After 8 ptraces accumulated in
        # free_slots, compact_state! must fire automatically.
        @context EagerContext() begin
            ctx = current_context()
            qs = [QBool(0) for _ in 1:12]
            @test ctx._compact_count == 0
            # ptrace the first 7 → below threshold, no auto-fire
            for i in 1:7
                ptrace!(qs[i])
            end
            @test ctx._compact_count == 0
            @test length(ctx.free_slots) == 7
            # 8th ptrace crosses the threshold and triggers
            ptrace!(qs[8])
            @test ctx._compact_count == 1
            @test isempty(ctx.free_slots)
            @test ctx.n_qubits == 4   # only qs[9..12] remain
            for i in 9:12; ptrace!(qs[i]); end
        end
    end

    @testset "auto-trigger: ping-pong stays bounded" begin
        # Bennett-shaped pattern: alloc burst, dealloc burst, repeat.
        # Without compaction n_qubits would ratchet up to peak across
        # rounds; with it the high-water-mark stays bounded near peak-burst.
        @context EagerContext() begin
            ctx = current_context()
            base = [QBool(0) for _ in 1:4]
            peak = ctx.n_qubits
            for round in 1:10
                burst = [QBool(0) for _ in 1:8]
                peak = max(peak, ctx.n_qubits)
                for q in burst; ptrace!(q); end
            end
            # Without compaction, peak would ratchet up by 8 per round
            # (multi-round monotonic growth). With compaction the high-water
            # mark stays bounded at base + burst + GROW_STEP hysteresis.
            @test peak <= 16
            for q in base; ptrace!(q); end
        end
    end

    # ── 6. HWM TRACKER (bead Sturm.jl-w9e) ─────────────────────────────────
    #
    # `_n_qubits_hwm` is the per-allocate hook that lets tests bound the
    # peak qubit count of an operation even when compaction fires
    # mid-execution. allocate! bumps the field; compact_state! must NOT
    # reset it. Required by tests that previously read `ctx.n_qubits` as
    # a peak (test_shor.jl HWM, test_bennett_integration deallocate_batch).

    @testset "_n_qubits_hwm tracks peak across allocations and compactions" begin
        @context EagerContext() begin
            ctx = current_context()
            @test ctx._n_qubits_hwm == 0
            a = QBool(0); b = QBool(0); c = QBool(0)
            @test ctx.n_qubits == 3
            @test ctx._n_qubits_hwm == 3
            # ptrace (below auto-trigger threshold) must not lower HWM.
            ptrace!(b)
            @test ctx._n_qubits_hwm == 3
            # Allocate into a recycled slot — n_qubits unchanged, HWM unchanged.
            d = QBool(0)
            @test ctx.n_qubits == 3
            @test ctx._n_qubits_hwm == 3
            # Allocate fresh — HWM bumps.
            e = QBool(0)
            @test ctx.n_qubits == 4
            @test ctx._n_qubits_hwm == 4
            # Force a compaction via threshold burst.
            burst = [QBool(0) for _ in 1:8]
            @test ctx._n_qubits_hwm >= 12   # 4 (live) + 8 (burst) at peak
            peak_before_compact = ctx._n_qubits_hwm
            for q in burst; ptrace!(q); end
            # After compact: n_qubits drops (live count = a, c, d, e = 4),
            # but HWM is preserved.
            @test ctx._compact_count >= 1
            @test ctx.n_qubits == 4
            @test ctx._n_qubits_hwm == peak_before_compact
            # New allocations after compact only bump HWM if they exceed peak.
            tail = [QBool(0) for _ in 1:5]   # n_qubits goes 4 → 9, below HWM
            @test ctx._n_qubits_hwm == peak_before_compact   # unchanged
            for q in tail; ptrace!(q); end
            ptrace!(a); ptrace!(c); ptrace!(d); ptrace!(e)
        end
    end

    # ── 7. PRE-FLIGHT VALIDATION (each error path fires) ───────────────────

    @testset "pre-flight validation errors" begin
        @testset "free_slots out-of-range" begin
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0)
                ptrace!(b)
                push!(ctx.free_slots, 99)   # impossible index
                err = try; Sturm.compact_state!(ctx); nothing; catch e; e; end
                @test err isa ErrorException
                @test occursin("out-of-range", err.msg)
                pop!(ctx.free_slots)
                ptrace!(a)
            end
        end

        @testset "free_slots duplicates" begin
            @context EagerContext() begin
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
            @context EagerContext() begin
                ctx = current_context()
                a = QBool(0); b = QBool(0)
                ptrace!(b)
                # Inject the live slot into free_slots
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
end
