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

end
