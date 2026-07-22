# M9 design proposal — full-space `mulmod!`, in-place permutation compilation, and correct `shor_order`

**Bead:** `Sturm.jl-addq`  
**Findings closed:** F7, F22, F23, F24  
**Decision summary:**

- `mulmod!` is the full-space permutation \(v\mapsto cv\bmod N\) below \(N\), identity on the padded tail.
- A new Bennett-backed `CompiledInplacePerm` contract composes forward accumulate, register swap, and inverse accumulate into one kernel `Perm`.
- Both the forward function and its inverse compile eagerly; inverse agreement is proved before any quantum action.
- `shor_order` becomes a bounded repeated-sampling driver with exact continued fractions, LCM accumulation, modular verification, and exact order minimization.
- `Int(x)` remains an honest machine `Int` cast and fails before measurement when the width cannot fit; `BigInt(x)` is the wide consuming cast.
- The modulus remains a type parameter. The public entry becomes `shor_order(a, ::Val{N}; ...)`, and `QMod{N}` has no runtime modulus field.

---

## 1. Correct `mulmod!` semantics

Let

\[
W=\lceil\log_2 N\rceil,\qquad
S_W=\{0,\ldots,2^W-1\},
\]

with \(N\ge2\). For an integer multiplier \(c\), normalize

\[
\bar c = c\bmod N.
\]

The surface action has the signature

```julia
mulmod!(y::QMod{N,W,C}, c::Integer)::QMod{N,W,C}
```

and denotes the permutation \(\pi_{\bar c,N}:S_W\to S_W\),

\[
\pi_{\bar c,N}(v)=
\begin{cases}
\bar c\,v\bmod N, & 0\le v<N,\\
v,                 & N\le v<2^W.
\end{cases}
\tag{1}
\]

The logical `QMod{N}` subspace is spanned by \(\{|0\rangle,\ldots,|N-1\rangle\}\); the remaining basis states are the physical padding required by the qubit backend. Equation (1), not merely its restriction to the logical subspace, is the process denotation.

### Preconditions and failures

Before compilation, allocation, or application:

1. `N isa Int` and `N ≥ 2`;
2. `W == ndigits(N - 1; base=2)`;
3. `g = gcd(c, N) == 1`.

Failure of (3) throws a `DomainError` whose message includes `c`, `N`, and `g`:

> `mulmod!(QMod{15}, 3): multiplier is not invertible modulo 15 (gcd = 3); no in-place unitary permutation exists`

There is no fallback to an accumulating oracle, table truncation, tracing the old input, or a non-unitary channel.

### Paper proof of bijectivity

Because \(\gcd(\bar c,N)=1\), there is a unique \(d\in\{0,\ldots,N-1\}\) such that

\[
d\bar c\equiv1\pmod N.
\]

Define \(\pi_{d,N}\) by the same full-space rule. For \(v<N\),

\[
\pi_{d,N}(\pi_{\bar c,N}(v))
 = d(\bar c v\bmod N)\bmod N
 = v.
\]

For \(v\ge N\), both maps are the identity. The reverse composition is identical, so

\[
\pi_{d,N}\circ\pi_{\bar c,N}
=\pi_{\bar c,N}\circ\pi_{d,N}
=\operatorname{id}_{S_W}.
\]

Thus \(\pi_{\bar c,N}\) has a two-sided inverse and is a permutation. Its matrix

\[
P_{\pi}=\sum_{v\in S_W}|\pi(v)\rangle\langle v|
\]

has exactly one `1` in every row and column, hence

\[
P_\pi^\dagger P_\pi=P_\pi P_\pi^\dagger=I.
\]

This proves unitarity on the entire physical Hilbert space. If the gcd precondition fails, multiplication is not injective on \(\mathbb Z_N\), so no tail convention can repair it.

### Arithmetic implementation warning

The Bennett function must not be written naïvely as `(c*v) % N` under `bit_width=W`: Bennett narrows arithmetic modulo \(2^W\), so the product may wrap before `% N`. The registered modular callable must use a fixed-\(W\), overflow-free add-and-double implementation, with modular addition expressed without forming a value at least \(2^W\). Exhaustive truth-table tests below are mandatory tripwires for this second, independent correctness hazard.

