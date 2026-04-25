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
                                  ctrls::Tuple = (),
                                  mbu::Bool = false,
                                  mbu_compute::Bool = false) where {W, Cpad, Wtot, Ly}
    check_live!(target); check_live!(y)
    target.reg.ctx === y.ctx ||
        error("plus_equal_product_mod!: target and y must share a context")
    window >= 1 || error("plus_equal_product_mod!: window must be ≥ 1, got $window")
    window <= Ly ||
        error("plus_equal_product_mod!: window=$window exceeds Ly=$Ly")
    Ly < 62 ||
        error("plus_equal_product_mod!: Ly=$Ly exceeds 2^i arithmetic margin (max 61)")
    # Berry App B forward (mbu_compute) consumes the kM scratch via App C
    # X-basis measurement — there is no naive XOR-undo path for the kM-wide
    # post-state, so the matching reverse must be measurement-based. Force
    # mbu=true when mbu_compute=true rather than silently flip it.
    if mbu_compute && !mbu
        error("plus_equal_product_mod!: mbu_compute=true requires mbu=true " *
              "(the App B forward post-state is consumed via App C X-basis " *
              "measurement; no naive XOR uncompute exists)")
    end
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
    #
    # mbu=true swaps the QROM reverse for Berry et al. 2019 measurement-based
    # uncomputation: bead Sturm.jl-9ij. Changes the reverse cost from
    # 2^w − 1 to ⌈2^w/k⌉ + k Toffoli ≈ 2√(2^w), at the cost of
    # 2^⌈w/2⌉ temporary ancillae per iteration. Orthogonal to `ctrls`.
    #
    # mbu_compute=true additionally swaps the FORWARD QROM for Berry et al.
    # 2019 App B Theorem 2 clean-ancilla compute (bead Sturm.jl-vbz). Forward
    # cost goes from 4·(2^w - 1) (Bennett-compiled qrom_lookup_xor!) to
    # 4·(2^Whi - 1) + Wtot·(k_b - 1) where k_b is the App B compression
    # factor (default 2 — see _pep_mod_iter!). Falls back to plain mbu when
    # the iteration's window is too small (w < 2) or the kM stacked table
    # overflows UInt64 (k_b · Wtot > 64).
    i = 0
    while i < Ly
        w = min(window, Ly - i)
        _pep_mod_iter!(target, k_mod_N, y, i, Val(w), N, ctrls, mbu, mbu_compute)
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
                                  ctrls::Tuple,
                                  mbu::Bool,
                                  mbu_compute::Bool) where {W, Cpad, Wtot, Ly, w}
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

    # Pick the App B compression factor k_b ∈ {2, 4, 8, …} that minimises the
    # analytical Sturm forward Toffoli cost
    #     cost(k) = 4·(2^(w − log₂k) − 1) + Wtot·(k − 1)         (k_b ≥ 2)
    #     cost(1) = 4·(2^w − 1)                                  (no App B)
    # subject to the storage cap k·Wtot ≤ 64. The 4× factor is Sturm's
    # Bennett-compile overhead on the inner lookup vs the raw Babbush-Gidney
    # unary iteration the Berry paper assumes (see `bd memories
    # app-b-vs-bennett-overhead`). Falls back to no-App-B when nothing wins.
    k_b = 1
    if mbu_compute && w >= 2
        no_app_b_cost = 4 * ((1 << w) - 1)
        best_cost = no_app_b_cost
        kk = 2
        while kk * Wtot <= 64 && kk < (1 << w)
            whi = w - trailing_zeros(kk)
            cost = 4 * ((1 << whi) - 1) + Wtot * (kk - 1)
            if cost < best_cost
                best_cost = cost
                k_b = kk
            end
            kk <<= 1
        end
    end
    use_app_b = k_b >= 2

    if use_app_b
        kM = k_b * Wtot
        scratch_full = QInt{kM}(0)
        qrom_lookup_xor_cleanancilla!(scratch_full, y_win, tbl; k=k_b)

        # Non-owning view of the first Wtot wires — these hold T[y_win] per
        # App B Theorem 2's "position 0 = f(addr)". The QFT-add only sees
        # the M-qubit slice; the other (k_b - 1)·Wtot wires of scratch_full
        # hold permuted other table entries that get consumed by the
        # matching App C measurement-based reverse below.
        scratch_view_wires = ntuple(j -> scratch_full.wires[j], Val(Wtot))
        scratch_view = QInt{Wtot}(scratch_view_wires, ctx, false)

        superpose!(target.reg)
        _apply_ctrls(ctrls) do
            add_qft_quantum!(target.reg, scratch_view)
        end
        interfere!(target.reg)

        qrom_lookup_uncompute_meas_cleanancilla!(scratch_full, y_win, tbl; k=k_b)
        return nothing
    end

    scratch = QInt{Wtot}(0)
    qrom_lookup_xor!(scratch, y_win, tbl)        # unconditional — scratch = T[y_win]

    superpose!(target.reg)                       # unconditional
    _apply_ctrls(ctrls) do                       # only the add is controlled
        add_qft_quantum!(target.reg, scratch)
    end
    interfere!(target.reg)                       # unconditional

    if mbu
        # Berry et al. 2019 measurement-based uncompute: ⌈2^w/k⌉ + k Toffoli
        # (vs 2^w − 1 for the naive re-lookup). Consumes scratch via X-basis
        # measurement; no ptrace needed — scratch wires are gone.
        qrom_lookup_uncompute_meas!(scratch, y_win, tbl)
    else
        qrom_lookup_xor!(scratch, y_win, tbl)    # unconditional — scratch → |0⟩
        ptrace!(scratch)
    end
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

