"""
    QROMTable{Ccmul, W, Nentries}

A classical lookup table for use in quantum read-only memory (QROM) circuits.
Stores `Nentries = 2^Ccmul` entries, each fitting in `W` bits. Pure classical
data with type parameters for dispatch — NOT a subtype of `Quantum`.

`Nentries` is a third type parameter to avoid `1 << Ccmul` arithmetic in the
struct field annotation (Julia does not permit type-parameter expressions there),
following the same `Wtot = W + Cpad` pattern used in `QCoset` and `QRunway`.
The constructor enforces `Nentries == 1 << Ccmul`.

# Type parameters
  * `Ccmul`    — address register width: table has exactly `2^Ccmul` entries.
  * `W`        — value register width in qubits: values must satisfy `v < 2^W`.
  * `Nentries` — NTuple size: must equal `1 << Ccmul`. Inferred by constructor.

# Storage
Entries are stored as `NTuple{Nentries, UInt64}` for stack-allocation and
zero-heap overhead at dispatch sites. Maximum practical table size: `Ccmul ≤ 20`
(1 M entries). For larger tables use `QROMTableLarge{Ccmul, W}`.

# Modular canonicalisation
If `modulus` is `nothing`, entries are stored as-is (mod 2^W only).
If `modulus = N`, each entry `v` is stored as `v mod N`, which is the
correct coset-arithmetic representation (Gidney 1905.08488 §3).

# Usage
`QROMTable` is consumed by `qrom_lookup!` (downstream bead 6oc), which
looks up the table using a quantum address register and XORs the result
into a quantum output register.

# References
  * Gidney (2019) "Approximate Encoded Permutations and Piecewise Quantum Adders",
    arXiv:1905.08488. §3 Definition 3.1, §4 Definition 4.1.
    `docs/physics/gidney_2019_approximate_encoded_permutations.pdf`
"""
struct QROMTable{Ccmul, W, Nentries}
    data::NTuple{Nentries, UInt64}     # Nentries == 1 << Ccmul, enforced by constructor
    modulus::Union{Int, Nothing}       # nothing = no modular canonicalisation
end

"""
    QROMTableLarge{Ccmul, W}

Large-table variant of `QROMTable{Ccmul, W}` for `Ccmul > 20`. Uses
`Vector{UInt64}` instead of `NTuple` to avoid stack-overflow on construction.
Otherwise identical semantics: `2^Ccmul` entries, each fitting in `W` bits.

# When to use
  * `Ccmul ≤ 20` → `QROMTable{Ccmul, W}` (NTuple, stack-allocated, fast dispatch)
  * `Ccmul > 20` → `QROMTableLarge{Ccmul, W}` (Vector, heap-allocated)

For quantum hardware targets at the scale of Shor's algorithm (Gidney 1905.08488
§5), `Ccmul ≤ 20` covers essentially all practical ROM sizes. The large variant
exists for completeness and for classical preprocessing pipelines.

# References
  Gidney (2019) arXiv:1905.08488. §5.
"""
struct QROMTableLarge{Ccmul, W}
    data::Vector{UInt64}
    modulus::Union{Int, Nothing}

    # Inner constructor: only called from the outer convenience constructor
    # after canonicalisation. Using `new` prevents the dispatch loop that
    # would occur if we called `QROMTableLarge{C,W}(processed::Vector{UInt64},
    # modulus)` from the outer method — that call would re-match the outer
    # `AbstractVector{<:Integer}` method signature since UInt64 <: Integer.
    QROMTableLarge{Ccmul, W}(data::Vector{UInt64}, modulus::Union{Int, Nothing}) where {Ccmul, W} =
        new{Ccmul, W}(data, modulus)
end

# ── Internal: entry canonicalisation ─────────────────────────────────────────