---

## 2. In-place permutation compiler contract

### 2.1 API and placement

The new contract is kernel-adjacent but not a new kernel process kind:

```julia
abstract type InversePairProof{W} end

struct VerifiedInversePair{W,F,G,P<:InversePairProof{W}}
    forward::F
    inverse::G
    proof::P
end

struct CompiledInplacePerm{W}
    perm::Perm
    scratch_width::Int
    proof::InplacePermProof
end

verify_inverse_pair(f, finv, ::Val{W}) where {W} ->
    VerifiedInversePair{W}

compile_inplace_perm(pair::VerifiedInversePair{W}; kwargs...) where {W} ->
    CompiledInplacePerm{W}

_apply_inplace_perm!(
    ctx::AbstractContext,
    data::NTuple{W,WireID},
    compiled::CompiledInplacePerm{W},
) where {W} -> ctx
```

`compile_inplace_perm` should be `public`, not exported. It is compiler/library-author machinery, not an eighth surface construct. Surface code reaches it only through registered actions such as `mulmod!`.

The implementation belongs in:

- `src/bennett/inplace.jl`: pure-Sturm artifact types, exact inverse verification, composition, scratch choreography, and application;
- `ext/SturmBennettExt.jl`: compilation of both ordinary Julia callables through the existing Bennett weak dependency;
- `src/library/modular.jl`: the `mulmod!` action and the certified modular inverse-pair constructor.

It does **not** belong in `src/kernel/perm.jl`: `Perm` is already the correct compile target, `ctrl(Perm)` already works, and no new algebraic process kind is needed.

### 2.2 Required accumulated oracles

For functions \(f,g:S_W\to S_W\), the shipped M7 bridge provides phase-free permutations

\[
U_f|x\rangle|t\rangle|0^{A_f}\rangle
 = |x\rangle|t\mathbin{\oplus}f(x)\rangle|0^{A_f}\rangle,
\tag{2}
\]

and analogously for \(U_g\). The new contract requires:

- exactly one width-\(W\) input block;
- exactly one full-width \(W\) output block;
- disjoint input and output blocks;
- no output wire read as a control;
- no loop-check wires;
- every Bennett ancilla structurally clean;
- `ReversibleCircuit` output only;
- both artifacts to satisfy every existing M7 validation.

Under-sized output targets are forbidden here. There is no zero-tail dynamic witness in an in-place compilation.

### 2.3 Compute/swap/uncompute construction

Let \(g=f^{-1}\). Start with a width-\(W\) data block \(D\), a fresh width-\(W\) copy block \(B\), and shared clean compiler scratch \(A\):

\[
|x\rangle_D|0^W\rangle_B|0^A\rangle.
\]

Apply:

1. \(U_f\), with \(D\) as input and \(B\) as accumulation target;
2. swap the complete \(D\) and \(B\) blocks;
3. \(U_g\), with the new \(D=f(x)\) as input and \(B=x\) as accumulation target.

On basis states,

\[
\begin{aligned}
|x\rangle|0\rangle|0^A\rangle
&\xmapsto{U_f}
 |x\rangle|f(x)\rangle|0^A\rangle\\
&\xmapsto{\mathrm{swap}}
 |f(x)\rangle|x\rangle|0^A\rangle\\
&\xmapsto{U_g}
 |f(x)\rangle|x\oplus g(f(x))\rangle|0^A\rangle\\
&=
 |f(x)\rangle|0\rangle|0^A\rangle.
\end{aligned}
\tag{3}
\]

Linearity extends (3) to every superposition, with no residual entanglement:

\[
\sum_x\alpha_x|x\rangle
\longmapsto
\sum_x\alpha_x|f(x)\rangle.
\]

Using `adjoint(U_f)` after the swap is not sufficient: it would use the wrong function relationship. The inverse callable \(g=f^{-1}\) is required.

The compiler emits one frozen kernel `Perm` whose generator order is:

```text
embedded forward Perm
complete width-W swap
embedded inverse Perm
```

