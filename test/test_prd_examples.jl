# SPDX-License-Identifier: AGPL-3.0-only
#
# PRD doctest lint (CLAUDE.md convention 9 / Sturm-v2-IMPLEMENTATION-PLAN.md
# M0). `Sturm-PRD-v2.md` is normative and its §7 examples are the surface
# vocabulary's own acceptance test: every fenced ```julia block must at
# least PARSE and LOWER. Review r6's B1 bug was a lowering-stage error
# (an invalid assignment location) that `Meta.parse` alone did not catch —
# `Meta.parse` only validates syntax; `Meta.lower` additionally validates
# things like assignment targets and macro resolution. Hence both stages
# are checked here, not just one.
#
# Only fences tagged exactly ```julia are linted. The PRD deliberately
# shows invalid-Julia traps (e.g. `dual(q) ⊻= r` as a bare call-LHS
# op-assign, D11) in prose or differently-tagged fences — those must NOT
# be linted as if they were normative code.
#
# This file defines no quantum code and is included from `runtests.jl`.

using Test

const PRD_PATH = joinpath(@__DIR__, "..", "Sturm-PRD-v2.md")

"""
    PRDLintSandbox

Execution-free sandbox module for macro resolution during `Meta.lower`.
The PRD's §7 examples use `@cases` (D3 classical branching) and prose
elsewhere mentions `@context` (§3.9 regions); neither surface macro
exists yet in milestone 0 (no quantum code). These stubs swallow their
arguments and expand to `nothing` — enough for lowering to resolve the
macro call without executing anything quantum. Nothing is exported from
this module and it must never be `using`'d outside this lint.
"""
module PRDLintSandbox
    macro cases(args...)
        return nothing
    end
    macro context(args...)
        return nothing
    end
end

"""
    extract_julia_blocks(path) -> Vector{NamedTuple{(:line, :code)}}

Scan a Markdown file for fenced code blocks whose opening fence is
EXACTLY ` ```julia ` (stripped of surrounding whitespace) and return each
block's source text together with the 1-based line number of its opening
fence, for error reporting. Deliberately ignores every other fence tag
(bare ` ``` `, ` ```julia-repl `, etc.) — the PRD uses those for invalid-
Julia traps that must not be linted as normative code.
"""
function extract_julia_blocks(path::AbstractString)
    text = read(path, String)
    lines = split(text, '\n'; keepempty=true)
    blocks = NamedTuple{(:line, :code), Tuple{Int, String}}[]

    in_block = false
    buf = String[]
    startline = 0
    for (i, line) in enumerate(lines)
        tag = strip(line)
        if !in_block && tag == "```julia"
            in_block = true
            buf = String[]
            startline = i
        elseif in_block && tag == "```"
            in_block = false
            push!(blocks, (line = startline, code = join(buf, '\n')))
        elseif in_block
            push!(buf, line)
        end
    end
    # FAIL FAST: an opening ```julia fence with no matching close means the
    # extraction itself is broken (or the PRD is malformed) — not a silent
    # empty-block skip.
    in_block && error("unterminated ```julia fence starting at line $startline in $path")

    return blocks
end

"""
    lowers_cleanly(code) -> (ok::Bool, detail::String)

Run `code` through `Meta.parseall` then `Meta.lower` (against
`PRDLintSandbox`, never executing anything) and report whether both
stages succeeded. `Meta.parse`/`Meta.parseall` throw `Base.Meta.ParseError`
on invalid syntax; `Meta.lower` does not throw for most lowering errors —
it returns an `Expr(:error, msg)` (possibly nested inside a `:toplevel`
block) — so both failure shapes are checked explicitly.
"""
function lowers_cleanly(code::AbstractString)
    local ex
    try
        ex = Meta.parseall(code)
    catch err
        return false, "parse error: $(sprint(showerror, err))"
    end

    local lowered
    try
        lowered = Meta.lower(PRDLintSandbox, ex)
    catch err
        return false, "lowering threw: $(sprint(showerror, err))"
    end

    errors = Expr[]
    _collect_lower_errors!(errors, lowered)
    isempty(errors) && return true, ""
    return false, "lowering error: " * join((e.args[1] for e in errors), "; ")
end

# `Meta.lower` returns an `Expr(:error, msg)` in place of the failing
# statement rather than throwing — walk the (possibly :toplevel) result
# to find every such node, so a failure buried in statement 3 of 5 is
# still reported instead of silently passing because the *outer* head
# isn't `:error`.
function _collect_lower_errors!(errors::Vector{Expr}, ex)
    if ex isa Expr
        if ex.head === :error
            push!(errors, ex)
        else
            for a in ex.args
                _collect_lower_errors!(errors, a)
            end
        end
    end
    return errors
end

@testset "PRD doctest lint" begin
    @test isfile(PRD_PATH)
    blocks = extract_julia_blocks(PRD_PATH)

    # Session 94 recorded 11 ```julia blocks in Sturm-PRD-v2.md at the
    # r6 prototype stage; session 98 (w5rw, Ruling D) added the §3.6
    # `@cases Bool(m)` classical-branching example, bringing the count to
    # 12. Pin the count so a silently-truncated extractor (or a PRD edit
    # that drops an example) is caught even if every remaining block still
    # happens to lower cleanly.
    @test length(blocks) == 12

    for b in blocks
        parts = split(strip(b.code), '\n'; keepempty = false)
        firstline = isempty(parts) ? "" : first(parts)
        label = "line $(b.line): $(firstline)"
        @testset "$label" begin
            ok, detail = lowers_cleanly(b.code)
            @test ok
            ok || @info "PRD block failed to lower" line = b.line detail = detail code = b.code
        end
    end
end
