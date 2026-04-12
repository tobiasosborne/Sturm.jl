"""
    to_ascii(ch::Channel; unicode=true, color=false) -> String

Render a `Channel` as a terminal circuit diagram.

The algorithm is a five-phase pipeline adapted from the consensus of
Qiskit `TextDrawer`, Cirq `TextDiagramDrawer`, and Stim `timeline_ascii`:

  1. **Collect wires** in first-appearance order (inputs fixed first).
  2. **Schedule columns** via ASAP with Level-B occupation: each node
     reserves the contiguous row range `[min_row..max_row]` across all
     its participating wires (target, own control, `when()`-controls).
  3. **Compute column widths** from each node's display glyph.
  4. **Rasterise** into a `Matrix{Char}` using Level-A drawing:
     endpoint glyphs on participating rows, `│` in gap rows, `┼`
     crossing interior wire rows. Because Phase 2 reserved the full
     range, interior cells are guaranteed free for crossings.
  5. **Emit** as a `String` with left-margin wire labels.

The separation of *Level-B scheduling* from *Level-A drawing* is the
load-bearing invariant: the scheduler reserves contiguous ranges so
crossings can be drawn without compositing against gate glyphs.

Keyword arguments:
- `unicode=true`: use Unicode box-drawing. Set to `false` for pure ASCII.
- `color=false`: emit ANSI color escapes. Enabled automatically when
  `Base.show` is called on a color-capable IO.

See also: `Base.show(::IO, ::MIME"text/plain", ::Channel)` which wraps this.
"""
function to_ascii(ch::Channel; unicode::Bool=true, color::Bool=false)
    isempty(ch.dag) && isempty(ch.input_wires) && isempty(ch.output_wires) && return ""

    row_of, wires = _draw_collect_wires(ch)
    schedule, n_cols = _draw_schedule(ch.dag, row_of)
    col_widths = _draw_col_widths(ch.dag, schedule, n_cols)
    col_offsets = _draw_col_offsets(col_widths)

    # Classical bits are rendered below the quantum wires. Each ObserveNode
    # produces one classical wire identified by its result_id. The bit row
    # starts at the Observe's column and continues to the right edge.
    bit_rows = _collect_bit_rows(ch.dag)   # result_id → row index (among bits only)

    W = length(wires)                       # number of quantum wires
    B = length(bit_rows)                    # number of classical bits
    # Row layout: quantum wires at 2i (i=0..W-1), gaps at 2i+1. Then optional
    # classical separator, then bits each on a single line with a gap above.
    # Total char-rows:
    #   Quantum region: 2W - 1  (wire, gap, wire, gap, ..., wire)
    #   If any bits: + 1 separator gap + B  (each bit on one line, gap above)
    n_q_rows = W == 0 ? 0 : 2W - 1
    n_c_rows = B == 0 ? 0 : (1 + B)
    total_rows = n_q_rows + n_c_rows
    total_cols = isempty(col_offsets) ? 0 : col_offsets[end]

    grid = fill(' ', total_rows, total_cols)
    styles = fill(_STYLE_PLAIN, total_rows, total_cols)  # for colour overlay

    # Paint default wire characters first (horizontal rules on every wire row).
    wire_char = unicode ? '─' : '-'
    for i in 0:W-1
        r = 2i
        for c in 1:total_cols
            grid[r+1, c] = wire_char
            styles[r+1, c] = _STYLE_WIRE
        end
    end
    # Classical bit wires default to blank until the Observe fires; painted below.

    # Bit-row absolute row indices (in the grid).
    # Quantum wires occupy rows 1..n_q_rows; separator at n_q_rows+1; bits at
    # rows n_q_rows+2, n_q_rows+3, ...
    bit_row_abs = Dict{UInt32,Int}()
    for (rid, bidx) in bit_rows
        bit_row_abs[rid] = n_q_rows + 2 + bidx
    end

    # Paint classical wires BEFORE nodes so measurement drains overlay correctly
    # with ╬ crossings. Each bit's wire starts at the Observe column centre + 1.
    _paint_classical_wires!(grid, styles, ch.dag, schedule, col_offsets,
                            bit_row_abs, total_cols, unicode)

    # Phase 4: rasterise each scheduled node.
    for (i, node) in enumerate(ch.dag)
        col = schedule[i]
        _draw_node!(grid, styles, node, col, col_offsets, col_widths,
                    row_of, bit_row_abs, n_q_rows, unicode)
    end

    # Phase 5: emit with left-margin labels.
    return _draw_emit(grid, styles, wires, bit_rows, n_q_rows, n_c_rows, color)