The M7 `_role_tables` function remains the only Bennett MSB/LSB remap. The new embedding pass merely renumbers already-remapped `Perm` positions into a canonical composite layout; it performs no second bit reversal.

### 2.4 Inverse agreement and compilation checks

A raw pair is accepted only if, for the exact width-\(W\) semantics \(\llbracket\cdot\rrbracket_W\),

\[
\forall x\in S_W:
\quad
g(f(x))=x
\quad\land\quad
f(g(x))=x.
\tag{4}
\]

There are two admission paths.

#### Generic exact verification

For `W ≤ INPLACE_INVERSE_MAXW`, with the initial constant set to `20`, `verify_inverse_pair` exhaustively evaluates both compositions over all \(2^W\) inputs using exact integer semantics. It checks range membership and both directions in (4). A mismatch throws before Bennett compilation and reports the first counterexample.

For `W > 20`, the generic constructor fails loudly. Sampling is not proof and there is no `check=false`.

#### Registered structural proof

Larger or library-owned maps use a closed, compiler-constructed proof type. For modular multiplication, a private `FullSpaceMulModProof{N,W}` stores \(\bar c\) and \(d=\bar c^{-1}\bmod N\), validates

\[
\bar c d\bmod N=1,
\]

and generates both callables from the same immutable specification. Arbitrary user closures cannot attach this proof through a keyword.

After inverse verification, both callables Bennett-compile eagerly. The contract returns nothing unless both compiles succeed and both artifacts pass all M7 structural checks. An inverse-compilation error identifies the inverse side explicitly.

For small generic widths, the extension should additionally compare `Bennett.simulate` for both compiled circuits against the verified classical maps. For registered large-width proofs, Bennett compiler correctness remains the trusted compiler boundary and is exercised through the property suite.

### 2.5 Scratch and wire budget

Let \(A_f\) and \(A_g\) be the forward and inverse Bennett ancilla counts. Because the forward circuit restores its ancillas before the swap, the same ancilla block can be reused by the inverse circuit:

\[
A=\max(A_f,A_g).
\]

The compiled `Perm` therefore has

\[
W_{\text{compiled}}=2W+\max(A_f,A_g)
\]

wires. Applying it to an existing width-\(W\) register allocates

\[
W+\max(A_f,A_g)
\]

fresh logical wires.

A depth-\(k\) control stack adds the existing \(k\) control wires but no new contract-level wires. Backend replay may temporarily borrow clean raw slots for multi-controlled lowering; that is the existing `Perm` emission budget, not part of the Bennett artifact.

### 2.6 Structural cleanliness and M8

M9 follows M8, so scratch release must use M8’s certificate discipline:

- the compiler emits a `PermClean` recipe naming every copy/ancilla position;
- Tracing materializes the corresponding `PermClean` proof on actual ports;
- the certified trace/free is licensed by that proof;
- `_clean_ancilla_assert!` may run as an Eager/DM debug cross-check, but it does not establish correctness.

The complete composite is one `Perm`, so `ctrl(Perm)=Perm` and the certificate remains structural under coherent control.

### 2.7 Control stack and MBU

Application is:

1. compile and verify completely;
2. allocate fresh scratch uncontrolled;
3. apply the single composite through `_act!`;
4. certified-clean free without measurement.

At nonzero control depth, `_act!` applies `ctrl^k(compiled.perm)`. In the non-firing branch, scratch remains zero; in the firing branch, equation (3) returns it to zero.

Measurement-based uncompute is excluded everywhere from this reusable artifact, not only when it happens to be applied under control. A `CompiledInplacePerm` may later be reused inside `when`, so its type must certify that it is always a controllable process value. Only fixed `ReversibleCircuit → Perm` artifacts cross this boundary.

### 2.8 Literature grounding

The local source already exists: [`docs/physics/bennett_1973_logical_reversibility.md`](docs/physics/bennett_1973_logical_reversibility.md), backed by the committed PDF. The relevant loci are:

- Bennett’s theorem, p. 527: \((I;B;B)\mapsto(I;B;P)\);
- compute/copy/retrace, Table 1, p. 528;
- the two-computation/two-oracle input-erasure pattern, Table 2, p. 530.

