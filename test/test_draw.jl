using Test
using Sturm

# Tests for the ASCII circuit drawer — src/channel/draw.jl
# Target: terminal-first Unicode box-drawing renderer for Channel DAGs.
#
# Convention (decided after surveying Qiskit TextDrawer, Cirq text_diagram_drawer,
# Stim timeline_ascii, PennyLane tape_text, quantikz LaTeX):
#   ─   U+2500    quantum wire
#   ═   U+2550    classical wire (post-observe)
#   │   U+2502    vertical connector (gap rows)
#   ┼   U+253C    vertical crossing through a wire
#   ●   U+25CF    control
#   ⊕   U+2295    CNOT target
#   ▷   U+25B7    discard / partial trace
#   ┤ ├  U+2524 / U+251C   measurement box brackets
#   ╥   U+2565    quantum→classical drain
#   ╫   U+256B    classical wire traversed by quantum wire
#   ╩   U+2569    classical fan-in

@testset "Draw / ASCII circuit diagrams" begin

    @testset "empty channel: no dag, no wires" begin
        ch = trace(0) do; nothing; end
        s = Sturm.to_ascii(ch)
        @test s == ""
    end

    @testset "single wire, single gate" begin
        ch = trace(1) do q
            q.θ += π/2
            q
        end
        s = Sturm.to_ascii(ch)
        # Expected: one line, a wire label, some wire and a gate glyph
        @test occursin("q0", s)
        @test occursin("─", s)
        # The Ry(π/2) must appear somewhere
        @test occursin("Ry", s) || occursin("π/2", s)
    end

    @testset "Bell state: Rz(π), Ry(π/2), CX" begin
        ch = trace(2) do a, b
            H!(a)        # → RzNode(π), RyNode(π/2)
            b ⊻= a        # → CXNode(a→b)
            (a, b)
        end
        s = Sturm.to_ascii(ch)
        # Structural expectations:
        # - two wire rows (q0, q1)
        # - a control and a target glyph
        # - a vertical connector between them
        @test occursin("q0", s)
        @test occursin("q1", s)
        @test occursin("●", s)
        @test occursin("⊕", s)
        @test occursin("│", s)
        # Gate recognition: Rz(π) → Z, Ry(π/2) → Ry(π/2) generic
        @test occursin("Z", s) || occursin("Rz", s)
    end

    @testset "Bell state: column compaction" begin
        # H! = Rz + Ry (2 nodes on same wire) then CX — should be 3 columns
        ch = trace(2) do a, b
            H!(a)
            b ⊻= a
            (a, b)
        end
        s = Sturm.to_ascii(ch)
        # Both wires should have the same number of character columns
        lines = split(s, '\n')
        nonempty = filter(!isempty, lines)
        # All non-empty lines have the same printable width (rectangularity)
        widths = unique(length.(nonempty))
        @test length(widths) == 1  # rectangular
    end

    @testset "CNOT spanning non-adjacent wires" begin
        # CX from wire 0 to wire 2 — wire 1 between them must show │ crossing
        ch = trace(3) do a, b, c
            c ⊻= a       # CNOT from a (row 0) to c (row 2)
            (a, b, c)
        end
        s = Sturm.to_ascii(ch)
        # Expect ●, ⊕, and │ connecting them, plus ┼ on the middle wire
        @test occursin("●", s)
        @test occursin("⊕", s)
        @test occursin("│", s) || occursin("┼", s)
    end

    @testset "when-controlled gate: ncontrols=1" begin
        ch = trace(2) do a, b
            when(a) do
                b.θ += π
            end
            (a, b)
        end
        s = Sturm.to_ascii(ch)
        # One gate with ncontrols=1: ● on a, Ry(π) glyph on b
        @test occursin("●", s)
        @test occursin("X", s) || occursin("Ry", s)  # Ry(π) → X or Ry(π)
    end

    @testset "measurement renders with classical wire" begin
        ch = trace(1) do q
            H!(q)
            _ = Bool(q)
            nothing
        end
        s = Sturm.to_ascii(ch)
        # Must have an M and a classical wire segment
        @test occursin("M", s)
        @test occursin("═", s) || occursin("c0", s)
    end

    @testset "angle prettifier: π, π/2, π/4" begin
        @test Sturm._fmt_angle(π) == "π"
        @test Sturm._fmt_angle(-π) == "-π"
        @test Sturm._fmt_angle(π/2) == "π/2"
        @test Sturm._fmt_angle(-π/2) == "-π/2"
        @test Sturm._fmt_angle(π/4) == "π/4"
        @test Sturm._fmt_angle(π/3) == "π/3"
        @test Sturm._fmt_angle(2π) == "2π"
        # non-recognised gets decimal
        @test occursin("0.", Sturm._fmt_angle(0.3))
    end

    @testset "gate name recogniser" begin
        # Pattern-match single-op named gates (angles only)
        w = Sturm.fresh_wire!()
        @test Sturm._gate_label(Sturm.RzNode(w, π)) == "Z"
        @test Sturm._gate_label(Sturm.RzNode(w, π/2)) == "S"
        @test Sturm._gate_label(Sturm.RzNode(w, -π/2)) == "S†"
        @test Sturm._gate_label(Sturm.RzNode(w, π/4)) == "T"
        @test Sturm._gate_label(Sturm.RzNode(w, -π/4)) == "T†"
        @test Sturm._gate_label(Sturm.RyNode(w, π)) == "X"
        # Generic angles fall through to Rz(θ) / Ry(θ)
        @test Sturm._gate_label(Sturm.RzNode(w, 0.3)) == "Rz(0.3)"
        @test occursin("Ry", Sturm._gate_label(Sturm.RyNode(w, 0.7)))
    end

    @testset "rectangular output: every line same printable width" begin
        ch = trace(2) do a, b
            H!(a); H!(b)
            b ⊻= a
            Z!(a); Z!(b)
            (a, b)
        end
        s = Sturm.to_ascii(ch)
        lines = split(rstrip(s), '\n')
        widths = unique(length.(lines))
        @test length(widths) == 1  # every row has the same number of chars
    end

    @testset "ASCII fallback" begin
        ch = trace(2) do a, b
            H!(a); b ⊻= a; (a, b)
        end
        s = Sturm.to_ascii(ch; unicode=false)
        # ASCII mode: no Unicode box-drawing
        @test !occursin("─", s)
        @test !occursin("●", s)
        @test !occursin("⊕", s)
        @test occursin("-", s)  # ASCII wire
        @test occursin("@", s) || occursin("*", s)  # ASCII control
    end

    @testset "Base.show dispatches" begin
        ch = trace(1) do q; H!(q); q; end
        io = IOBuffer()
        show(io, MIME"text/plain"(), ch)
        s = String(take!(io))
        @test !isempty(s)
        @test occursin("q0", s)
    end

    @testset "three-qubit GHZ" begin
        ch = trace(3) do a, b, c
            H!(a)
            b ⊻= a
            c ⊻= b
            (a, b, c)
        end
        s = Sturm.to_ascii(ch)
        @test occursin("q0", s)
        @test occursin("q1", s)
        @test occursin("q2", s)
        # Two CXs → two ● / ⊕ pairs
        @test count(c -> c == '●', s) == 2
        @test count(c -> c == '⊕', s) == 2
    end

    @testset "Steane encoder: 7 wires, 17 gates" begin
        # Smoke test: the renderer survives a realistic QECC circuit
        ctx = TracingContext()
        q = Sturm.allocate!(ctx)
        in_qb = Sturm.QBool(q, ctx, false)
        task_local_storage(:sturm_context, ctx) do
            encode!(Steane(), in_qb)
        end
        ch = Sturm.Channel{1,0}(ctx.dag, (q,), ())
        s = Sturm.to_ascii(ch)
        @test !isempty(s)
        @test length(split(s, '\n')) >= 7  # at least one line per wire
    end

    @testset "compact mode packs parallel gates" begin
        # CR(q0→q2) with H on q1: span mode serialises them; compact packs them.
        ctx = TracingContext()
        wires = [Sturm.allocate!(ctx) for _ in 1:3]
        qs = [Sturm.QBool(w, ctx, false) for w in wires]
        task_local_storage(:sturm_context, ctx) do
            when(qs[1]) do; qs[3].φ += π/2; end
            H!(qs[2])
        end
        ch = Sturm.Channel{3,3}(ctx.dag, Tuple(wires), Tuple(wires))
        s_span    = to_ascii(ch)
        s_compact = to_ascii(ch; compact=true)
        # Compact must be strictly narrower than span on this circuit
        w_span    = length(first(split(s_span, '\n')))
        w_compact = length(first(split(s_compact, '\n')))
        @test w_compact < w_span
        # Gate-wins: q1's H labels (Z, Ry(π/2)) survive intact in compact output
        @test occursin("Ry(π/2)", s_compact)
        @test occursin("Z", s_compact)
    end

    @testset "to_openqasm still works after draw is loaded" begin
        # Regression: loading draw.jl mustn't break the existing exporter
        ch = trace(2) do a, b
            H!(a); b ⊻= a; (a, b)
        end
        qasm = to_openqasm(ch)
        @test occursin("OPENQASM 3.0;", qasm)
    end

end
