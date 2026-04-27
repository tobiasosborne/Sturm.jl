using Test

# Bead Sturm.jl-oddg — docs/physics/ link integrity.
#
# CLAUDE.md Rule 4 (two-tier docs policy) requires every `docs/physics/<…>.md`
# path referenced from src/ to resolve to a real file. This catches the
# common drift where a docstring is updated to cite a new distillation that
# never gets written, or a distillation is renamed without sweeping
# references. Companion lint to bead Sturm.jl-la55's Rule 11 lint.

const _DOCS_PHYSICS_REF = r"docs/physics/[A-Za-z0-9_./-]+\.md"

function _docs_physics_refs(file::AbstractString)
    refs = Tuple{Int, String}[]
    for (lineno, line) in enumerate(eachline(file))
        for m in eachmatch(_DOCS_PHYSICS_REF, line)
            push!(refs, (lineno, m.match))
        end
    end
    return refs
end

@testset "docs/physics/ references resolve (bead oddg)" begin
    srcdir = joinpath(@__DIR__, "..", "src")
    physics_dir = joinpath(@__DIR__, "..", "docs", "physics")
    @assert isdir(srcdir)
    @assert isdir(physics_dir)
    missing_refs = Tuple{String, Int, String}[]   # (src_file, lineno, ref)
    for (root, _, files) in walkdir(srcdir)
        for f in files
            endswith(f, ".jl") || continue
            path = joinpath(root, f)
            for (lineno, ref) in _docs_physics_refs(path)
                # ref is e.g. "docs/physics/nielsen_chuang_5.2.md"
                target = joinpath(@__DIR__, "..", ref)
                if !isfile(target)
                    push!(missing_refs, (relpath(path, srcdir), lineno, ref))
                end
            end
        end
    end
    if !isempty(missing_refs)
        @info "Missing docs/physics/ distillations referenced from src/:"
        for (file, lineno, ref) in missing_refs
            @info "  src/$file:$lineno  → $ref"
        end
    end
    @test isempty(missing_refs)
end