Before M9 code, that distillation should gain equation (3) explicitly, identifying the copy block, full-register swap, and inverse accumulate. No new Bennett PDF is required.

There is no committed Shor/order-finding distillation. Before implementing §7.7, add `docs/physics/shor_order_finding.md` with a local primary-source PDF, exact continued-fraction theorem locators, the \(Q\ge N^2\) precision condition, and success-probability equations.

---

## 3. Corrected `shor_order`

### 3.1 Signature and preconditions

The public classical driver becomes:

```julia
shor_order(
    a::Integer,
    ::Val{N};
    max_samples::Int = 32,
)::Int where {N}
```

`W` is derived as `ndigits(N - 1; base=2)`; callers cannot supply an inconsistent width.

Preconditions, checked before quantum allocation:

- `N isa Int`;
- `N ≥ 2`;
- `max_samples ≥ 1`;
- `a₀ = mod(a, N)`;
- `g = gcd(a₀, N) == 1`.

If `g != 1`, order finding is not defined in the unit group. Throw a dedicated `NonCoprimeBaseError` or `DomainError` containing the nontrivial factor `g`. Do not silently continue: the caller has already found a factor.

If `a₀ == 1`, return `1` without sampling.

### 3.2 One quantum sample

A private quantum kernel performs one fresh experiment:

```julia
_shor_phase_sample(a₀, ::Val{N}, ::Val{W})::BigInt
```

Its surface body remains the §7.7 program:

```julia
k = QInt{2W}(0)
superpose!(k)
y = QMod{N}(1)

c = a₀
for j in 2W:-1:1
    when(k[j]) do
        mulmod!(y, c)
    end
    c = powermod(c, 2, N)
end

m = BigInt(dual(k))
```

The `2W:-1:1` schedule remains: wire `2W` is the LSB and controls \(a^{2^0}\).

Each multiplier is coprime to \(N\), because every `c` is a power of the coprime base. Nevertheless, each `mulmod!` independently enforces its gcd precondition.

The phase denominator is constructed exactly:

```julia
Q = big(1) << (2W)
```

There is no `4^W`, floating division, or floating `rationalize`.

### 3.3 Exact continued-fraction candidates

For sample \(m\), enumerate the continued-fraction convergents \(p/q\) of the exact rational \(m/Q\), with \(q<N\). Retain the largest denominator satisfying the exact integer form of

\[
\left|\frac mQ-\frac pq\right|\le\frac1{2N^2}:
\]

\[
2N^2|mq-pQ|\le Qq.
\tag{5}
\]

If none exists, or \(q=1\), the sample contributes no information and the loop continues. In particular, the \(s=0\) outcome no longer returns order `1`.

For an ideal phase \(s/r\), reduction gives

\[
\frac{s}{r}
=
\frac{s/\gcd(s,r)}{r/\gcd(s,r)},
\]

so the observed denominator is generally

\[
q=\frac r{\gcd(s,r)},
\tag{6}
\]

a divisor of the true order, not necessarily the order.

### 3.4 LCM, verification, and exact minimization

Maintain an exact `BigInt` accumulator \(L\), initially `1`:

\[
L\leftarrow\operatorname{lcm}(L,q).
\]

For genuine candidates from (6), every \(q\mid r\), so \(L\mid r<N\). If a new LCM is at least \(N\), treat the candidate history as contaminated by a bad approximation and restart the accumulator from the current \(q\); do not allow unbounded LCM growth.

After every update, test

\[
a_0^L\equiv1\pmod N
\]

using `powermod`. Failure means only that more divisor candidates are needed.

Passing this test proves that the true order divides \(L\), but not that \(L\) is minimal. Therefore minimize it exactly:

```text
for each distinct prime p dividing L
    while L % p == 0 && powermod(a₀, L ÷ p, N) == 1
        L ÷= p
    end
end
```

Finally re-check `powermod(a₀, L, N) == 1` and the prime-factor minimality conditions, then return `Int(L)`.

Proof of minimality: if the resulting \(L\) were a proper multiple of the true order \(r\), then \(L/r>1\) would contain a prime factor \(p\), and \(L/p\) would still be a multiple of \(r\). The reduction loop would therefore not have terminated.

