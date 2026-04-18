# Arithmetic: QFT-based reversible arithmetic, the foundation for
# polynomial-in-L Shor.
#
# Physics:
#   Draper 2000 (quant-ph/0008033) §3, §5 — classical-constant QFT-adder.
#   Local copy: docs/physics/draper_2000_qft_adder.pdf.
#
# Design principles:
#   * 4 primitives only — no raw matrices, no named gates outside `gates.jl`.
#   * Caller manages the QFT↔computational-basis sandwich. This file
#     implements the in-basis operations.
#   * `a` is a classical `Integer` — Draper's n²/2 controlled rotations
#     collapse to L unconditional Rz rotations. O(L) gates per call.

"""
    add_qft!(y::QInt{L}, a::Integer) -> y

Add the classical integer `a` to a quantum register `y` that is already
in Fourier basis (post-QFT). Returns with `y` still in Fourier basis —
the caller applies `interfere!(y)` to recover `(y + a) mod 2^L` in
the computational basis.

Gate count: exactly L Rz rotations. No ancillae.

# Conventions

  * `y.wires[k]` for k ∈ 1..L is the k-th qubit of a QInt{L} in
    little-endian storage (`wires[1]` holds bit 2^0, `wires[L]` holds
    bit 2^{L-1}). Sturm's `superpose!` ends with a bit-reversal SWAP,
    so after QFT:

        wires[1]  holds |φ_L(y)⟩ = (|0⟩ + e^(2πi·y/2^L)|1⟩)/√2      (full-precision phase)
        wires[2]  holds |φ_{L-1}(y)⟩
        ...
        wires[L]  holds |φ_1(y)⟩ = (|0⟩ + e^(πi·y)|1⟩)/√2           (just (-1)^y)

    i.e. `wires[k]` holds `|φ_{L-k+1}(y)⟩`. To add classical `a` to
    its phase, apply `Rz(2π·a / 2^{L-k+1})` at `wires[k]`.

  * Sturm's `q.φ += δ` is `Rz(δ) = diag(e^(-iδ/2), e^(iδ/2))`. The
    relative phase between |1⟩ and |0⟩ is `e^(iδ)`, so `δ = 2π·a/2^k`
    produces the desired relative phase `e^(2πi·a/2^k)` on qubit k.

  * A global phase of `e^(-iπ·a·(1 − 2^(-L)))` accumulates over all L
    rotations. Invisible for an isolated `add_qft!`; observable when
    the call is inside `when(ctrl) do … end` (it becomes a relative
    phase on `ctrl`). The Beauregard modular adder compensates by
    composing an add-followed-by-subtract pattern that cancels the
    global phase — see Sturm.jl-dgy.

# Reference

  Draper 2000 §5 "Quantum Addition", paragraph starting "The quantum
  addition is performed using a sequence of conditional rotations…",
  specialised to classical `b` so that the n² controlled rotations
  collapse to n unconditional ones.
  `docs/physics/draper_2000_qft_adder.pdf` p. 6.
"""
function add_qft!(y::QInt{L}, a::Integer) where {L}
    check_live!(y)
    ctx = y.ctx
    # Negative a and a ≥ 2^L both wrap cleanly via mod.
    a_mod = mod(Int(a), 1 << L)
    a_mod == 0 && return y
    for k in 1:L
        # wires[k] holds |φ_{L-k+1}(y)⟩; its phase denominator is 2^(L-k+1).
        jj = L - k + 1
        θ = 2π * a_mod / (1 << jj)
        θ = mod(θ + π, 2π) - π      # fold into (-π, π] to keep angles small
        if θ != 0
            qk = QBool(y.wires[k], ctx, false)
            qk.φ += θ
        end
    end
    return y
end

"""
    sub_qft!(y::QInt{L}, a::Integer) -> y

Subtract the classical integer `a` from a Fourier-basis quantum
register `y`, in-place. Adjoint of [`add_qft!`](@ref).

`y` is expected in Fourier basis; output is in Fourier basis; result
computes `(y − a) mod 2^L` in the computational basis after `interfere!`.
"""
sub_qft!(y::QInt{L}, a::Integer) where {L} = add_qft!(y, -Int(a))

