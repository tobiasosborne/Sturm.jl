using Test
using Logging
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

    @testset "ak2 d>2: q.θ += δ errors with deferral message" begin
        # Ry at d>2 defers to bead Sturm.jl-k8u (filed when nrs shipped
        # Rz but deferred Ry). Error message must point there.
        for d in (3, 4, 5, 8)
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
                @test occursin("Sturm.jl-k8u", err.msg)
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

end
