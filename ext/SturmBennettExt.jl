# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# Sturm.jl ⇄ Bennett.jl package extension (weakdep glue; Julia ≥ 1.9, Sturm's
# floor is 1.11). Milestone M7 (bead Sturm.jl-7a0v). This is the ONLY file in the
# whole codebase that names a Bennett type — it quarantines the LLVM.jl-touching
# `reversible_compile` frontend behind the weak dependency so `using Sturm` (all
# non-oracle work) never precompiles LLVM (CLAUDE.md conv 4). Mirrors Bennett's
# OWN write-once backend hook (`_REVERSIBLE_VM_BACKEND`): this `__init__` registers
# the `f → CompiledOracle` compiler into `Sturm._BENNETT_BACKEND`.
#
# The whole milestone is a plumbing problem wearing a physics hat: a Bennett
# `ReversibleCircuit` on Bennett-numbered wires becomes a kernel `Perm` (gate
# indices VERBATIM — no reversal in the gates), and the MSB/LSB remap lives in
# EXACTLY ONE function (`_role_tables`) — the single-remap discipline that keeps a
# silent bit-reversal (wm28 class) out of the gate list. Ground truth for the
# remap: docs/design/bennett-bit-order-probe.md (Bennett is positionally little-
# endian, position 1 = LSB; Sturm is MSB-first, wire 1 = MSB). The four compile-
# time rejections (VM/non-circuit, loop_check, in∩out overlap, output-as-control)
# make a future Bennett strategy change break LOUD, not silent.

module SturmBennettExt

using Sturm
using Sturm: CompiledOracle, Perm, MCX
import Bennett

# --- Backend registration (mirrors Bennett↔BennettVM's write-once hook) ---

function __init__()
    Sturm._BENNETT_BACKEND[] = _compile
end

# --- The covering native arg type (width comes from `bit_width`) ----------

"""
    _covering_type(W) -> Type

A native unsigned integer type with ≥ `W` bits; `bit_width=W` does the genuine
narrowing (Bennett computes mod `2^W`, matching `QInt{W}`'s ℤ_{2^W} ring).
Unsigned by default — `QInt` is ℤ_{2^W}; the two's-complement bits are identical
to signed for `+/−/*`, and unsigned is what `QInt{W}` means for `>>`/`÷`/compare.
(A `signed=true` covering type is a designed-in but deferred follow-on.)
"""
function _covering_type(W::Int)
    W ≤ 8  && return UInt8
    W ≤ 16 && return UInt16
    W ≤ 32 && return UInt32
    W ≤ 64 && return UInt64
    error("oracle(f, x): input width W=$W exceeds Bennett's 64-bit native ceiling")
end

# --- The f → CompiledOracle compiler (behind the weakdep) -----------------

