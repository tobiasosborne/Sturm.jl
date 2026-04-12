using Test
using Sturm
using PNGFiles
using ColorTypes: RGB, N0f8

@testset "Pixel / PNG circuit rendering" begin

    @testset "empty channel" begin
        ch = trace(0) do; nothing; end
        img = to_pixels(ch)
        @test size(img) == (0, 0)
    end

    @testset "Bell state: dimensions and colours (with gaps)" begin
        ch = trace(2) do a, b; H!(a); b ⊻= a; (a, b); end
        img = to_pixels(ch)
        sch = birren_dark_scheme()

        # 2 wires with gap: H = 2*2-1 = 3 rows. 3 columns × 3 px = 9 px wide.
        @test size(img) == (3, 9)

        # Col 0 gate pixel (Rz on q0) at row 1, col 2
        @test img[1, 2] == sch.gate
        @test img[1, 1] == sch.bg       # left shadow
        @test img[1, 3] == sch.bg       # right shadow
        # Row 2 is the GAP row — bg everywhere except the CNOT column where
        # the vertical connector passes through it.
        @test img[2, 1] == sch.bg
        @test img[2, 2] == sch.bg
        @test img[2, 4] == sch.bg
        # col 8 is the CNOT centre — connector punches through the gap
        @test img[2, 8] == sch.connector
        # q1 wire at row 3 continues unchanged through col 0
        @test img[3, 1] == sch.q_wire
        @test img[3, 2] == sch.q_wire
        @test img[3, 3] == sch.q_wire

        # Col 2 (CNOT): control on q0 at (1, 8), connector in gap at (2, 8), target at (3, 8)
        @test img[1, 8] == sch.control      # seafoam
        @test img[2, 8] == sch.connector    # vertical line through the gap
        @test img[3, 8] == sch.target       # complement
    end

    @testset "non-adjacent CNOT: connector fills interior (with gaps)" begin
        ch = trace(5) do a, b, c, d, e
            e ⊻= a; (a, b, c, d, e)
        end
        img = to_pixels(ch)
        sch = birren_dark_scheme()

        # 5 wires × 1 column × 3 px = 9 rows × 3 cols.
        # Wires at 1, 3, 5, 7, 9. Gaps at 2, 4, 6, 8.
        @test size(img) == (9, 3)
        @test img[1, 2] == sch.control    # q0 control
        @test img[2, 2] == sch.connector  # gap 0–1
        @test img[3, 2] == sch.connector  # q1 interior
        @test img[4, 2] == sch.connector  # gap 1–2
        @test img[5, 2] == sch.connector  # q2 interior
        @test img[6, 2] == sch.connector  # gap 2–3
        @test img[7, 2] == sch.connector  # q3 interior
        @test img[8, 2] == sch.connector  # gap 3–4
        @test img[9, 2] == sch.target     # q4 target
        # Shadows at col 1 and col 3 on every row
        for r in 1:9
            @test img[r, 1] == sch.shadow
            @test img[r, 3] == sch.shadow
        end
    end

    @testset "complementary target colour" begin
        sch = birren_dark_scheme()
        q = sch.q_wire
        t = sch.target
        # For each channel: r_wire + r_target ≈ 255 (mod rounding)
        @test UInt8(reinterpret(UInt8, q.r)) + UInt8(reinterpret(UInt8, t.r)) == 0xff
        @test UInt8(reinterpret(UInt8, q.g)) + UInt8(reinterpret(UInt8, t.g)) == 0xff
        @test UInt8(reinterpret(UInt8, q.b)) + UInt8(reinterpret(UInt8, t.b)) == 0xff
    end

    @testset "Birren palette values" begin
        # Dark scheme expected hex values
        sch = birren_dark_scheme()
        @test sch.bg       == Sturm._hex("#1E2226")
        @test sch.q_wire   == Sturm._hex("#82B896")   # seafoam
        @test sch.gate     == Sturm._hex("#E2C46C")   # yellow
        @test sch.measurement == Sturm._hex("#C4392F") # red
        @test sch.discard  == Sturm._hex("#8C8C84")   # gray
    end

    @testset "light scheme: distinct palette" begin
        d = birren_dark_scheme()
        l = birren_light_scheme()
        @test d.bg != l.bg
        @test l.bg == Sturm._hex("#F4F1E8")          # beige
        @test l.q_wire == Sturm._hex("#3D7A55")       # safety green
    end

    @testset "measurement drain paints classical wire" begin
        ch = trace(2) do a, b
            H!(a); _ = Bool(a)
            H!(b); H!(b)
            b
        end
        img = to_pixels(ch)
        sch = birren_dark_scheme()
        # 2 quantum wires + 1 classical bit = 3 wire-slots → 2*3-1 = 5 rows
        @test size(img, 1) == 5
        H_, W = size(img)
        # Classical bit is at row 5 (last). On that row, c_wire must appear
        # (extended rightward past the drain column).
        @test any(img[5, c] == sch.c_wire for c in 1:W)
        # The drain landing: somewhere on the classical row, measurement colour
        @test any(img[5, c] == sch.measurement for c in 1:W)
    end

    @testset "PNG roundtrip" begin
        ch = trace(2) do a, b; H!(a); b ⊻= a; (a, b); end
        path = tempname() * ".png"
        to_png(ch, path)
        @test isfile(path)
        @test filesize(path) > 0
        img1 = to_pixels(ch)
        img2 = PNGFiles.load(path)
        @test size(img1) == size(img2)
        # PNGFiles loads as RGB{N0f8} — match expected
        @test all(img1[i,j].r == img2[i,j].r &&
                  img1[i,j].g == img2[i,j].g &&
                  img1[i,j].b == img2[i,j].b
                  for i in axes(img1,1), j in axes(img1,2))
        rm(path)
    end

    @testset "column_width validation" begin
        ch = trace(1) do q; H!(q); q; end
        @test_throws ErrorException to_pixels(ch; column_width=2)
        @test_throws ErrorException to_pixels(ch; column_width=4)  # must be odd
        img5 = to_pixels(ch; column_width=5)
        # 1 wire (no gap needed for single wire) × 2 cols × 5 px = 1 × 10
        @test size(img5) == (1, 10)
    end

    @testset "gaps=false restores dense layout" begin
        ch = trace(2) do a, b; H!(a); b ⊻= a; (a, b); end
        img = to_pixels(ch; gaps=false)
        # 2 wires, no gap → 2 rows
        @test size(img) == (2, 9)
    end

    @testset "scale: 100-wire stress (with gaps)" begin
        N = 100
        ctx = TracingContext()
        wires = [Sturm.allocate!(ctx) for _ in 1:N]
        qs = [Sturm.QBool(w, ctx, false) for w in wires]
        task_local_storage(:sturm_context, ctx) do
            H!(qs[1])
            for i in 2:N; qs[i] ⊻= qs[i-1]; end
        end
        ch = Sturm.Channel{N, N}(ctx.dag, Tuple(wires), Tuple(wires))
        img = to_pixels(ch)
        # With gaps: 2N - 1 rows
        @test size(img, 1) == 2N - 1
        @test size(img, 2) == 101 * 3
        path = tempname() * ".png"
        to_png(ch, path)
        @test filesize(path) > 0
        rm(path)
    end

    @testset "unknown scheme errors" begin
        ch = trace(1) do q; H!(q); q; end
        @test_throws ErrorException to_pixels(ch; scheme=:moonlit_forest)
    end

    @testset "pass PixelScheme directly" begin
        ch = trace(2) do a, b; H!(a); b ⊻= a; (a, b); end
        custom = birren_light_scheme()
        img = to_pixels(ch; scheme=custom)
        @test img[3, 1] == custom.q_wire  # q1 wire (row 3 with gaps) uses custom palette
    end

end
