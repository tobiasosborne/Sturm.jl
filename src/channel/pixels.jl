"""
Pixel-art circuit rendering: PNG output at 1 pixel per wire.

Target: massive circuits (~1000 wires) where ASCII is hopeless and LaTeX is too
slow. Each wire is a single pixel tall. Each DAG column is `column_width` pixels
wide (default 3: `shadow | gate | shadow`). Controls render in the wire's own
colour; targets render in its complement. Colours follow Faber Birren's
industrial safety palette (see docs/birren-colour-schemes.md / ../generalrelativity/).

Pipeline:
  Channel → collect wires (first-appearance) → ASAP schedule (Level-B)
         → allocate H×W pixel buffer → fill wires + bg
         → paint each node into its 3-px column
         → save PNG via PNGFiles.save

Scheduling is shared with the ASCII drawer: `_draw_collect_wires` and
`_draw_schedule` from `src/channel/draw.jl` are reused directly. The pixel
renderer differs only in Phases 3–5 (fixed column width; pixel buffer; no
Unicode labels).

See `to_pixels`, `to_png`.
"""

using PNGFiles
using ColorTypes: RGB, N0f8

# ── Birren palette ───────────────────────────────────────────────────────────

"""Parse a `#RRGGBB` hex string into `RGB{N0f8}`."""
function _hex(s::String)
    s = replace(s, "#" => "")
    r = parse(UInt8, s[1:2]; base=16)
    g = parse(UInt8, s[3:4]; base=16)
    b = parse(UInt8, s[5:6]; base=16)
    RGB{N0f8}(reinterpret(N0f8, r), reinterpret(N0f8, g), reinterpret(N0f8, b))
end

"""Complement of an RGB colour, per pixel: `(255-r, 255-g, 255-b)`.
Used for CNOT target rendering when the wire colour is known."""
function _complement(c::RGB{N0f8})
    r = 0xff - reinterpret(UInt8, c.r)
    g = 0xff - reinterpret(UInt8, c.g)
    b = 0xff - reinterpret(UInt8, c.b)
    RGB{N0f8}(reinterpret(N0f8, r), reinterpret(N0f8, g), reinterpret(N0f8, b))
end

"""
    PixelScheme

Colour palette for pixel-art circuit rendering. All fields are `RGB{N0f8}`.

Semantic roles (Birren industrial safety):
- `bg`: image background
- `shadow`: overpass-line halo pixels flanking each gate centre (usually = bg)
- `q_wire`: quantum wire colour (default seafoam — "primary reading target")
- `c_wire`: classical wire colour (default orange — "caution")
- `control`: control-dot colour at its centre pixel (default = q_wire)
- `target`: CNOT target colour (default = complement of q_wire)
- `gate`: single-qubit rotation gates (Ry, Rz) — default yellow
- `prep`: preparation marker (default cyan/seafoam variant)
- `measurement`: measurement / type boundary — default red
- `discard`: partial trace — default gray
- `connector`: vertical line crossing uninvolved wires — default gate colour
"""
struct PixelScheme
    bg::RGB{N0f8}
    shadow::RGB{N0f8}
    q_wire::RGB{N0f8}
    c_wire::RGB{N0f8}
    control::RGB{N0f8}
    target::RGB{N0f8}
    gate::RGB{N0f8}
    prep::RGB{N0f8}
    measurement::RGB{N0f8}
    discard::RGB{N0f8}
    connector::RGB{N0f8}
end

