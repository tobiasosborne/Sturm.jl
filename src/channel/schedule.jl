# Shared schedulers for Channel rendering.
#
# Lives between channel/draw.jl (defines `_draw_touches`) and
# channel/pixels.jl (consumes Level-A schedules) so the dependency
# direction is unambiguous and an include-order shuffle in src/Sturm.jl
# can't accidentally make a forward reference.
#
# Level-A (compact) is shared between the ASCII and PNG renderers and
# therefore lives here. Level-B is currently ASCII-only and stays in
# draw.jl. Bead Sturm.jl-gxpx.

"""ASAP schedule with Level-A occupation: each node reserves only the rows
it actually touches (target, control, when()-controls). Parallel gates on
disjoint wires share columns. Interior wire rows spanned by a vertical
connector are NOT blocked — the renderer handles potential overlap by
favouring whatever was painted first (single-qubit gates win over
connectors in centre pixels).

Used by both `to_ascii` (channel/draw.jl) and `to_pixels` (channel/pixels.jl).
"""
function _draw_schedule_compact(dag::AbstractVector, row_of::Dict{WireID,Int})
    W = maximum(values(row_of); init=-1) + 1
    next_free = zeros(Int, max(W, 0))
    schedule = Vector{Int}(undef, length(dag))
    for (i, node) in enumerate(dag)
        touched_rows = Int[]
        for w in _draw_touches(node)
            if haskey(row_of, w)
                push!(touched_rows, row_of[w])
            end
        end
        if isempty(touched_rows)
            schedule[i] = 0
            continue
        end
        col = 0
        for r in touched_rows
            col = max(col, next_free[r+1])
        end
        schedule[i] = col
        for r in touched_rows
            next_free[r+1] = col + 1
        end
    end
    n_cols = isempty(schedule) ? 0 : maximum(next_free)
    return schedule, n_cols
end