# ═══════════════════════════════════════════════════════════════════════════
# Sturm.jl-9ij Stage 2 — measurement-based QROM uncomputation.
#
# Ground truth: Berry et al. 2019 arXiv:1902.02134, Appendix C, Theorem 3
# (Eq. 67) and Fig 6 (clean-ancilla version).
#
# Contract (channel acting on addr ⊗ scratch ⊗ environment):
#   pre :  Σ_x α_x |x⟩_addr ⊗ |T[x]⟩_scratch ⊗ |rest⟩
#   post:  Σ_x α_x |x⟩_addr ⊗ |rest⟩                    (up to global phase)
#
# The forward `qrom_lookup_xor!` puts scratch in |T[addr]⟩; this function
# consumes scratch via X-basis measurement and applies a classically-
# conditioned phase fixup to addr that cancels the random per-basis-state
# phase induced by the measurement, restoring the addr marginal exactly
# (up to a shot-dependent GLOBAL phase, which is unobservable).
#
# Toffoli cost: ⌈d/k⌉ + k per Berry Thm 3, minimised at k ≈ √d. For d = 2^Win
# and k = 2^Wlo with Wlo = ⌈Win/2⌉, cost ≈ 2√d. At c_mul=5 (Win=5, d=32,
# Wlo=3, k=8): 4 + 8 = 12 Toffoli, vs 62 for the naive reverse lookup.
# ═══════════════════════════════════════════════════════════════════════════