"""Birren industrial dark palette — for light-on-dark circuit rendering.
Reference: Birren 1963 *Color for Interiors*; Mathews 2025 "Why So Many
Control Rooms Were Seafoam Green"."""
function birren_dark_scheme()
    bg       = _hex("#1E2226")
    shadow   = bg                      # clean hole in the wire
    q_wire   = _hex("#82B896")         # seafoam — primary reading target
    c_wire   = _hex("#D4785A")         # orange — caution / data channel
    control  = q_wire                  # per spec: control = wire colour
    target   = _complement(q_wire)     # per spec: target = complement of wire
    gate     = _hex("#E2C46C")         # yellow — mild caution (string/literal)
    prep     = _hex("#6A9EC0")         # blue — informational
    measure  = _hex("#C4392F")         # red — type boundary (emergency stop)
    discard  = _hex("#8C8C84")         # gray — structural recede
    connector = gate                   # same visual family as the active gate
    PixelScheme(bg, shadow, q_wire, c_wire, control, target,
                gate, prep, measure, discard, connector)
end

"""Birren industrial light palette — for dark-on-light circuit rendering."""
function birren_light_scheme()
    bg       = _hex("#F4F1E8")         # beige — Birren for sunless rooms
    shadow   = bg
    q_wire   = _hex("#3D7A55")         # safety green
    c_wire   = _hex("#B55A38")         # muted orange
    control  = q_wire
    target   = _complement(q_wire)
    gate     = _hex("#B09830")         # darker yellow for contrast on beige
    prep     = _hex("#3A6E8E")         # blue
    measure  = _hex("#A02820")         # darker red
    discard  = _hex("#8C8C84")
    connector = gate
    PixelScheme(bg, shadow, q_wire, c_wire, control, target,
                gate, prep, measure, discard, connector)
end

"""Select a named scheme. Accepts `:birren_dark` (default) or `:birren_light`."""
function _resolve_scheme(name::Symbol)
    name === :birren_dark && return birren_dark_scheme()
    name === :birren_light && return birren_light_scheme()
    error("Unknown scheme $(repr(name)); expected :birren_dark or :birren_light")
end
_resolve_scheme(s::PixelScheme) = s

# ── to_pixels ────────────────────────────────────────────────────────────────

"""
    to_pixels(ch::Channel; scheme=:birren_dark, column_width=3, gaps=true) -> Matrix{RGB{N0f8}}

Render `ch` as a pixel-art circuit.

Each wire is 1 pixel tall. By default (`gaps=true`), a 1-pixel-tall bg row
separates every adjacent pair of wires — giving the image its signature
striped appearance and room for multi-qubit gates' vertical connectors to
run between rows. Set `gaps=false` for maximum density.

Each scheduled column is `column_width` pixels wide (default 3:
`shadow | gate-centre | shadow`).

Grid geometry (with gaps, 0-indexed wire k, 1-indexed grid row):
- Quantum wire k → grid row `2k + 1`
- Gap between wires k and k+1 → grid row `2k + 2`
- Classical bit j → grid row `2(W + j) + 1`
- Total height → `2(W + B) - 1`

ASAP-scheduled columns from `_draw_schedule` determine horizontal gate
positions — identical to the ASCII drawer's layout.
"""
function to_pixels(ch::Channel; scheme=:birren_dark, column_width::Int=3,
                    gaps::Bool=true)
    column_width < 3 && error("column_width must be >= 3 (shadow|gate|shadow)")
    isodd(column_width) || error("column_width must be odd (centre pixel is the gate)")

    sch = _resolve_scheme(scheme)

    isempty(ch.dag) && isempty(ch.input_wires) && isempty(ch.output_wires) && begin
        return Matrix{RGB{N0f8}}(undef, 0, 0)
    end

    row_of, wires = _draw_collect_wires(ch)
    schedule, n_cols = _draw_schedule(ch.dag, row_of)
    bit_rows = _collect_bit_rows(ch.dag)

    W = length(wires)
    B = length(bit_rows)
    stride = gaps ? 2 : 1
    # Total rows: (W+B) wire rows + (W+B-1) gap rows when gaps=true
    H = (W + B) == 0 ? 0 : stride * (W + B) - (gaps ? 1 : 0)
    Wd = column_width * max(n_cols, 1)

    img = fill(sch.bg, H, Wd)

    # Grid-row helper: 0-indexed wire k ∈ [0, W+B-1] → 1-indexed grid row.
    # Quantum wires first, classical bits after.
    # Classical wire row lookup: bit j → wire-index slot (W + j).
    _grid_row = (k_zero_based::Int) -> stride * k_zero_based + 1

    # Paint default quantum wires on their wire rows only (gap rows stay bg).
    for i in 0:W-1
        r = _grid_row(i)
        for c in 1:Wd
            img[r, c] = sch.q_wire
        end
    end

    # Absolute bit-row index: bit j ∈ [0, B-1] at wire-slot (W + j).
    bit_row_abs = Dict{UInt32,Int}()
    for (rid, bidx) in bit_rows
        bit_row_abs[rid] = _grid_row(W + bidx)
    end

    # Paint classical wires from each Observe column rightward.
    _paint_classical_wires_px!(img, ch.dag, schedule, bit_row_abs, column_width, sch)

    # Paint each scheduled node.
    stride_int = stride
    for (i, node) in enumerate(ch.dag)
        col = schedule[i]
        _paint_node_px!(img, node, col, column_width, row_of, bit_row_abs,
                        sch, W, stride_int)
    end

    return img