"""
    modadd!(y::QInt{Lplus1}, anc::QBool, a::Integer, N::Integer) -> y

Modular addition of classical constant `a` into a Fourier-basis register
`y`, using one ancilla qubit that is returned clean. Beauregard 2003 Fig. 5.

# Preconditions
  * `y` is in **Fourier basis**, representing some `b` with `0 ≤ b < N`.
  * `y` has `L + 1` qubits, one more than needed for `N`, so `N < 2^L`.
    The extra qubit prevents mid-circuit overflow in the raw `a+b` step.
  * `anc` is `|0⟩`.
  * `0 ≤ a < N`.

# Postconditions
  * `y` is in Fourier basis, representing `(a + b) mod N`.
  * `anc` is `|0⟩`.

# Controlled use

When this function is called inside `when(ctrl) do … end` (or nested
whens), every primitive inherits those controls. If `ctrl = |0⟩`, the
entire circuit evaluates to the identity on `(y, anc)` — this follows
from Beauregard's invariance argument in §2.2: the unconditional QFT,
subtract-N, CNOT, X-on-MSB, X-on-MSB, subtract-a, …
pattern collectively cancels to the identity on `(y, anc)` when the
three `add_qft!(y, a)` / `sub_qft!(y, a)` calls are skipped.

In our case the SKIP is implicit (every primitive is under `when(ctrl)`,
so ctrl=0 skips everything). Simpler, same correctness.

# Circuit (13 steps, Beauregard Fig. 5)

     1. add_qft!(y, a)               — y := Φ(a + b)
     2. sub_qft!(y, N)               — y := Φ(a + b − N)
     3. interfere!(y)                — y to computational basis
     4. anc ⊻= MSB(y)                — flip anc iff a+b < N
     5. superpose!(y)                — y back to Fourier
     6. when(anc) add_qft!(y, N)     — if we overshot, add N back
     7. sub_qft!(y, a)               — y := Φ((a+b) mod N − a)
     8. interfere!(y)                — to computational basis
     9. MSB.θ += π                   — Ry(π): flip MSB
    10. anc ⊻= MSB(y)                — un-flip anc (works since b < N)
    11. MSB.θ -= π                   — Ry(-π): un-flip MSB, phases cancel
    12. superpose!(y)                — to Fourier
    13. add_qft!(y, a)               — y := Φ((a+b) mod N)

# Gate-phase note

Beauregard's Fig. 5 specifies "X on MSB" at steps 9 and 11. Sturm's
`X!` is `Ry(π) = −iY`, not the standard `X = [[0,1],[1,0]]`, so two
`X!`s would accumulate a `(−i)² = −1` global phase. Under `when(ctrl)`
that becomes a *relative* phase on `ctrl`, which is an unrelated Z
rotation — a bug. We use `θ += π` (Ry(π)) at step 9 and `θ −= π`
(Ry(−π)) at step 11; the two rotations are exact inverses and the
global phase cancels. The classical MSB flip-and-unflip effect on the
CNOT at step 10 is unchanged.

# Reference
  Beauregard 2003 §2.2 "The modular adder gate", p. 5–6, Fig. 5.
  `docs/physics/beauregard_2003_2n3_shor.pdf`.
"""
function modadd!(y::QInt{Lp1}, anc::QBool, a::Integer, N::Integer) where {Lp1}
    check_live!(y); check_live!(anc)
    ctx = y.ctx
    msb = QBool(y.wires[Lp1], ctx, false)

    add_qft!(y, a)                 # 1.  Φ(b)     → Φ(a+b)
    sub_qft!(y, N)                 # 2.           → Φ(a+b−N)
    interfere!(y)                  # 3.  Fourier  → computational
    anc ⊻= msb                     # 4.  anc = 1 iff a+b < N
    superpose!(y)                  # 5.  comp.    → Fourier
    when(anc) do                   # 6.  if overshoot, add N back
        add_qft!(y, N)
    end
    sub_qft!(y, a)                 # 7.           → Φ((a+b) mod N − a)
    interfere!(y)                  # 8.
    msb.θ += π                     # 9.  flip MSB (Ry(π))
    anc ⊻= msb                     # 10. un-flip anc: correlated with flipped-MSB
    msb.θ -= π                     # 11. un-flip MSB (Ry(−π)) — phases cancel
    superpose!(y)                  # 12.
    add_qft!(y, a)                 # 13. final Φ((a+b) mod N)

    return y
end