"""
    _compile(f, W::Int, kw) -> CompiledOracle

Compile `f` at input width `W` to a `CompiledOracle`, or raise a LOUD, fail-fast
error naming `f`'s limitation. `kw` are the user's `oracle(f, x; kw...)` — passed
through to `reversible_compile` — except `target=:reversible_vm`, which is rejected
up front (the bridge is circuit-only, D14). Forces `auto_self_reversing=false`
(the kickback needs the output block DISJOINT from the input block).
"""
function _compile(f, W::Int, kw)
    (1 ≤ W ≤ 64) || error("oracle(f, x): input width W=$W is out of range 1:64")

    # D14 — the VM lowering is not a fixed permutation and cannot cross the boundary.
    if get(kw, :target, :gate_count) === :reversible_vm
        error(
            "oracle(f, x): target=:reversible_vm requests the BennettVM (unbounded " *
            "loop / runtime-sized memory). The VM lowering is NOT a fixed permutation " *
            "and cannot cross into a Sturm process value — the bridge is circuit-only " *
            "(D14). Rewrite `f` with statically-bounded loops and fixed-width state.")
    end

    T = _covering_type(W)
    circuit = try
        Bennett.reversible_compile(f, T; bit_width=W, auto_self_reversing=false, kw...)
    catch err
        error(
            "oracle(f, x): Bennett could not compile `f` to a fixed reversible " *
            "circuit — $(sprint(showerror, err)). If `f` needs unbounded loops or " *
            "runtime-sized memory it requires the BennettVM (out of scope — D14, " *
            "circuit-only bridge); rewrite with statically-bounded loops and " *
            "fixed-width state.")
    end

    # Rejection 1 — only a ReversibleCircuit crosses (MBU-exclusion is structural).
    circuit isa Bennett.ReversibleCircuit || error(
        "oracle(f, x): `reversible_compile` returned a $(typeof(circuit)), not a " *
        "ReversibleCircuit — the bridge crosses only fixed phase-free permutations " *
        "(D14). Measurement-based / VM lowerings are out of scope.")

    # Rejection 2 — a non-empty loop_check is a dirty, x-correlated convergence flag.
    isempty(circuit.loop_check_wires) || error(
        "oracle(f, x): `f` compiles to a data-dependent loop whose convergence flag " *
        "cannot be uncomputed — it is not a clean reversible oracle (its scratch does " *
        "not return to |0⟩; §3.9/D14). Increasing max_loop_iterations fixes overflow, " *
        "not the garbage flag: a genuinely data-dependent loop keeps its guard at any " *
        "K. Rewrite `f` with a statically-bounded loop (a compile-time trip count " *
        "fully unrolls with no guard), or restructure the computation.")

    # Rejection 3 — in ∩ out overlap (auto_self_reversing forced false; belt-and-braces).
    isempty(intersect(Set(circuit.input_wires), Set(circuit.output_wires))) || error(
        "oracle(f, x): the compiled circuit writes its output onto its input wires " *
        "(input ∩ output ≠ ∅) — a self-reversing primitive is incompatible with " *
        "`b ⊻= oracle(f, x)`, whose target `b` is a SEPARATE register. " *
        "(auto_self_reversing was forced false; a Bennett change broke the invariant.)")

    # Rejection 4 — no output wire may be read as a control (the D9 accumulate law).
    _assert_no_output_as_control(circuit)

    return _build_compiled(circuit, W)
end

# --- Gate map: NOT/CNOT/Toffoli → MCX (lossless, audit Q2) -----------------

_to_mcx(g::Bennett.NOTGate)     = MCX(Int[],                    Int(g.target))
_to_mcx(g::Bennett.CNOTGate)    = MCX(Int[g.control],          Int(g.target))
_to_mcx(g::Bennett.ToffoliGate) = MCX(Int[g.control1, g.control2], Int(g.target))

_gate_controls(g::Bennett.NOTGate)     = Int[]
_gate_controls(g::Bennett.CNOTGate)    = Int[g.control]
_gate_controls(g::Bennett.ToffoliGate) = Int[g.control1, g.control2]

"""
    _assert_no_output_as_control(circuit)

D9 per-circuit re-verification: NO output wire is ever read as a CNOT/Toffoli
control. This is WHY the accumulate law `b ↦ b ⊕ f(x)` holds for arbitrary `b`
(the output is a write-only XOR target, independent of its incoming value —
Nielsen–Chuang §1.4.4). One gate-list scan; a future Bennett strategy that read
an output would break here LOUD, not silently ship a soundness bug (§4.2).
"""
function _assert_no_output_as_control(circuit)
    outset = Set(circuit.output_wires)
    for g in circuit.gates
        for c in _gate_controls(g)
            c in outset && error(
                "oracle(f, x): the compiled circuit reads an output wire ($c) as a " *
                "control — the accumulate law `b ↦ b ⊕ f(x)` requires output wires to " *
                "be write-only targets (D9). A Bennett strategy change broke this " *
                "invariant; fail loud (§4.2).")
        end
    end
    nothing