"""
    _canonicalize_table_entries(entries::Vector{<:Integer},
                                 modulus::Union{Int, Nothing},
                                 W::Int) -> Vector{UInt64}

Process a vector of raw table entries for storage in a `QROMTable` or
`QROMTableLarge`:

  1. Apply modular reduction: `v mod N` if `modulus = N`, else `v mod 2^W`.
  2. Range-check each entry fits in W bits after reduction.
  3. Convert to `UInt64`.

This is a classical preprocessing step — no quantum operations.

# Arguments
  * `entries`  — raw classical values (any `<:Integer`).
  * `modulus`  — `Int` for coset arithmetic, `nothing` for plain W-bit truncation.
  * `W`        — output register width; values must satisfy `0 ≤ v < 2^W`.

# Errors
  * Any entry, after reduction, that does not fit in W bits.
"""
function _canonicalize_table_entries(
    entries::AbstractVector{<:Integer},
    modulus::Union{Int, Nothing},
    W::Int
)::Vector{UInt64}
    W >= 1 || error("_canonicalize_table_entries: W must be ≥ 1, got $W")
    maxval = 1 << W
    result = Vector{UInt64}(undef, length(entries))
    for (i, v) in enumerate(entries)
        reduced = if modulus === nothing
            mod(Int(v), maxval)
        else
            mod(Int(v), Int(modulus))
        end
        (0 <= reduced < maxval) || error(
            "_canonicalize_table_entries: entry[$i] = $v reduces to $reduced, " *
            "which does not fit in W=$W bits (max $(maxval - 1))"
        )
        result[i] = UInt64(reduced)
    end
    return result
end

# ── Constructors ─────────────────────────────────────────────────────────────

"""
    QROMTable{Ccmul, W}(entries::AbstractVector{<:Integer},
                         modulus::Union{Int, Nothing} = nothing)

Construct a `QROMTable{Ccmul, W}` from a vector of classical entries.

# Preconditions
  * `Ccmul ≤ 20`                        — use `QROMTableLarge` for larger tables.
  * `length(entries) == 2^Ccmul`        — exactly one entry per address.
  * Each entry (after modular reduction) fits in `W` bits.

# Modular reduction
If `modulus = N`, entries are stored as `v mod N` (coset arithmetic).
If `modulus = nothing`, entries are stored as `v mod 2^W`.
"""
function QROMTable{Ccmul, W}(
    entries::AbstractVector{<:Integer},
    modulus::Union{Int, Nothing} = nothing
) where {Ccmul, W}
    Ccmul <= 20 || error(
        "QROMTable: Ccmul=$Ccmul exceeds the NTuple limit of 20. " *
        "Use QROMTableLarge{$Ccmul, $W} for tables with more than 2^20 entries."
    )
    n_expected = 1 << Ccmul
    length(entries) == n_expected || error(
        "QROMTable{$Ccmul,$W}: expected exactly $n_expected entries " *
        "(= 2^$Ccmul), got $(length(entries))"
    )

    processed = _canonicalize_table_entries(entries, modulus, W)

    # Convert to NTuple for stack-allocation.
    # Pass Nentries = n_expected as the third type parameter.
    data = ntuple(i -> processed[i], Val(n_expected))

    return QROMTable{Ccmul, W, n_expected}(data, modulus)
end

"""
    QROMTableLarge{Ccmul, W}(entries::AbstractVector{<:Integer},
                              modulus::Union{Int, Nothing} = nothing)

Construct a `QROMTableLarge{Ccmul, W}` from a vector of classical entries.
No size limit — heap-allocated.

# Preconditions
  * `length(entries) == 2^Ccmul`.
  * Each entry (after modular reduction) fits in `W` bits.
"""
function QROMTableLarge{Ccmul, W}(
    entries::AbstractVector{<:Integer},
    modulus::Union{Int, Nothing} = nothing
) where {Ccmul, W}
    n_expected = 1 << Ccmul
    length(entries) == n_expected || error(
        "QROMTableLarge{$Ccmul,$W}: expected exactly $n_expected entries " *
        "(= 2^$Ccmul), got $(length(entries))"
    )

    processed = _canonicalize_table_entries(entries, modulus, W)
    # processed::Vector{UInt64} dispatches to the inner constructor
    # `QROMTableLarge{Ccmul,W}(::Vector{UInt64}, ::Union{Int,Nothing})`
    # defined inside the struct body, which calls `new` directly.
    # This avoids the dispatch loop: the inner constructor is more specific
    # than this outer method (inner: exact Vector{UInt64}; outer: AbstractVector{<:Integer}).
    return QROMTableLarge{Ccmul, W}(processed, modulus)
end

"""Number of entries in the table (= 2^Ccmul)."""
Base.length(tbl::QROMTable{Ccmul, W, Nentries}) where {Ccmul, W, Nentries} = Nentries
Base.length(tbl::QROMTableLarge{Ccmul, W}) where {Ccmul, W} = 1 << Ccmul