end

# ── Phase 1 ───────────────────────────────────────────────────────────────────

"""Collect wires in first-appearance order. Inputs fixed at the top."""
function _draw_collect_wires(ch::Channel)
    row_of = Dict{WireID,Int}()
    wires = WireID[]
    for w in ch.input_wires
        if !haskey(row_of, w)
            row_of[w] = length(wires)
            push!(wires, w)
        end
    end
    for node in ch.dag
        for w in _draw_touches(node)
            if w != _ZERO_WIRE && !haskey(row_of, w)
                row_of[w] = length(wires)
                push!(wires, w)
            end
        end
    end
    for w in ch.output_wires
        if !haskey(row_of, w)
            row_of[w] = length(wires)
            push!(wires, w)
        end
    end
    return row_of, wires
end

"""Return all wires a node touches (including when()-controls)."""
function _draw_touches(n::RyNode);     _draw_touched_tuple(n.wire, n); end
function _draw_touches(n::RzNode);     _draw_touched_tuple(n.wire, n); end
function _draw_touches(n::PrepNode);   _draw_touched_tuple(n.wire, n); end
function _draw_touches(n::ObserveNode); (n.wire,); end
function _draw_touches(n::DiscardNode); (n.wire,); end
function _draw_touches(n::CXNode)
    cs = get_controls(n)
    return (n.control, n.target, cs...)
end

@inline function _draw_touched_tuple(w::WireID, n)
    cs = get_controls(n)
    return (w, cs...)
end

# ── Phase 2 ───────────────────────────────────────────────────────────────────

"""ASAP schedule with Level-B (contiguous row range) occupation.

Returns `(schedule::Vector{Int}, n_cols::Int)` where `schedule[i]` is the
0-indexed column assigned to `ch.dag[i]`.
"""
function _draw_schedule(dag::AbstractVector, row_of::Dict{WireID,Int})
    W = maximum(values(row_of); init=-1) + 1
    next_free = zeros(Int, max(W, 0))
    schedule = Vector{Int}(undef, length(dag))
    for (i, node) in enumerate(dag)
        rows = _row_range(node, row_of)
        if isempty(rows)
            schedule[i] = 0
            continue
        end
        col = 0
        for r in rows
            nf = next_free[r+1]
            col = max(col, nf)
        end
        schedule[i] = col
        for r in rows
            next_free[r+1] = col + 1
        end
    end
    n_cols = isempty(schedule) ? 0 : maximum(next_free)
    return schedule, n_cols
end

"""Contiguous row range occupied by a node (Level-B)."""
function _row_range(node, row_of::Dict{WireID,Int})
    wires_tuple = _draw_touches(node)
    rows = Int[]
    for w in wires_tuple
        if haskey(row_of, w)
            push!(rows, row_of[w])
        end
    end
    isempty(rows) && return 0:-1
    return minimum(rows):maximum(rows)
end

# ── Phase 3 ───────────────────────────────────────────────────────────────────

"""Column width = max over nodes in that column of glyph-width + 2 padding."""
function _draw_col_widths(dag::AbstractVector, schedule::Vector{Int}, n_cols::Int)
    col_widths = fill(3, n_cols)  # minimum width 3 (─G─)
    for (i, node) in enumerate(dag)
        col = schedule[i]
        w = _glyph_width(node) + 2   # 1 pad on each side
        if col + 1 <= n_cols
            col_widths[col+1] = max(col_widths[col+1], w)
        end
    end
    return col_widths
end

"""Prefix-sum of column widths → starting char-column of each column."""
function _draw_col_offsets(col_widths::Vector{Int})
    offs = Vector{Int}(undef, length(col_widths) + 1)
    offs[1] = 0
    for i in eachindex(col_widths)
        offs[i+1] = offs[i] + col_widths[i]
    end
    return offs
end