This exact minimization is deliberately conservative. It prevents a bad continued-fraction candidate from causing the function to return a verified but nonminimal exponent.

### 3.5 Termination and failure

The loop executes at most `max_samples` quantum experiments. If no exact order is established, throw:

```julia
OrderFindingFailure(a₀, N, max_samples, observed_denominators)
```

The error must distinguish:

- no useful continued-fraction candidates;
- candidates accumulated but never satisfied modular verification;
- only contaminated LCM histories.

There is no infinite retry and no return of the last denominator.

### 3.6 PRD §7.7 example changes

The normative example must:

- change the signature to `shor_order(a, ::Val{N}; max_samples=32)`;
- derive `W` from `N`;
- check `gcd(a,N)` before allocation;
- split the one-shot quantum kernel from the repeated classical driver;
- use `BigInt(dual(k))`;
- replace `4^W` and floating `rationalize` with exact `Q` and continued fractions;
- skip denominator `1`;
- LCM candidates across samples;
- verify with `powermod`;
- minimize a verified exponent before returning;
- throw `OrderFindingFailure` at the finite retry limit;
- document `mulmod!` as the full-space in-place permutation.

---

## 4. F23 overflow policy

### Decision

`Int(x)` always means a consuming cast whose scalar Eager result is an actual machine `Int`. It never silently returns `BigInt`.

```julia
Int(x::QInt{W}) -> Int
Int(dual(x::QInt{W})) -> Int
```

The scalar path is admitted only when

\[
1\le W\le \texttt{Sys.WORD_SIZE}-1.
\]

This is the exact all-values-fit condition for an unsigned \(W\)-bit register and a signed machine `Int`. For a 64-bit Julia, `W=63` is valid and `W=64` is not.

The width check occurs before any basis transformation or measurement. Failure throws `OverflowError` and says:

> `Int(QInt{64}) cannot represent every 64-bit outcome on this 64-bit host; use BigInt(x)`

The wide consuming cast is:

```julia
BigInt(x::QInt{W}) -> BigInt
BigInt(dual(x::QInt{W})) -> BigInt
```

It supports every positive registered width and reconstructs with `big(1) << bit`. Under DM/Tracing, Option D still returns the context’s record/wire representation; its width and requested scalar representation are carried in the classical handle and remain inference-visible after F16.

This is Julia-idiomatic: a constructor named `Int` does not return another integer type, while `BigInt(x)` explicitly requests arbitrary precision. It is the same measurement-cast construct, not a new measurement verb.

All public `QInt{W}` constructors must reject `W ≤ 0`. Literal range checks must use exact bounds such as `big(1) << W`, not `1 << W`.

For Shor:

```julia
Q = big(1) << (2W)
m = BigInt(dual(k))
```

so the original-parameter boundary `W=32` and phase-register boundary `2W=64` are exact.

---

## 5. F24 `QMod` decision

### Decision: modulus in the type

The concrete handle is:

```julia
struct QMod{N,W,C}
    ctx::C
    wires::NTuple{W,WireID}
end
```

with the public partially applied spelling `QMod{N}`. Its constructor computes

```julia
W = ndigits(N - 1; base=2)
```

and returns the concrete `QMod{N,W,C}`. The inner constructor rejects any inconsistent `(N,W)` pair.

```julia
QMod{N}(v::Integer) where {N} -> QMod{N,W,C}
```

There is no `modulus::Int` field.

The second parameter is required because Julia cannot express a field type such as `NTuple{ndigits(N-1),WireID}` directly from a `TypeVar`. It is derived representation metadata, not a second independent user choice.

### Rationale

This follows the same discipline as `QInt{W}`:

- `QInt` width determines its Hilbert space, wire layout, arithmetic, and Fourier view, so width is type-level.
- `QMod` modulus determines its logical Hilbert space \(\mathbb C^N\), label group \(\mathbb Z_N\), valid subspace, modular actions, bicharacter, and Fourier structure, so the modulus is likewise type-level.
- P7 says the register type declares its Hilbert, symmetry, and conjugate structures. A runtime modulus field would make those structures value-dependent and force hot-path branches.
- Static `N` lets `mulmod!`, preparation, comparison, and future `dual(::QMod)` specialize and infer concrete layouts.
- Different runtime moduli legitimately produce different compiled quantum programs. JIT specialization per modulus is an explicit cost of this representation, not an inference accident.