"""
    qrom_lookup_uncompute_meas!(scratch::QInt{Wtot}, addr::QInt{Win},
                                tbl::QROMTable{Win, Wtot, Nentries}) -> nothing

Measurement-based uncomputation of a QROM read `scratch ← T[addr]`. Consumes
`scratch` via X-basis measurement and applies a classically-conditioned
phase fixup to `addr` so that the combined `qrom_lookup_xor!` +
`qrom_lookup_uncompute_meas!` pair is the identity on `addr` up to a shot-
dependent global phase.

# Cost
`⌈2^Win / k⌉ + k` Toffoli for k = 2^Wlo with Wlo = ⌈Win/2⌉. Optimal ≈ 2·√(2^Win).
Additional O(log k) ancillae from `qrom_lookup_xor!` on the fixup table.

# Preconditions
  * Same context for `scratch`, `addr`, and `tbl`.
  * `scratch` must currently hold `|T[addr]⟩` (i.e., the partner
    `qrom_lookup_xor!(scratch, addr, tbl)` was called immediately prior).

# Postconditions
  * `scratch` is consumed (wires deallocated via measurement).
  * `addr` is left in its pre-forward-lookup state up to a shot-
    dependent GLOBAL phase.

# Reference
  Berry, Gidney, Motta, McClean, Babbush (2019), "Qubitization of arbitrary
  basis quantum chemistry leveraging sparsity and low rank factorization",
  arXiv:1902.02134, Appendix C, Theorem 3 (Eq. 67) and Figs 6 + 8.
  `docs/physics/berry_gidney_motta_mcclean_babbush_2019_qubitization.pdf`
"""
function qrom_lookup_uncompute_meas!(scratch::QInt{Wtot},
                                      addr::QInt{Win},
                                      tbl::QROMTable{Win, Wtot, Nentries}
                                      ) where {Wtot, Win, Nentries}
    check_live!(scratch); check_live!(addr)
    scratch.ctx === addr.ctx ||
        error("qrom_lookup_uncompute_meas!: scratch and addr must share a context")
    ctx = scratch.ctx

    # ── Step 1: X-basis measure scratch, collecting m ∈ {0,1}^Wtot ──────────
    #
    # TracingContext dispatch: `Bool(q)` errors inside tracing (the outcome is
    # a placeholder, branching on it would mis-trace). For Toffoli-count
    # benchmarks we emit the same H on each scratch wire (same 0 Toffoli as
    # the real path), ptrace! scratch, and unconditionally execute the
    # fixup circuit with a canonical all-ones phase_bits pattern. The circuit
    # structure — hence the Toffoli count — is identical to any shot of the
    # real MBU path (Berry Thm 3 cost depends only on Win, not on the phase
    # pattern). `m_word = 0` is a sentinel that triggers the trace branch.
    is_tracing = ctx isa TracingContext
    m_word = UInt64(0)
    if is_tracing
        for j in 1:Wtot
            H!(QBool(scratch.wires[j], ctx, false))
        end
        ptrace!(scratch)
    else
        for j in 1:Wtot
            m_qb = QBool(scratch.wires[j], ctx, false)
            H!(m_qb)                         # X-basis rotation: H · Z · H = X
            bit = Bool(m_qb)                 # computational-basis measure, consumes wire
            bit && (m_word |= UInt64(1) << (j - 1))
        end
        scratch.consumed = true              # all wires gone — mark scratch dead
    end

    # ── Step 2: classical phase_bits[x] = parity(m · T[x]) ─────────────────
    n_entries = 1 << Win
    any_flip = is_tracing  # force fixup emission in trace mode
    phase_bits = Vector{Bool}(undef, n_entries)
    if is_tracing
        fill!(phase_bits, true)              # canonical all-ones for trace
    else
        @inbounds for x in 0:(n_entries - 1)
            pb = isodd(count_ones(m_word & tbl.data[x + 1]))
            phase_bits[x + 1] = pb
            any_flip |= pb
        end
    end

    # No-op fast path: measurement outcome happens to yield identity fixup.
    any_flip || return nothing

    # ── Step 3: phase fixup on addr ────────────────────────────────────────
    if Win == 1
        # Berry Thm 3 requires 1 < k < d = 2; no valid k exists. Direct fixup:
        # phase_bits[1] = phase on |0⟩, phase_bits[2] = phase on |1⟩.
        # Up to a global phase that is unobservable, only the RELATIVE phase
        # matters; apply Z (= Rz(π)) iff the bits differ.
        if phase_bits[1] != phase_bits[2]
            Z!(QBool(addr.wires[1], ctx, false))
        end
        return nothing
    end

    # General Win ≥ 2: split-address fixup per Berry Fig 6.
    Wlo = cld(Win, 2)                        # ⌈Win/2⌉
    Whi = Win - Wlo
    K = 1 << Wlo
    n_hi = 1 << Whi

    # Allocate K clean ancillae; seed with |1⟩ at position 0.
    anc_list = [QBool(ctx, 0.0) for _ in 1:K]
    X!(anc_list[1])
    anc = tuple(anc_list...)

    # Views onto addr's low and high slices.
    addr_lo_wires = ntuple(i -> addr.wires[i], Val(Wlo))
    addr_hi_wires = ntuple(i -> addr.wires[Wlo + i], Val(Whi))
    addr_lo = QInt{Wlo}(addr_lo_wires, ctx, false)
    addr_hi = QInt{Whi}(addr_hi_wires, ctx, false)

    # Forward binary→unary cascade.
    _binary_to_unary!(addr_lo, anc)

    # H-sandwich: maps phase-flip on ancilla → bit-flip on ancilla.
    for a in anc; H!(a); end

    # Classically compute the fixup table: entry h has bit j = phase_bits[h*K + j + 1].
    fixup_entries = Vector{UInt64}(undef, n_hi)
    @inbounds for h in 0:(n_hi - 1)
        word = UInt64(0)
        for j in 0:(K - 1)
            phase_bits[h * K + j + 1] && (word |= UInt64(1) << j)
        end
        fixup_entries[h + 1] = word
    end
    fixup_tbl = QROMTable{Whi, K}(fixup_entries)

    # XOR the fixup table into the unary ancillae.
    anc_wires = ntuple(i -> anc[i].wire, Val(K))
    anc_qint = QInt{K}(anc_wires, ctx, false)
    qrom_lookup_xor!(anc_qint, addr_hi, fixup_tbl)

    # Close the H-sandwich.
    for a in anc; H!(a); end

    # Reverse binary→unary cascade.
    _binary_to_unary!(addr_lo, anc; uncompute=true)

    # Ancillae back to |1, 0, 0, ..., 0⟩ → |0, 0, ..., 0⟩; release.
    X!(anc[1])
    for a in anc; ptrace!(a); end

    return nothing