"""
    mulmod_beauregard!(x::QInt{L}, a::Integer, N::Integer, ctrl::QBool) -> x

Controlled modular multiplication by a classical constant:
`|ctrl⟩|x⟩ ↦ |ctrl⟩|(a·x) mod N⟩` when `ctrl = |1⟩`, identity when
`ctrl = |0⟩`. Beauregard 2003 Fig. 7 (the `c-U_a` gate).

# Preconditions
  * `0 ≤ x < N` and `0 ≤ a < N`.
  * `N < 2^L` (i.e. N fits in L bits, matching x's register width).
  * `gcd(a, N) = 1` — a must be invertible mod N. Enforced by error.

# Postconditions
  * `x := (a·x) mod N` on the `ctrl = 1` branch, `x` unchanged on
    `ctrl = 0`. Linear in superposition on `ctrl`.
  * No net change to any allocated ancilla register.

# Gate count

  `mulmod_beauregard!` uses `2L` calls to [`modadd!`](@ref), each with a
  classical constant smaller than N, plus one L-qubit controlled-SWAP.
  Each `modadd!` is O(L) gates (dominated by the QFT + add_qft pair).
  Total: **O(L²) gates** per mulmod, **O(L² log L)** if counting
  approximate-QFT optimisations. Polynomial in L — compare QROM-based
  impls (A/B/C in `src/library/shor.jl`) which are O(2^L).

# Method (Fig. 7)

Allocate an (L+1)-qubit accumulator `b := |0⟩` and one ancilla.
Under `when(ctrl)`:

  1. `CMULT(a) MOD(N)` : for each bit j of x, doubly-controlled
     modular addition of `(a · 2^j) mod N` into `b`. Result: `b = (a·x) mod N`.
  2. Controlled-SWAP(x, b[1..L]): swaps x with the first L qubits of b.
     After: `x = (a·x_orig) mod N`, `b[1..L] = x_orig`, `b[L+1] = 0`.
  3. `CMULT(a⁻¹) MOD(N)⁻¹` : inverse of forward CMULT with a⁻¹ — for
     each bit j of x (the NEW x = (a·x_orig) mod N), controlled
     modular SUBTRACTION of `(a⁻¹ · 2^j) mod N` from `b`. This
     computes `b := b − a⁻¹·x mod N = x_orig − a⁻¹·(a·x_orig) mod N = 0`.

`a⁻¹ = invmod(a, N)` computed classically via extended Euclid.
Modular subtraction of `c` is implemented as `modadd!(b, …, N − c, N)`
since `(b + (N − c)) mod N = (b − c) mod N`.

# Reference
  Beauregard 2003 §2.3 "The controlled multiplier gate", p. 7–8,
  Fig. 6 (CMULT) and Fig. 7 (c-U_a). Eq. (2)–(3).
  `docs/physics/beauregard_2003_2n3_shor.pdf`.
"""
function mulmod_beauregard!(x::QInt{L}, a::Integer, N::Integer,
                            ctrl::QBool) where {L}
    check_live!(x); check_live!(ctrl)
    N > 0       || error("mulmod_beauregard!: N must be positive, got $N")
    N < (1 << L) || error("mulmod_beauregard!: N must fit in L bits, got N=$N, L=$L")
    a_mod = mod(Int(a), Int(N))
    gcd(a_mod, Int(N)) == 1 ||
        error("mulmod_beauregard!: need gcd(a, N) = 1, got gcd($(a_mod), $N) = $(gcd(a_mod, Int(N)))")
    a_inv = invmod(a_mod, Int(N))

    ctx = x.ctx

    # Allocate work registers UNCONDITIONALLY (outside when(ctrl)) so that
    # allocation/deallocation is not itself controlled. When ctrl = 0, the
    # body is skipped and these stay at |0⟩; when ctrl = 1, the circuit
    # restores them to |0⟩.
    b   = QInt{L + 1}(0)
    anc = QBool(0)

    when(ctrl) do
        # ── 1. CMULT(a)MOD(N): b ← b + a·x mod N ─────────────────────
        superpose!(b)
        for j in 1:L
            xj = QBool(x.wires[j], ctx, false)
            c  = (a_mod * (1 << (j - 1))) % Int(N)
            c == 0 && continue
            when(xj) do
                modadd!(b, anc, c, N)
            end
        end
        interfere!(b)
        # state: |ctrl=1⟩|x⟩|b = a·x mod N⟩|anc=0⟩

        # ── 2. Controlled SWAP(x, b[1..L]) ────────────────────────────
        for j in 1:L
            xj = QBool(x.wires[j], ctx, false)
            bj = QBool(b.wires[j], ctx, false)
            swap!(xj, bj)
        end
        # state: |ctrl=1⟩|a·x_orig mod N⟩|b[1..L]=x_orig, b[L+1]=0⟩|anc=0⟩

        # ── 3. CMULT(a⁻¹)MOD(N)⁻¹: b ← b − a⁻¹·x mod N = 0 ───────────
        superpose!(b)
        for j in 1:L
            xj = QBool(x.wires[j], ctx, false)
            c  = (a_inv * (1 << (j - 1))) % Int(N)
            c == 0 && continue
            when(xj) do
                # inverse of "add c": subtract c mod N  ≡  add (N − c) mod N
                modadd!(b, anc, mod(Int(N) - c, Int(N)), N)
            end
        end
        interfere!(b)
        # state: |ctrl=1⟩|a·x_orig mod N⟩|b=0⟩|anc=0⟩
    end

    # Work registers are in |0⟩ on both ctrl branches — clean discard.
    discard!(b)
    discard!(anc)

    return x
end
