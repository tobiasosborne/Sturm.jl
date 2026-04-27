using Test

# Bead Sturm.jl-la55 — Rule 11 lint.
#
# CLAUDE.md axiom 11: "All quantum code must be written using the four
# primitives. No imported gate matrices, no raw unitary arrays applied
# directly." The same logic extends to bare `apply_*!(ctx, wire, ...)` calls
# on a `WireID` in library code: these bypass the DSL surface (q.θ/.φ/⊻=),
# losing type safety, the global-phase audit (cf. ls8 / 3yz Y-vs-X bugs),
# and literate documentation. Library functions must wrap WireIDs in a
# QBool view and use operator syntax.
#
# This lint scans every .jl under src/library/ and asserts no line outside
# of a comment matches `apply_(ry|rz|cx|ccx)!\s*\(`. Permitted to appear in
# comments (where it documents the equivalent ccall).

const _RULE11_FORBIDDEN = r"\bapply_(ry|rz|cx|ccx)!\s*\("

function _strip_comment(line::AbstractString)
    # Strip everything from the first un-quoted `#` onwards. We don't have
    # full Julia parser here; the string-handling heuristic is good enough
    # because library code doesn't put `apply_*!(` inside string literals.
    i = findfirst('#', line)
    isnothing(i) ? line : line[1:i-1]
end

function _rule11_violations(file::AbstractString)
    violations = Tuple{Int, String}[]
    for (lineno, line) in enumerate(eachline(file))
        code = _strip_comment(line)
        if occursin(_RULE11_FORBIDDEN, code)
            push!(violations, (lineno, strip(line)))
        end
    end
    return violations
end

@testset "Rule 11 lint — no raw apply_*!(ctx, wire) in src/library/" begin
    libdir = joinpath(@__DIR__, "..", "src", "library")
    @assert isdir(libdir)
    found = Dict{String, Vector{Tuple{Int, String}}}()
    for (root, _, files) in walkdir(libdir)
        for f in files
            endswith(f, ".jl") || continue
            path = joinpath(root, f)
            v = _rule11_violations(path)
            isempty(v) || (found[relpath(path, libdir)] = v)
        end
    end
    if !isempty(found)
        @info "Rule 11 violations — wrap WireID in QBool and use q.θ/.φ/⊻= primitive syntax"
        for (file, lines) in found
            for (lineno, code) in lines
                @info "  $file:$lineno  $code"
            end
        end
    end
    @test isempty(found)
end
