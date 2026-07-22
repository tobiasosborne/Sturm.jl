# SPDX-License-Identifier: AGPL-3.0-only
#
# Sturm.jl boot pass. Milestone 0 (bead 23o1 + 2o0y): no quantum code
# exists yet, so this file wires only the two boot lints CLAUDE.md
# requires before anything else is allowed to land:
#
#   (a) Physics-cite lint  — CLAUDE.md rule 4: every `docs/physics/*.md`
#       reference found in `src/` must resolve to a real file.
#   (b) PRD doctest lint   — CLAUDE.md convention 9: every fenced
#       ```julia block in Sturm-PRD-v2.md must parse AND lower
#       (test/test_prd_examples.jl).

using Test
using Sturm

const REPO_ROOT = abspath(joinpath(@__DIR__, ".."))

"""
    find_physics_refs(text) -> Vector{String}

Return every substring of `text` matching the citation-path pattern
`docs/physics/<name>.md` (CLAUDE.md rule 4: "PHYSICS = LOCAL PDF +
EQUATION" — every cited paper needs a local distillation at exactly this
path shape). Pure string function, no filesystem access — this is what
lets the lint be unit-tested directly against a synthetic string below,
independent of whatever real files currently live under `src/`.
"""
function find_physics_refs(text::AbstractString)
    re = r"docs/physics/[A-Za-z0-9_\-]+\.md"
    return [m.match for m in eachmatch(re, text)]
end

"""
    find_ctrl_constructions(text) -> Vector{String}

Return every `Ctrl(` or `_ctrl(` CONSTRUCTION token in `text` (capital-`C`
`Ctrl(` and the private `_ctrl(`), but NOT the lowercase public API `ctrl(`,
nor type positions `Ctrl{…}` / `::Ctrl`. Pure string function — the mechanical
half of the single-choke-point invariant (CLAUDE.md #2, PRD-v2 §4.2): the only
constructor of a `Ctrl` is `_ctrl`, reachable only through `ctrl`, and both
appear in `src/` ONLY in `src/kernel/ctrl.jl`. Self-tested below.
"""
function find_ctrl_constructions(text::AbstractString)
    toks = String[]
    for m in eachmatch(r"\bCtrl\(", text)
        push!(toks, m.match)
    end
    for m in eachmatch(r"_ctrl\(", text)
        push!(toks, m.match)
    end
    return toks
end

"""
    find_controlled_lowerings(text) -> Vector{String}

Return every controlled-lowering token (`orkan_cx`, or the whole word
`controlled`) in `text`. Pure string function — the second choke-point lint
(PRD-v2 §4.2: `ctrl` is the only constructor of controlled lowerings
system-wide). Such tokens may appear in `src/` ONLY under `src/kernel/` or
`src/orkan/`. Self-tested below.
"""
function find_controlled_lowerings(text::AbstractString)
    return [m.match for m in eachmatch(r"orkan_cx|\bcontrolled\b", text)]
end

"""
    find_ccalls(text) -> Vector{String}

Every `ccall` token (`@ccall` and bare `ccall`). Pure string function — the M2
FFI-confinement lint (M2 directive / proposal B §6): the raw FFI is not a
language (P5), so `ccall` may appear in `src/` ONLY under `src/orkan/`.
"""
find_ccalls(text::AbstractString) = [m.match for m in eachmatch(r"ccall", text)]

"""
    find_single_from_mat(text) -> Vector{String}

Every `single_from_mat` token. Pure string function — the M2 lint (audit §8.5):
the header-private, tiled-DM-only, `LOG_TILE_DIM`-coupled matrix entry must
appear NOWHERE in `src/` (not bound, not even named in code — the biggest M2 ABI
risk is kept off the critical path entirely).
"""
find_single_from_mat(text::AbstractString) = [m.match for m in eachmatch(r"single_from_mat", text)]