end

# ═══════════════════════════════════════════════════════════════════════════
# Sturm.jl-vbz Phase D4 — clean-ancilla forward QROM compute.
#
# Ground truth: Berry, Gidney, Motta, McClean, Babbush (2019) arXiv:1902.02134,
# "Qubitization of arbitrary basis quantum chemistry leveraging sparsity and
# low rank factorization", Appendix B Theorem 2 (Eq. 66).
# docs/physics/berry_gidney_motta_mcclean_babbush_2019_qubitization.pdf
#
# Pairs with the App C measurement-based uncompute already shipped in 9ij to
# give a sqrt-Toffoli pair: forward ⌈d/k⌉ + M(k-1), reverse ⌈d/k⌉ + k.
#
# Note (vbz memory): Berry's forward count assumes a unit-cost-per-entry
# table lookup (raw Babbush-Gidney unary iteration). Sturm's
# `qrom_lookup_xor!` is Bennett-compiled and carries a 4× overhead, so the
# practical Sturm App B forward cost is `4·(2^Whi - 1) + M·(k-1)` vs the
# original `4·(2^Win - 1)`. The headline saving at k=2 is ~25%, not the
# ~70% the bare Berry count implies. See `bd memories app-b-vs-bennett-overhead`.
# ═══════════════════════════════════════════════════════════════════════════

"""
    _app_b_sigma_perm(l::Integer, i::Integer, c::Integer) -> Int

Classical model of the σ_l permutation produced by the App B "swap subroutine
S": after `S` is applied to k = 2^c registers controlled by the bottom log k
bits of address (= `l`), position `i` holds the data that was originally at
position `σ_l(i)`. So if before S we lookup the high address `h` and store
`f(h·k + j)` at position `j`, then after S, position `i` holds
`f(h·k + σ_l(i))` and in particular position 0 holds `f(h·k + l) = f(j)`
where `j = h·k + l`.

The descending-tree pair-block-swap construction: at level p ∈ {c-1, …, 0}
(high bit first), if bit p of `l` is set, swap pairs at distance 2^p within
the leading 2^(p+1) positions. Position `i` is touched by level p iff
`i < 2^(p+1)`, i.e., for all p ≥ highest-set-bit(i). Therefore

    σ_l(i) = i ⊻ (l & mask_i),
    mask_i = ~((1 << h_i) - 1) & (k - 1)
    h_i = floor(log_2 i)        (with the convention h_0 = -1 so mask_0 = k-1)

For `i = 0` the formula collapses to `σ_l(0) = l`, recovering r_l → r_0.

Pure classical helper — no quantum operations.
"""
function _app_b_sigma_perm(l::Integer, i::Integer, c::Integer)::Int
    c >= 1 || error("_app_b_sigma_perm: c must be ≥ 1, got $c")
    i_int = Int(i); l_int = Int(l)
    k = 1 << c
    (0 <= i_int < k) || error("_app_b_sigma_perm: i=$i_int outside [0, $k)")
    (0 <= l_int < k) || error("_app_b_sigma_perm: l=$l_int outside [0, $k)")
    if i_int == 0
        return l_int   # h_0 ≡ -1 ⇒ mask is all c bits ⇒ σ_l(0) = l
    end
    # h_i = highest set bit position (0-indexed). For Int64 / UInt: 8·8 - 1 - leading_zeros.
    h_i = 8 * sizeof(Int) - 1 - leading_zeros(i_int)
    mask = ~((1 << h_i) - 1) & (k - 1)
    return i_int ⊻ (l_int & mask)