Accordingly, order finding accepts `::Val{N}`. A convenience method taking an ordinary runtime `N` should not ship in M9: `Val(N)` at a high-cardinality call site would cause unbounded specialization pressure while obscuring the static-program contract. A future runtime-modulus abstraction, if needed, should be a distinct type with a different performance contract.

The modular permutation is a canonical zero-phase `Perm` on \(2^W\) physical states. Future general `QMod` process values remain U(\(N\)), not SU(\(N\)); nothing here reintroduces a phase quotient.

---

## 6. Required document and plan amendments

### `Sturm-v2-IMPLEMENTATION-PLAN.md` §M9

Replace the current “filed, not designed” block with these resolved deliverables:

1. Add the exact full-space definition (1), gcd precondition, inverse, and proof.
2. Add `src/bennett/inplace.jl` and the `CompiledInplacePerm{W}` contract.
3. Require eager forward and inverse Bennett compilation with full-width outputs.
4. Require generic exhaustive inverse verification through width 20 and registered structural proof types above it.
5. State the composite budget \(2W+\max(A_f,A_g)\).
6. State that the composite is one `Perm`, uses `PermClean`, and is controlled only through `_act!`.
7. Exclude MBU from reusable in-place artifacts in every context.
8. Add `QMod{N,W,C}` with static `N`; remove modulus-as-field as an open alternative.
9. Add the `Int`/`BigInt` width policy and exact BigInt phase denominator.
10. Replace single-sample post-processing with the bounded algorithm in §3.
11. Replace the stale plan wording `@cases measure(m)` with `@cases Bool(m)`; there is no `measure` verb under the session-98 ruling.
12. Add the Bennett distillation extension and the new Shor/order-finding distillation as prerequisites.
13. Change the acceptance test from merely “seeded small N” to the statistical and exact law suite in §7 below.

### PRD-v2 §3.1/§3.2

Add:

- the concrete `QMod{N,W,C}` representation and derived-width invariant;
- `N` as a static type parameter;
- `Int(QInt{W})` machine-fit bound;
- `BigInt(QInt{W})` as the explicit wide cast;
- pre-backaction overflow failure;
- rejection of nonpositive widths.

### PRD-v2 §3.4

Add a distinct paragraph after the M7 accumulate form:

- `b ⊻= oracle(f,x)` remains the two-register XOR-accumulating action;
- registered library actions may use `compile_inplace_perm(f,finv,Val(W))`;
- the in-place contract is equation (3), not input discard;
- both directions must Bennett-compile and carry an exact inverse proof;
- only full-width accumulated outputs are admissible;
- the result is a phase-free `Perm` and therefore closed under `ctrl`.

The current generic discussion suggesting MBU may be selected outside control should be qualified: M7 and the new reusable in-place artifact admit only fixed `ReversibleCircuit → Perm` values. No MBU artifact crosses either boundary.

### PRD-v2 §7.6

No algorithmic injection change is required. Preserve the ruled spelling:

```julia
@cases Bool(m) begin
    ...
end
```

Remove any concurrent-edit remnants mentioning `measure`. A raw quantum register passed to `@cases` remains rejected.

### PRD-v2 §7.7

Replace the entire one-shot function and docstring with the two-layer quantum-sample/classical-driver contract in §3. The return claim becomes:

> Returns the exact multiplicative order after verification and minimization, or throws `OrderFindingFailure` after `max_samples`.

Document the noncoprime-base exception and factor payload.

---

## 7. Test plan

### 7.1 Full-space permutation properties

Exhaustively test \(S_W\) for at least:

- `(N,c) = (3,2)`;
- `(5,2)`, `(5,3)`;
- `(8,3)`, `(8,5)` — power-of-two, no tail;
- `(10,3)`, `(10,7)`, `(10,9)`;
- `(13,2)`, `(13,5)`;
- `(15,2)`, `(15,4)`, `(15,7)`, `(15,14)`;
- `(21,2)`, `(21,5)`.

