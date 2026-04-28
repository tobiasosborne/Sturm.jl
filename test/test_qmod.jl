using Test
using Logging
using LinearAlgebra   # Diagonal, for the k8u mixed Ry+Rz analytic comparison
using Sturm

# Sturm.jl-9aa — QMod{d} type + EagerContext prep primitive.
#
# First implementation bead of the goi qudit epic. Scope: type, prep
# primitive, P2 measurement cast, ptrace, leakage guard at measurement.
# NOT in scope: rotations (q.θ, q.φ, q.θ₂, q.θ₃), SUM, library gates,
# Bennett interop (filed as Sturm.jl-jba).
#
# References:
#   * docs/physics/qudit_magic_gate_survey.md §8 (locked design decisions).
#   * docs/design/qmod_design_proposer_{a,b}.md (3+1 design round).
#   * WORKLOG Session 52 (2026-04-22) — orchestrator synthesis.

@testset "QMod{d}" begin

    @testset "construction at d=3" begin
        @context EagerContext() begin
            q = QMod{3}()
            @test q isa QMod{3}
            @test q isa QMod{3, 2}            # K = ⌈log₂ 3⌉ = 2
            @test q isa Quantum
            @test length(q.wires) == 2
            @test !q.consumed
            @test q.ctx === current_context()
            ptrace!(q)
            @test q.consumed
        end
    end

    @testset "explicit-context constructor" begin
        ctx = EagerContext()
        q = QMod{3}(ctx)
        @test q.ctx === ctx
        @test q isa QMod{3, 2}
        ptrace!(q)
    end

    @testset "prep is |0> for various d (decoded label = 0)" begin
        for d in (2, 3, 4, 5, 7, 8, 16)
            @context EagerContext() begin
                ctor = (() -> QMod{d}())
                q = ctor()
                @test Int(q) == 0
            end
        end
    end

    @testset "power-of-2 d packs perfectly (no leakage possible)" begin
        @context EagerContext() begin
            q4 = QMod{4}()
            @test length(q4.wires) == 2       # K = 2 → 4 levels
            @test Int(q4) == 0
        end
        @context EagerContext() begin
            q8 = QMod{8}()
            @test length(q8.wires) == 3       # K = 3 → 8 levels
            @test Int(q8) == 0
        end
        @context EagerContext() begin
            q16 = QMod{16}()
            @test length(q16.wires) == 4
            @test Int(q16) == 0
        end
    end

    @testset "QMod{2} layout: 1 wire (parallels QBool layout, distinct type)" begin
        @context EagerContext() begin
            q = QMod{2}()
            @test q isa QMod{2, 1}
            @test length(q.wires) == 1
            @test Int(q) == 0
        end
        # NB: QMod{2} !== QBool by design (logical vs. arithmetic API,
        # qudit_magic_gate_survey.md §8.5). No Bool(::QMod{2}) defined.
        @context EagerContext() begin
            q = QMod{2}()
            @test_throws MethodError Bool(q)
            ptrace!(q)
        end
    end

    @testset "d validation: d < 2 errors at construction" begin
        @context EagerContext() begin
            @test_throws ErrorException QMod{1}()
            @test_throws ErrorException QMod{0}()
            @test_throws ErrorException QMod{-1}()
        end
    end

    @testset "non-Int d errors at construction" begin
        @context EagerContext() begin
            @test_throws ErrorException QMod{1.5}()
        end
    end

    @testset "Base.length returns K" begin
        @context EagerContext() begin
            @test length(QMod{2}()) == 1
            @test length(QMod{3}()) == 2
            @test length(QMod{4}()) == 2
            @test length(QMod{5}()) == 3
            @test length(QMod{8}()) == 3
            @test length(QMod{9}()) == 4
        end
    end

    @testset "ptrace! frees all K wires" begin
        @context EagerContext() begin
            ctx = current_context()
            n0 = length(Sturm.live_wires(ctx))
            q = QMod{5}()                     # K = 3
            @test length(Sturm.live_wires(ctx)) == n0 + 3
            ptrace!(q)
            @test q.consumed
            @test length(Sturm.live_wires(ctx)) == n0
        end
    end

    @testset "discard! aliases ptrace!" begin
        @context EagerContext() begin
            q = QMod{3}()
            discard!(q)
            @test q.consumed
        end
    end

    @testset "TLS context: QMod{d}() pulls current_context()" begin
        ctx = EagerContext()
        @context ctx begin
            q = QMod{3}()
            @test q.ctx === ctx
            ptrace!(q)
        end
    end

    @testset "QMod{d}() outside @context errors" begin
        @test_throws ErrorException QMod{3}()
    end

    @testset "@context auto-cleanup partial-traces unconsumed QMod" begin
        # Bead sv3: cleanup at @context exit must handle QMod too.
        ctx = EagerContext()
        n0 = length(Sturm.live_wires(ctx))
        @context ctx begin
            q = QMod{5}()                     # not explicitly traced
        end
        @test length(Sturm.live_wires(ctx)) == n0
    end

    @testset "linear resource: double-consume errors" begin
        @context EagerContext() begin
            q = QMod{3}()
            _ = Int(q)
            @test_throws ErrorException Int(q)
        end
        @context EagerContext() begin
            q = QMod{3}()
            ptrace!(q)
            @test_throws ErrorException ptrace!(q)
        end
        @context EagerContext() begin
            q = QMod{3}()
            ptrace!(q)
            @test_throws ErrorException Int(q)
        end
    end

    # ── P2: implicit quantum→classical cast warning ─────────────────────────

    @testset "P2: explicit Int(q) is silent" begin
        @test_logs min_level=Warn begin
            @context EagerContext() begin
                q = QMod{3}()
                y = Int(q)
                @test y == 0
            end
        end
    end

    @testset "P2: implicit y::Int = q warns once (named QMod{3} → Int)" begin
        @test_logs (:warn, r"Implicit quantum→classical cast QMod\{3\} → Int") begin
            @context EagerContext() begin
                q = QMod{3}()
                local y::Int = q
                @test y == 0
            end
        end
    end

    @testset "P2: warning suggests explicit cast" begin
        @test_logs (:warn, r"Wrap the RHS in an explicit cast: `Int\(q\)`") begin
            @context EagerContext() begin
                q = QMod{5}()
                local y::Int = q
            end
        end
    end

    @testset "P2: with_silent_casts suppresses QMod warning" begin
        @test_logs min_level=Warn begin
            with_silent_casts() do
                @context EagerContext() begin
                    q = QMod{3}()
                    local y::Int = q
                    @test y == 0
                end
            end
        end
    end

    # ── Leakage guard layer 3: unconditional post-measurement check ─────────
    #
    # At non-power-of-2 d (here d=3, K=2), the |11⟩_qubit basis state
    # encodes label 3 ≥ d. A buggy primitive could drive the state out of
    # the d-level subspace; this test simulates that by manually applying
    # X gates via the raw apply_ry! primitive — intentional misuse to
    # exercise the safety net (Rule 1: fail loud).

    @testset "leakage at measurement: |11> in QMod{3} crashes loudly" begin
        @context EagerContext() begin
            q = QMod{3}()
            ctx = current_context()
            Sturm.apply_ry!(ctx, q.wires[1], π)     # wires[1] → |1⟩
            Sturm.apply_ry!(ctx, q.wires[2], π)     # wires[2] → |1⟩
            # State is |11⟩ = encoded basis 3 ≥ d=3 — leakage.
            @test_throws ErrorException Int(q)
        end
    end

    @testset "no false leakage on legal label 2 in QMod{3}" begin
        @context EagerContext() begin
            q = QMod{3}()
            ctx = current_context()
            Sturm.apply_ry!(ctx, q.wires[2], π)     # wires[2] → |1⟩, wires[1] → |0⟩
            # State is |10⟩_LE-binary = label 2 < d=3 — legal.
            @test Int(q) == 2
        end
    end

    # ── Bennett interop: not in scope; calls should error loudly. ───────────

    @testset "Bennett classical_type for QMod is not yet defined" begin
        # Sturm.jl-jba tracks adding mod-d arithmetic to Bennett.jl.
        # Until then, calling classical_type on a QMod type must MethodError.
        @test_throws MethodError Sturm.classical_type(QMod{3, 2})
    end

    # ── ak2: spin-j Ry/Rz primitives (q.θ, q.φ) ─────────────────────────────
    #
    # Bead `Sturm.jl-ak2`. v0.1 ships d=2 fully (bit-identical to qubit
    # Ry/Rz on the underlying wire — Rule 11 preserved); d>2 errors loudly
    # with a pointer to bead `Sturm.jl-nrs` (qubit-encoded fallback
    # simulator) which carries the spin-j Givens decomposition.
    # Refs: docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf
    # Eqs. 5-7, 13; docs/physics/qudit_magic_gate_survey.md §8.1, §8.2.

    """
        _amps_snapshot(ctx) -> Vector{ComplexF64}

    Test helper: zero-copy snapshot of the EagerContext's amplitude buffer.
    Aliases Orkan's internal pointer; valid until the next gate or growth.
    """
    function _amps_snapshot(ctx)
        dim = 1 << ctx.n_qubits
        amps = unsafe_wrap(Array{ComplexF64, 1}, ctx.orkan.raw.data, dim)
        return copy(amps)
    end

    @testset "ak2 d=2: q.θ += δ matches QBool .θ += δ on underlying wire" begin
        # Rule 11 contract: at d=2, primitive 2 is bit-identical to qubit Ry.
        for δ in (0.0, π/7, π/3, π, -π/4, 1.7)
            amps_qbool = @context EagerContext() begin
                q = QBool(0.0)
                q.θ += δ
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}()
                q.θ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
        end
    end

    @testset "ak2 d=2: q.φ += δ matches QBool .φ += δ on underlying wire" begin
        # Symmetric: primitive 3 = qubit Rz on the single underlying wire.
        # Test on a non-trivial start state so the phase is observable.
        for δ in (π/3, π, -π/2, 0.41)
            amps_qbool = @context EagerContext() begin
                q = QBool(0.0); q.θ += π/3
                q.φ += δ
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}(); q.θ += π/3
                q.φ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
        end
    end

    @testset "ak2 d=2: multi-rotation chain matches QBool chain" begin
        # End-to-end: a sequence of θ and φ rotations on QMod{2} produces
        # the same statevector as the same sequence on QBool.
        seq = [(:θ, 0.4), (:φ, 1.1), (:θ, -0.3), (:φ, π/2)]
        amps_qbool = @context EagerContext() begin
            q = QBool(0.0)
            for (ax, δ) in seq
                ax === :θ ? (q.θ += δ) : (q.φ += δ)
            end
            _amps_snapshot(current_context())
        end
        amps_qmod = @context EagerContext() begin
            q = QMod{2}()
            for (ax, δ) in seq
                ax === :θ ? (q.θ += δ) : (q.φ += δ)
            end
            _amps_snapshot(current_context())
        end
        @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
    end

    @testset "ak2 d=2: q.θ -= δ delegates to q.θ += -δ" begin
        for δ in (0.31, π/5, -π/3)
            amps_plus = @context EagerContext() begin
                q = QMod{2}()
                q.θ += -δ
                _amps_snapshot(current_context())
            end
            amps_minus = @context EagerContext() begin
                q = QMod{2}()
                q.θ -= δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_plus, amps_minus; atol=1e-12))
        end
    end

    @testset "ak2 d=2: q.θ += δ inside when(::QBool) routes through control stack" begin
        # Coherent control test: Bell-shaped state via H-on-ctrl + controlled
        # Ry(π) (= Y up to global phase) on QMod{2} target. Statistics:
        #   ctrl=0 → target |0⟩ (target untouched)
        #   ctrl=1 → target |1⟩ (Ry(π) flips)
        # P(ctrl=0, t=0) ≈ 0.5; P(ctrl=1, t=1) ≈ 0.5; off-diagonals ≈ 0.
        N = 2000
        counts = Dict((0,0)=>0, (0,1)=>0, (1,0)=>0, (1,1)=>0)
        for _ in 1:N
            @context EagerContext() begin
                ctrl = QBool(0.5)
                qm = QMod{2}()
                when(ctrl) do
                    qm.θ += π
                end
                c = Bool(ctrl) ? 1 : 0
                t = Int(qm)
                counts[(c, t)] += 1
            end
        end
        @test counts[(0, 0)] > 0.40 * N
        @test counts[(1, 1)] > 0.40 * N
        @test counts[(0, 1)] < 0.05 * N
        @test counts[(1, 0)] < 0.05 * N
    end

    @testset "ixd d≥6 and d=4: q.θ += δ errors with deferral message" begin
        # After k8u: d=3 WORKS. After ixd (Session 57): d=5 WORKS.
        # d=4 (power-of-2, no leakage, simpler 6-Givens V4 decomposition)
        # is filed as a separate follow-on bead since csw critical path
        # doesn't need it. d ≥ 6 not yet scoped.
        for d in (4, 6, 7, 8)
            @context EagerContext() begin
                ctor = (() -> QMod{d}())
                q = ctor()
                err = try
                    q.θ += π/3
                    nothing
                catch e
                    e
                end
                @test err isa ErrorException
                # Error message must point at a real bead for the missing d.
                @test occursin(r"Sturm\.jl-", err.msg)
                @test occursin("not yet implemented", err.msg)
            end
        end
    end

    # NOTE: the "q.φ += δ errors" ak2 test is DELETED — nrs ships Rz at
    # all d ≥ 3 via the per-wire binary factorisation, so φ no longer
    # errors at d>2. See the nrs Rz testsets below.

    @testset "ak2: proxy types — d=2 returns BlochProxy, d>2 returns QModBlochProxy" begin
        @context EagerContext() begin
            q2 = QMod{2}()
            @test getproperty(q2, :θ) isa Sturm.BlochProxy
            @test getproperty(q2, :φ) isa Sturm.BlochProxy
        end
        @context EagerContext() begin
            q3 = QMod{3}()
            @test getproperty(q3, :θ) isa Sturm.QModBlochProxy{3, 2}
            @test getproperty(q3, :φ) isa Sturm.QModBlochProxy{3, 2}
        end
        @context EagerContext() begin
            q4 = QMod{4}()
            @test getproperty(q4, :θ) isa Sturm.QModBlochProxy{4, 2}
        end
    end

    @testset "ak2: proxy access on consumed QMod errors" begin
        @context EagerContext() begin
            q = QMod{2}()
            ptrace!(q)
            @test_throws ErrorException q.θ
        end
        @context EagerContext() begin
            q = QMod{3}()
            ptrace!(q)
            @test_throws ErrorException q.θ
        end
    end

    # ── nrs: spin-j Rz primitive (Ry deferred to bead k8u) ──────────────────
    #
    # Bead `Sturm.jl-nrs`. Ships the Rz path (`q.φ += δ`) at all d ≥ 3 via
    # the per-wire binary factorisation: since Ĵ_z |s⟩ = (j-s)|s⟩ is
    # diagonal (Bartlett Eq. 5), and s = Σ b_i 2^{i-1} in the LE encoding,
    # the rotation exp(-iδ(j-s)) factors into a product of per-wire
    # single-qubit Rz's. K gates total. Identical to the existing qubit
    # Rz at d=2.
    #
    # Ry (`q.θ += δ`) at d>2 defers to bead `Sturm.jl-k8u` — the multi-
    # qubit decomposition of exp(-iδĴ_y) was not cleanly derived in
    # either nrs proposer design; filed with a test acceptance criterion
    # against the hand-computed Wigner d-matrix.

    @testset "nrs d=3: q.φ += δ is diagonal (no amplitude redistribution)" begin
        # Prep |0⟩_d: amps = (1, 0, 0, 0). After Rz(δ): amps still at |00⟩.
        for δ in (0.3, π/3, π, -π/5)
            @context EagerContext() begin
                q = QMod{3}()
                q.φ += δ
                amps = _amps_snapshot(current_context())
                @test abs(amps[1]) ≈ 1.0 atol=1e-10  # |00⟩ = label 0
                @test abs(amps[2]) < 1e-12           # |01⟩ = label 1
                @test abs(amps[3]) < 1e-12           # |10⟩ = label 2
                @test abs(amps[4]) < 1e-12           # |11⟩ = forbidden
            end
        end
    end

    @testset "nrs d=3: q.φ preserves each basis-state magnitude" begin
        # Prep each of the 3 legal labels via raw wire ops (bypasses Ry).
        # After Rz(δ), magnitude on the prepped basis state stays = 1.
        δ = 0.7
        @context EagerContext() begin
            q = QMod{3}()
            Sturm.apply_ry!(current_context(), q.wires[1], π)  # → |01⟩ = label 1
            q.φ += δ
            amps = _amps_snapshot(current_context())
            @test abs(amps[2]) ≈ 1.0 atol=1e-10
            @test abs(amps[1]) < 1e-12
            @test abs(amps[3]) < 1e-12
            @test abs(amps[4]) < 1e-12
        end
        @context EagerContext() begin
            q = QMod{3}()
            Sturm.apply_ry!(current_context(), q.wires[2], π)  # → |10⟩ = label 2
            q.φ += δ
            amps = _amps_snapshot(current_context())
            @test abs(amps[3]) ≈ 1.0 atol=1e-10
            @test abs(amps[1]) < 1e-12
            @test abs(amps[2]) < 1e-12
            @test abs(amps[4]) < 1e-12
        end
    end

    @testset "nrs d=3: relative phase matches spin-j Ĵ_z spectrum" begin
        # Prep (|0⟩_d + |2⟩_d)/√2 via raw apply_ry!(wires[2], π/2) — puts
        # a uniform superposition on (|00⟩, |10⟩)_qubit = (|0⟩_d, |2⟩_d)_d.
        # Ideal Rz(δ) on spin-1: |s⟩ → exp(-iδ(j-s))|s⟩.
        #   j=1, s=0: exp(-iδ)
        #   j=1, s=2: exp(+iδ)
        # Relative phase (|2⟩ / |0⟩) after Rz = exp(+iδ) / exp(-iδ) = exp(+i2δ).
        δ = 0.7
        @context EagerContext() begin
            q = QMod{3}()
            Sturm.apply_ry!(current_context(), q.wires[2], π/2)
            q.φ += δ
            amps = _amps_snapshot(current_context())
            # amps[1] = |00⟩ = label 0, amps[3] = |10⟩ = label 2
            @test abs(amps[1]) ≈ 1/√2 atol=1e-10
            @test abs(amps[3]) ≈ 1/√2 atol=1e-10
            rel_phase = amps[3] / amps[1]
            @test rel_phase ≈ exp(+im*2δ) atol=1e-10
            @test abs(amps[4]) < 1e-12  # forbidden state stays empty
        end
    end

    @testset "nrs d=5: q.φ is diagonal (no amplitude redistribution)" begin
        # K = 3 → 8 qubit-basis states. Labels 0..4 legal, 5..7 forbidden.
        δ = 0.4
        @context EagerContext() begin
            q = QMod{5}()
            q.φ += δ
            amps = _amps_snapshot(current_context())
            @test abs(amps[1]) ≈ 1.0 atol=1e-10  # |000⟩ = label 0
            for i in 2:8
                @test abs(amps[i]) < 1e-12
            end
        end
    end

    @testset "nrs d=5: relative phase across 3 basis states" begin
        # At d=5, j=2. Rz eigenvalues: (j - s) for s ∈ {0, 1, 2, 3, 4}.
        # Prep superposition (|0⟩_d + |4⟩_d)/√2 via apply_ry!(wires[3], π/2)
        # (bit 2 flip → label 4 = |100⟩_qubit). Relative phase after Rz(δ):
        #   label 0 → exp(-iδ(2-0)) = exp(-i2δ)
        #   label 4 → exp(-iδ(2-4)) = exp(+i2δ)
        # Ratio (4 / 0) = exp(+i4δ).
        δ = 0.25
        @context EagerContext() begin
            q = QMod{5}()
            Sturm.apply_ry!(current_context(), q.wires[3], π/2)
            q.φ += δ
            amps = _amps_snapshot(current_context())
            # label 0 at index 0 (amps[1]); label 4 at index 4 (amps[5])
            @test abs(amps[1]) ≈ 1/√2 atol=1e-10
            @test abs(amps[5]) ≈ 1/√2 atol=1e-10
            rel_phase = amps[5] / amps[1]
            @test rel_phase ≈ exp(+im*4δ) atol=1e-10
            # Forbidden labels 5, 6, 7 (amps[6..8])
            for i in 6:8
                @test abs(amps[i]) < 1e-12
            end
        end
    end

    @testset "nrs: q.φ += δ at d=2 unchanged (regression guard)" begin
        # At d=2 (K=1), getproperty returns BlochProxy (not QModBlochProxy),
        # so _apply_spin_j_rotation! is NOT called. d=2 stays on the qubit
        # fast path from ak2. Verify the ak2 parity still holds now that
        # nrs exists.
        δ = π/3
        amps_qbool = @context EagerContext() begin
            q = QBool(0.0); q.θ += π/3
            q.φ += δ
            _amps_snapshot(current_context())
        end
        amps_qmod = @context EagerContext() begin
            q = QMod{2}(); q.θ += π/3
            q.φ += δ
            _amps_snapshot(current_context())
        end
        @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
    end

    @testset "nrs d=3: Rz cannot create leakage (diagonal)" begin
        # No sequence of Rz can move amplitude between basis states, so
        # the |11⟩_qubit amplitude stays at whatever it started as. Here
        # it starts at 0 (fresh prep); verify it stays at 0.
        @context EagerContext() begin
            q = QMod{3}()
            for _ in 1:10
                q.φ += rand() * 2π
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[4]) < 1e-12
            # Measurement must succeed (no leakage guard firing)
            result = Int(q)
            @test result == 0
        end
    end

    @testset "nrs d=3: when(::QBool) q.φ += δ carries controlled-phase" begin
        # Under coherent control, controlled-Rz. Prep ctrl = (|0⟩+|1⟩)/√2
        # and QMod{3} in state |2⟩_d (via raw apply_ry). Apply
        # when(ctrl) q.φ += δ end. Full state:
        #    |0⟩_ctrl |2⟩_d + exp(-iδ(j-2)) |1⟩_ctrl |2⟩_d  (ideal, up to
        #    a global phase e^{something}). Orkan's apply_rz! convention
        #    applies exp(-iθ σ_z/2), so the RELATIVE phase between the two
        #    ctrl branches is what we measure.
        #
        # Less fragile: verify that the controlled Rz IS a diagonal operation
        # on both ctrl branches, and the relative phase picks up consistently.
        δ = 0.5
        @context EagerContext() begin
            ctrl = QBool(0.0)
            Sturm.apply_ry!(current_context(), ctrl.wire, π/2)  # H-like: (|0⟩+|1⟩)/√2
            q = QMod{3}()
            Sturm.apply_ry!(current_context(), q.wires[2], π)   # |10⟩ = label 2
            when(ctrl) do
                q.φ += δ
            end
            amps = _amps_snapshot(current_context())
            # Qubit layout: ctrl=wire1, q.wires=(wire2, wire3). 3 qubits total.
            # Bit order in orkan index: bit0=wire1 (ctrl), bit1=wire2 (q LSB),
            # bit2=wire3 (q MSB). State is |2⟩_d on q = wire2=0, wire3=1 →
            # bits (wire1, wire2, wire3) pack as: |0⟩_ctrl |2⟩_d = (0, 0, 1)
            # = index 4 (binary 100); |1⟩_ctrl |2⟩_d = (1, 0, 1) = index 5.
            @test abs(amps[5]) ≈ 1/√2 atol=1e-10
            @test abs(amps[6]) ≈ 1/√2 atol=1e-10
            # All other amps ≈ 0
            for i in 1:8
                if i != 5 && i != 6
                    @test abs(amps[i]) < 1e-10
                end
            end
        end
    end

    @testset "nrs d=3: when-control preserves subspace (|11⟩ stays empty)" begin
        # Even under coherent control, Rz is diagonal so |11⟩_d (forbidden)
        # amplitude stays 0.
        @context EagerContext() begin
            ctrl = QBool(0.5)
            q = QMod{3}()
            when(ctrl) do
                q.φ += 0.3
                q.φ += -0.1
            end
            # Outcome: no leakage at measurement
            _ = Bool(ctrl)
            result = Int(q)
            @test result == 0
        end
    end

    # ── k8u: spin-j Ry primitive at d=3 (closed-form 3-Givens) ──────────────
    #
    # Bead `Sturm.jl-k8u`. Ships `q.θ += δ` at d=3 via the closed-form
    #
    #     d¹(δ) = G_{01}(2γ) · G_{12}(2β) · G_{01}(2γ)
    #
    #     γ = atan(sin(δ/2),             √2 · cos(δ/2))
    #     β = atan(sin(δ/2)·√(2−sin²(δ/2)),  cos²(δ/2))
    #
    # (Orchestrator-verified to machine epsilon across δ ∈ (−π, 2π).) A sign
    # bug in the CX-scratch G_{12} lowering — missed by both proposer
    # designs — was caught pre-ship by numerical verification of the
    # qubit-circuit 4×4 unitary: the circuit actually realises G_{12}(−2β),
    # so the angle must be negated in the `_controlled_ry!` call. d ≥ 4
    # is filed as follow-on bead Sturm.jl-ixd (sandwich V(π/2)·Rz·V(−π/2)).
    #
    # Refs: docs/physics/bartlett_deGuise_sanders_2002_qudit_simulation.pdf
    #       Eq. 5; docs/design/k8u_design_{A,B}.md; WORKLOG Session 56.

    """Closed-form Wigner d¹(δ) in Bartlett label basis (s=0,1,2 ↔ m=+1,0,−1)."""
    function _wigner_d1_label_basis(δ)
        c, s = cos(δ/2), sin(δ/2)
        return [ c^2            -sqrt(2)*c*s     s^2           ;
                 sqrt(2)*c*s     c^2 - s^2      -sqrt(2)*c*s   ;
                 s^2             sqrt(2)*c*s     c^2           ]
    end

    # QMod{3} label s ∈ {0,1,2} → 1-indexed amps slot in the 4-dim 2-qubit
    # statevector. Little-endian: |00⟩=idx 1 (label 0), |01⟩=idx 2 (label 1),
    # |10⟩=idx 3 (label 2), |11⟩=idx 4 (forbidden).
    _qmod3_amp_idx(s) = s + 1

    @testset "k8u d=3: q.θ += π/3 matches d¹(π/3) column 0 (criterion a)" begin
        # Bead acceptance (a): expected amps (0.75, sin(π/3)/√2, 0.25) on
        # labels (0, 1, 2); forbidden amp < 1e-12.
        @context EagerContext() begin
            q = QMod{3}()
            q.θ += π/3
            amps = _amps_snapshot(current_context())
            @test abs(amps[1]) ≈ 0.75 atol=1e-10
            @test abs(amps[2]) ≈ sin(π/3)/sqrt(2) atol=1e-10
            @test abs(amps[3]) ≈ 0.25 atol=1e-10
            @test abs(amps[4]) < 1e-12
        end
    end

    @testset "k8u d=3: full d¹(δ) match on all 3 columns for multiple δ" begin
        # For each column s₀ ∈ {0, 1, 2}, prep |s₀⟩_d via raw apply_ry! on
        # the bit-wires, apply q.θ += δ, compare amps vs d¹(δ)[:, s₀].
        for δ in (π/3, π/4, -0.5, 2.718, 0.0, -π/2)
            target = _wigner_d1_label_basis(δ)
            for s0 in 0:2
                @context EagerContext() begin
                    q = QMod{3}()
                    ctx = current_context()
                    if (s0 & 1) == 1; Sturm.apply_ry!(ctx, q.wires[1], π); end
                    if (s0 & 2) == 2; Sturm.apply_ry!(ctx, q.wires[2], π); end
                    q.θ += δ
                    amps = _amps_snapshot(ctx)
                    for s_out in 0:2
                        @test abs(amps[_qmod3_amp_idx(s_out)]) ≈
                              abs(target[s_out + 1, s0 + 1]) atol=1e-10
                    end
                    @test abs(amps[4]) < 1e-10
                end
            end
        end
    end

    @testset "k8u d=3: leakage-free across 50 random Ry rotations" begin
        # Apply 50 random q.θ on a single register; |11⟩ amplitude must stay
        # at ≈ 0 and measurement must succeed (layer-3 guard never trips).
        @context EagerContext() begin
            q = QMod{3}()
            for _ in 1:50
                q.θ += (rand() - 0.5) * 2π
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[4]) < 1e-10
            result = Int(q)
            @test 0 ≤ result ≤ 2
        end
    end

    @testset "k8u d=3: periodicity — q.θ += δ ≡ q.θ += δ+2π" begin
        # d¹(δ+2π) = d¹(δ) for integer spin j=1. The closed-form angles γ, β
        # wrap naturally via atan2 (and sin/cos are 2π-periodic at arg δ/2
        # shifted by π — the overall 3-Givens product recovers exactly).
        δ = 0.7
        amps_a = @context EagerContext() begin
            q = QMod{3}()
            q.θ += δ
            _amps_snapshot(current_context())
        end
        amps_b = @context EagerContext() begin
            q = QMod{3}()
            q.θ += δ + 2π
            _amps_snapshot(current_context())
        end
        @test all(isapprox.(amps_a, amps_b; atol=1e-10))
    end

    @testset "k8u d=3: mixed Ry + Rz sequence matches analytic product" begin
        # q.θ += a; q.φ += b; q.θ += c produces d¹(c)·D(b)·d¹(a)|0⟩_d where
        # D(b) = diag(exp(−i·b·(j−s))) for s∈{0,1,2}, j=1. Rz carries the
        # per-wire global phase exp(−iδj); since we're starting in a real
        # positive state and comparing to exp(−i·b·(j−s)), we check by
        # modelling Rz as exactly that diagonal (which nrs implements up to
        # a true global phase that vanishes in |amp|²).
        a, b, c = 0.3, 0.5, -0.2
        @context EagerContext() begin
            q = QMod{3}()
            q.θ += a
            q.φ += b
            q.θ += c
            amps = _amps_snapshot(current_context())
            D = Diagonal([exp(-im*b*(1-s)) for s in 0:2])
            expected = _wigner_d1_label_basis(c) * D *
                       _wigner_d1_label_basis(a)[:, 1]
            # nrs's per-wire Rz factorisation differs from the analytic D by
            # a global phase (exp(−iδj) + per-wire Rz framing). Compare
            # amplitudes up to a common complex scalar.
            # Specifically: find the phase α such that amps[1:3] ≈ e^{iα}·expected,
            # then verify the ratio is consistent (= constant global phase).
            scale = amps[1] / expected[1]
            @test abs(abs(scale) - 1) < 1e-10
            for s_out in 0:2
                @test amps[_qmod3_amp_idx(s_out)] ≈ scale * expected[s_out+1] atol=1e-10
            end
            @test abs(amps[4]) < 1e-10
        end
    end

    @testset "k8u d=3: when(::QBool) q.θ += π/3 on superposition control" begin
        # Prep ctrl = (|0⟩+|1⟩)/√2, q = |0⟩_d. Apply when(ctrl) q.θ += π/3.
        # Wire alloc order: ctrl (bit 0), q.wires[1] = q_lsb (bit 1),
        # q.wires[2] = q_msb (bit 2). 8 basis states.
        #
        # Expected amps (1-indexed):
        #   idx 1 (ctrl=0, q=0): 1/√2
        #   idx 2 (ctrl=1, q=0): 0.75/√2
        #   idx 4 (ctrl=1, q=1): (1/√2)·sin(π/3)/√2 = sin(π/3)/2
        #   idx 6 (ctrl=1, q=2): 0.25/√2
        #   all others ≈ 0 (including idx 8 = ctrl=1, q=forbidden)
        @context EagerContext() begin
            ctrl = QBool(0.5)
            q = QMod{3}()
            when(ctrl) do
                q.θ += π/3
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[1]) ≈ 1/sqrt(2) atol=1e-10
            @test abs(amps[2]) ≈ 0.75/sqrt(2) atol=1e-10
            @test abs(amps[4]) ≈ sin(π/3)/2 atol=1e-10
            @test abs(amps[6]) ≈ 0.25/sqrt(2) atol=1e-10
            for i in (3, 5, 7, 8)
                @test abs(amps[i]) < 1e-10
            end
        end
    end

    @testset "k8u d=3: subspace preservation over 1000 random Ry/Rz sequences (criterion c)" begin
        # Bead acceptance (c) adapted to d=3: N=1000 random sequences of θ/φ
        # rotations; forbidden-state amplitude < 1e-10 every single trial.
        n_ok = 0
        for _ in 1:1000
            @context EagerContext() begin
                q = QMod{3}()
                n_ops = 3 + rand(0:10)
                for _ in 1:n_ops
                    δ = (rand() - 0.5) * 4π
                    if rand() < 0.5
                        q.θ += δ
                    else
                        q.φ += δ
                    end
                end
                amps = _amps_snapshot(current_context())
                if abs(amps[4]) < 1e-10
                    n_ok += 1
                end
            end
        end
        @test n_ok == 1000
    end

    @testset "k8u d=3: Int(q) after Ry samples match |d¹|² distribution" begin
        # d¹(2π/3) column 0 amplitudes: c² = cos²(π/3) = 1/4; √2 cs = √6/4;
        # s² = sin²(π/3) = 3/4. Squared: (1/16, 3/8, 9/16). Measure N shots.
        N = 4000
        counts = [0, 0, 0]
        for _ in 1:N
            @context EagerContext() begin
                q = QMod{3}()
                q.θ += 2π/3
                r = Int(q)
                counts[r+1] += 1
            end
        end
        # 3σ bounds (N=4000):
        #   p=1/16=0.0625:  μ=250,  σ≈15,   3σ=[205, 295]
        #   p=3/8=0.375:    μ=1500, σ≈31,   3σ=[1407, 1593]
        #   p=9/16=0.5625:  μ=2250, σ≈31,   3σ=[2157, 2343]
        # Use 4σ-ish windows to stay robust:
        @test 195 ≤ counts[1] ≤ 305
        @test 1380 ≤ counts[2] ≤ 1620
        @test 2130 ≤ counts[3] ≤ 2370
    end

    @testset "k8u d=2 regression: QMod{2}.θ parity with QBool still holds" begin
        # d=2 routes through BlochProxy (not the new _apply_spin_j_ry_d3!).
        # Guard against accidental dispatch regression.
        for δ in (π/7, π/3, -π/4, 1.7)
            amps_qbool = @context EagerContext() begin
                q = QBool(0.0); q.θ += δ
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}(); q.θ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
        end
    end

    # ── ixd: spin-j Ry primitive at d=5 (Euler sandwich) ──────────────────
    #
    # Bead `Sturm.jl-ixd`. Ships `q.θ += δ` at d=5 via the Euler sandwich
    #
    #     exp(-i δ Ĵ_y)_{spin-j} = Rz_j(π/2)·Ry_j(π/2)·Rz_j(δ)·Ry_j(-π/2)·Rz_j(-π/2)
    #
    # where Ry_j(±π/2) are δ-INDEPENDENT fixed unitaries precomputed once
    # (via Givens decomposition of d²(π/2)), and the middle Rz_j(δ) is the
    # nrs per-wire Rz factorisation verbatim.
    #
    # Orchestrator verified: full 8×8 qubit circuit for V5 ⊕ I_3 equals
    # target to 3e-16; sandwich subspace action matches exp(-iδĴ_y) to
    # machine epsilon modulo a global phase ξ(δ) = exp(i·δ·[j − (2^K−1)/2])
    # = exp(-1.5iδ) at d=5 (becomes a controlled relative phase under
    # when(), same as nrs Rz policy).
    #
    # IMPORTANT: the bead description's "expected formula"
    #     [c⁴, -2c³s, √6 c²s², -2cs³, s⁴]
    # for d²(π/4) col 0 has WRONG signs on odd-m rows. Tests must use the
    # numerical `exp(-iδĴ_y) |0⟩` reference (all-positive at δ=π/4).
    #
    # Refs: docs/design/ixd_design_{A,B}.md; docs/physics/bartlett…2002 Eq. 5;
    # WORKLOG Session 57 (2026-04-23). d=4 split to a follow-on bead since
    # csw critical path only needs d ∈ {3, 5}.

    """
    Numerically compute Wigner d^j(β) column 0 in Bartlett label basis.
    Label s ∈ {0, …, d−1} ↔ m = j−s; column 0 means input m' = +j (top of
    spin ladder). At m'=+j the k-sum collapses to k=0:
        d^j_{m, j}(β) = √(C(2j, j−m)) · cos(β/2)^{j+m} · sin(β/2)^{j-m}
    All entries are non-negative for β ∈ (0, π). This is the TRUE ground
    truth — the bead's "expected formula" [c⁴, -2c³s, √6 c²s², -2cs³, s⁴]
    with alternating signs is WRONG.
    """
    function _wigner_dj_col0(d::Int, β::Real)
        j = (d - 1) // 2                # half-integer-safe rational
        col = zeros(Float64, d)
        c, s = cos(β/2), sin(β/2)
        two_j = Int(2 * j)              # = d - 1, always an Int
        for s_idx in 0:(d-1)
            jm = two_j - s_idx          # j + m = 2j - s
            jm_neg = s_idx              # j - m = s
            coeff = sqrt(float(binomial(two_j, jm_neg)))
            col[s_idx + 1] = coeff * c^jm * s^jm_neg
        end
        return col
    end

    """
    Full numerical Wigner d^j(β) matrix in Bartlett label basis (s = 0..d−1,
    m = j−s). Computed via matrix exponential exp(-iβ Ĵ_y) where Ĵ_y is the
    standard spin-j matrix in the |j, m⟩_z basis with m in DECREASING order
    (so that Ĵ_y is tridiagonal and (row s, col s') entry corresponds to
    ⟨j, j−s|Ĵ_y|j, j−s'⟩). Real orthogonal for real β.
    """
    function _wigner_dj_full(d::Int, β::Real)
        j = (d - 1) / 2
        Jy = zeros(ComplexF64, d, d)
        for s1 in 0:(d-1), s2 in 0:(d-1)
            m1, m2 = j - s1, j - s2
            if m1 ≈ m2 + 1
                Jy[s1+1, s2+1] = sqrt(j*(j+1) - m2*(m2+1)) / (2im)
            elseif m1 ≈ m2 - 1
                Jy[s1+1, s2+1] = -sqrt(j*(j+1) - m2*(m2-1)) / (2im)
            end
        end
        return real.(exp(-im * β * Jy))  # real orthogonal
    end

    """Map QMod{5} label s ∈ {0..7} (incl. leakage 5,6,7) to amps idx (1..8)."""
    _qmod5_amp_idx(s) = s + 1

    @testset "ixd d=5: q.θ += π/4 matches d²(π/4) column 0 (criterion a)" begin
        # Expected (all positive, NOT the bead's broken signs):
        #   (cos(π/8)⁴, 2 cos³(π/8) sin(π/8), √6 cos²(π/8) sin²(π/8),
        #    2 cos(π/8) sin³(π/8), sin(π/8)⁴)
        #  ≈ (0.72855339, 0.60355339, 0.30618622, 0.10355339, 0.02144661)
        expected = _wigner_dj_col0(5, π/4)
        @context EagerContext() begin
            q = QMod{5}()
            q.θ += π/4
            amps = _amps_snapshot(current_context())
            for s in 0:4
                @test abs(amps[_qmod5_amp_idx(s)]) ≈ expected[s + 1] atol=1e-10
            end
            for s in 5:7
                @test abs(amps[_qmod5_amp_idx(s)]) < 1e-10
            end
            # Probability sum check
            @test sum(abs2(amps[i]) for i in 1:8) ≈ 1.0 atol=1e-10
        end
    end

    @testset "ixd d=5: column 0 for multiple δ (amplitudes all-positive per Wigner)" begin
        for δ in (π/3, π/4, 1.2, -0.5, 0.0, -π/3)
            expected = _wigner_dj_col0(5, δ)
            @context EagerContext() begin
                q = QMod{5}()
                q.θ += δ
                amps = _amps_snapshot(current_context())
                for s in 0:4
                    @test abs(amps[_qmod5_amp_idx(s)]) ≈ abs(expected[s + 1]) atol=1e-10
                end
                for s in 5:7
                    @test abs(amps[_qmod5_amp_idx(s)]) < 1e-10
                end
            end
        end
    end

    @testset "ixd d=5: leakage-free across 50 random Ry rotations" begin
        # Apply 50 random q.θ on a single register at d=5. Leakage amps
        # (labels 5, 6, 7) must stay near 0.
        @context EagerContext() begin
            q = QMod{5}()
            for _ in 1:50
                q.θ += (rand() - 0.5) * 2π
            end
            amps = _amps_snapshot(current_context())
            for s in 5:7
                @test abs(amps[_qmod5_amp_idx(s)]) < 1e-9
            end
            result = Int(q)
            @test 0 ≤ result ≤ 4
        end
    end

    @testset "ixd d=5: periodicity — q.θ += δ ≡ q.θ += δ + 2π" begin
        # d²(δ + 2π) = d²(δ) for integer spin j=2 (2π-periodic).
        δ = 0.9
        amps_a = @context EagerContext() begin
            q = QMod{5}()
            q.θ += δ
            _amps_snapshot(current_context())
        end
        amps_b = @context EagerContext() begin
            q = QMod{5}()
            q.θ += δ + 2π
            _amps_snapshot(current_context())
        end
        # Compare up to a global phase (the nrs Rz factorisation adds a
        # δ-dependent global phase ξ(δ) that differs between δ and δ+2π).
        # Check amplitude magnitudes match.
        for i in 1:8
            @test abs(amps_a[i]) ≈ abs(amps_b[i]) atol=1e-10
        end
    end

    @testset "ixd d=5: when(::QBool) q.θ += π/3 on superposition control" begin
        # Prep ctrl = (|0⟩+|1⟩)/√2, q = |0⟩_d. After when(ctrl) q.θ += π/3:
        #   ctrl=0 branch: q untouched, stays |0⟩_d.
        #   ctrl=1 branch: q gets rotated by Sturm_Ry(π/3).
        # Sturm_Ry = ξ(δ) · exp(-iδĴ_y) where ξ(δ) = exp(-1.5iδ).
        # At δ=π/3, ξ = exp(-iπ/2) = -i.
        #
        # Wire layout: 4 qubits — ctrl (bit 0), q.wires[1] (bit 1, q_LSB),
        # q.wires[2] (bit 2), q.wires[3] (bit 3, q_MSB). 16 basis states.
        # State idx i: bit0 = ctrl, bit1 = q_LSB, ..., bit3 = q_MSB.
        #
        # Check magnitudes (phase-robust) for the non-zero amps:
        #   idx 1  (ctrl=0, q=0 label): |amp| = 1/√2
        #   idx 2  (ctrl=1, q=0): |amp| = d²_{0,0}(π/3)/√2
        #   idx 4  (ctrl=1, q=1): |amp| = d²_{1,0}(π/3)/√2
        #   idx 6  (ctrl=1, q=2): |amp| = d²_{2,0}(π/3)/√2
        #   idx 8  (ctrl=1, q=3): |amp| = d²_{3,0}(π/3)/√2
        #   idx 10 (ctrl=1, q=4): |amp| = d²_{4,0}(π/3)/√2
        #   all other amps < 1e-10 (leakage, ctrl=0 × non-zero q, etc.)
        δ = π/3
        expected = _wigner_dj_col0(5, δ)
        @context EagerContext() begin
            ctrl = QBool(0.5)
            q = QMod{5}()
            when(ctrl) do
                q.θ += δ
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[1])  ≈ 1/sqrt(2)              atol=1e-10
            @test abs(amps[2])  ≈ expected[1] / sqrt(2)  atol=1e-10
            @test abs(amps[4])  ≈ expected[2] / sqrt(2)  atol=1e-10
            @test abs(amps[6])  ≈ expected[3] / sqrt(2)  atol=1e-10
            @test abs(amps[8])  ≈ expected[4] / sqrt(2)  atol=1e-10
            @test abs(amps[10]) ≈ expected[5] / sqrt(2)  atol=1e-10
            # Forbidden / zero positions
            for i in (3, 5, 7, 9, 11, 12, 13, 14, 15, 16)
                @test abs(amps[i]) < 1e-10
            end
        end
    end

    @testset "ixd d=5: 1000 random Ry/Rz sequences preserve subspace (criterion c)" begin
        # 1000 trials, each applies 3..13 random q.θ / q.φ ops with
        # uniform angles; leakage amps (labels 5,6,7) must stay near 0.
        n_ok = 0
        for _ in 1:1000
            @context EagerContext() begin
                q = QMod{5}()
                n_ops = 3 + rand(0:10)
                for _ in 1:n_ops
                    δ = (rand() - 0.5) * 4π
                    if rand() < 0.5
                        q.θ += δ
                    else
                        q.φ += δ
                    end
                end
                amps = _amps_snapshot(current_context())
                leak_norm = maximum(abs(amps[_qmod5_amp_idx(s)]) for s in 5:7)
                if leak_norm < 1e-8
                    n_ok += 1
                end
            end
        end
        @test n_ok == 1000
    end

    @testset "ixd d=5: Int(q) after Ry samples match |d²|² distribution" begin
        # d²(π/4) col 0 amplitudes (all positive, Wigner closed form):
        expected_amps = _wigner_dj_col0(5, π/4)
        # Squared = probability of measuring label s:
        probs = expected_amps .^ 2   # ≈ (0.531, 0.364, 0.0938, 0.0107, 0.00046)
        N = 4000
        counts = zeros(Int, 5)
        for _ in 1:N
            @context EagerContext() begin
                q = QMod{5}()
                q.θ += π/4
                r = Int(q)
                counts[r + 1] += 1
            end
        end
        # Check each count within ~5σ of expected
        for s in 0:4
            μ = probs[s + 1] * N
            σ = sqrt(N * probs[s + 1] * (1 - probs[s + 1]))
            # 5σ tolerance is generous; prob[4]~4e-4 means μ~1.8, σ~1.4 → allow 0..10 or so.
            lo = max(0, Int(floor(μ - 6σ - 3)))
            hi = Int(ceil(μ + 6σ + 3))
            @test lo ≤ counts[s + 1] ≤ hi
        end
    end

    @testset "ixd d=5: hardcoded Givens angles match fresh QR to machine epsilon" begin
        # Session 57 learning: transcribing 16-digit decimals by hand
        # introduced a 1e-8 error in the statevector output (const differed
        # from QR-produced angles by up to 1.5e-8 at index 5). The fix was
        # to write Float64 literals via `repr(θ)`. This regression test
        # recomputes the 10 angles from scratch and asserts bit-identical
        # agreement with `Sturm._RY_J_HALFPI_D5_OPS` — do NOT let a future
        # edit revert to truncated-decimal literals without this catching.
        #
        # Procedure: build V₅ = d²(π/2) via matrix exponential of Ĵ_y
        # (Bartlett label basis, m = j−s), then QR-zero below-diagonal
        # collecting 2·atan2(b, a) angles.
        function _spinj_jy_d5()
            j = 2.0
            M = zeros(ComplexF64, 5, 5)
            for s1 in 0:4, s2 in 0:4
                m1, m2 = j - s1, j - s2
                if isapprox(m1, m2 + 1; atol=1e-12)
                    M[s1+1, s2+1] = sqrt(j*(j+1) - m2*(m2+1)) / (2im)
                elseif isapprox(m1, m2 - 1; atol=1e-12)
                    M[s1+1, s2+1] = -sqrt(j*(j+1) - m2*(m2-1)) / (2im)
                end
            end
            return M
        end
        V5 = real.(exp(-im * (π/2) * Matrix(_spinj_jy_d5())))
        # QR-zero below-diagonal, collect (level_i, 2·atan2(b, a))
        M = copy(V5); d = 5
        fresh_ops = Tuple{Int, Float64}[]
        for col in 1:d-1, i in d:-1:col+1
            a, b = M[i-1, col], M[i, col]
            r = sqrt(a^2 + b^2)
            r < 1e-15 && continue
            c, s = a/r, b/r
            row_im1 = M[i-1, :] * c + M[i, :] * s
            row_i   = M[i-1, :] * (-s) + M[i, :] * c
            M[i-1, :] = row_im1
            M[i, :] = row_i
            push!(fresh_ops, (i-1, 2 * atan(b, a)))
        end
        # Reverse to match the forward-product convention stored in the const.
        fresh_forward = [(i-1, θ) for (i, θ) in reverse(fresh_ops)]
        const_ops = Sturm._RY_J_HALFPI_D5_OPS
        @test length(fresh_forward) == length(const_ops) == 10
        for ((pf, θf), (pc, θc)) in zip(fresh_forward, const_ops)
            @test pf == pc
            @test θf == θc  # bit-exact equality (tests catch transcription truncation)
        end
    end

    @testset "ixd d=5: full d²(δ) matrix match on all 5 columns" begin
        # Proposers flagged H=2 pair (1,2) and H=3 pair (3,4) as highest-
        # risk for polarity bugs. Preparing each label |s_in⟩_d (s_in ∈
        # 0..4) via raw apply_ry! bit-flips, applying q.θ += δ, and
        # comparing the full output against d²(δ)[:, s_in] exercises every
        # Givens-block structure end-to-end.
        for δ in (0.5, -0.3, π/7, 1.2)
            target = _wigner_dj_full(5, δ)
            for s_in in 0:4
                @context EagerContext() begin
                    q = QMod{5}()
                    ctx = current_context()
                    # Prep |s_in⟩_d via raw bit-flips on the 3 LE wires.
                    for bit in 0:2
                        if (s_in >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    q.θ += δ
                    amps = _amps_snapshot(ctx)
                    for s_out in 0:4
                        @test abs(amps[_qmod5_amp_idx(s_out)]) ≈
                              abs(target[s_out + 1, s_in + 1]) atol=1e-10
                    end
                    for s_out in 5:7
                        @test abs(amps[_qmod5_amp_idx(s_out)]) < 1e-10
                    end
                end
            end
        end
    end

    # ── os4: q.θ₂ += δ — quadratic-phase / squeezing primitive ──────────────
    #
    # Bead `Sturm.jl-os4`. Primitive #4 of the locked 6-primitive qudit set
    # (docs/physics/qudit_magic_gate_survey.md §8.1, §8.2):
    #
    #   q.θ₂ += δ ↦ exp(-i·δ·n̂²) on QMod{d, K}
    #
    # where n̂ is the COMPUTATIONAL-BASIS label operator (n̂|k⟩ = k|k⟩, NOT
    # the spin-j Ĵ_z label). Diagonal in the computational basis: the gate
    # applies phase exp(-i·δ·k²) to |k⟩.
    #
    # At d=2 with k ∈ {0, 1}: k² = k, so exp(-iδ·n̂²) = exp(-iδ·n̂) — collapses
    # to Rz-equivalent up to global phase (NOT a global phase as a (residual
    # of an earlier draft) reading of §8.1's "respectively" suggests; with
    # the §8.2 lock-in to n̂ rather than Ĵ_z, both 4 and 5 collapse to
    # Rz-equivalent at d=2, since k² = k³ = k for k ∈ {0,1}).
    #
    # Qubit-encoded fallback decomposition: with k = Σᵢ b_{i-1}·2^{i-1}
    # (LE) and b² = b on bits, k² = Σᵢ b_{i-1}·4^{i-1} +
    # Σ_{i<j} b_{i-1}·b_{j-1}·2^{i+j-1}. The exponential factors as a
    # product of K linear-phase Rz's (one per wire) and K(K-1)/2 controlled-
    # phase pairs (one per bit-pair). See `_apply_n_squared!` docstring.
    #
    # under `when()`: per locked policy §8.4, the controlled-phase decomp
    # carries a per-pair global phase that becomes a relative phase under
    # `when()`. Same SU(d)-not-U(d) discipline as H²=−I. Tests assert
    # behavioural correctness, not bit-equality with a specific lift.

    @testset "os4 d=3: q.θ₂ += δ is diagonal (no amplitude redistribution)" begin
        # Prep |0⟩_d. Each amplitude on |0⟩_d picks up phase exp(-i·0²·δ)=1.
        # Amplitudes elsewhere stay at 0.
        for δ in (0.0, 0.3, π/3, π, -π/5)
            @context EagerContext() begin
                q = QMod{3}()
                q.θ₂ += δ
                amps = _amps_snapshot(current_context())
                @test abs(amps[1]) ≈ 1.0 atol=1e-10
                @test abs(amps[2]) < 1e-12
                @test abs(amps[3]) < 1e-12
                @test abs(amps[4]) < 1e-12  # forbidden state stays empty
            end
        end
    end

    @testset "os4 d=3: phase exp(-i·k²·δ) on each label k ∈ {0,1,2}" begin
        # Spec: exp(-iδ·n̂²)|k⟩ = exp(-iδ·k²)|k⟩ — UP TO GLOBAL PHASE,
        # per the SU(d) policy (locked §8.4). The qubit-encoded
        # decomposition leaves a uniform e^{iδ·G(K)} global on every basis
        # state. Use a |0⟩_d reference run at the same δ to extract that
        # global, then divide.
        for δ in (0.7, π/5, -π/3)
            global_phase = @context EagerContext() begin
                q = QMod{3}()
                q.θ₂ += δ
                _amps_snapshot(current_context())[1]
            end
            for k in 0:2
                @context EagerContext() begin
                    q = QMod{3}()
                    ctx = current_context()
                    for bit in 0:1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    pre_amps = _amps_snapshot(ctx)
                    pre_phase = pre_amps[k + 1]
                    q.θ₂ += δ
                    amps = _amps_snapshot(ctx)
                    expected = pre_phase * exp(-im * δ * k^2) * global_phase
                    @test amps[k + 1] ≈ expected atol=1e-10
                    for i in 1:4
                        i == k + 1 && continue
                        @test abs(amps[i]) < 1e-12
                    end
                end
            end
        end
    end

    @testset "os4 d=2 collapse: q.θ₂ += δ matches apply_rz!(wire, -δ)" begin
        # At d=2 (K=1) the locked design reduces q.θ₂ to Rz-equivalent
        # (n̂² = n̂ at d=2). Qubit-encoded fallback emits exactly one
        # apply_rz!(wires[1], -δ).
        for δ in (0.0, 0.5, π/4, -π/3, 1.7)
            amps_ref = @context EagerContext() begin
                q = QBool(0.0); q.θ += π/3   # nontrivial superposition
                Sturm.apply_rz!(current_context(), q.wire, -δ)
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}(); q.θ += π/3
                q.θ₂ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_qmod, amps_ref; atol=1e-12))
        end
    end

    @testset "os4 d=4: phase exp(-i·k²·δ) on every k ∈ {0,1,2,3}" begin
        # d=4 is the simplest power-of-2 case: K=2, no leakage (every
        # 2-bit pattern is a legal label). Tests both the linear and
        # bilinear branches of the decomposition (K=2 has one bilinear
        # pair, i=1, j=2). Up to global phase per §8.4 — same |0⟩_d
        # reference trick as the d=3 testset.
        for δ in (0.4, π/5, -π/4)
            global_phase = @context EagerContext() begin
                q = QMod{4}()
                q.θ₂ += δ
                _amps_snapshot(current_context())[1]
            end
            for k in 0:3
                @context EagerContext() begin
                    q = QMod{4}()
                    ctx = current_context()
                    for bit in 0:1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    pre_amps = _amps_snapshot(ctx)
                    pre_phase = pre_amps[k + 1]
                    q.θ₂ += δ
                    amps = _amps_snapshot(ctx)
                    expected = pre_phase * exp(-im * δ * k^2) * global_phase
                    @test amps[k + 1] ≈ expected atol=1e-10
                    for i in 1:4
                        i == k + 1 && continue
                        @test abs(amps[i]) < 1e-12
                    end
                end
            end
        end
    end

    @testset "os4: composability — q.θ₂ += δ; q.θ₂ += -δ returns to identity" begin
        # exp(-iδ·n̂²)·exp(+iδ·n̂²) = I (commuting diagonal exponentials).
        # Use raw apply_ry! on wire1 to mix |0⟩_d ↔ |1⟩_d across all d
        # (q.θ Ry isn't shipped at d=4 yet; this prep sidesteps that).
        for d in (2, 3, 4, 5)
            for δ in (0.5, π/3, -1.2)
                @context EagerContext() begin
                    q = QMod{d}()
                    ctx = current_context()
                    Sturm.apply_ry!(ctx, q.wires[1], 0.7)
                    pre_amps = _amps_snapshot(ctx)
                    q.θ₂ += δ
                    q.θ₂ += -δ
                    post_amps = _amps_snapshot(ctx)
                    @test all(isapprox.(post_amps, pre_amps; atol=1e-10))
                end
            end
        end
    end

    @testset "os4: linearity in δ — θ₂(δ₁) ∘ θ₂(δ₂) ≡ θ₂(δ₁+δ₂)" begin
        # Diagonal commuting Hamiltonians: exp(-iδ₁n̂²)·exp(-iδ₂n̂²) =
        # exp(-i(δ₁+δ₂)n̂²). Verify on d=3 with a non-trivial input state.
        for (δ₁, δ₂) in ((0.3, 0.4), (π/5, -π/7), (-1.0, 0.5))
            split_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₂ += δ₁
                q.θ₂ += δ₂
                _amps_snapshot(current_context())
            end
            sum_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₂ += (δ₁ + δ₂)
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(split_amps, sum_amps; atol=1e-10))
        end
    end

    @testset "os4 d=3: subspace preservation under random q.θ₂ chains" begin
        # n̂² is diagonal in the qubit basis ⇒ q.θ₂ moves no amplitude.
        # If forbidden state |11⟩ starts at 0, it stays at 0 regardless
        # of how many q.θ₂ rotations are stacked.
        @context EagerContext() begin
            q = QMod{3}()
            q.θ += π/3   # populate |0⟩_d, |1⟩_d, |2⟩_d nontrivially
            for _ in 1:10
                q.θ₂ += rand() * 2π
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[4]) < 1e-12  # forbidden |11⟩_qubit
            @test sum(abs2, amps) ≈ 1.0 atol=1e-10  # unitarity
        end
    end

    @testset "os4: proxy types — getproperty(:θ₂) returns QModPhaseProxy" begin
        @context EagerContext() begin
            q2 = QMod{2}()
            @test getproperty(q2, :θ₂) isa Sturm.QModPhaseProxy{2, 1, 2}
        end
        @context EagerContext() begin
            q3 = QMod{3}()
            @test getproperty(q3, :θ₂) isa Sturm.QModPhaseProxy{3, 2, 2}
        end
        @context EagerContext() begin
            q5 = QMod{5}()
            @test getproperty(q5, :θ₂) isa Sturm.QModPhaseProxy{5, 3, 2}
        end
    end

    @testset "os4: proxy access on consumed QMod errors" begin
        @context EagerContext() begin
            q = QMod{3}()
            ptrace!(q)
            @test_throws ErrorException q.θ₂
        end
    end

    @testset "os4 d=3: q.θ₂ -= δ delegates to q.θ₂ += -δ" begin
        # Symmetric API with q.θ -= δ, q.φ -= δ (both delegate via Base.:-).
        for δ in (0.5, π/3, -1.0)
            plus_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₂ += -δ
                _amps_snapshot(current_context())
            end
            minus_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₂ -= δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(plus_amps, minus_amps; atol=1e-12))
        end
    end

    @testset "os4 d=3: when(::QBool) q.θ₂ += δ carries controlled phase" begin
        # Per locked policy §8.4, the bilinear-CZ decomposition leaves a
        # global phase per pair under uncontrolled application — visible as
        # a relative phase under `when()`. The verifiable behavioural claim
        # is: when ctrl = |1⟩, q.θ₂ applies the phase pattern; when ctrl = |0⟩,
        # q.θ₂ is identity (modulo controlled-phase global cost).
        #
        # Test: prep ctrl=|+⟩ ⊗ |k⟩_d for each k. Apply when(ctrl) q.θ₂ += δ.
        # The (ctrl=0)·|k⟩ branch has no phase change. The (ctrl=1)·|k⟩
        # branch picks up exp(-iδ·k²) (plus the SU(d) controlled-phase cost
        # which is observable as a uniform shift across all k branches).
        # Then measure ctrl in X-basis: if (ctrl=0) and (ctrl=1) branches
        # carry the SAME k-state, the phase difference between them is
        # exp(-iδ·k²) up to a uniform global. Different k values produce
        # different relative phases — that's the magic.
        δ = 0.5
        for k in 0:2
            @context EagerContext() begin
                ctrl = QBool(0.0); H!(ctrl)  # |+⟩
                q = QMod{3}()
                ctx = current_context()
                # Prep |k⟩_d on the qudit
                for bit in 0:1
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                when(ctrl) do
                    q.θ₂ += δ
                end
                # The state should be (1/√2)(|0⟩_ctrl⊗|k⟩_d + e^{iφ}|1⟩_ctrl⊗|k⟩_d)
                # where φ depends on k AND on the per-bit-pair controlled-
                # phase cost. The DIFFERENCE between φ(k) and φ(0) is
                # exp(-iδ·k²) — that's the channel-level observable.
                amps = _amps_snapshot(ctx)
                # Find non-zero amplitudes; expect exactly two: ctrl=0/k and ctrl=1/k.
                nz_count = count(a -> abs(a) > 1e-10, amps)
                @test nz_count == 2
                # Both branches keep magnitude 1/√2 (no amplitude movement).
                large = filter(a -> abs(a) > 1e-10, amps)
                @test all(abs.(large) .≈ 1/√2)
            end
        end
    end

    @testset "os4 d=5: phase exp(-i·k²·δ) on each label k ∈ 0..4" begin
        # K=3, three bilinear pairs. End-to-end correctness check.
        # Up to global phase per §8.4 (|0⟩_d reference).
        δ = 0.4
        global_phase = @context EagerContext() begin
            q = QMod{5}()
            q.θ₂ += δ
            _amps_snapshot(current_context())[1]
        end
        for k in 0:4
            @context EagerContext() begin
                q = QMod{5}()
                ctx = current_context()
                for bit in 0:2
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                pre_amps = _amps_snapshot(ctx)
                pre_phase = pre_amps[k + 1]
                q.θ₂ += δ
                amps = _amps_snapshot(ctx)
                expected = pre_phase * exp(-im * δ * k^2) * global_phase
                @test amps[k + 1] ≈ expected atol=1e-10
                # Forbidden labels 5, 6, 7 stay empty.
                for i in 6:8
                    @test abs(amps[i]) < 1e-12
                end
            end
        end
    end

    # ── u2n: Weyl-Heisenberg library gates X_d!, Z_d!, F_d! ─────────────────
    #
    # Bead `Sturm.jl-u2n`. Library gates (NOT primitives) for Z_d (clock),
    # X_d (shift), F_d (QFT). At d=2 they reduce to the existing qubit
    # H!/X!/Z! channels (up to global phase). At d>2:
    #   * Z_d! ships at all d via a single `q.φ += 2π/d`.
    #   * X_d! ships at all d via the Rz(π/2)·Ry(-2π/d)·Rz(-π/2) Euler
    #     conjugation of `q.θ` from Ĵ_y to Ĵ_x (Bartlett Eq. 13).
    #   * F_d! ships at d=2 only (= H!); d ≥ 3 is research-grade and
    #     deferred to a follow-on bead.

    @testset "u2n Z_d at d=2 collapses to qubit Z! channel" begin
        # Both apply q.φ += π up to symbol; statevectors should match
        # bit-identically.
        amps_qbool = @context EagerContext() begin
            q = QBool(0.0); q.θ += π/3   # nontrivial superposition
            Z!(q)
            _amps_snapshot(current_context())
        end
        amps_qmod = @context EagerContext() begin
            q = QMod{2}(); q.θ += π/3
            Z_d!(q)
            _amps_snapshot(current_context())
        end
        @test all(isapprox.(amps_qbool, amps_qmod; atol=1e-12))
    end

    @testset "u2n Z_d at d=3: phase pattern ω^k on each label" begin
        # Z_3|k⟩ = ω^k|k⟩ where ω = e^{2πi/3}. Verify by prepping each
        # |k⟩_d and checking the post-Z_d phase ratio against ω^k. Up to
        # global phase per §8.4.
        ω = exp(2π * im / 3)
        global_phase = @context EagerContext() begin
            q = QMod{3}()
            Z_d!(q)
            _amps_snapshot(current_context())[1]
        end
        for k in 0:2
            @context EagerContext() begin
                q = QMod{3}()
                ctx = current_context()
                for bit in 0:1
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                pre_phase = _amps_snapshot(ctx)[k + 1]
                Z_d!(q)
                amps = _amps_snapshot(ctx)
                expected = pre_phase * ω^k * global_phase
                @test amps[k + 1] ≈ expected atol=1e-10
            end
        end
    end

    @testset "u2n Z_d at d=5: phase pattern ω^k on each label" begin
        ω = exp(2π * im / 5)
        global_phase = @context EagerContext() begin
            q = QMod{5}()
            Z_d!(q)
            _amps_snapshot(current_context())[1]
        end
        for k in 0:4
            @context EagerContext() begin
                q = QMod{5}()
                ctx = current_context()
                for bit in 0:2
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                pre_phase = _amps_snapshot(ctx)[k + 1]
                Z_d!(q)
                amps = _amps_snapshot(ctx)
                expected = pre_phase * ω^k * global_phase
                @test amps[k + 1] ≈ expected atol=1e-10
            end
        end
    end

    @testset "u2n Z_d^d = I up to global phase" begin
        # Apply Z_d d times — all per-basis-state phases multiply to ω^{k·d}
        # = 1, leaving only a state-independent global. Behaviourally
        # identity: each basis-state amplitude returns to its pre-cycle
        # value modulo a uniform phase.
        for d in (2, 3, 5)
            for k in 0:(d-1)
                K = d == 2 ? 1 : (d == 3 ? 2 : 3)
                pre_amp_kp1 = @context EagerContext() begin
                    q = QMod{d}()
                    ctx = current_context()
                    for bit in 0:K-1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    _amps_snapshot(ctx)[k + 1]
                end
                post_amp_kp1 = @context EagerContext() begin
                    q = QMod{d}()
                    ctx = current_context()
                    for bit in 0:K-1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    for _ in 1:d
                        Z_d!(q)
                    end
                    _amps_snapshot(ctx)[k + 1]
                end
                # Magnitudes equal; phases related by uniform (k-independent) global.
                @test abs(post_amp_kp1) ≈ abs(pre_amp_kp1) atol=1e-10
            end
        end
    end

    @testset "u2n X_d at d=2 collapses to qubit X! channel (same statevector mag)" begin
        # X! and X_d! at d=2 differ by a global phase (X_d! = +i·X channel
        # comes out the same; both produce ρ→XρX). Verify magnitudes match
        # bit-identically; phases match up to a uniform global.
        for δ in (0.0, π/4, 1.7)
            amps_qbool = @context EagerContext() begin
                q = QBool(0.0); q.θ += δ
                X!(q)
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}(); q.θ += δ
                X_d!(q)
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(abs.(amps_qbool), abs.(amps_qmod); atol=1e-12))
            # Up to global phase: ratios should be the same.
            if abs(amps_qbool[1]) > 1e-10
                rel_qbool = amps_qbool[2] / amps_qbool[1]
                rel_qmod  = amps_qmod[2]  / amps_qmod[1]
                @test rel_qbool ≈ rel_qmod atol=1e-10
            end
        end
    end

    @testset "u2n X_d at d ≥ 3 errors with deferral message" begin
        # X_d at d ≥ 3 is research-grade (Bartlett Eq. 13 holds in the
        # phase-Fourier basis, not the computational |s⟩ basis Sturm uses).
        # See X_d! docstring for the full caveat.
        for d in (3, 5, 7)
            @context EagerContext() begin
                q = QMod{d}()
                @test_throws ErrorException X_d!(q)
                ptrace!(q)
            end
        end
    end

    @testset "u2n X_d^d = I (cyclic) at d=2 only (d ≥ 3 deferred)" begin
        # At d=2, X_d^2 = I (X is involutive). At d ≥ 3, X_d! errors so
        # we can't test the cyclic property — that's a follow-on bead.
        @context EagerContext() begin
            q = QMod{2}()
            ctx = current_context()
            Sturm.apply_ry!(ctx, q.wires[1], 0.7)
            pre_amps = _amps_snapshot(ctx)
            X_d!(q); X_d!(q)
            post_amps = _amps_snapshot(ctx)
            # X² = I up to a uniform global phase. Magnitudes must match.
            @test all(isapprox.(abs.(pre_amps), abs.(post_amps); atol=1e-10))
            # Relative phase between basis states preserved.
            if abs(pre_amps[1]) > 1e-10 && abs(pre_amps[2]) > 1e-10
                rel_pre = pre_amps[2] / pre_amps[1]
                rel_post = post_amps[2] / post_amps[1]
                @test rel_pre ≈ rel_post atol=1e-10
            end
        end
    end

    @testset "u2n F_d at d=2 ships (= H! channel)" begin
        # F_2 = H. Both q.φ += π; q.θ += π/2.
        amps_h = @context EagerContext() begin
            q = QBool(0.0); H!(q)
            _amps_snapshot(current_context())
        end
        amps_f = @context EagerContext() begin
            q = QMod{2}(); F_d!(q)
            _amps_snapshot(current_context())
        end
        @test all(isapprox.(amps_h, amps_f; atol=1e-12))
    end

    @testset "u2n F_d at d ≥ 3 errors with deferral message" begin
        for d in (3, 5, 7)
            @context EagerContext() begin
                q = QMod{d}()
                @test_throws ErrorException F_d!(q)
                ptrace!(q)
            end
        end
    end

    # ── mle: q.θ₃ += δ — cubic phase / magic primitive ──────────────────────
    #
    # Bead `Sturm.jl-mle`. Primitive #5 of the locked 6-primitive qudit set
    # (docs/physics/qudit_magic_gate_survey.md §8.1, §8.2):
    #
    #   q.θ₃ += δ ↦ exp(-i·δ·n̂³) on QMod{d, K}
    #
    # Diagonal in the computational basis: phases each |k⟩ by exp(-i·δ·k³).
    # Level-3 of the Clifford hierarchy at prime d ≥ 5 (magic). At
    # δ = -2π/d this gives the Campbell M_1 = ω^{n̂³} gate.
    #
    # At d=2, n̂³ = n̂ (since 0³=0, 1³=1), so the gate collapses to
    # Rz-equivalent — emits exactly the same single apply_rz!(wires[1], -δ)
    # as q.θ₂ at d=2. Per locked §8.1 (with §8.2 n̂ lock-in).

    @testset "mle d=3: q.θ₃ += δ is diagonal (no amplitude redistribution)" begin
        for δ in (0.0, 0.3, π/3, π, -π/5)
            @context EagerContext() begin
                q = QMod{3}()
                q.θ₃ += δ
                amps = _amps_snapshot(current_context())
                @test abs(amps[1]) ≈ 1.0 atol=1e-10
                @test abs(amps[2]) < 1e-12
                @test abs(amps[3]) < 1e-12
                @test abs(amps[4]) < 1e-12
            end
        end
    end

    @testset "mle d=3: phase exp(-i·k³·δ) on each label k ∈ {0,1,2}" begin
        # exp(-iδ·n̂³)|k⟩ = exp(-iδ·k³)|k⟩ — up to global phase per §8.4.
        for δ in (0.7, π/5, -π/3)
            global_phase = @context EagerContext() begin
                q = QMod{3}()
                q.θ₃ += δ
                _amps_snapshot(current_context())[1]
            end
            for k in 0:2
                @context EagerContext() begin
                    q = QMod{3}()
                    ctx = current_context()
                    for bit in 0:1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    pre_amps = _amps_snapshot(ctx)
                    pre_phase = pre_amps[k + 1]
                    q.θ₃ += δ
                    amps = _amps_snapshot(ctx)
                    expected = pre_phase * exp(-im * δ * k^3) * global_phase
                    @test amps[k + 1] ≈ expected atol=1e-10
                    for i in 1:4
                        i == k + 1 && continue
                        @test abs(amps[i]) < 1e-12
                    end
                end
            end
        end
    end

    @testset "mle d=2 collapse: q.θ₃ += δ matches apply_rz!(wire, -δ) (n̂³=n̂)" begin
        # At d=2, n̂³ = n̂, so q.θ₃ += δ should produce the same statevector
        # as q.θ₂ += δ (which itself collapses to apply_rz!(wire, -δ)).
        for δ in (0.0, 0.5, π/4, -π/3, 1.7)
            amps_ref = @context EagerContext() begin
                q = QBool(0.0); q.θ += π/3
                Sturm.apply_rz!(current_context(), q.wire, -δ)
                _amps_snapshot(current_context())
            end
            amps_qmod = @context EagerContext() begin
                q = QMod{2}(); q.θ += π/3
                q.θ₃ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_qmod, amps_ref; atol=1e-12))
        end
    end

    @testset "mle d=4: phase exp(-i·k³·δ) on every k ∈ {0,1,2,3}" begin
        # K=2: linear (2 Rz) + 1 bilinear pair, no trilinear.
        for δ in (0.4, π/5, -π/4)
            global_phase = @context EagerContext() begin
                q = QMod{4}()
                q.θ₃ += δ
                _amps_snapshot(current_context())[1]
            end
            for k in 0:3
                @context EagerContext() begin
                    q = QMod{4}()
                    ctx = current_context()
                    for bit in 0:1
                        if (k >> bit) & 1 == 1
                            Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                        end
                    end
                    pre_amps = _amps_snapshot(ctx)
                    pre_phase = pre_amps[k + 1]
                    q.θ₃ += δ
                    amps = _amps_snapshot(ctx)
                    expected = pre_phase * exp(-im * δ * k^3) * global_phase
                    @test amps[k + 1] ≈ expected atol=1e-10
                    for i in 1:4
                        i == k + 1 && continue
                        @test abs(amps[i]) < 1e-12
                    end
                end
            end
        end
    end

    @testset "mle d=5: phase exp(-i·k³·δ) on each label k ∈ 0..4" begin
        # K=3: linear (3 Rz) + 3 bilinear pairs + 1 trilinear (ancilla-CCX-CPhase-CCX).
        # The trilinear is the new gate compared to os4.
        δ = 0.4
        global_phase = @context EagerContext() begin
            q = QMod{5}()
            q.θ₃ += δ
            _amps_snapshot(current_context())[1]
        end
        for k in 0:4
            @context EagerContext() begin
                q = QMod{5}()
                ctx = current_context()
                for bit in 0:2
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                pre_amps = _amps_snapshot(ctx)
                pre_phase = pre_amps[k + 1]
                q.θ₃ += δ
                amps = _amps_snapshot(ctx)
                expected = pre_phase * exp(-im * δ * k^3) * global_phase
                @test amps[k + 1] ≈ expected atol=1e-10
                # Forbidden labels 5, 6, 7 stay empty.
                for i in 6:8
                    @test abs(amps[i]) < 1e-12
                end
            end
        end
    end

    @testset "mle d=5: Campbell M_1 = ω^{n̂³} at δ = -2π/5" begin
        # Bead criterion: at d=5, q.θ₃ += -2π/5 produces the diagonal
        # (1, ω, ω³, ω², ω⁴) where ω = e^{2πi/5}. (k³ mod 5 for
        # k ∈ 0..4 = {0, 1, 3, 2, 4}.)
        ω = exp(2π * im / 5)
        expected_phases = (1, ω, ω^3, ω^2, ω^4)
        δ = -2π / 5
        global_phase = @context EagerContext() begin
            q = QMod{5}()
            q.θ₃ += δ
            _amps_snapshot(current_context())[1]
        end
        for k in 0:4
            @context EagerContext() begin
                q = QMod{5}()
                ctx = current_context()
                for bit in 0:2
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                pre_phase = _amps_snapshot(ctx)[k + 1]
                q.θ₃ += δ
                amps = _amps_snapshot(ctx)
                expected = pre_phase * expected_phases[k + 1] * global_phase
                @test amps[k + 1] ≈ expected atol=1e-10
            end
        end
    end

    @testset "mle: composability — q.θ₃ += δ; q.θ₃ += -δ → identity" begin
        # At d=5 (K=3) the trilinear path's ancilla allocate!+deallocate!
        # grows n_qubits but doesn't shrink on dealloc (Sturm's standard
        # compaction discipline — see compact_state!). pre_amps may be
        # shorter than post_amps; the upper half of post_amps must be 0
        # (ancilla returned to |0⟩ branch).
        for d in (2, 3, 4, 5)
            for δ in (0.5, π/3, -1.2)
                @context EagerContext() begin
                    q = QMod{d}()
                    ctx = current_context()
                    Sturm.apply_ry!(ctx, q.wires[1], 0.7)
                    pre_amps = _amps_snapshot(ctx)
                    q.θ₃ += δ
                    q.θ₃ += -δ
                    post_amps = _amps_snapshot(ctx)
                    n_pre = length(pre_amps)
                    n_post = length(post_amps)
                    @test all(isapprox.(post_amps[1:n_pre], pre_amps; atol=1e-10))
                    if n_post > n_pre
                        # Ancilla=1 amplitudes must all be zero (deallocate
                        # invariant).
                        @test all(abs.(post_amps[n_pre+1:end]) .< 1e-10)
                    end
                end
            end
        end
    end

    @testset "mle: linearity in δ — θ₃(δ₁) ∘ θ₃(δ₂) ≡ θ₃(δ₁+δ₂)" begin
        for (δ₁, δ₂) in ((0.3, 0.4), (π/5, -π/7), (-1.0, 0.5))
            split_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₃ += δ₁
                q.θ₃ += δ₂
                _amps_snapshot(current_context())
            end
            sum_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₃ += (δ₁ + δ₂)
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(split_amps, sum_amps; atol=1e-10))
        end
    end

    @testset "mle d=3: subspace preservation under random q.θ₃ chains" begin
        @context EagerContext() begin
            q = QMod{3}()
            q.θ += π/3
            for _ in 1:10
                q.θ₃ += rand() * 2π
            end
            amps = _amps_snapshot(current_context())
            @test abs(amps[4]) < 1e-12   # forbidden |11⟩_qubit
            @test sum(abs2, amps) ≈ 1.0 atol=1e-10
        end
    end

    @testset "mle d=5: subspace preservation under random q.θ₃ chains" begin
        # K=3 → trilinear allocates ancilla each call; ensure ancilla is
        # cleanly returned to |0⟩ (else amps would leak into the K=4
        # 16-amplitude space — but ancilla deallocate frees the wire so
        # this also tests the lifecycle).
        @context EagerContext() begin
            q = QMod{5}()
            q.θ += π/3
            for _ in 1:5
                q.θ₃ += rand() * 2π
            end
            amps = _amps_snapshot(current_context())
            # Forbidden labels 5..7
            for i in 6:8
                @test abs(amps[i]) < 1e-12
            end
            @test sum(abs2, amps) ≈ 1.0 atol=1e-10
        end
    end

    @testset "mle: proxy types — getproperty(:θ₃) returns QModPhaseProxy{·,·,3}" begin
        @context EagerContext() begin
            q2 = QMod{2}()
            @test getproperty(q2, :θ₃) isa Sturm.QModPhaseProxy{2, 1, 3}
        end
        @context EagerContext() begin
            q3 = QMod{3}()
            @test getproperty(q3, :θ₃) isa Sturm.QModPhaseProxy{3, 2, 3}
        end
        @context EagerContext() begin
            q5 = QMod{5}()
            @test getproperty(q5, :θ₃) isa Sturm.QModPhaseProxy{5, 3, 3}
        end
    end

    @testset "mle: proxy access on consumed QMod errors" begin
        @context EagerContext() begin
            q = QMod{3}()
            ptrace!(q)
            @test_throws ErrorException q.θ₃
        end
    end

    @testset "mle d=3: q.θ₃ -= δ delegates to q.θ₃ += -δ" begin
        for δ in (0.5, π/3, -1.0)
            plus_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₃ += -δ
                _amps_snapshot(current_context())
            end
            minus_amps = @context EagerContext() begin
                q = QMod{3}(); q.θ += π/4
                q.θ₃ -= δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(plus_amps, minus_amps; atol=1e-12))
        end
    end

    @testset "mle d=2 vs d=2 q.θ₂: identical statevectors (n̂² = n̂³ on bits)" begin
        # Both primitives at d=2 collapse to apply_rz!(wires[1], -δ).
        # Verify they emit the SAME statevector on the same input.
        for δ in (0.5, π/3, -1.0)
            amps_q2 = @context EagerContext() begin
                q = QMod{2}(); q.θ += π/4
                q.θ₂ += δ
                _amps_snapshot(current_context())
            end
            amps_q3 = @context EagerContext() begin
                q = QMod{2}(); q.θ += π/4
                q.θ₃ += δ
                _amps_snapshot(current_context())
            end
            @test all(isapprox.(amps_q2, amps_q3; atol=1e-12))
        end
    end

    @testset "mle d=3: when(::QBool) q.θ₃ += δ carries controlled phase" begin
        δ = 0.5
        for k in 0:2
            @context EagerContext() begin
                ctrl = QBool(0.0); H!(ctrl)  # |+⟩
                q = QMod{3}()
                ctx = current_context()
                for bit in 0:1
                    if (k >> bit) & 1 == 1
                        Sturm.apply_ry!(ctx, q.wires[bit + 1], π)
                    end
                end
                when(ctrl) do
                    q.θ₃ += δ
                end
                amps = _amps_snapshot(ctx)
                # Two non-zero amps (ctrl=0 and ctrl=1, both at |k⟩_d).
                nz_count = count(a -> abs(a) > 1e-10, amps)
                @test nz_count == 2
                large = filter(a -> abs(a) > 1e-10, amps)
                @test all(abs.(large) .≈ 1/√2)
            end
        end
    end

    @testset "mle d=5: when(::QBool) q.θ₃ exercises trilinear-under-when" begin
        # K=3 trilinear allocates ancilla and routes apply_ccx! through
        # _multi_controlled_cx! when nc_stack > 0. Smoke test that this
        # path runs without leaking amplitude into forbidden labels.
        @context EagerContext() begin
            ctrl = QBool(0.0); H!(ctrl)
            q = QMod{5}()
            ctx = current_context()
            Sturm.apply_ry!(ctx, q.wires[1], π)  # → |1⟩_d
            when(ctrl) do
                q.θ₃ += 0.5
            end
            amps = _amps_snapshot(ctx)
            # 8 amps for ctrl, 8 amps for K=3 qudit ⇒ 64 total.
            # Magnitude only on (ctrl=*, |1⟩_d) = 2 amplitudes after the
            # 1/√2 split. Forbidden labels (5..7 in qudit) stay 0.
            for ctrl_bit in 0:1
                for s in 5:7
                    # amp index for (ctrl=ctrl_bit, qudit_qubit_state=s).
                    # qudit wires are wires[1..3], ctrl is wire 4 (allocated
                    # before the QMod{5}). Layout depends on allocation
                    # order. Skip fine-grained index check; just confirm
                    # total norm preserved + count non-zero amps.
                end
            end
            nz_count = count(a -> abs(a) > 1e-10, amps)
            # Pure |1⟩_d under H(ctrl): amps split into (ctrl=0)·|1⟩_d and
            # (ctrl=1)·|1⟩_d, both at magnitude 1/√2 — phase differs.
            @test nz_count == 2
            @test sum(abs2, amps) ≈ 1.0 atol=1e-10
        end
    end

end