end

"""
    to_png(ch::Channel, path::AbstractString; scheme=:birren_dark, column_width=3, gaps=true)

Render `ch` as a PNG file at `path`. Thin wrapper around `to_pixels` + PNGFiles.save.
"""
function to_png(ch::Channel, path::AbstractString;
                 scheme=:birren_dark, column_width::Int=3, gaps::Bool=true)
    img = to_pixels(ch; scheme=scheme, column_width=column_width, gaps=gaps)
    PNGFiles.save(path, img)
    return path
end

# ── Classical-wire painter ───────────────────────────────────────────────────

function _paint_classical_wires_px!(img, dag, schedule, bit_row_abs, col_w, sch)
    Wd = size(img, 2)
    for (i, node) in enumerate(dag)
        node isa ObserveNode || continue
        haskey(bit_row_abs, node.result_id) || continue
        br = bit_row_abs[node.result_id]
        col = schedule[i]
        # Classical wire starts at the pixel AFTER the Observe's full 3-px
        # shadow column so the drain's right-shadow pixel is not clobbered.
        x_start = (col + 1) * col_w + 1
        for c in x_start:Wd
            img[br, c] = sch.c_wire
        end
    end
end

# ── Per-node painter ─────────────────────────────────────────────────────────

"""Paint a DAG node into its column slot.

Column geometry: for scheduled column index `col` (0-based) and width `col_w`,
pixel range is `[col*col_w + 1 .. (col+1)*col_w]`; centre pixel is
`col*col_w + col_w÷2 + 1`. Left/right shadow pixels flank the centre.

Row geometry (`stride` parameter): 0-indexed wire k → grid row `stride*k + 1`
(1-indexed). With `stride=2` (default, `gaps=true`), rows `2k+2` are blank
gap rows used by vertical connectors.
"""
function _paint_node_px! end

@inline _grow(k::Int, stride::Int) = stride * k + 1

