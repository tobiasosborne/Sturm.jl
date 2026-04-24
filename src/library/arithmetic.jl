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

  * `sub_qft!(y, a)` dispatches to `add_qft!(y, -a)` and the two calls
    compose to identity exactly — `Rz(θ)·Rz(−θ) = I`. This requires that
    `add_qft!` emit the **raw angle** `θ_raw = 2π·a/2^jj` per wire rather
    than folding into `(-π, π]`: the fold maps both `θ_raw = +π` and
    `θ_raw = -π` to `-π`, breaking the inverse property and leaking a
    `−I` global phase per wire. When the call is inside `when(ctrl)`,
    that global phase becomes a relative `π` phase on `ctrl=|1⟩` — the
    root cause of Sturm.jl-di9.

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
    a_int = Int(a)
    a_int == 0 && return y
    for k in 1:L
        # wires[k] holds |φ_{L-k+1}(y)⟩; its phase denominator is 2^(L-k+1).
        jj = L - k + 1
        θ = 2π * a_int / (1 << jj)
        # No fold. `add_qft(+a) ∘ add_qft(-a)` must reduce to Rz(θ)·Rz(−θ)=I
        # per wire as unitaries; any canonicalisation (mod into a half-open
        # interval) breaks this when θ_raw hits the interval boundary.
        # Orkan computes Rz(θ) in double precision for any θ — no need to
        # keep the angle small.
        qk = QBool(y.wires[k], ctx, false)
        qk.φ += θ
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
    add_qft_quantum!(y::QInt{L}, b::QInt{L}) -> y

Add the quantum register `b` into a Fourier-basis quantum register `y`,
in-place. Full two-register Draper 2000 §5 construction — the generalisation
of [`add_qft!`](@ref) where the addend is quantum rather than a classical
constant. `b` is in computational basis and is preserved; `y` starts and
ends in Fourier basis. After `interfere!(y)` the caller recovers
`(y₀ + b) mod 2^L`.

Gate count: `L(L+1)/2` controlled `Rz` rotations, no ancillae. Under
`when(ctrl)`, each rotation picks up one extra control via Sturm's control
stack — still a single primitive-3 call per rotation.

# Convention

Draper §5 Fig. "Transform Addition": target wire `|φ_{jj}(y)⟩` receives
rotation `R_d` controlled on source bit `b_j`, with `d = jj − j + 1`, for
each `j = 1..jj`. Sturm's `superpose!` stores `|φ_{jj}⟩` at `wires[L−jj+1]`
(bit-reversal), and `b.wires[j]` stores bit `2^(j−1)` of `b`. So the code
loop walks target wire `k ∈ 1..L`, sets `jj = L − k + 1`, and inside it walks
`j = 1..jj` emitting `Rz(2π / 2^(jj − j + 1))` controlled on `b.wires[j]`.

The classical specialisation `add_qft!(y, a::Integer)` sums the rotations
across `j` classically into a single `Rz(2π · a / 2^jj)` per target wire.
This function keeps the rotations per-control, giving the full O(L²) count.

# di9 carry-over

No angle fold. Each rotation is emitted at raw value `2π / 2^d`. Inverse is
`sub_qft_quantum!(y, b) ≡ add_qft_quantum!` with negated angles — the two
compose to identity per wire as unitaries `Rz(θ)·Rz(−θ) = I`, preserving
control-branch coherence. See Sturm.jl-di9 WORKLOG for why any fold would
be a ctrl=|1⟩ phase leak.

# Reference

  Draper 2000 §5 "Quantum Addition", Fig. "Transform Addition", p. 6.
  `docs/physics/draper_2000_qft_adder.pdf`.
"""
function add_qft_quantum!(y::QInt{L}, b::QInt{L}) where {L}
    _add_qft_quantum_signed!(y, b, +1)
end

"""
    sub_qft_quantum!(y::QInt{L}, b::QInt{L}) -> y