end

# --- Build the CompiledOracle -----------------------------------------------

function _build_compiled(circuit, W::Int)
    gates = MCX[_to_mcx(g) for g in circuit.gates]
    perm = Perm(circuit.n_wires, gates)

    # Single-register / single-output is the M7 required path (multi is deferred).
    length(circuit.input_widths) == 1 || error(
        "oracle(f, x): `f` takes $(length(circuit.input_widths)) input registers " *
        "(input_widths=$(circuit.input_widths)); multi-register oracle is deferred " *
        "past M7 (single-register `QInt{W}` only).")
    length(circuit.output_elem_widths) == 1 || error(
        "oracle(f, x): `f` returns $(length(circuit.output_elem_widths)) outputs " *
        "(output_elem_widths=$(circuit.output_elem_widths)); multi-output oracle is " *
        "deferred past M7 (single scalar output only).")

    Wout = circuit.output_elem_widths[1]
    in_positions, out_positions, anc_positions = _role_tables(circuit, W, Wout)
    return CompiledOracle(perm, circuit.n_wires, in_positions, out_positions, Wout, anc_positions)
end

# --- THE single MSB/LSB remap (the ONLY register-vector indexing in src/+ext/) --

"""
    _role_tables(circuit, W, Wout) -> (in_positions, out_positions, anc_positions)

THE single bit-order remap (boot-lint enforced: the bracket indexing of Bennett's
input/output register vectors appears in `src/`+`ext/` ONLY inside this function).
Bennett is positionally little-endian (position 1 = LSB); Sturm is MSB-first
(wire 1 = MSB). The remap is a plain end-to-end reversal WITHIN each register block
(probe §4 formula `sturm bit j ↔ bennett position W−j+1`), never a bit-twiddle on
wire values, and it never touches the gate indices — the `Perm` keeps Bennett's
numbering, the reversal lives only in which Bennett wire each register bit binds to.

- `in_positions[reg][j]` (j MSB-first, 1..w_reg) = the Bennett input wire of that
  bit — Bennett position `offset + (w_reg − j + 1)`.
- `out_positions[β+1]` (β LSB-first, 0..Wout−1) = the Bennett output wire of that
  bit — Bennett position `β + 1` (which already carries bit β).
- `anc_positions` = the ancilla wires (no MSB/LSB significance; consistent slots).

Ground truth: docs/design/bennett-bit-order-probe.md (re-validated at Bennett HEAD
b6f13802).
"""
function _role_tables(circuit, W::Int, Wout::Int)
    length(circuit.input_wires) == sum(circuit.input_widths) || error(
        "oracle: input_wires length $(length(circuit.input_wires)) ≠ Σ input_widths " *
        "$(sum(circuit.input_widths)) — unexpected Bennett artifact shape (fail loud).")
    length(circuit.output_wires) == Wout || error(
        "oracle: output_wires length $(length(circuit.output_wires)) ≠ output width " *
        "$Wout — unexpected Bennett artifact shape (fail loud).")

    # Input blocks: MSB-first bit j ↔ Bennett position (w_reg − j + 1) within the block.
    in_positions = Vector{Int}[]
    offset = 0
    for w_reg in circuit.input_widths
        pos = Vector{Int}(undef, w_reg)
        for j in 1:w_reg
            pos[j] = circuit.input_wires[offset + (w_reg - j + 1)]
        end
        push!(in_positions, pos)
        offset += w_reg
    end

    # Output block (single element): LSB-first bit β ↔ Bennett position (β + 1).
    out_positions = Vector{Int}(undef, Wout)
    for β in 0:(Wout - 1)
        out_positions[β + 1] = circuit.output_wires[β + 1]
    end

    anc_positions = Int[Int(a) for a in circuit.ancilla_wires]
    return in_positions, out_positions, anc_positions
end

end # module SturmBennettExt