end

"""
    _app_b_swap_cascade!(scratch_full::QInt{N}, addr_lo::QInt{Wlo}, M::Int)

In-place pair-block-swap cascade on the kM-qubit scratch register, controlled
on the log k bits of `addr_lo`. Implements the App B swap subroutine S:
after the cascade, the M-qubit block at position 0 holds whatever was at
position `Int(addr_lo)` before the cascade.

Cost: M·(k-1) Toffoli + 2M·(k-1) CNOT, where k = 2^Wlo. The swap order
is high-bit-first (descending p ∈ {Wlo-1, …, 0}); at each level p, swap
register pairs at distance 2^p within the leading 2^(p+1) registers.

Self-inverse: the same cascade applied a second time undoes the first
(Fredkin is self-inverse, and the level order is symmetric — high-then-low
mirrors low-then-high since each level commutes with itself).
"""
function _app_b_swap_cascade!(scratch_full::QInt{N},
                                addr_lo::QInt{Wlo},
                                M::Integer) where {N, Wlo}
    check_live!(scratch_full); check_live!(addr_lo)
    scratch_full.ctx === addr_lo.ctx ||
        error("_app_b_swap_cascade!: scratch_full and addr_lo must share a context")
    M_int = Int(M)
    k = 1 << Wlo
    N == k * M_int ||
        error("_app_b_swap_cascade!: N=$N must equal k·M = $(k*M_int) (k=2^Wlo=$k, M=$M_int)")
    ctx = scratch_full.ctx

    # Descending tree: high bit first. At level p ∈ {Wlo-1, …, 0}, conditional
    # on bit p of addr_lo, swap register pairs at distance 2^p within the
    # leading 2^(p+1) registers. Each register is M qubits; each register-
    # level swap is M Fredkins.
    for p in (Wlo - 1):-1:0
        ctrl_wire = addr_lo.wires[p + 1]
        block_size = 1 << p          # = number of pairs at this level
        for j in 0:(block_size - 1)
            base_a = j * M_int
            base_b = (j + block_size) * M_int
            for m in 1:M_int
                ctrl = QBool(ctrl_wire,                ctx, false)
                a    = QBool(scratch_full.wires[base_a + m], ctx, false)
                b    = QBool(scratch_full.wires[base_b + m], ctx, false)
                _fredkin!(ctrl, a, b)
            end
        end
    end
    return nothing
end

"""
    _stacked_permuted_table(tbl::QROMTable{Win, M, NumEntries}, k::Integer)
        -> Vector{UInt64}

Classical preprocessor: build the d-entry kM-bit table whose entry j is the
kM-bit concatenation matching `scratch_full` at the end of the App B
forward primitive when called at address `j`. Used by
`qrom_lookup_uncompute_meas_cleanancilla!` to phase-fix `addr` against the
right effective lookup value.

For each address `j` ∈ [0, d) with `l = j mod k`, `h = j div k`, the stacked
entry packs `tbl[h·k + σ_l(i)]` into bits `[i·M, (i+1)·M)` for i ∈ [0, k).
Bit i·M of position 0 holds `tbl[j]`'s LSB (the user-visible f(j)).

Returns `Vector{UInt64}` (length d, each element a kM-bit packed value).
"""
function _stacked_permuted_table(tbl::QROMTable{Win, M, NumEntries},
                                  k::Integer
                                  )::Vector{UInt64} where {Win, M, NumEntries}
    k_int = Int(k)
    k_int >= 2 && (k_int & (k_int - 1)) == 0 ||
        error("_stacked_permuted_table: k=$k_int must be a power of 2 ≥ 2")
    c = trailing_zeros(k_int)
    c < Win || error(
        "_stacked_permuted_table: k=$k_int (= 2^$c) must satisfy k < 2^Win=2^$Win")
    kM = k_int * M
    kM <= 64 || error(
        "_stacked_permuted_table: k·M=$kM exceeds the UInt64 storage limit (64). " *
        "Reduce k or M (or extend to UInt128 if a future caller needs it).")
    d = NumEntries
    block_mask = (UInt64(1) << M) - UInt64(1)
    out = Vector{UInt64}(undef, d)
    @inbounds for j in 0:(d - 1)
        l = j & (k_int - 1)
        h = j >> c
        word = UInt64(0)
        for i in 0:(k_int - 1)
            src_idx = h * k_int + _app_b_sigma_perm(l, i, c)
            entry = tbl.data[src_idx + 1] & block_mask
            word |= entry << (i * M)
        end
        out[j + 1] = word
    end
    return out