"""Display width of a node's primary glyph (not including padding).
Counts characters, not bytes — `π` is one display column but two UTF-8 bytes."""
function _glyph_width(n::RyNode); length(collect(_gate_label(n))); end
function _glyph_width(n::RzNode); length(collect(_gate_label(n))); end
function _glyph_width(n::PrepNode); length(collect(_prep_label(n.p))); end
function _glyph_width(::CXNode);   1; end   # control/target dot is 1 char
function _glyph_width(::ObserveNode); 3; end # "┤M├"
function _glyph_width(::DiscardNode); 1; end

# ── Phase 4: node rendering ──────────────────────────────────────────────────

"""Dispatch rendering based on node type."""
function _draw_node!(grid, styles, node::RyNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    _draw_singleton_gate!(grid, styles, node, _gate_label(node),
                          node.wire, col, offs, widths, row_of, unicode, _STYLE_GATE)
end

function _draw_node!(grid, styles, node::RzNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    _draw_singleton_gate!(grid, styles, node, _gate_label(node),
                          node.wire, col, offs, widths, row_of, unicode, _STYLE_GATE)
end

function _draw_node!(grid, styles, node::PrepNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    _draw_singleton_gate!(grid, styles, node, _prep_label(node.p),
                          node.wire, col, offs, widths, row_of, unicode, _STYLE_PREP)
end

function _draw_node!(grid, styles, node::CXNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    ctrl_char = unicode ? '●' : '@'
    tgt_char  = unicode ? '⊕' : 'X'
    ctrl_row = row_of[node.control]
    tgt_row  = row_of[node.target]
    extra_ctrls = Int[row_of[w] for w in get_controls(node)]
    all_ctrl_rows = vcat([ctrl_row], extra_ctrls)

    # Column centre char position (1-based)
    c0 = offs[col+1] + 1
    w  = widths[col+1]
    x  = c0 + (w ÷ 2)

    # Collect all participating rows
    rows = sort(vcat(all_ctrl_rows, tgt_row))
    rmin, rmax = first(rows), last(rows)

    # Controls: ● at each control row. Target: ⊕.
    for r in all_ctrl_rows
        grid[2r + 1, x] = ctrl_char
        styles[2r + 1, x] = _STYLE_CX
    end
    grid[2tgt_row + 1, x] = tgt_char
    styles[2tgt_row + 1, x] = _STYLE_CX

    # Vertical connects rmin..rmax. All participating rows (controls and
    # target) already hold glyphs — skip them in the interior-row pass so the
    # `┼` doesn't overwrite `●`/`⊕`.
    skip = Set{Int}(all_ctrl_rows)
    push!(skip, tgt_row)
    _paint_vertical!(grid, styles, rmin, rmax, x, unicode; skip_rows=skip)
end

function _draw_node!(grid, styles, node::ObserveNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    row = row_of[node.wire]
    c0 = offs[col+1] + 1
    w  = widths[col+1]
    x  = c0 + (w ÷ 2)
    # ┤M├ spanning 3 cells centred on x
    if unicode
        grid[2row + 1, x - 1] = '┤'
        grid[2row + 1, x    ] = 'M'
        grid[2row + 1, x + 1] = '├'
    else
        grid[2row + 1, x - 1] = '['
        grid[2row + 1, x    ] = 'M'
        grid[2row + 1, x + 1] = ']'
    end
    styles[2row + 1, x - 1] = _STYLE_MEAS
    styles[2row + 1, x    ] = _STYLE_MEAS
    styles[2row + 1, x + 1] = _STYLE_MEAS
    # Drain from quantum wire down to the classical wire
    if haskey(bit_rows, node.result_id)
        bit_r = bit_rows[node.result_id]
        _paint_meas_drain!(grid, styles, 2row + 1, bit_r, x, n_q_rows, unicode)
    end
end

function _draw_node!(grid, styles, node::DiscardNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    row = row_of[node.wire]
    c0 = offs[col+1] + 1
    w  = widths[col+1]
    x  = c0 + (w ÷ 2)
    grid[2row + 1, x] = unicode ? '▷' : '|'
    styles[2row + 1, x] = _STYLE_DISCARD
end

function _draw_node!(grid, styles, node::CasesNode, col, offs, widths,
                     row_of, bit_rows, n_q_rows, unicode)
    # v1: emit a labelled placeholder glyph. Full recursive rendering of
    # sub-branches is a v2 feature (see Sturm.jl-11a follow-up).
    c0 = offs[col+1] + 1
    label = "c#$(node.condition_id)?"
    chars = collect(label)
    n = min(length(chars), widths[col+1])
    for i in 1:n
        grid[1, c0 + i - 1] = chars[i]
        styles[1, c0 + i - 1] = _STYLE_CASES
    end
end

"""Single-qubit gate (including when()-controls): draw gate glyph on target
row and ● on each control row, connected by a vertical."""
function _draw_singleton_gate!(grid, styles, node, label::String, wire::WireID,
                                col, offs, widths, row_of, unicode, gate_style)
    target_row = row_of[wire]
    extra_ctrls = Int[row_of[w] for w in get_controls(node)]

    c0 = offs[col+1] + 1
    w  = widths[col+1]
    # Centre the label inside the column. Use char iteration (strings are
    # byte-indexed in Julia; π is 2 bytes but 1 display column).
    chars = collect(label)
    lbl_n = length(chars)
    lbl_start = c0 + ((w - lbl_n) ÷ 2)

    for i in 1:lbl_n
        grid[2target_row + 1, lbl_start + i - 1] = chars[i]
        styles[2target_row + 1, lbl_start + i - 1] = gate_style
    end

    if !isempty(extra_ctrls)
        # Vertical connector spans {extra_ctrls..., target_row}
        all_rows = vcat(extra_ctrls, target_row)
        rmin, rmax = minimum(all_rows), maximum(all_rows)
        x = c0 + (w ÷ 2)
        ctrl_char = unicode ? '●' : '@'
        for r in extra_ctrls
            grid[2r + 1, x] = ctrl_char
            styles[2r + 1, x] = _STYLE_CX
        end
        # Skip control rows and target row so the vertical's `┼` doesn't
        # clobber the control dots or the centre glyph of the gate label.
        skip = Set{Int}(extra_ctrls)
        push!(skip, target_row)
        _paint_vertical!(grid, styles, rmin, rmax, x, unicode; skip_rows=skip)
    end
end

# ── Vertical-line painter ────────────────────────────────────────────────────

"""Paint `│` in gap rows and `┼` in interior wire rows between `rmin` and `rmax`
at character column `x`. Rows listed in `skip_rows` already hold glyphs (gate
label, control dot, target dot) and are not overwritten — the vertical line
simply connects through them."""
function _paint_vertical!(grid, styles, rmin::Int, rmax::Int, x::Int, unicode::Bool;
                           skip_rows=())
    rmin == rmax && return
    vbar = unicode ? '│' : '|'
    cross = unicode ? '┼' : '+'
    # Gap rows between adjacent wires: grid row 2k+2 for k in [rmin, rmax-1]
    for k in rmin:rmax-1
        grid[2k + 2, x] = vbar
        styles[2k + 2, x] = _STYLE_CX
    end
    # Interior wire rows: grid row 2k+1 for k in (rmin, rmax), skipping rows
    # that already contain gate glyphs.
    for k in (rmin+1):(rmax-1)
        k in skip_rows && continue
        grid[2k + 1, x] = cross
        styles[2k + 1, x] = _STYLE_CX
    end
end

"""Paint the measurement drain: a double vertical ║ from the quantum wire
(row `qr`) down to the classical bit row (`br`), with ╩ landing on the bit
line. Crossings: quantum wire → ╫ (double-through-single), classical wire →
╬ (double-through-double), gap rows → ║."""
function _paint_meas_drain!(grid, styles, qr::Int, br::Int, x::Int,
                             n_q_rows::Int, unicode::Bool)
    sep     = unicode ? '║' : ':'
    q_cross = unicode ? '╫' : '+'
    c_cross = unicode ? '╬' : '#'
    land    = unicode ? '╩' : '^'
    cwire = unicode ? '═' : '='
    for r in (qr+1):(br-1)
        cur = grid[r, x]
        if r <= n_q_rows && isodd(r)
            grid[r, x] = q_cross         # drain crossing a quantum wire row ─ → ╫
        elseif cur == cwire              # drain crossing an active classical wire ═ → ╬
            grid[r, x] = c_cross
        else
            grid[r, x] = sep             # blank / gap row → ║
        end
        styles[r, x] = _STYLE_MEAS
    end
    grid[br, x] = land
    styles[br, x] = _STYLE_MEAS
end

# ── Classical wire painting ──────────────────────────────────────────────────

"""Paint ═ on each classical-bit row from the Observe's column rightward."""
function _paint_classical_wires!(grid, styles, dag, schedule, offs, bit_rows,
                                  total_cols, unicode)
    cwire = unicode ? '═' : '='
    for (i, node) in enumerate(dag)
        node isa ObserveNode || continue
        haskey(bit_rows, node.result_id) || continue
        br = bit_rows[node.result_id]
        col = schedule[i]
        c0 = offs[col+1] + 1
        w  = offs[col+2] - offs[col+1]
        x  = c0 + (w ÷ 2)
        # Before the Observe column: blank. At the Observe column: ╩ at x.
        # After: ═ everywhere on this row.
        for c in (x+1):total_cols
            grid[br, c] = cwire
            styles[br, c] = _STYLE_CWIRE
        end
        # (╩ glyph was already placed by _paint_meas_drain)
    end
end

# ── Phase 5: emit ────────────────────────────────────────────────────────────

function _draw_emit(grid, styles, wires::Vector{WireID},
                    bit_rows::Dict{UInt32,Int}, n_q_rows::Int, n_c_rows::Int,
                    color::Bool)
    W = length(wires)
    B = length(bit_rows)
    # Labels: "qN: " / "cN: "
    max_q_label = W == 0 ? 0 : length("q$(W-1)")
    max_c_label = B == 0 ? 0 : length("c$(B-1)")
    label_w = max(max_q_label, max_c_label) + 2   # +2 for ": "

    buf = IOBuffer()
    nrows, ncols = size(grid)

    # Invert bit_rows for label lookup: bit row index (0..B-1) → result_id
    bit_idx_to_rid = Vector{UInt32}(undef, B)
    for (rid, idx) in bit_rows
        bit_idx_to_rid[idx + 1] = rid
    end

    for r in 1:nrows
        # Determine what this row is (quantum wire, gap, classical sep, classical wire)
        is_q_wire_row = r <= n_q_rows && isodd(r)
        is_q_gap_row  = r <= n_q_rows && iseven(r)
        is_c_sep_row  = n_c_rows > 0 && r == n_q_rows + 1
        is_c_wire_row = r > n_q_rows + 1 && r <= nrows

        # Left margin label
        if is_q_wire_row
            qi = (r - 1) ÷ 2  # wire index 0..W-1
            lbl = "q$(qi):"
            print(buf, rpad(lbl, label_w))
        elseif is_c_wire_row
            bi = r - n_q_rows - 1 - 1   # 0-based bit index
            lbl = "c$(bi):"
            print(buf, rpad(lbl, label_w))
        else
            print(buf, repeat(' ', label_w))
        end

        # Grid contents
        if color
            _emit_row_colored!(buf, grid, styles, r, ncols)
        else
            for c in 1:ncols
                print(buf, grid[r, c])
            end
        end
        print(buf, '\n')
    end

    # Strip trailing blank lines and per-line trailing whitespace
    raw = String(take!(buf))
    lines = split(raw, '\n')
    # Trim trailing whitespace from each line but preserve internal structure
    trimmed = String[String(rstrip(l)) for l in lines]
    # Pad each line back to the max char-width so output is rectangular.
    # `length` on a String counts characters, not bytes, in Julia.
    maxw = maximum(length, trimmed; init=0)
    padded = String[rpad(l, maxw) for l in trimmed]
    # Drop trailing empty lines only (from the final \n)
    while !isempty(padded) && isempty(strip(padded[end]))
        pop!(padded)
    end
    return join(padded, '\n')
end

# ── Colour overlay ───────────────────────────────────────────────────────────

# Style tags used in the styles matrix. _STYLE_PLAIN = no color.
const _STYLE_PLAIN   = UInt8(0)
const _STYLE_WIRE    = UInt8(1)
const _STYLE_GATE    = UInt8(2)
const _STYLE_CX      = UInt8(3)
const _STYLE_MEAS    = UInt8(4)
const _STYLE_DISCARD = UInt8(5)
const _STYLE_PREP    = UInt8(6)
const _STYLE_CWIRE   = UInt8(7)
const _STYLE_CASES   = UInt8(8)

function _style_color(s::UInt8)
    s == _STYLE_GATE    && return :green
    s == _STYLE_CX      && return :yellow
    s == _STYLE_MEAS    && return :red
    s == _STYLE_DISCARD && return :magenta
    s == _STYLE_PREP    && return :cyan
    s == _STYLE_CWIRE   && return :light_black
    s == _STYLE_CASES   && return :magenta
    return :normal
end

function _emit_row_colored!(buf, grid, styles, r::Int, ncols::Int)
    # Run-length group consecutive cells with the same style to minimise escapes.
    c = 1
    while c <= ncols
        s = styles[r, c]
        c2 = c
        while c2 <= ncols && styles[r, c2] == s
            c2 += 1
        end
        seg = String(grid[r, c:c2-1])
        if s == _STYLE_PLAIN || s == _STYLE_WIRE
            print(buf, seg)
        else
            printstyled(IOContext(buf, :color => true), seg; color=_style_color(s))
        end
        c = c2
    end
end

# ── Gate label formatting ────────────────────────────────────────────────────

"""Pattern-matched or generic label for a single rotation gate."""
function _gate_label(n::RzNode)
    θ = n.angle
    _isclose(θ,  π)     && return "Z"
    _isclose(θ,  π/2)   && return "S"
    _isclose(θ, -π/2)   && return "S†"
    _isclose(θ,  π/4)   && return "T"
    _isclose(θ, -π/4)   && return "T†"
    return "Rz(" * _fmt_angle(θ) * ")"
end

function _gate_label(n::RyNode)
    θ = n.angle
    _isclose(θ,  π) && return "X"
    _isclose(θ, -π) && return "X"
    return "Ry(" * _fmt_angle(θ) * ")"
end

"""Prep label based on p."""
function _prep_label(p::Float64)
    _isclose(p, 0.0) && return "|0⟩"
    _isclose(p, 1.0) && return "|1⟩"
    _isclose(p, 0.5) && return "|+⟩"
    return "P(" * _fmt_num(p) * ")"
end

@inline _isclose(a, b; atol::Float64=1e-10) = abs(a - b) <= atol

"""Pretty-print an angle: recognise common π-fractions, else 3-sig-fig decimal."""
function _fmt_angle(θ::Real)
    θ == 0 && return "0"
    # Try common π fractions
    for (k, sym) in ((1, "π"), (2, "π/2"), (3, "π/3"), (4, "π/4"),
                      (6, "π/6"), (8, "π/8"))
        _isclose(θ,  π/k) && return sym
        _isclose(θ, -π/k) && return "-" * sym
    end
    # Integer π multiples
    for m in 2:6
        _isclose(θ,  m*π) && return "$(m)π"
        _isclose(θ, -m*π) && return "-$(m)π"
    end
    return _fmt_num(θ)
end

function _fmt_num(x::Real)
    # 3-significant-figure format, trimming trailing zeros
    s = string(round(x; sigdigits=3))
    return s
end

# ── Classical-bit accounting ─────────────────────────────────────────────────

"""Map each ObserveNode.result_id to a sequential bit row index (0-based)."""
function _collect_bit_rows(dag)
    m = Dict{UInt32,Int}()
    idx = 0
    for node in dag
        if node isa ObserveNode && !haskey(m, node.result_id)
            m[node.result_id] = idx
            idx += 1
        end
    end
    return m
end

# ── Base.show integration ────────────────────────────────────────────────────

"""
    Base.show(io::IO, ::MIME"text/plain", ch::Channel)

Render a Channel as a terminal-friendly ASCII/Unicode circuit diagram.

Respects IOContext keys:
- `:color` — ANSI color output (set automatically by the REPL on color terminals)
- `:unicode` — defaults to `true`; set to `false` for pure ASCII
"""
function Base.show(io::IO, ::MIME"text/plain", ch::Channel)
    color = get(io, :color, false)::Bool
    unicode = get(io, :unicode, true)::Bool
    print(io, to_ascii(ch; unicode=unicode, color=color))
end