For each pair:

- `sort(π.(S_W)) == collect(S_W)`;
- `πinv(π(v)) == v` and `π(πinv(v)) == v`;
- every `v ≥ N` is fixed;
- every `v < N` agrees with exact modular multiplication;
- the ideal permutation matrix satisfies \(P^\dagger P=I\).

Negative tests include `(15,3)`, `(15,5)`, `(10,2)`, `N<2`, inconsistent `W`, and negative multipliers after normalization.

### 7.2 Compiler-contract tests

Named tests should cover:

- correct generic forward/inverse pair accepted;
- first counterexample reported for a mismatched inverse;
- one-sided inverse claims rejected by the opposite-composition check;
- generic verification above width 20 rejected;
- registered modular proof accepted above the generic ceiling without a skip flag;
- forward compile failure;
- inverse compile failure;
- inverse output width mismatch;
- loop-check rejection on either side;
- non-circuit/VM rejection on either side;
- no output-as-control on either side;
- artifact is a frozen `Perm`;
- `nwires == 2W + max(Af,Ainv)`;
- only `_role_tables` performs Bennett bit-order reversal.

### 7.3 In-place denotation and scratch cleanliness

For feasible compiled sizes:

- compare the compiled composite’s permutation directly with the ideal full-space \(\pi\);
- verify every copy and compiler-ancilla wire ends in zero for every basis input;
- apply to asymmetric superpositions and compare the complete statevector, including relative phases;
- verify the data register is replaced in place and no preserved input copy survives;
- verify application returns the identical handle.

For larger artifacts, use three-way agreement:

1. exact classical \(\pi\);
2. Bennett forward/inverse simulation;
3. Sturm execution.

No marginal-only test is acceptable.

### 7.4 Channel-level discipline

Where the memory budget permits:

- construct the channel through the DSL and compare its Choi matrix with the ideal permutation channel;
- compare the controlled channel with `ctrl(ideal Perm)` on a reference-entangled input;
- compare the phase-fixed process matrices as well as Choi matrices, because Choi alone is insensitive to global phase;
- run the MBU-exclusion named test: the accepted artifact contains only frozen `Perm`/`MCX` structure and no measurement/classical branch;
- assert the M8 `PermClean` certificate is accepted and an altered scratch declaration is rejected structurally.

Above the exact Choi budget, use maximally entangled pure-state/reference-assisted tests plus exhaustive basis replay. State explicitly that a large fake “Choi test” is not performed.

### 7.5 Control-stack tests

For a superposed control and asymmetric data state:

- `when(c) do mulmod!(y,k) end` equals the controlled ideal permutation;
- amplitudes in firing/non-firing branches retain the correct relative phase;
- scratch is zero in both branches;
- guard externality rejects aliasing the controlling wire;
- nested distinct controls work through `ctrl^k(Perm)`;
- no measurement or state-dependent cleanup occurs.

### 7.6 Order-finding tests

#### Deterministic classical post-processing

Feed controlled sample sequences into the postprocessor:

- \(N=15,a=2,r=4\): denominator `2` followed by `4` returns `4`;
- \(N=21,a=2,r=6\): denominators `2` and `3` LCM to `6`;
- repeated \(s=0\) samples contribute no candidate;
- a contaminated candidate history is reset when its LCM reaches \(N\);
- a verified multiple such as `12` for a true order `6` is minimized to `6`;
- noncoprime bases throw and expose the gcd factor;
- exhausted samples throw `OrderFindingFailure`;
- no execution path returns an unverified denominator.

#### End-to-end statistics

Use at least 1,000 actual quantum samples per fixture.

For `N=15, a=2`, \(r=4\) divides \(Q=256\), so the four ideal peaks are exactly uniform. Each peak count must lie within a declared five-standard-deviation binomial band around 250, and all 1,000 samples fed to the driver must yield exact order `4`.

For `N=21, a=2`, compare the useful-candidate rate with the exact classically calculated finite-\(Q\) phase distribution using a five-standard-deviation tolerance; the accumulated driver must return exact order `6`. The test records failures separately from wrong answers: a wrong returned order is never permitted.

