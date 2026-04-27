# test_bennett_compact.jl — Bead Sturm.jl-2qp diagnostic counter coverage.
#
# This bead investigates the ~750× per-DAG-gate slowdown of `_shor_mulmod_E_
# controlled!` vs `mulmod_beauregard!` at N=15. The counters added in
# `src/context/eager.jl` (`reset_gate_counts!`, `gate_counts`) are the
# diagnostic instrument — they record per-primitive `apply_*!` entries
# plus a control-stack-depth (`nc`) breakdown plus per-gate sampling of
# `ctx.n_qubits` (the active statevector size at gate time).
#
# These tests pin the counter contract so the diagnostic stays honest as
# the codebase evolves: a future change that breaks the counters would
# produce silent mis-diagnosis on the next perf investigation.
#
# The actual perf-fix bead is filed separately (the n_qubits ratchet cannot
# be reclaimed mid-Bennett-burst without an in-place compaction primitive —
# either a logical-only `compact_state!` variant that does not reallocate
# the Orkan buffer, or a different QROM construction with lower peak
# ancilla count).

using Test
using Sturm
using Sturm: apply_reversible!, qrom_lookup_xor!, _shor_mulmod_E_controlled!
using Sturm: WireID, QROMTable

@testset "Sturm.jl-2qp diagnostic gate counters" begin

    @testset "reset_gate_counts! zeros every counter" begin
        @context EagerContext() begin
            a = QBool(0)
            b = QBool(0)
            b ⊻= a                    # one apply_cx!
            a.θ += π / 4              # one apply_ry!
            a.φ += π / 8              # one apply_rz!
            ptrace!(a); ptrace!(b)
        end
        reset_gate_counts!()
        c = gate_counts()
        @test c.ry == 0 && c.rz == 0 && c.cx == 0 && c.ccx == 0
        @test c.total == 0
        @test c.nq_max == 0
        @test c.nq_sum_2 == 0.0
        @test all(c.nq_buckets .== 0)
    end

    @testset "counters track unconditional primitives 1:1" begin
        @context EagerContext() begin
            a = QBool(0); b = QBool(0); c = QBool(0)
            reset_gate_counts!()
            a.θ += π / 4              # apply_ry!: 1
            a.θ += π / 8              # apply_ry!: 2
            a.φ += π / 16             # apply_rz!: 1
            b ⊻= a                    # apply_cx!: 1
            counts = gate_counts()
            @test counts.ry == 2 && counts.rz == 1 && counts.cx == 1
            @test counts.ccx == 0
            @test counts.total == 4
            # All at nc=0 (no `when` block).
            @test counts.nc_ry[1] == 2
            @test counts.nc_rz[1] == 1
            @test counts.nc_cx[1] == 1
            ptrace!(a); ptrace!(b); ptrace!(c)
        end
    end

    @testset "nc bucket increments inside when()" begin
        @context EagerContext() begin
            a = QBool(0); b = QBool(0); c = QBool(0)
            reset_gate_counts!()
            when(a) do
                # Inside when(a): nc=1 at every primitive entry.
                # `c ⊻= b` is one CX with nc=1 → orkan_ccx fast path; one apply_cx!.
                c ⊻= b
                # `c.θ += π` at nc=1: dispatches into _controlled_ry! which
                # clears the stack (nc=0) and re-emits 4 primitives. So the
                # outer apply_ry! is one nc=1 entry, plus the inner cascade
                # produces 2 nc=0 apply_ry! and 2 nc=0 apply_cx!.
                c.θ += π
            end
            counts = gate_counts()
            @test counts.nc_ry[2] == 1   # outer apply_ry! at nc=1
            @test counts.nc_ry[1] == 2   # inner cascade apply_ry! at nc=0
            @test counts.nc_cx[2] == 1   # `c ⊻= b` at nc=1
            @test counts.nc_cx[1] == 2   # cascade CX at nc=0
            ptrace!(a); ptrace!(b); ptrace!(c)
        end
    end

    @testset "nq sampling captures the working-set size at each gate" begin
        @context EagerContext() begin
            ctx = current_context()
            # Pre-allocate a few wires so n_qubits is non-trivial when the
            # measured gate runs.
            wires = WireID[Sturm.allocate!(ctx) for _ in 1:5]
            reset_gate_counts!()
            # One apply_ry! at the current n_qubits = 5.
            Sturm.apply_ry!(ctx, wires[1], π / 4)
            counts = gate_counts()
            @test counts.nq_max == 5
            @test counts.nq_sum_2 ≈ 32.0    # 2^5 from one ccall
            # Bucket 2 is nq ∈ [4, 7], so n_qubits=5 lands there.
            @test counts.nq_buckets[2] == 1
            for w in wires; Sturm.deallocate!(ctx, w); end
        end
    end

    @testset "Bennett qrom_lookup_xor! records the in-burst peak" begin
        # End-to-end: a QROM lookup must (a) emit Bennett-compiled gates that
        # bump the counters, (b) those gates' nq sampling must capture the
        # in-burst peak (above the user-visible working set, by the K
        # Bennett ancillae). Today the peak does NOT compact down at the end
        # of `apply_reversible!` for sub-threshold bursts — the ratchet
        # behaviour the bead's perf investigation revealed. This test pins
        # the diagnosis (peak > working set) but does NOT yet assert the
        # downstream fix.
        @context EagerContext() begin
            ctx = current_context()
            addr = QInt{2}(1)
            scratch = QInt{5}(0)
            tbl = QROMTable{2, 5}(UInt64[0, 7, 14, 11], 16)

            user_qubits = ctx.n_qubits      # 7 — addr=2 + scratch=5
            reset_gate_counts!()
            qrom_lookup_xor!(scratch, addr, tbl)
            counts = gate_counts()

            # Bennett emitted at least one primitive.
            @test counts.total > 0
            # Peak n_qubits during the QROM burst exceeded the user working
            # set (Bennett allocated ancillae). This pins the bug's footprint.
            @test counts.nq_max > user_qubits
            # The total should be a small multiple of the textbook 4·(2^Ccmul-1)=12
            # Toffoli cost. Loose upper bound — exact count depends on
            # Bennett's lowering. Tightening this would risk brittleness.
            @test counts.total < 200

            ptrace!(addr); ptrace!(scratch)
        end
    end
end