"""
    find_role_indexing(text) -> Vector{String}

Every `input_wires[` / `output_wires[` bracket-INDEXING token. Pure string
function — the M7 single-remap lint (bead Sturm.jl-7a0v; ruling: mirrors the ctrl
choke-point lint). The MSB/LSB bit-order remap (a silent bit-reversal is the wm28
class) must live in EXACTLY ONE function (`_role_tables`, in the extension), so its
tell-tale register-vector indexing may appear in `src/`+`ext/` nowhere else. Set-
construction like `Set(circuit.output_wires)` is NOT indexing (no bracket) and is
allowed anywhere. Self-tested below.
"""
find_role_indexing(text::AbstractString) = [m.match for m in eachmatch(r"input_wires\[|output_wires\[", text)]

"""
    relsrc(root, fname) -> String

`src/…`-relative path of a walked file, with `/` separators, for the
choke-point lints' allow-list comparison.
"""
function relsrc(root::AbstractString, fname::AbstractString)
    rp = relpath(joinpath(root, fname), REPO_ROOT)
    return replace(rp, '\\' => '/')
end

@testset "Sturm.jl boot lints" begin

    # Method-ambiguity gate (F16/F15, bead vanm): the broad number-like-handle
    # guards `==`/`isequal`/`isless(::AbstractQRegister, ::Any)` (register.jl) can
    # clash with Base's `::Any`-methods (Missing/WeakRef); they are disambiguated
    # explicitly. Pin the whole module ambiguity-free so a future broad method
    # cannot silently reintroduce one.
    @testset "no method ambiguities in Sturm" begin
        @test length(detect_ambiguities(Sturm; recursive=true)) == 0
    end

    @testset "Physics-cite lint" begin
        @testset "lint function catches a fabricated missing reference" begin
            # This is the "actually works" self-test the deliverable
            # demands: prove the regex+resolution logic would catch a
            # dangling citation, using a reference that is guaranteed
            # never to exist on disk — independent of whether src/ has
            # any real citations yet (it does not, in milestone 0).
            synthetic = "See docs/physics/nonexistent_topic_zzz.md eq. (3)."
            refs = find_physics_refs(synthetic)
            @test refs == ["docs/physics/nonexistent_topic_zzz.md"]
            @test !isfile(joinpath(REPO_ROOT, only(refs)))
        end

        @testset "every docs/physics reference cited in src/ resolves" begin
            src_dir = joinpath(REPO_ROOT, "src")
            @test isdir(src_dir)

            nrefs = 0
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    text = read(joinpath(root, fname), String)
                    for ref in find_physics_refs(text)
                        nrefs += 1
                        @test isfile(joinpath(REPO_ROOT, ref))
                    end
                end
            end

            # Milestone 0 ships no quantum code and hence no physics
            # citations: the loop above passes vacuously TODAY. The lint
            # is the per-reference `isfile` @test inside the loop — a
            # dangling citation fails there. nrefs is reported (not
            # pinned: valid citations start landing in M1 and each one
            # would break a `== 0` pin).
            @info "physics-cite lint walked src/" nrefs
        end
    end

    @testset "Choke-point lints (§4.2 single-choke-point invariant)" begin
        @testset "lint functions catch synthetic violations" begin
            @test find_ctrl_constructions("y = Ctrl(2, u)") == ["Ctrl("]
            @test find_ctrl_constructions("y = _ctrl(1, u)") == ["_ctrl("]
            # lowercase public API and type positions are NOT constructions:
            @test find_ctrl_constructions("z = ctrl(u); w::Ctrl; A = Ctrl{U2}") == String[]
            @test find_controlled_lowerings("orkan_cx(state, c, t)") == ["orkan_cx"]
            @test find_controlled_lowerings("a controlled gate") == ["controlled"]
            @test find_controlled_lowerings("the control wire") == String[]
        end

        @testset "Ctrl construction appears only in src/kernel/ctrl.jl" begin
            src_dir = joinpath(REPO_ROOT, "src")
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    rel = relsrc(root, fname)
                    text = read(joinpath(root, fname), String)
                    toks = find_ctrl_constructions(text)
                    if rel == "src/kernel/ctrl.jl"
                        @test !isempty(toks)          # the choke point itself constructs
                    else
                        @test isempty(toks)           # nowhere else may
                    end
                end
            end
        end

        @testset "controlled lowerings appear only under src/kernel/ or src/orkan/" begin
            src_dir = joinpath(REPO_ROOT, "src")
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    rel = relsrc(root, fname)
                    allowed = startswith(rel, "src/kernel/") || startswith(rel, "src/orkan/")
                    allowed && continue
                    text = read(joinpath(root, fname), String)
                    @test isempty(find_controlled_lowerings(text))
                end
            end
        end
    end

    @testset "M8 PASS_REGISTRY law-coverage lint (§4.2 pass law, mirrors ctrl choke point)" begin
        # The pass-side analogue of the ctrl choke-point lint (design m8-5hr7 §3.3):
        # every registered UnitaryPass must have BOTH required law tests — direct
        # representative equality AND the ctrl-wrapped Choi equality — running against
        # it. `passes_missing_laws` is the pure checker; test_m8_passes.jl applies it
        # to the runtime record of what actually ran. Here we (a) self-test the checker
        # for TEETH (mirrors "lint function catches a synthetic violation") and (b)
        # assert the shipped registry is populated with genuine `UnitaryPass` values.
        both = Set([:representative, :controlled])
        passes_missing_laws(reg, ran) =
            sort([n for n in reg if get(ran, n, Set{Symbol}()) != both])
        # TEETH: a pass with no laws, or only one, is flagged; both ⇒ clean.
        @test passes_missing_laws([:dummy], Dict{Symbol,Set{Symbol}}()) == [:dummy]
        @test passes_missing_laws([:a], Dict(:a => Set([:representative]))) == [:a]
        @test passes_missing_laws([:a], Dict(:a => Set([:controlled]))) == [:a]
        @test passes_missing_laws([:a], Dict(:a => both)) == Symbol[]
        # The shipped registry is real and every entry is a UnitaryPass (channel
        # passes are deliberately NOT registered — their law is Choi, not the phase
        # representative). The full runtime coverage assertion runs in test_m8_passes.jl.
        @test !isempty(Sturm.PASS_REGISTRY)
        @test all(p -> p isa Sturm.UnitaryPass, values(Sturm.PASS_REGISTRY))
    end

    @testset "M2 FFI-confinement lints" begin
        @testset "lint functions catch synthetic violations" begin
            @test find_ccalls("@ccall lib.f()") == ["ccall"]
            @test find_ccalls("no foreign calls here") == String[]
            @test find_single_from_mat("single_from_mat(state, t, mat)") == ["single_from_mat"]
            @test find_single_from_mat("named-gate path only") == String[]
        end

        @testset "ccall appears only under src/orkan/" begin
            src_dir = joinpath(REPO_ROOT, "src")
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    rel = relsrc(root, fname)
                    startswith(rel, "src/orkan/") && continue
                    text = read(joinpath(root, fname), String)
                    @test isempty(find_ccalls(text))
                end
            end
        end

        @testset "single_from_mat appears nowhere in src/" begin
            src_dir = joinpath(REPO_ROOT, "src")
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    text = read(joinpath(root, fname), String)
                    @test isempty(find_single_from_mat(text))
                end
            end
        end
    end

    @testset "M7 single-remap lint (§4.2-style single choke point for bit order)" begin
        @testset "lint function catches synthetic violations" begin
            @test find_role_indexing("circuit.input_wires[3]") == ["input_wires["]
            @test find_role_indexing("output_wires[β+1]") == ["output_wires["]
            @test find_role_indexing("Set(circuit.output_wires)") == String[]
        end

        @testset "register-vector indexing appears NOWHERE in src/" begin
            src_dir = joinpath(REPO_ROOT, "src")
            for (root, _dirs, files) in walkdir(src_dir)
                for fname in files
                    endswith(fname, ".jl") || continue
                    text = read(joinpath(root, fname), String)
                    @test isempty(find_role_indexing(text))
                end
            end
        end

        @testset "in ext/, register-vector indexing appears ONLY in _role_tables" begin
            extfile = joinpath(REPO_ROOT, "ext", "SturmBennettExt.jl")
            @test isfile(extfile)
            lines = readlines(extfile)
            s = findfirst(l -> occursin("function _role_tables", l), lines)
            @test s !== nothing
            e = s - 1 + findfirst(==("end"), @view lines[s:end])   # top-level `end` (col 0)
            hits = [i for i in eachindex(lines) if !isempty(find_role_indexing(lines[i]))]
            @test !isempty(hits)                     # non-vacuous: the remap really indexes
            @test all(i -> s ≤ i ≤ e, hits)          # ...and ONLY inside _role_tables
        end
    end

    include("test_prd_examples.jl")

    @testset "Kernel process values (M1)" begin
        include("test_kernel_u2.jl")
        include("test_kernel_perm.jl")
        include("test_kernel_ctrl.jl")
    end

    @testset "M2 — Orkan FFI + Ad + contexts + regions" begin
        include("test_m2_common.jl")
        include("test_orkan_ffi.jl")
        include("test_ad.jl")
        include("test_contexts.jl")
        include("test_regions.jl")
    end

    @testset "M3 — QBool, boundary casts, Choi harness" begin
        include("choi.jl")            # the Choi harness + channel-level boundary laws
        include("test_m3_qbool.jl")   # state/value-level + error-taxonomy laws
    end

    @testset "M4 — views, dual, the action family, teleportation" begin
        include("test_m4_views.jl")   # §3.3/§3.4/§7.1 laws (reuses the choi.jl above)
    end

    @testset "M5 — when: streaming control, guardrails, deferred teleport" begin
        include("test_m5_when.jl")    # §3.5/§3.4/§3.9/§7.1b laws (reuses the choi.jl above)
    end

    @testset "M6 — QInt, slices, two worlds, Pontryagin pins, QFT dual" begin
        include("test_m6_qint.jl")    # §3.3/§3.4/D2/D12 laws + strict-mode detector
    end

    @testset "M7 — Bennett bridge: oracle, accumulate, DJ/BV, control" begin
        include("test_m7_bennett.jl") # §3.4/§7.4/§7.5/D9/D14 laws (needs Bennett loaded)
    end

    @testset "M8 — ChannelDAG, certify, UnitaryBlock (parts 1–3)" begin
        include("test_m8_channel.jl") # §4.1/§4.1a/§4.2 laws: typed IR, structural cert, block ctrl
    end

    @testset "M8 — block execution, Eager tee-tracing, TR2 poison (part 4)" begin
        include("test_m8_when_materialize.jl")   # §1.4/§5/§8-TR2: exec seams, seal-as-witness, stream≡materialized
    end

    @testset "M8 — pass frameworks: channel + unitary, registry, sentinel (parts 5–6)" begin
        include("test_m8_passes.jl")   # §3 pass law: ChannelPass/UnitaryPass, PASS_REGISTRY, phase sentinel, within
    end

    @testset "M8 — i4ri classical control: tokens, cases, select, shots (part 7, DM/Eager)" begin
        include("test_m8_i4ri.jl")     # §3.6/§3.8 L-battery: Ruling-D tokens, instrument-sum cases, L5 phase form
    end

    @testset "M8 — i4ri classical control: TracingContext, materialize, defer (part 7, Tracing)" begin
        include("test_m8_tracing.jl")  # §2.4/§2.3/§13: MeasureN/CasesN, join-typing, stream≡materialized, defer/dead-record
    end

    @testset "F16/F15/F19 — context-parameterized handles, number-like contract, bicharacter" begin
        include("test_vanm_context_param.jl")  # bead Sturm.jl-vanm (representation-only refactor)
    end
end