Quantum-addend QFT subtractor. Adjoint of [`add_qft_quantum!`](@ref).
Emits `Rz(−2π / 2^d)` per Draper §5 pair instead of `Rz(+2π / 2^d)`; the
angle negation is structural, so the pair `add_qft_quantum!` then
`sub_qft_quantum!` composes to the per-wire identity `Rz(θ)·Rz(−θ) = I`
regardless of control context (no di9-style phase leak under `when`).
"""
function sub_qft_quantum!(y::QInt{L}, b::QInt{L}) where {L}
    _add_qft_quantum_signed!(y, b, -1)
end

@inline function _add_qft_quantum_signed!(y::QInt{L}, b::QInt{L}, sign::Int) where {L}
    check_live!(y); check_live!(b)
    y.ctx === b.ctx ||
        error("add_qft_quantum!: y and b must live in the same context")
    ctx = y.ctx
    for k in 1:L
        jj = L - k + 1                       # Sturm wires[k] ↔ Draper φ_{jj}
        qk = QBool(y.wires[k], ctx, false)
        for j in 1:jj
            d = jj - j + 1                   # Draper R_d conditional rotation
            θ = sign * 2π / (1 << d)
            bj = QBool(b.wires[j], ctx, false)
            when(bj) do
                qk.φ += θ
            end
        end
    end
    return y
end

# ── Internal: nested `when`s from a tuple of controls ─────────────────────
#
# `_apply_ctrls(f, ())`            ≡ f()
# `_apply_ctrls(f, (c1,))`         ≡ when(c1) do f() end
# `_apply_ctrls(f, (c1, c2))`      ≡ when(c1) do when(c2) do f() end end
#
# Hot-path helper for modadd!'s ctrls kwarg. Stays @inline so Julia elides
# the Tuple dispatch at the call site.
@inline _apply_ctrls(f, ::Tuple{}) = f()
@inline _apply_ctrls(f, c::Tuple{QBool}) = when(c[1]) do; f(); end
@inline _apply_ctrls(f, c::Tuple{QBool,QBool}) =
    when(c[1]) do; when(c[2]) do; f(); end; end

"""
    modadd!(y::QInt{Lplus1}, anc::QBool, a::Integer, N::Integer;
             ctrls::Tuple = ()) -> y

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

# Controlled use — the `ctrls` kwarg

