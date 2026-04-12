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

    @testset "Bell state: dimensions and colours" begin
        ch = trace(2) do a, b; H!(a); b ⊻= a; (a, b); end
        img = to_pixels(ch)
        sch = birren_dark_scheme()

        # 2 wires × 3 columns × 3 pixels = 2 × 9
        @test size(img) == (2, 9)

        # Col 0 gate pixel (Rz on q0) at (1, 2)
        @test img[1, 2] == sch.gate
        # Shadows flanking: (1, 1) and (1, 3) are bg
        @test img[1, 1] == sch.bg
        @test img[1, 3] == sch.bg
        # q1 wire continues unchanged through col 0
        @test img[2, 1] == sch.q_wire
        @test img[2, 2] == sch.q_wire
        @test img[2, 3] == sch.q_wire

        # Col 2 (CNOT): control on q0 at (1, 8), target on q1 at (2, 8)
        @test img[1, 8] == sch.control       # seafoam (matches q_wire by default)
        @test img[2, 8] == sch.target        # complement
        # Shadows around the CX column on both wires
        @test img[1, 7] == sch.bg
        @test img[1, 9] == sch.bg
        @test img[2, 7] == sch.bg
        @test img[2, 9] == sch.bg
    end

    @testset "non-adjacent CNOT: connector fills interior" begin
        ch = trace(5) do a, b, c, d, e
            e ⊻= a; (a, b, c, d, e)
        end
        img = to_pixels(ch)
        sch = birren_dark_scheme()

        # 5 wires × 1 column × 3 px = 5 × 3
        @test size(img) == (5, 3)
        # Centre pixel at col 2
        @test img[1, 2] == sch.control   # q0 control
        @test img[2, 2] == sch.connector  # q1 interior
        @test img[3, 2] == sch.connector  # q2 interior
        @test img[4, 2] == sch.connector  # q3 interior
        @test img[5, 2] == sch.target    # q4 target
        # Shadow column on every row at x=1 and x=3
        for r in 1:5
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
        # Measure q0 early, then do something on q1 so there are columns after
        # the Observe where the classical wire can extend.
        ch = trace(2) do a, b
            H!(a); _ = Bool(a)
            H!(b); H!(b)
            b
        end
        img = to_pixels(ch)
        sch = birren_dark_scheme()
        # 2 quantum wires + 1 classical bit = 3 rows
        @test size(img, 1) == 3
        H_, W = size(img)
        # Somewhere on the classical row (row 3), c_wire must appear
        @test any(img[3, c] == sch.c_wire for c in 1:W)
        # The drain landing: somewhere on the classical row, measurement colour
        @test any(img[3, c] == sch.measurement for c in 1:W)
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
        # 1 wire × 2 cols × 5 px wide = 1 × 10
        @test size(img5) == (1, 10)
    end

    @testset "scale: 100-wire stress" begin
        # Build a 100-wire GHZ cascade via manual TracingContext
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
        @test size(img, 1) == N
        # 1 H (2 nodes: Rz+Ry) + 99 CNOTs = 101 columns
        @test size(img, 2) == 101 * 3
        # PNG should save without error
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
        @test img[2, 1] == custom.q_wire  # wire colour from custom scheme
    end

end
