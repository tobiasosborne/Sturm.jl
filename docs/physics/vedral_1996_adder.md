# Quantum Networks for Elementary Arithmetic Operations

Source: Vedral, Barenco, Ekert, *Phys. Rev. A* 54, 147 (1996).
arXiv:quant-ph/9511018v1, 16 Nov 1995. PDF in
`docs/physics/vedral_barenco_ekert_1996_arith.pdf`.

This is the foundational paper for in-place quantum integer arithmetic
on registers with explicit carry handling. Sturm.jl's `QInt{W}` ripple-
carry adder follows the §III.A construction directly.

## In-place plain adder (Eqs. 8 and 9)

The paper defines two flavours:

  Eq. 8 (out-of-place):  |a, b, 0⟩ → |a, b, a+b⟩
  Eq. 9 (in-place):       |a, b⟩   → |a, a+b⟩

Sturm uses Eq. 9 — the in-place form — because there is no information
loss (the input `(a, b)` is recoverable from the output `(a, a+b)`), so
the operation is straightforwardly reversible without a third register.
For overflow safety the second register must have one more qubit than
the first when both `a` and `b` are encoded on `n` qubits: the second is
of size `n+1`. The construction also uses an `n-1` qubit *temporary
carry register* initialised to `|0⟩` and uncomputed back to `|0⟩` at the
end of the operation.

## Carry / sum recurrences (§III.A)

The two arithmetic primitives that drive the network are:

  Carry:  c_i ← a_i AND b_i AND c_{i-1}     (Toffoli-controlled write)
  Sum:    b_i ← a_i XOR b_i XOR c_{i-1}     (two CNOTs into b_i)

Specifically the network proceeds in two phases:

  1. **Forward carry**: For i = 1..n compute c_i from a_i, b_i, c_{i-1}.
     The most-significant carry c_n becomes the high bit of a+b and is
     written into the (n+1)-th qubit of the second register.

  2. **Reverse uncompute + sum**: For i = n-1 down to 0, reverse the
     carry computation (returns the temporary register to |0⟩) and
     simultaneously emit the sum bit b_i ← a_i XOR b_i XOR c_{i-1}.

The reverse-and-sum interleaving is what restores the temporary carry
register to |0⟩ for reuse in subsequent operations (e.g., repeated
modular addition inside controlled multiplication, §III.C).

## Subtraction by reverse running (§III.A)

Running the same network *in reverse order* with input |a, b⟩ produces
|a, b - a⟩ when b ≥ a. When b < a, the output is `(a, 2^{n+1} - (a-b))`
— two's-complement underflow with the most-significant qubit of the
second register set to 1. Sturm uses this *overflow bit* as the
arithmetic-comparison primitive: testing whether `a > b` reduces to
running subtraction and inspecting the high bit.

## Adder modulo N (§III.B, Eq. 10)

The mod-N variant chains:

  1. plain adder (a, b) → (a, a+b)
  2. swap second register with a temporary loaded with N
  3. subtractor (= reversed plain adder) (N, a+b) → (N, a+b-N) — high
     bit of second register flags overflow, conditionally signalling
     whether a+b ≥ N
  4. CNOT high bit of (a+b-N) into a fresh ancilla |t⟩ — captures the
     overflow flag
  5. controlled (on |t⟩) re-add of N to undo the subtraction when
     a+b < N (no overflow), leaving the second register holding
     a+b mod N
  6. swap-back, then run a second subtractor cycle to reset |t⟩ to |0⟩

The temporary qubit |t⟩ MUST be reset because subsequent modular
additions would entangle with it. The §III.B network costs 2 plain-add
+ 2 plain-sub + a few CNOTs/Toffoli; resource scaling is O(n).

## Resource summary (§IV, total at the end)

Plain adder uses an extra `n-1`-qubit carry register.
Modular adder adds one more `n`-qubit (N-storage) and a single |t⟩.
Controlled multiplier modulo N (§III.C) chains n modular adders.
Modular exponentiation (§III.D) chains m controlled multipliers.

Total qubits for `a^x mod N` with N up to 2^n: **7n + 1** with the
direct construction, reducible to **5n + 2** by classicalising the
N-register (since it always holds a known constant). The point of the
paper is that this overhead is **linear** in n — not quadratic, not
exponential — so the modular-exponentiation step in Shor (the dominant
cost in the algorithm) is feasible.

## Sturm.jl mapping

Sturm.jl's `QInt{W}` ripple-carry adder (`src/types/qint.jl`,
`Base.:+(::QInt{W}, ::QInt{W}) where {W}`) implements Eq. 9 with the
forward-carry / reverse-and-sum interleaving from §III.A. Each carry
gate is a Toffoli (three-qubit `when(a) when(b) do not!(c) end` in the
DSL); each sum bit is two CNOTs (`b ⊻= a; b ⊻= c`). The temporary carry
register is allocated/freed inside the adder and is invisible to the
caller.

The mod-N adder lives in `src/library/arithmetic.jl` (`add_mod!` and
friends). The Beauregard 2L+4 Shor implementation in
`src/library/shor.jl` builds on Vedral §III.D (modular exponentiation
by repeated controlled-modular-multiplication) but uses the QFT-domain
adder of Draper 2000 instead of Vedral's plain-adder for in-circuit
classical-quantum addition.