end

"""
    qrom_lookup_xor_cleanancilla!(scratch_full::QInt{N}, addr::QInt{Win},
                                    tbl::QROMTable{Win, M, NumEntries};
                                    k::Int) -> scratch_full

Berry et al. 2019 App B Thm 2 (Eq. 66) clean-ancilla forward QROM compute.
Allocates `scratch_full` of width `N = k·M` (caller-owned), and after
return: bits `[0, M)` of `scratch_full` hold `tbl[Int(addr)]`; bits
`[M, kM)` hold permuted other table entries (specifically
`tbl[h·k + σ_l(i)]` at bit-block `i` for i ∈ [1, k)). The "other" bits are
NOT zeroed — they are consumed by the matching
[`qrom_lookup_uncompute_meas_cleanancilla!`](@ref) reverse call.

# Cost
`⌈2^Win/k⌉ + M·(k − 1)` Toffoli (Berry Eq. 66 abstract count). Sturm's
inner lookup is Bennett-compiled with a 4× overhead vs raw Babbush-Gidney
unary iteration, so the practical Toffoli count is
`4·(2^Whi − 1) + M·(k − 1)` with `Whi = Win − log₂ k`.

# Preconditions (fail-loud per Rule 1)
  * `k` is a power of 2 with `1 < k < 2^Win`.
  * `N == k·M`.
  * `k·M ≤ 64` (UInt64 storage limit on the stacked table entries).
  * `scratch_full`, `addr`, and `tbl` share a context.
  * `scratch_full` initial state is `|0⟩^N`.

# References
  * Berry, Gidney, Motta, McClean, Babbush (2019), "Qubitization of arbitrary
    basis quantum chemistry leveraging sparsity and low rank factorization",
    arXiv:1902.02134, Appendix B Thm 2 (Eq. 66).
  * Procedure described p. 25; the matching figure (Fig 4) shows the
    *dirty*-ancilla App A variant. App B is described in text only.
"""
function qrom_lookup_xor_cleanancilla!(scratch_full::QInt{N},
                                         addr::QInt{Win},
                                         tbl::QROMTable{Win, M, NumEntries};
                                         k::Int
                                         ) where {N, Win, M, NumEntries}
    check_live!(scratch_full); check_live!(addr)
    scratch_full.ctx === addr.ctx ||
        error("qrom_lookup_xor_cleanancilla!: scratch_full and addr must share a context")
    k >= 2 && (k & (k - 1)) == 0 ||
        error("qrom_lookup_xor_cleanancilla!: k=$k must be a power of 2 ≥ 2")
    Wlo = trailing_zeros(k)
    Wlo < Win ||
        error("qrom_lookup_xor_cleanancilla!: k=$k (= 2^$Wlo) must satisfy k < 2^Win = 2^$Win")
    Whi = Win - Wlo
    N == k * M ||
        error("qrom_lookup_xor_cleanancilla!: scratch_full width N=$N must equal k·M=$(k*M) " *
              "(k=$k, M=$M)")
    kM = k * M
    kM <= 64 ||
        error("qrom_lookup_xor_cleanancilla!: k·M=$kM exceeds 64-bit table-entry storage. " *
              "Reduce k or M.")
    ctx = scratch_full.ctx
    n_h = 1 << Whi

    # ── Step 1: build the stacked table T_stacked indexed by h.
    # T_stacked[h] has bits [i·M, (i+1)·M) = tbl[h·k + i] for i ∈ [0, k).
    # This is a one-shot classical preprocessing — no quantum ops yet.
    block_mask = (UInt64(1) << M) - UInt64(1)
    stacked_entries = Vector{UInt64}(undef, n_h)
    @inbounds for h in 0:(n_h - 1)
        word = UInt64(0)
        for i in 0:(k - 1)
            entry = tbl.data[h * k + i + 1] & block_mask
            word |= entry << (i * M)
        end
        stacked_entries[h + 1] = word
    end
    tbl_stacked = QROMTable{Whi, kM}(collect(Int, stacked_entries))

    # Non-owning view of addr's high bits (top Whi qubits) and low bits.
    addr_hi_wires = ntuple(i -> addr.wires[Wlo + i], Val(Whi))
    addr_hi = QInt{Whi}(addr_hi_wires, ctx, false)
    addr_lo_wires = ntuple(i -> addr.wires[i], Val(Wlo))
    addr_lo = QInt{Wlo}(addr_lo_wires, ctx, false)

    # ── Step 2: T — single lookup at addr_hi targeting all kM scratch bits.
    qrom_lookup_xor!(scratch_full, addr_hi, tbl_stacked)

    # ── Step 3: S — pair-block-swap cascade controlled on addr_lo.
    _app_b_swap_cascade!(scratch_full, addr_lo, M)

    return scratch_full
