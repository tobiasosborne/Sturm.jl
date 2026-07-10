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

    include("test_prd_examples.jl")
end