Pass `ctrls = (c1,)` or `ctrls = (c1, c2)` to make the gate
doubly/singly controlled *in the Beauregard sense*: only the three
`add_qft!(y, a)` / `sub_qft!(y, a)` calls at steps 1, 7, 13 inherit the
controls; everything else runs unconditionally. Beauregard 2003 p. 6
("we will doubly control only the φADD(a) gates instead of all the
gates") proves this is correct — if the three φADD(a) gates are
skipped, the remaining QFT/sub-N/CNOT/X pattern collapses to identity
on `(y, anc)` because `b < N`.

This is **not** equivalent to `when(c1) do modadd!(y, anc, a, N) end`.
The `when`-wrapped form puts `c1` on the control stack for *every*
primitive inside modadd, including the `when(anc) add_qft!(y, N)` at
step 6 — producing a depth-2 control (c1, anc) on each Rz.  With
`ctrls`, step 6 still sees only `[anc]` → depth 1.  The saving is
dramatic in nested callers: `mulmod_beauregard!` goes from a 3-deep
multi-controlled cascade (which triggers
`_multi_controlled_gate!` workspace allocation for every primitive) to
a 2-deep fast path.

Backward compatibility: with `ctrls = ()` (the default) and an outer
`when(ctrl) do modadd!(...) end` wrapper, every primitive inherits
`ctrl` as before.  All existing call sites keep working.

# Circuit (13 steps, Beauregard Fig. 5)

     1. add_qft!(y, a)               — y := Φ(a + b)                [under ctrls]
     2. sub_qft!(y, N)               — y := Φ(a + b − N)             (unconditional)
     3. interfere!(y)                — y to computational basis       (unconditional)
     4. anc ⊻= MSB(y)                — flip anc iff a+b < N           (unconditional)
     5. superpose!(y)                — y back to Fourier              (unconditional)
     6. when(anc) add_qft!(y, N)     — if we overshot, add N back     (anc-controlled)
     7. sub_qft!(y, a)               — y := Φ((a+b) mod N − a)        [under ctrls]
     8. interfere!(y)                — to computational basis         (unconditional)
     9. MSB.θ += π                   — Ry(π): flip MSB                (unconditional)
    10. anc ⊻= MSB(y)                — un-flip anc                    (unconditional)
    11. MSB.θ -= π                   — Ry(-π): un-flip MSB            (unconditional)
    12. superpose!(y)                — to Fourier                     (unconditional)
    13. add_qft!(y, a)               — y := Φ((a+b) mod N)            [under ctrls]

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
function modadd!(y::QInt{Lp1}, anc::QBool, a::Integer, N::Integer;
                 ctrls::Tuple = ()) where {Lp1}
    check_live!(y); check_live!(anc)
    ctx = y.ctx
    msb = QBool(y.wires[Lp1], ctx, false)

    _apply_ctrls(() -> add_qft!(y, a), ctrls)  # 1.  Φ(b)     → Φ(a+b)
    sub_qft!(y, N)                             # 2.           → Φ(a+b−N)
    interfere!(y)                              # 3.  Fourier  → computational
    anc ⊻= msb                                 # 4.  anc = 1 iff a+b < N
    superpose!(y)                              # 5.  comp.    → Fourier
    when(anc) do                               # 6.  if overshoot, add N back
        add_qft!(y, N)
    end
    _apply_ctrls(() -> sub_qft!(y, a), ctrls)  # 7.           → Φ((a+b) mod N − a)
    interfere!(y)                              # 8.
    msb.θ += π                                 # 9.  flip MSB (Ry(π))
    anc ⊻= msb                                 # 10. un-flip anc
    msb.θ -= π                                 # 11. un-flip MSB (Ry(−π))
    superpose!(y)                              # 12.
    _apply_ctrls(() -> add_qft!(y, a), ctrls)  # 13. final Φ((a+b) mod N)

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

  `mulmod_beauregard!` uses `2L` calls to [`modadd!`](@ref) (with
  `ctrls = (ctrl, xj)` doubly controlled), plus two unconditional QFT
  sandwiches on the `(L+1)`-qubit accumulator and a single
  `ctrl`-controlled SWAP of L qubits. Each `modadd!` is O(L) gates.
  Total: **O(L²) gates** per mulmod. Polynomial in L — compare QROM-based
  impls (A/B/C in `src/library/shor.jl`) which are O(2^L).

# Control-depth optimisation (the fix for the 3-deep cascade)

The naive transcription of Fig. 7 wraps *everything* in
`when(ctrl) do … end`, and each CMULT inner loop adds a second
`when(xj)`. Combined with modadd's own `when(anc) add_qft!(y, N)` at
step 6 this yields depth 3 — every primitive goes through Sturm's
`_multi_controlled_gate!` cascade (2 workspace qubits allocated per
gate). At L=3 this is thousands of gates per mulmod.

Per Beauregard 2003 p. 6, the φADD(a) calls inside modadd are the
*only* ones that need the external (c, xj) control: "If the φADD(a)
gates are not performed, it is easy to verify that the rest of the
circuit implements the identity on all qubits because b < N." We pass
`ctrls = (ctrl, xj)` via `modadd!`'s kwarg so only those three calls
pick up the extra controls — the 10 non-ADD(a) primitives inside
modadd stay unconditional (or anc-controlled at step 6). Depth caps
at 2 on the ADD(a) calls and 1 elsewhere: Sturm fast path, no cascade.

The outer QFT / QFT⁻¹ on `b` are also lifted out of `when(ctrl)`:
with ctrl=0 all modadds are skipped, so `b` stays in the state produced
by the forward QFT, and the closing QFT⁻¹ inverts it — net identity on
`b`. Same for the inverse CMULT sandwich.

# Method (Fig. 7, with Beauregard p. 6 optimisation)

Allocate an (L+1)-qubit accumulator `b := |0⟩` and one ancilla, both
unconditional.

  1. `QFT(b)` — unconditional (identity when paired with closing QFT⁻¹
     even if ctrl=0 because modadds all skip).
  2. CMULT(a)MOD(N) forward sweep: for each bit j of x, call
     `modadd!(b, anc, (a·2^j) mod N, N; ctrls=(ctrl, xj))`.  Result
     (ctrl=1): `b = (a·x) mod N` in Fourier basis.
  3. `QFT⁻¹(b)` — unconditional.  b is now in computational basis.
  4. Controlled-SWAP(x, b[1..L]) under `when(ctrl)`: single control,
     depth 1, fast path.
  5. `QFT(b)` — unconditional.
  6. CMULT(a⁻¹)MOD(N)⁻¹ reverse sweep: same pattern as step 2 but with
     `(N − a⁻¹·2^j) mod N` as the classical constant (modular subtract
     via add-of-negation). Zeroes `b` by `b := b − a⁻¹·x_new = 0`.
  7. `QFT⁻¹(b)` — unconditional.

`a⁻¹ = invmod(a, N)` computed classically via extended Euclid.

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

    # Work registers allocated unconditionally: b is the (L+1)-qubit
    # Fourier accumulator, anc is modadd's 1-qubit overflow flag.  Both
    # return to |0⟩ on either ctrl branch and get clean-discarded.
    b   = QInt{L + 1}(0)
    anc = QBool(0)

    # ── 1. QFT on b (unconditional) ──────────────────────────────────
    superpose!(b)

    # ── 2. CMULT(a)MOD(N) forward: b ← b + a·x mod N ────────────────
    # Each modadd doubly controlled by (ctrl, xj) via the ctrls kwarg —
    # the φADD(a) gates inside modadd pick up depth 2, everything else
    # stays unconditional (Beauregard p. 6).
    for j in 1:L
        xj = QBool(x.wires[j], ctx, false)
        c  = (a_mod * (1 << (j - 1))) % Int(N)
        c == 0 && continue
        modadd!(b, anc, c, N; ctrls=(ctrl, xj))
    end

    # ── 3. QFT⁻¹ on b ────────────────────────────────────────────────
    interfere!(b)
    # state (ctrl=1): |ctrl⟩|x⟩|b = a·x mod N⟩|anc=0⟩
    # state (ctrl=0): |ctrl⟩|x⟩|b = 0⟩|anc=0⟩  (QFT·QFT⁻¹ on |0⟩ = |0⟩)

    # ── 4. Controlled-SWAP(x, b[1..L]) ──────────────────────────────
    # Single control: depth 1, fast path.  3 CNOTs per bit via swap!.
    when(ctrl) do
        for j in 1:L
            xj = QBool(x.wires[j], ctx, false)
            bj = QBool(b.wires[j], ctx, false)
            swap!(xj, bj)
        end
    end
    # state (ctrl=1): |a·x_orig mod N⟩|b[1..L]=x_orig, b[L+1]=0⟩|anc=0⟩
    # state (ctrl=0): unchanged

    # ── 5. QFT on b (unconditional) ──────────────────────────────────
    superpose!(b)

    # ── 6. CMULT(a⁻¹)MOD(N)⁻¹ reverse: b ← b − a⁻¹·x mod N = 0 ──────
    # x now holds (a·x_orig) mod N on the ctrl=1 branch.  Subtracting
    # a⁻¹·x = a⁻¹·(a·x_orig) = x_orig from the SWAPped register
    # b[1..L] = x_orig gives b = 0.  Modular subtract via add-of-negation.
    for j in 1:L
        xj = QBool(x.wires[j], ctx, false)
        c  = (a_inv * (1 << (j - 1))) % Int(N)
        c == 0 && continue
        modadd!(b, anc, mod(Int(N) - c, Int(N)), N; ctrls=(ctrl, xj))
    end

    # ── 7. QFT⁻¹ on b ────────────────────────────────────────────────
    interfere!(b)
    # state: |a·x_orig mod N⟩|b=0⟩|anc=0⟩    (ctrl=1)
    #        |x_orig⟩|b=0⟩|anc=0⟩              (ctrl=0)

    ptrace!(b)
    ptrace!(anc)

    return x
end

"""
    plus_equal_product!(target::QInt{Lt}, k::Integer, y::QInt{Ly}; window::Int) -> target

Windowed product-addition: `target += k·y` mod `2^Lt`, with classical `k`
and quantum `y`. Implements Gidney 2019 §3.1 (arXiv:1905.07682) using a
window of `window` qubits of `y` per iteration.

# Semantics
For each `window`-qubit chunk `y[i:i+window]` of `y` (little-endian,
starting at bit `i = 0, window, 2·window, …`), precompute a
`2^window`-entry classical table `T[j] = j·k` truncated to `Lt − i` bits,
then compute `target[i:] += T[y[i:i+window]]` via a QROM lookup of the
quantum window into a scratch register, QFT-basis addition into the
target tail, and uncomputation of the scratch.

# Asymptotic cost
`O(Ly·(Lt + 2^window) / window)` Toffoli. With `window ≈ lg Ly`:
`O(Lt·Ly / lg Ly)`, one log-factor below the naïve ripple-carry over
classical `k`. GE21 Eq. 2 uses this repeatedly inside windowed mulmod.

# Preconditions
  * `window` divides `Ly`.
  * `1 ≤ window ≤ Ly`.
  * `Lt ≤ 62` (UInt64 margin for `j·k` table entries).
  * `target` and `y` share a context.

# Automatic control
Wraps `qrom_lookup_xor!` and `add_qft_quantum!`, both of which auto-control
under `when(…) do … end` via Sturm's control stack.

# References
  * Gidney (2019) "Windowed quantum arithmetic", arXiv:1905.07682 §3.1.
    `docs/physics/gidney_2019_windowed_arithmetic.pdf`.
  * Gidney-Ekerå (2021) arXiv:1905.09749 §2.5.
    `docs/physics/gidney_ekera_2021_rsa2048.pdf`.
"""
function plus_equal_product!(target::QInt{Lt}, k::Integer, y::QInt{Ly};
                             window::Int) where {Lt, Ly}
    check_live!(target); check_live!(y)
    target.ctx === y.ctx ||
        error("plus_equal_product!: target and y must share a context")
    window >= 1 || error("plus_equal_product!: window must be ≥ 1, got $window")
    window <= Ly ||
        error("plus_equal_product!: window=$window exceeds Ly=$Ly")
    Ly % window == 0 ||
        error("plus_equal_product!: window=$window must divide Ly=$Ly")
    Lt <= 62 ||
        error("plus_equal_product!: Lt=$Lt exceeds UInt64 margin (max 62)")
    ctx = target.ctx

    # k = 0 is the identity — no lookups, no QFT, no ancillae.
    k == 0 && return target

    # Little-endian window iteration: window 0 covers wires y[1..window] (LSB),
    # window 1 covers wires y[window+1..2·window], etc.
    for i in 0:window:(Ly - 1)
        W_tail = Lt - i
        W_tail >= 1 || break      # target exhausted; higher windows are invisible

        # Non-owning view of y's window chunk as QInt{window}.
        y_win_wires = ntuple(j -> y.wires[i + j], Val(window))
        y_win = QInt{window}(y_win_wires, ctx, false)

        # Non-owning view of target's tail as QInt{W_tail}.
        target_tail_wires = ntuple(j -> target.wires[i + j], Val(W_tail))
        target_tail = QInt{W_tail}(target_tail_wires, ctx, false)

        # Classical table T[j] = (j·k) mod 2^W_tail, j ∈ [0, 2^window).
        n_entries = 1 << window
        mask = W_tail >= 64 ? typemax(UInt64) :
                              (UInt64(1) << W_tail) - UInt64(1)
        entries = Vector{UInt64}(undef, n_entries)
        @inbounds for j in 0:(n_entries - 1)
            entries[j + 1] = (UInt64(j) * UInt64(k)) & mask
        end
        tbl = QROMTable{window, W_tail}(entries)

        # Scratch |0⟩_{W_tail} — compute T[y_win], add into tail, uncompute.
        scratch = QInt{W_tail}(0)
        qrom_lookup_xor!(scratch, y_win, tbl)          # scratch = T[y_win]

        # QFT sandwich on the target tail. Per-iteration sandwich is simplest;
        # batching the QFT across iterations is an optimisation opportunity
        # (each iteration's tail is a different width, so batching needs care).
        superpose!(target_tail)
        add_qft_quantum!(target_tail, scratch)         # target_tail += scratch
        interfere!(target_tail)

        qrom_lookup_xor!(scratch, y_win, tbl)          # uncompute: scratch → |0⟩
        ptrace!(scratch)
    end

    return target
end

"""
    plus_equal_product_mod!(target::QCoset{W, Cpad, Wtot}, k::Integer,
                             y::QInt{Ly}; window::Int) -> target

Windowed modular product-addition on a coset-encoded target: the encoded
residue r of `target` becomes `(r + k·y) mod N` where `N = target.modulus`,
`k` is classical, and `y` is quantum. Implements Gidney 2019 §3.3
(arXiv:1905.07682) combined with the Gidney-Ekerå 2021 §2.4 coset trick.

# How it works
GE21 §2.4: on a coset-encoded register, ordinary (non-modular) addition of
a value `a ∈ [0, N)` acts as modular addition mod N, with per-op deviation
bounded by `2^{-Cpad}` (Gidney 1905.08488 Thm 3.2). The deviation only
fires when a coset branch wraps past `2^Wtot`; when table entries are
reduced mod N (and `N < 2^W`, the QCoset invariant), the max branch value
is `(2^Cpad − 1)·N + (N − 1) = 2^Cpad·N − 1 < 2^Wtot`, so no wrap occurs
and the operation is deterministic per shot.

# Loop structure vs `plus_equal_product!` (§3.1)
  * No target slicing — every iteration adds into the full `Wtot`-bit
    `target.reg`. There is no `target[i:]` because mod-N addition cannot
    be localised to a bit slice.
  * Position factor `2^i` is folded into each window's lookup table:
    `T[j] = (j · k · 2^i) mod N`. The table is rebuilt per window.
  * Entries are pre-reduced mod N (stored via `QROMTable(…, modulus=N)`),
    fit in W bits, hence cleanly into the Wtot-bit scratch (top Cpad
    bits stay `|0⟩`).

# Preconditions (all fail-loud per Rule 1)
  * `1 ≤ window ≤ Ly`. `window` need not divide Ly — the final iteration
    uses a smaller `window_last = Ly - i` bits if necessary (Phase C1).
  * `target.reg.ctx === y.ctx`.
  * `Ly < 62` (UInt64 margin on `2^i` during table construction).

# Controls (`ctrls` kwarg) — Beauregard pattern
  * `ctrls = ()`      — unconditional (default).
  * `ctrls = (c1,)`   — apply only to the quantum addition step; the
    QFT/IQFT and QROM compute/uncompute run unconditionally and
    self-cancel on the `c1=|0⟩` branch.

  This is **NOT** equivalent to `when(c1) do plus_equal_product_mod!(…) end`.
  The `when`-wrapped form puts `c1` on the control stack for every
  primitive inside — including the QROM's Toffolis, which would then need
  `_multi_controlled_cx!` workspace ancillae and blow Orkan's 30-qubit cap
  at N=15, c_mul=2. The `ctrls` kwarg keeps those Toffolis at depth 1 and
  still produces the correct channel (QFT·QFT⁻¹ = I, QROM·QROM = I).

  Matches the same kwarg pattern used by [`modadd!`](@ref).

# References
  * Gidney (2019) arXiv:1905.07682 §3.3.
    `docs/physics/gidney_2019_windowed_arithmetic.pdf`.
  * Gidney-Ekerå (2021) arXiv:1905.09749 §2.4, §2.5.
    `docs/physics/gidney_ekera_2021_rsa2048.pdf`.
  * Gidney (2019) arXiv:1905.08488 Thm 3.2 (coset deviation bound).
    `docs/physics/gidney_2019_approximate_encoded_permutations.pdf`.
"""
function plus_equal_product_mod!(target::QCoset{W, Cpad, Wtot}, k::Integer,
                                  y::QInt{Ly}; window::Int,
                                  ctrls::Tuple = ()) where {W, Cpad, Wtot, Ly}
    check_live!(target); check_live!(y)
    target.reg.ctx === y.ctx ||
        error("plus_equal_product_mod!: target and y must share a context")
    window >= 1 || error("plus_equal_product_mod!: window must be ≥ 1, got $window")
    window <= Ly ||
        error("plus_equal_product_mod!: window=$window exceeds Ly=$Ly")
    Ly < 62 ||
        error("plus_equal_product_mod!: Ly=$Ly exceeds 2^i arithmetic margin (max 61)")
    ctx = target.reg.ctx
    N = Int(target.modulus)

    # k = 0 — identity, no lookups, no QFT.
    k == 0 && return target

    k_mod_N = mod(Int(k), N)

    # Ragged-last-window support (Gidney 2019 §3.1/§3.3 allow this implicitly).
    # If window doesn't divide Ly, the final iteration uses window_last = Ly-i
    # bits instead of `window`. Semantically identical: the last chunk of y
    # is narrower, the lookup table has fewer entries (2^window_last), and
    # the position factor 2^i still multiplies the entries. Julia dispatches
    # on the Val(w) boxing per distinct w seen at runtime (at most 2 here).
    i = 0
    while i < Ly
        w = min(window, Ly - i)
        _pep_mod_iter!(target, k_mod_N, y, i, Val(w), N, ctrls)
        i += w
    end

    return target
end

# Helper: one iteration of the plus_equal_product_mod! sweep. Factored out
# so each distinct window size (`w`) triggers its own Julia specialisation
# via `Val(w)` dispatch.
#
# The `ctrls` kwarg follows the `modadd!` pattern: only the (quantum)
# addition step needs to be controlled, not the self-inverse surroundings.
#   qrom_lookup_xor! (compute) + qrom_lookup_xor! (uncompute) = I  unconditionally
#   superpose! + interfere!                                    = I  unconditionally
# so wrapping only `add_qft_quantum!` in the controls preserves the
# ctrl=|0⟩ identity branch while avoiding a full when(ctrl) cascade over
# the QROM Toffolis (which would bump them to CCCX via _multi_controlled_cx!
# and cost workspace ancillae past Orkan's 30-qubit cap).
@inline function _pep_mod_iter!(target::QCoset{W, Cpad, Wtot},
                                  k_mod_N::Int,
                                  y::QInt{Ly},
                                  i::Int,
                                  ::Val{w},
                                  N::Int,
                                  ctrls::Tuple) where {W, Cpad, Wtot, Ly, w}
    ctx = target.reg.ctx
    n_entries = 1 << w

    # y window view: wires [i+1 .. i+w] as QInt{w}.
    y_win_wires = ntuple(j -> y.wires[i + j], Val(w))
    y_win = QInt{w}(y_win_wires, ctx, false)

    # Table entries T[j] = (j · k · 2^i) mod N.
    two_pow_i_modN = powermod(2, i, N)
    entries = Vector{UInt64}(undef, n_entries)
    @inbounds for j in 0:(n_entries - 1)
        jk_mod = mod(Int(j) * k_mod_N, N)
        v = mod(jk_mod * two_pow_i_modN, N)
        entries[j + 1] = UInt64(v)
    end
    tbl = QROMTable{w, Wtot}(entries, N)

    scratch = QInt{Wtot}(0)
    qrom_lookup_xor!(scratch, y_win, tbl)        # unconditional — scratch = T[y_win]

    superpose!(target.reg)                       # unconditional
    _apply_ctrls(ctrls) do                       # only the add is controlled
        add_qft_quantum!(target.reg, scratch)
    end
    interfere!(target.reg)                       # unconditional

    qrom_lookup_xor!(scratch, y_win, tbl)        # unconditional — scratch → |0⟩
    ptrace!(scratch)
    return nothing
end

# ═══════════════════════════════════════════════════════════════════════════
# Sturm.jl-9ij Stage 1 — binary-to-unary encoder for measurement-based QROM
# uncomputation.
#
# Ground truth: Berry, Gidney, Motta, McClean, Babbush (2019) arXiv:1902.02134,
# "Qubitization of arbitrary basis quantum chemistry leveraging sparsity and
# low rank factorization", Appendix C, Figs 6 + 8.
# docs/physics/berry_gidney_motta_mcclean_babbush_2019_qubitization.pdf
#
# `_binary_to_unary!` is the controlled-swap cascade (Fig 8) that converts a
# binary address `addr::QInt{Wlo}` into a one-hot unary encoding on
# K = 2^Wlo ancillae. `_fredkin!` is the efficient CSWAP (1 Toffoli + 2 CNOTs
# per CSWAP, as opposed to the naive 3-Toffoli decomposition of
# `when(ctrl) do swap! end`).
# ═══════════════════════════════════════════════════════════════════════════

"""
    _fredkin!(ctrl::QBool, a::QBool, b::QBool)

Controlled-SWAP (Fredkin gate): swap `a` and `b` iff `ctrl = |1⟩`.
Decomposition: `CNOT(b,a); CCX(ctrl,a,b); CNOT(b,a)` — 1 Toffoli + 2 CNOTs,
same as Nielsen-Chuang §4.3 and Berry et al. 2019 arXiv:1902.02134 App C.
The naive spelling `when(ctrl) do swap!(a, b) end` expands to 3 Toffolis
because `swap!` is 3 CNOTs each lifted to CCX under the control; this
helper avoids that overhead.
"""
@inline function _fredkin!(ctrl::QBool, a::QBool, b::QBool)
    a ⊻= b
    when(ctrl) do
        b ⊻= a
    end
    a ⊻= b
    return nothing
end

"""
    _binary_to_unary!(addr::QInt{Wlo}, anc::NTuple{K, QBool}; uncompute::Bool=false)

Controlled-swap cascade that converts the binary value in `addr` into a one-
hot unary encoding on `anc`, where `K = 2^Wlo`. Implements Berry et al. 2019
arXiv:1902.02134 Appendix C Fig 8.

# Preconditions
  * `K == 1 << Wlo`.
  * `anc[1]` in `|1⟩`, `anc[2..K]` all in `|0⟩` (one-hot seeded at position 0).
  * All qubits share the same context as `addr`.

# Postcondition
For every basis state `|x⟩` of `addr`, `anc[x+1]` holds `|1⟩` and every other
`anc[j]` holds `|0⟩` — a one-hot encoding of `addr` on the `anc` register.

# Uncompute
`_binary_to_unary!(addr, anc; uncompute=true)` reverses the cascade by
traversing address bits from high to low. The forward + uncompute pair is
exact identity on the joint state (not approximate — every Fredkin is self-
inverse and b-levels with disjoint targets commute within themselves).

# Cost
`K − 1` Fredkin gates = `K − 1` Toffoli + `2(K − 1)` CNOTs. No extra
workspace ancillae.

# Reference
  Berry, Gidney, Motta, McClean, Babbush (2019) arXiv:1902.02134, App C,
  Fig 6 (clean-ancilla uncompute pipeline) and Fig 8 (explicit Fredkin
  cascade, here for 3→8 bits).
"""
function _binary_to_unary!(addr::QInt{Wlo},
                            anc::NTuple{K, QBool};
                            uncompute::Bool=false) where {Wlo, K}
    K == 1 << Wlo ||
        error("_binary_to_unary!: K ($K) must equal 2^Wlo ($(1 << Wlo))")
    ctx = addr.ctx
    b_range = uncompute ? reverse(0:(Wlo - 1)) : (0:(Wlo - 1))
    for b in b_range
        ctrl_wire = addr.wires[b + 1]
        for j in 0:((1 << b) - 1)
            ctrl = QBool(ctrl_wire, ctx, false)
            _fredkin!(ctrl, anc[j + 1], anc[j + 1 + (1 << b)])
        end
    end
    return nothing
end
