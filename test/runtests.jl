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
    relsrc(root, fname) -> String

`src/…`-relative path of a walked file, with `/` separators, for the
choke-point lints' allow-list comparison.
"""
function relsrc(root::AbstractString, fname::AbstractString)
    rp = relpath(joinpath(root, fname), REPO_ROOT)
    return replace(rp, '\\' => '/')
end

@testset "Sturm.jl boot lints" begin

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

    include("test_prd_examples.jl")

    @testset "Kernel process values (M1)" begin
        include("test_kernel_u2.jl")
        include("test_kernel_perm.jl")
        include("test_kernel_ctrl.jl")
    end
end