end

"""
    qrom_lookup_uncompute_meas_cleanancilla!(scratch_full::QInt{N},
                                              addr::QInt{Win},
                                              tbl::QROMTable{Win, M, NumEntries};
                                              k::Int) -> nothing

Matching reverse for [`qrom_lookup_xor_cleanancilla!`](@ref). X-basis
measures all `kM` wires of `scratch_full`, applies an addr phase fixup
against the σ_l-permuted stacked table so the joint forward+reverse pair
is identity on `addr` (up to a shot-dependent global phase). Internally
delegates to `qrom_lookup_uncompute_meas!` with the stacked table.

# Cost
`⌈2^Win/k_inner⌉ + k_inner ≈ 2·√(2^Win)` Toffoli for the App C clean-
ancilla phase fixup with optimal `k_inner = 2^⌈Win/2⌉`.

# Preconditions
  Same as `qrom_lookup_xor_cleanancilla!` plus `scratch_full` must currently
  hold the App B forward post-state (i.e., the partner forward call was
  immediately prior, with the same `addr`, `tbl`, and `k`).

# Postconditions
  * `scratch_full` is consumed (all wires deallocated via measurement).
  * `addr` is left in its pre-forward state up to a shot-dependent global
    phase.
"""
function qrom_lookup_uncompute_meas_cleanancilla!(scratch_full::QInt{N},
                                                    addr::QInt{Win},
                                                    tbl::QROMTable{Win, M, NumEntries};
                                                    k::Int
                                                    ) where {N, Win, M, NumEntries}
    check_live!(scratch_full); check_live!(addr)
    scratch_full.ctx === addr.ctx ||
        error("qrom_lookup_uncompute_meas_cleanancilla!: scratch_full and addr must share a context")
    k >= 2 && (k & (k - 1)) == 0 ||
        error("qrom_lookup_uncompute_meas_cleanancilla!: k=$k must be a power of 2 ≥ 2")
    Wlo = trailing_zeros(k)
    Wlo < Win ||
        error("qrom_lookup_uncompute_meas_cleanancilla!: k=$k (= 2^$Wlo) must satisfy k < 2^Win = 2^$Win")
    N == k * M ||
        error("qrom_lookup_uncompute_meas_cleanancilla!: scratch_full width N=$N must equal k·M=$(k*M) " *
              "(k=$k, M=$M)")
    kM = k * M
    kM <= 64 ||
        error("qrom_lookup_uncompute_meas_cleanancilla!: k·M=$kM exceeds 64-bit table-entry storage.")

    # Build the σ-permuted stacked table indexed by FULL addr j ∈ [0, 2^Win).
    # Entry j at bit-block i holds tbl[h·k + σ_l(i)] where h = j÷k, l = j mod k.
    # This is the kM-bit value of `scratch_full` after the App B forward call
    # at address j; X-measuring against this table is exactly the App C
    # uncompute pattern (already implemented for arbitrary table widths).
    stacked_perm = _stacked_permuted_table(tbl, k)
    tbl_eff = QROMTable{Win, kM}(collect(Int, stacked_perm))

    # Delegate to the existing measurement-based uncompute. It X-measures
    # all `kM` wires of `scratch_full`, computes phase_bits[j] = parity(m &
    # tbl_eff[j]), and applies the App C clean-ancilla phase fixup to addr.
    qrom_lookup_uncompute_meas!(scratch_full, addr, tbl_eff)

    return nothing
end