function _paint_node_px!(img, node::RyNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    row = _grow(row_of[node.wire], stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    _paint_singleton_px!(img, node, row, x_c, col_w, row_of, sch, W, sch.gate, stride)
end

function _paint_node_px!(img, node::RzNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    row = _grow(row_of[node.wire], stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    _paint_singleton_px!(img, node, row, x_c, col_w, row_of, sch, W, sch.gate, stride)
end

function _paint_node_px!(img, node::PrepNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    row = _grow(row_of[node.wire], stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    _paint_singleton_px!(img, node, row, x_c, col_w, row_of, sch, W, sch.prep, stride)
end

function _paint_node_px!(img, node::CXNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    tgt_row = _grow(row_of[node.target], stride)
    ctrl_row = _grow(row_of[node.control], stride)
    extra_ctrl_rows = Int[_grow(row_of[w], stride) for w in get_controls(node)]
    all_ctrl_rows = vcat(ctrl_row, extra_ctrl_rows)

    all_rows = sort(vcat(all_ctrl_rows, tgt_row))
    rmin, rmax = first(all_rows), last(all_rows)

    # Shadow every row from rmin..rmax (every pixel of the column)
    for r in rmin:rmax
        _paint_shadow_cell_px!(img, r, x_c, col_w, sch)
    end

    # Participating wire-row centre pixels
    for r in all_ctrl_rows
        img[r, x_c] = sch.control
    end
    img[tgt_row, x_c] = sch.target
    # Non-participating interior rows (both uninvolved wires AND gap rows)
    # get the connector colour at the centre pixel.
    involved = Set{Int}(all_ctrl_rows); push!(involved, tgt_row)
    for r in (rmin+1):(rmax-1)
        r in involved && continue
        img[r, x_c] = sch.connector
    end
end

function _paint_node_px!(img, node::ObserveNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    row = _grow(row_of[node.wire], stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    _paint_shadow_cell_px!(img, row, x_c, col_w, sch)
    img[row, x_c] = sch.measurement
    if haskey(bit_row_abs, node.result_id)
        br = bit_row_abs[node.result_id]
        for r in (row+1):br
            _paint_shadow_cell_px!(img, r, x_c, col_w, sch)
            img[r, x_c] = sch.measurement
        end
    end
end

function _paint_node_px!(img, node::DiscardNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    row = _grow(row_of[node.wire], stride)
    x_c = col * col_w + col_w ÷ 2 + 1
    _paint_shadow_cell_px!(img, row, x_c, col_w, sch)
    img[row, x_c] = sch.discard
end

function _paint_node_px!(img, node::CasesNode, col, col_w, row_of, bit_row_abs, sch, W, stride)
    # v1 placeholder — magenta stripe across the quantum wire section.
    x_c = col * col_w + col_w ÷ 2 + 1
    last_row = _grow(W - 1, stride)
    for r in 1:last_row
        _paint_shadow_cell_px!(img, r, x_c, col_w, sch)
        img[r, x_c] = sch.measurement
    end
end

"""Paint a single-qubit gate (including when()-controls). The target row is
given absolute (1-indexed, stride-aware). Extra controls resolved via
`row_of` + `stride`. Shadow on every row in [rmin, rmax]; connector centre
pixel in uninvolved interior rows (both wire and gap rows)."""
function _paint_singleton_px!(img, node, target_row::Int, x_c::Int, col_w::Int,
                               row_of, sch::PixelScheme, W::Int,
                               centre_colour::RGB{N0f8}, stride::Int)
    extra_ctrl_rows = Int[_grow(row_of[w], stride) for w in get_controls(node)]

    if isempty(extra_ctrl_rows)
        _paint_shadow_cell_px!(img, target_row, x_c, col_w, sch)
        img[target_row, x_c] = centre_colour
        return
    end

    all_rows = sort(vcat(extra_ctrl_rows, target_row))
    rmin, rmax = first(all_rows), last(all_rows)

    for r in rmin:rmax
        _paint_shadow_cell_px!(img, r, x_c, col_w, sch)
    end
    for r in extra_ctrl_rows
        img[r, x_c] = sch.control
    end
    img[target_row, x_c] = centre_colour
    involved = Set{Int}(extra_ctrl_rows); push!(involved, target_row)
    for r in (rmin+1):(rmax-1)
        r in involved && continue
        img[r, x_c] = sch.connector
    end
end

"""Paint the shadow halo: all pixels in the column except the centre."""
@inline function _paint_shadow_cell_px!(img, row::Int, x_c::Int, col_w::Int, sch::PixelScheme)
    half = col_w ÷ 2
    for dx in -half:half
        if dx != 0
            img[row, x_c + dx] = sch.shadow
        end
    end
end