### 7.7 Overflow boundaries

Let `B = Sys.WORD_SIZE`.

- width validator accepts `W=B-1`;
- `Int` rejects `W=B` before backaction;
- `BigInt` reconstructs widths `B` and `2B`;
- computational- and Fourier-basis casts share the same checks;
- `_phase_denominator(Val(31)) == big(1)<<62`;
- `_phase_denominator(Val(32)) == big(1)<<64`;
- widths `0` and negative are rejected;
- literal bounds at `W=B` do not use overflowing machine shifts.

### 7.8 `QMod` inference

Under each implemented context type:

```julia
@inferred QMod{15}(1)           # concrete QMod{15,4,C}
@inferred mulmod!(y, 2) === y
@inferred shor_order(2, Val(15); sample_source = deterministic_source)
```

Also require:

- `@code_warntype` shows no `Any` in `mulmod!` application or QMod wire assembly;
- the handle has no runtime `modulus` field;
- an inconsistent internal `QMod{N,W,C}` construction fails;
- multiple static moduli produce distinct concrete types;
- the public hot path contains no ordinary runtime `N` branch.

---

## 8. Risks, rejected alternatives, and human rulings

### Risks

1. **Artifact size.** The compiled sequence costs roughly both Bennett circuits plus a width-\(W\) swap. Scratch grows by \(W+\max(A_f,A_g)\). This is correct but potentially expensive.
2. **Generic inverse verification is exponential.** It is intentionally capped at width 20; scalable maps require registered structural proofs.
3. **Modular arithmetic narrowing.** A naïve multiply-then-reduce callable is wrong under width narrowing. Fixed-width overflow-free arithmetic and exhaustive tests are mandatory.
4. **Static-modulus specialization.** Every distinct `N` creates compiled Julia and quantum artifacts. This is appropriate for static quantum programs but unsuitable for high-cardinality runtime services.
5. **Exact order minimization.** Factoring the verified candidate exponent is acceptable for the M9 fixtures but is not an asymptotically satisfactory production strategy. It is the conservative way to guarantee “order,” rather than “some verified exponent.”
6. **M8 dependency.** `PermClean` and certified scratch release must exist before M9 application can be considered structurally sound under Tracing.

### Alternatives considered and rejected

- **Apply `v -> c*v % N` to every padded state:** many-to-one; not unitary.
- **Leave padded behavior unspecified:** a physical process must act on the entire Hilbert space.
- **Use the M7 accumulating oracle and trace the input:** dephases superpositions.
- **Use `adjoint(U_f)` after swapping:** does not generally clear the copied input; \(f^{-1}\) is required.
- **Accept only the forward callable and infer an inverse table:** exponential and hides a required compilation failure.
- **Sample-test inverse agreement:** not a proof.
- **Allow `check=false`:** silent unsoundness.
- **Use measurement-based uncompute outside control:** the artifact may later be controlled, so it must always be a process value.
- **Return the first continued-fraction denominator:** fails on \(s=0\) and non-coprime numerators.
- **Return the first exponent satisfying `powermod`:** may return a proper multiple of the order.
- **Retry forever:** no termination contract.
- **Make `Int(x)` return `BigInt`:** violates Julia constructor expectations and obscures inference.
- **Store `N` in each `QMod`:** makes Hilbert/group structure value-dependent and defeats P7-parametric dispatch.
- **Offer an ordinary runtime-`N` Shor wrapper in M9:** hides specialization pressure and recreates F24.

### Human rulings requested

Two non-semantic API rulings remain:

1. Ratify `compile_inplace_perm` as `public` but not exported. Recommendation: **yes**, matching the library-author status of kernel machinery without expanding the seven-construct surface.
2. Ratify `INPLACE_INVERSE_MAXW = 20`. Recommendation: **yes**, matching the existing `PERM_EQ_MAXW` ceiling; changing it later is a resource-policy adjustment, not a semantic change.

The F23 and F24 axes are not left open: `Int` is bounded with explicit `BigInt`, and `QMod` uses a static modulus.