# M9 design proposal — full-space modular permutations, inverse-assisted in-place compilation, and correct order finding

## Decision summary

This proposal adopts five linked decisions:

1. `mulmod!(y, c)` denotes multiplication by `c` on the valid residues and the identity on every padded basis state.
2. A new Bennett-backed compiler constructs an in-place permutation from separately compiled `f` and `f⁻¹`, producing one kernel `Perm`.
3. `shor_order` repeats phase sampling, combines continued-fraction candidates with `lcm`, verifies modular exponents, and never returns an unverified denominator.
4. Eager `Int(x)` remains an `Int` cast and rejects widths that cannot fit before any backaction; Shor consequently rejects `2W ≥ Sys.WORD_SIZE`.
5. The modulus stays static: callers pass `Val(N)`, and `N` remains the leading type parameter of `QMod`. A runtime modulus field is rejected.

---

## 1. Correct `mulmod!` semantics

Let

\[
W=\lceil \log_2 N\rceil,\qquad
X_W=\{0,1,\ldots,2^W-1\},
\]

with \(N\ge2\). `QMod{N}` uses a binary padded representation on \(W\) wires. Its valid logical subspace is spanned by \(|v\rangle\) for \(0\le v<N\); the remaining basis states are physical padding and must still receive a unitary semantics.

For an integer \(c\), first normalize

\[
\bar c = c\bmod N.
\]

The exact full-space permutation is

\[
\pi_{\bar c,N}(v)=
\begin{cases}
\bar c\,v\bmod N,&0\le v<N,\\
v,&N\le v<2^W.
\end{cases}
\tag{1}
\]

Thus the public action is:

```julia
mulmod!(y::QMod{N}, c::Integer) -> y
```

with denotation

\[
|v\rangle\longmapsto|\pi_{\bar c,N}(v)\rangle
\quad\text{for every }v\in X_W.
\]

It mutates and returns the same handle, like every registered action-world operation.

### Preconditions and failure

Before compiling or applying any quantum operation:

- `N ≥ 2`;
- `gcd(mod(c, N), N) == 1`.

If coprimality fails, `mulmod!` throws `DomainError` naming `c`, `N`, and the nontrivial gcd. It must fail before scratch allocation or mutation, including when called inside `when`.

There is no fallback to the many-to-one map, no implicit restriction to the valid subspace, and no measurement-based cleanup.

### Proof that (1) is a permutation

Let

\[
A=\{0,\ldots,N-1\},\qquad
T=\{N,\ldots,2^W-1\}.
\]

These sets are disjoint and invariant under (1). Because \(\gcd(\bar c,N)=1\), there is a unique \(\bar c^{-1}\in\mathbb Z_N\) satisfying

\[
\bar c^{-1}\bar c\equiv1\pmod N.
\]

For \(v\in A\),

\[
\pi_{\bar c^{-1},N}(\pi_{\bar c,N}(v))
 = \bar c^{-1}\bar c v\bmod N
 = v.
\]

For \(v\in T\), both maps are the identity. Therefore

\[
\pi_{\bar c^{-1},N}\circ\pi_{\bar c,N}
=\pi_{\bar c,N}\circ\pi_{\bar c^{-1},N}
=\operatorname{id}_{X_W}.
\tag{2}
\]

Hence \(\pi_{\bar c,N}\) has a two-sided inverse and is a permutation of all \(2^W\) basis states. Its permutation matrix is consequently unitary. The `N=15` collision is removed: `0 ↦ 0`, while padded state `15 ↦ 15`.

If `N` is a power of two, the tail \(T\) is empty and the same proof applies.

---

## 2. In-place `Perm` compiler contract

### 2.1 API and placement

The core, Bennett-independent API should live in a new file:

```text
src/bennett/inplace.jl
```

The existing weak-dependency extension remains the only file naming Bennett types:

```text
ext/SturmBennettExt.jl
```

The kernel remains unchanged semantically: it receives an ordinary `Perm`. Julia functions, inverse witnesses, modular arithmetic, and Bennett role tables do not belong in `src/kernel/`.

The exact public-but-not-exported compiler contract is:

```julia
compile_inplace_perm(
    f,
    finv,
    ::Val{W};
    kwargs...,
) -> CompiledInplacePerm{W}
```

The application seam is internal:

```julia
_apply_inplace!(
    ctx::AbstractContext,
    compiled::CompiledInplacePerm{W},
    data::NTuple{W,WireID},
) -> ctx
```

`mulmod!` calls this seam and returns its original register handle.

The artifact is not itself a `ProcessValue`: it owns a physical `Perm` containing internal scratch positions, while its external semantic boundary is only the leading `W` data wires.

```julia
struct CompiledInplacePerm{W}
    perm::Perm

    global _compiled_inplace_perm(
        ::Val{W},
        perm::Perm,
    ) where {W} = new{W}(perm)
end
```

`_compiled_inplace_perm` is a private construction choke point. A boot lint should restrict calls to `src/bennett/inplace.jl`, just as `_ctrl` is restricted to the control constructor. After M8/TR5, the contained `Perm` and `MCX` data are deeply frozen.

`CompiledInplacePerm` and `compile_inplace_perm` may be `public`, but neither is exported and neither becomes an eighth surface construct.

### 2.2 Requirements on `f` and `finv`

Both functions must:

- be total on the width-\(W\) unsigned domain;
- return a width-\(W\) value;
- Bennett-compile through the existing circuit-only backend;
- produce a `CompiledOracle` with one width-\(W\) input and one full width-\(W\) output;
- have no loop-check garbage;
- preserve their input and clean every Bennett ancilla;
- satisfy, as compiled permutations,

\[
f^{-1}(f(x))=x,\qquad f(f^{-1}(x))=x
\quad\forall x\in X_W.
\tag{3}
\]

The existing `_BENNETT_BACKEND` is called twice. The in-place compiler does not call `oracle(f, x)`, because it needs x-independent compiled artifacts rather than live-bound `OracleQuery` values.

All `kwargs` are passed identically to both compilations. `auto_self_reversing=false`, circuit-only output, no output-as-control, and the other M7 invariants remain compulsory.

### 2.3 Inverse verification

A user-supplied `finv` is not trusted merely because it has that name. Verification happens eagerly inside `compile_inplace_perm`, before the private artifact constructor and before any quantum application.

There are two admitted proof routes.

#### Generic functions: exact exhaustive verification

Define:

```julia
const INPLACE_EXHAUSTIVE_MAXW = 16
```

For `W ≤ INPLACE_EXHAUSTIVE_MAXW`, replay each compiled `Perm` classically on every \(x\in X_W\), with its output and ancilla roles initialized to zero. This replay is linear in the compiled gate count per input and does not materialize a \(2^n\)-element permutation over all Bennett ancilla wires.

For every `x`, the checker verifies:

- the input roles remain `x`;
- all Bennett ancillas return to zero;
- the full width-\(W\) output is extracted without truncation;
- both identities in (3).

The first counterexample raises an `InverseContractError` containing `W`, `x`, the two realized images, and the failed direction. No sampling and no `isapprox` participates.

For arbitrary user functions with `W > 16`, the generic method fails loudly: M9 has no solver capable of proving (3), and finite probes are not a certificate.

#### Closed modular specification: analytic witness

`mulmod!` uses an internal, closed specification rather than an extensible user-certification trait:

```julia
_FullSpaceMulSpec{W}(c, N, cinv)
```

Its private constructor validates:

- \(2^{W-1}<N\le2^W\), with the obvious lower-bound adjustment for `N=2`;
- `gcd(c, N) == 1`;
- `mod(c * cinv, N) == 1`, evaluated with widened classical arithmetic;
- both forward and inverse functions use the piecewise definition (1).

Equation (2) is then the inverse certificate for all \(2^W\) values. Both generated functions must still Bennett-compile. For `W ≤ 16`, the compiled artifacts additionally receive the exhaustive cross-check; above it, correctness of each compilation rests on the already-shipped M7 Bennett contract, while inverse agreement rests on the analytic witness.

There is deliberately no `check=false`, sampling-only verifier, or open `AbstractInverseWitness` that downstream code could subtype and lie through.

### 2.4 Overflow-free classical function supplied to Bennett

The compiled full-space function must not evaluate `c*v` in a type where that product can wrap before `% N`.

Use a fixed-\(W\) binary double-and-add implementation. For `0 ≤ a,b < N`, define overflow-free modular addition by

\[
a\oplus_N b=
\begin{cases}
a-(N-b),&a\ge N-b,\\
a+b,&a<N-b.
\end{cases}
\tag{4}
\]

The addition in the second branch is safe because its branch condition proves \(a+b<N\). Expanding \(c\) in binary and applying (4) for exactly `W` statically bounded iterations computes \(cv\bmod N\) without a wide intermediate.

The implementation gate must empirically verify that Bennett compiles this fixed-loop helper. Failure is a compiler error; falling back to overflowing native multiplication is forbidden.

### 2.5 Compute/swap/uncompute construction

Let the two shipped M7 accumulators be

\[
B_f:|x\rangle_D|t\rangle_T|0\rangle_{A_f}
 \mapsto |x\rangle_D|t\oplus f(x)\rangle_T|0\rangle_{A_f},
\tag{5}
\]

and analogously \(B_{f^{-1}}\). The new compiler relabels their role tables into one canonical physical layout:

- slots `1:W`: external data \(D\);
- slots `W+1:2W`: work register \(T\);
- remaining slots: a shared Bennett-ancilla pool.

The pool may be shared because the forward compilation has returned it to zero before the inverse compilation begins. If the two compilers require \(A_f\) and \(A_{f^{-1}}\) ancillas, the shared pool has size

\[
A=\max(A_f,A_{f^{-1}}).
\]

The composite gate list is:

1. relabeled \(B_f\), with input \(D\), output \(T\);
2. a reversible bitwise swap of \(D\) and \(T\);
3. relabeled \(B_{f^{-1}}\), with input \(D\), output \(T\).

The output is one frozen kernel `Perm`, not three surface operations.

Starting with clean scratch,

\[
\begin{aligned}
|x\rangle_D|0\rangle_T|0\rangle_A
&\xmapsto{B_f}
 |x\rangle_D|f(x)\rangle_T|0\rangle_A\\
&\xmapsto{\mathrm{swap}}
 |f(x)\rangle_D|x\rangle_T|0\rangle_A\\
&\xmapsto{B_{f^{-1}}}
 |f(x)\rangle_D
 |x\oplus f^{-1}(f(x))\rangle_T
 |0\rangle_A\\
&=
 |f(x)\rangle_D|0\rangle_T|0\rangle_A.
\end{aligned}
\tag{6}
\]

Equation (6) proves the clean-subspace property on every basis state. Linearity extends it to every superposition. The full physical composite is itself a permutation for arbitrary scratch contents because it is a composition of permutations.

Using `adjoint(B_f)` after the swap is not sufficient: it would accumulate \(f(f(x))\), not \(f^{-1}(f(x))\). The separately compiled inverse is load-bearing.

### 2.6 Application and wire budget

For a compiled artifact with forward/inverse Bennett ancilla counts \(A_f,A_{f^{-1}}\):

- external data: `W` live wires;
- persistent clean scratch allocated by `_apply_inplace!`:
  \[
  W+\max(A_f,A_{f^{-1}});
  \]
- underlying `Perm` width:
  \[
  2W+\max(A_f,A_{f^{-1}}).
  \]

Application performs:

1. liveness and context checks;
2. scratch allocation as fresh \(|0\rangle\);
3. one `_act!(ctx, compiled.perm, wires)` call;
4. `_free_clean!` on every scratch wire.

Every clean assertion is defensive execution checking, not the inverse certificate.

At control depth \(k\), the semantic control wires already exist and are prepended by `_act!`; no additional persistent semantic ancilla is introduced. The current Orkan `Perm` lowering may transiently need, for a generator with `m` local controls,

\[
\max(0,k+m-2)
\]

scratch slots for its multi-control reduction. These are lowered, uncomputed, and recycled per generator.

### 2.7 Interaction with `when` and M8 certificates

The full composite crosses the action choke point as one `Perm`. Therefore:

\[
\operatorname{ctrl}^k(P)\text{ is again a `Perm`}.
\]

If the outer controls do not fire, the composite acts as the identity and the initially zero scratch remains zero. If they fire, equation (6) cleans it. Hence scratch release is valid in both branches.

No observation cast, `cases`, noise, or measurement-based uncompute appears. The §3.4 exclusion is structural, exactly as in M7.

M8’s `PermClean` acquisition rule must be clarified to admit two trusted compiler origins:

- M7’s target-accumulating Bennett theorem;
- `CompiledInplacePerm`’s inverse-pair theorem (6).

No new `CleanCert` variant is necessary: the recorded body is still a single `Perm` with declared clean ancilla ports. The checker must validate private-constructor provenance rather than accept an arbitrary `Perm` plus an assertion.

### 2.8 Literature grounding

The existing local source and distillation are sufficient in principle:

- `docs/physics/bennett_1973_logical_reversibility.pdf`;
- `docs/physics/bennett_1973_logical_reversibility.md`.

The distillation already records Bennett’s compute/copy/retrace construction from Table 1, p. 528, and the inverse-assisted disposal pattern associated with Table 2, p. 530.

Before implementation, amend that distillation with an explicit subsection titled “Inverse-assisted in-place permutation,” including equations corresponding to (5) and (6). Code docstrings should cite that subsection, not this proposal or an unlocated textbook statement.

A Shor/order-finding distillation is not currently present. Before §7.7 code lands, add a local source PDF and `docs/physics/shor_order_finding.md` covering the phase-sample equation, continued-fraction theorem, divisor-denominator issue, repetition, and modular verification. This is mandatory under CLAUDE.md principle 4.

---

## 3. Corrected `shor_order` classical driver

### 3.1 Signature

Replace the runtime modulus argument with a static modulus:

```julia
shor_order(
    a::Integer,
    ::Val{N};
    max_samples::Int = 64,
) -> Int
```

A typical call becomes:

```julia
shor_order(2, Val(15))
```

`W` is derived internally as `ceil(log2(N))`; a separate caller-supplied `Val{W}` would duplicate an invariant and permit inconsistent `(N,W)` pairs.

### 3.2 Preconditions

All checks happen before the first register allocation:

- `N isa Int`;
- `N ≥ 2`;
- `max_samples ≥ 1`;
- normalize `aa = mod(a, N)`;
- require `1 ≤ aa < N`;
- let `g = gcd(aa, N)`.

If `g != 1`, order finding is unnecessary: `g` is already a factor. Throw a typed `NonCoprimeBaseError` carrying `a`, `N`, and `g`. This preserves the single successful return type while making the factor available to a factoring driver.

The eager overflow bound is also checked here:

\[
2W < \texttt{Sys.WORD\_SIZE}.
\tag{7}
\]

Failure raises `ArgumentError` before any quantum state exists.

### 3.3 One independent phase sample

Each attempt runs in a fresh region:

```julia
function _shor_phase_sample(a, ::Val{N}, ::Val{W}) where {N,W}
    region() do
        k = QInt{2W}(0)
        superpose!(k)
        y = QMod{N}(1)

        c = mod(a, N)
        for j in 2W:-1:1
            when(k[j]) do
                mulmod!(y, c)
            end
            c = Int(powermod(big(c), 2, big(N)))
        end

        return Int(dual(k))
    end
end
```

This retains the corrected wire schedule: wire `2W` is the least-significant wire and controls \(a^{2^0}\); wire `1` controls the highest power.

Each attempt creates fresh `k` and `y`. The cast consumes `k`; `y` is unreturned and traced at region exit. A sample is never reused as though it were a fresh experiment.

### 3.4 Exact continued-fraction processing

Set

\[
Q=2^{2W}.
\]

Do not compute `4^W` in `Int`, and do not convert `z/Q` to `Float64`. Construct `Q` and all continued-fraction arithmetic as `BigInt`.

For each sampled `z`:

1. Compute the simple continued-fraction convergents \(p/q\) of the exact rational \(z/Q\).
2. Retain denominators satisfying:
   - \(1<q<N\);
   - the exact integer form of
     \[
     \left|\frac zQ-\frac pq\right|
     \le \frac1{2N^2}.
     \tag{8}
     \]
3. Prefer the largest qualifying denominator from that sample. If none exists, continue.
4. Ignore `q=1`. In particular, the `s=0` sample contributes no information.
5. Accumulate
   \[
   L\leftarrow\operatorname{lcm}(L,q),
   \qquad L_0=1.
   \tag{9}
   \]
6. Maintain `L ≤ N`. If a new candidate would make the LCM exceed `N`, discard the poisoned accumulation and restart the accumulator from the new `q`.
7. After every update, test exactly:
   \[
   a^L\bmod N=1.
   \tag{10}
   \]
   Use `powermod(BigInt(a), L, BigInt(N))`; never form \(a^L\).

A good phase sample approximates \(s/r\). After reduction its denominator is

\[
q=\frac r{\gcd(s,r)},
\tag{11}
\]

which explains both `q=1` for `s=0` and the need for repeated LCM accumulation.

### 3.5 Returning the exact order, not merely a verified multiple

Finite-precision or unlucky samples can produce a spurious denominator. Consequently, equation (10) proves only that the true order divides `L`.

Before returning, factor the verified `L` classically and strip prime factors:

```text
for each prime p dividing L
    while L % p == 0 && powermod(a, L ÷ p, N) == 1
        L ÷= p
    end
end
```

Call the result `r`. Recheck:

\[
a^r\bmod N=1.
\]

This `r` is the exact multiplicative order. Proof: suppose the true order \(r_0\) properly divided the final `r`. Then `r/r₀` has some prime factor \(p\), so \(r_0\mid r/p\), implying \(a^{r/p}\equiv1\pmod N\). The stripping loop would not have terminated. Contradiction.

Trial division is acceptable for the small M9 capstone. A faster integer-factorization helper can replace it later without changing semantics.

### 3.6 Termination and failure

The driver terminates in one of three ways:

- returns the exact verified order;
- throws `NonCoprimeBaseError` with an already-found factor;
- after `max_samples`, throws `OrderFindingFailure(a, N, max_samples, L)`.

It must never return `nothing`, `1` from an uninformative sample, a raw continued-fraction denominator, or an unverified LCM.

The algorithm is probabilistic in runtime success, not in returned correctness: every successful return is verified and minimized.

---

## 4. F23 overflow policy

### 4.1 Decision

Keep eager `Int(x)` honest: it either returns a machine `Int` or throws before any backaction. Do not make a function named `Int` return `BigInt` based on width.

After the F16 context-parameter refactor, the relevant signatures remain:

```julia
Int(x::QInt{W,EagerContext}) -> Int
Int(v::DualView{<:QInt{W,EagerContext}}) -> Int
```

Both require:

\[
1\le W<\texttt{Sys.WORD\_SIZE}.
\tag{12}
\]

On a 64-bit host this admits `W ≤ 63`; on a 32-bit host, `W ≤ 31`.

For `W ≥ Sys.WORD_SIZE`, throw:

```text
ArgumentError: Int(QInt{W}) cannot represent every W-bit outcome on a
Sys.WORD_SIZE-bit host; the cast was rejected before measurement.
```

The check must run:

- before the first `_measure_wire!` in `Int(x)`;
- before applying the Fourier basis transform in `Int(dual(x))`.

The second ordering is essential: applying the transform and then discovering the width error would mutate the state before failure.

Exact DM/Tracing/Hardware contexts may still produce a fixed-width `ClassicalWord{W}` token. The limitation is on conversion to a host scalar, not on the existence of wide quantum registers or classical record wires.

### 4.2 Consequences for Shor

The sampled phase register has width `2W`, so `shor_order` enforces (7). On a 64-bit host, `W ≤ 31`; on a 32-bit host, `W ≤ 15`.

The denominator is constructed as:

```julia
Q = big(1) << (2W)
```

All continued-fraction cross-products use `BigInt`, even when `z` itself fits in `Int`.

### 4.3 Adjacent constructor repair

Existing expressions such as `1 << W` in `QInt{W}(n)` also overflow at boundary widths. M9 must replace range calculations with checked or widened arithmetic and reject `W ≤ 0`. Preparation range validation must not depend on an overflowing machine shift.

### 4.4 Rejected alternatives

- Automatic `BigInt` returns from `Int(x)` weaken Julia’s constructor contract and make `Int(x) isa Int` false on eager execution.
- A new wide-observation verb would alter the seven-construct surface and contradict the no-`measure` ruling.
- Silent wrap is categorically rejected.

This policy limits one host projection, not the P7 register abstraction.

---

## 5. F24 `QMod` decision

### 5.1 Static modulus

The modulus is a value type parameter. Callers cross the dynamic boundary explicitly with `Val(N)`.

The complete post-F16 representation should separate logical dimension, physical representation, and context:

```julia
struct BinaryPadded{W}
    wires::NTuple{W,WireID}
end

struct QMod{N,R,C}
    ctx::C
    repr::R
end
```

The user-facing partial type remains `QMod{N}`. Its constructor returns a concrete type such as:

```julia
QMod{15,BinaryPadded{4},EagerContext}
```

Public constructors are:

```julia
QMod{N}(n::Integer = 0) where {N}
QMod(::Val{N}, n::Integer = 0) where {N}
```

There is no `QMod(N::Integer, n)` constructor that dynamically forms `QMod{N}` from an ordinary runtime value.

`shor_order(a, Val(N))` therefore specializes with `N` known and constructs `QMod{N}` inference-cleanly.

### 5.2 Rationale

`N` is not merely storage metadata. It determines:

- the logical Hilbert dimension and valid subspace;
- the cyclic group \(\mathbb Z_N\);
- which multipliers are units;
- the conjugate transform \(F_N\);
- promotion and mixed-modulus laws;
- the padded-space permutation (1).

Two registers with the same binary width but moduli 13 and 15 do not carry the same symmetry structure. A runtime modulus field would put both in the same concrete type and defer algebraic compatibility, dispatch, and lowering decisions to runtime branches. That contradicts the same reasoning that puts `W` in `QInt{W}` and the P7 requirement that the register type declare its symmetry structure.

`R` separately records the physical encoding. The padded tail belongs to `BinaryPadded{W}`; it does not erase the logical distinction carried by `N`.

Per-modulus specialization is an accepted cost: modular multiplication already requires an `N`-specific compiled permutation. A future service processing unbounded streams of unrelated moduli may introduce a distinct dynamic register type, but must not weaken `QMod`.

---

## 6. Required specification and plan amendments

### 6.1 `Sturm-v2-IMPLEMENTATION-PLAN.md` §M9

Replace the current “fix filed, not designed” language with the following decisions:

1. **Full-space semantics:** record equation (1), `N ≥ 2`, and fail-fast coprimality.
2. **Compiler prerequisite:** name `compile_inplace_perm(f, finv, Val(W))`, the two Bennett compilations, exact/analytic inverse verification, and the one-`Perm` construction.
3. **Wire budget:** state `W + max(A_f,A_finv)` semantic scratch and one `_act!`.
4. **M8 dependency:** extend `PermClean` provenance to `CompiledInplacePerm`.
5. **F23 decision:** `Int(QInt{W})` rejects `W ≥ Sys.WORD_SIZE` before backaction; `shor_order` requires `2W < Sys.WORD_SIZE`; replace `4^W` with exact shifted `BigInt`.
6. **F24 decision:** static modulus and `shor_order(a, Val(N))`; no runtime-modulus `QMod` constructor.
7. **F22 decision:** repeated fresh samples, exact convergents, LCM, modular verification, prime-factor minimization, typed failure.
8. **Documentation gate:** amend the Bennett distillation and add the local Shor distillation before code.
9. **Testing gate:** add the permutation, controlled-channel, inverse-contract, statistical order-finding, overflow, and inference suites from §7 below.
10. Correct the stale injection bullet from `@cases measure(m)` to `@cases Bool(m)`.

The milestone dependency order becomes:

```text
M8 frozen Perm/CleanCert work
    → in-place compiler contract
    → QMod + mulmod!
    → repeated order-finding driver
    → end-to-end Shor tests
```

### 6.2 PRD-v2 §7.6

The current quantum listing is already consistent with the session-98 ruling and should retain:

```julia
@cases Bool(m) begin
    ...
end
```

Make only these wording changes:

- say explicitly that `Bool(m)` is the consuming cast and `@cases` branches on its result;
- retain the rejection of a bare quantum register operand;
- require both observation branches in the injection channel tests;
- remove any concurrent wording-round residue that mentions a `measure` verb.

No modular-arithmetic semantic change belongs in §7.6.

### 6.3 PRD-v2 §7.7

Replace the example and prose as follows:

- signature becomes `shor_order(a, ::Val{N}; max_samples=64) -> Int`;
- derive `W` from `N`;
- add the coprimality/factor precondition;
- retain the corrected `2W:-1:1` control schedule;
- specify `mulmod!` using equation (1), including identity on padded states;
- say that each attempt uses fresh registers;
- replace `r / 4^W` and `rationalize` with exact `z//2^(2W)` continued fractions;
- explain equation (11);
- accumulate candidates by LCM;
- verify with `powermod`;
- minimize any verified multiple before returning;
- document `NonCoprimeBaseError` and `OrderFindingFailure`;
- state the machine-width precondition;
- add the `using Bennett` weak-dependency precondition, as in §§7.4–7.5.

### 6.4 PRD-v2 §4.1a clarification

Although outside the requested example sections, `PermClean` needs one precise sentence: a trusted clean `Perm` may originate either from the M7 accumulate compiler or from the M9 inverse-pair in-place compiler, with the corresponding private constructor proving its clean-subspace theorem.

---

## 7. Test plan

All tests are named. Quantum equivalence is checked at the permutation or channel level, never only through output marginals.

### 7.1 Full-space permutation laws

`M9.MULMOD.FULL-SPACE-BIJECTION`

For at least:

```text
(c,N) = (2,3), (2,5), (2,15), (4,15), (3,16), (2,21)
```

compute every image in `0:2^W-1` and assert:

- the sorted image list is exactly `0:2^W-1`;
- every `v ≥ N` is fixed;
- `π_cinv(π_c(v)) == v`;
- `π_c(π_cinv(v)) == v`.

Include the explicit `N=15` regression asserting `π(0)=0` and `π(15)=15`.

`M9.MULMOD.NONUNIT-FAILS-BEFORE-ACTION`

For `(c,N)=(3,15)`, assert the error includes `gcd=3` and that no allocation, state mutation, or control-stack emission occurred.

`M9.MULMOD.OVERFLOW-FREE-REFERENCE`

Cross-check the fixed-loop modular multiplication helper against `BigInt(c)*BigInt(v) % N` near each supported native-width boundary.

### 7.2 Compiler contract

`M9.INPLACE.BOTH-COMPILE`

Assert both forward and inverse artifacts pass every M7 structural check.

`M9.INPLACE.EXHAUSTIVE-INVERSE`

Compile asymmetric small permutations and verify (3) on every input.

`M9.INPLACE.WRONG-INVERSE-REJECTED`

Supply an incorrect `finv`; assert the first counterexample is reported before `_apply_inplace!`.

`M9.INPLACE.NONBIJECTION-REJECTED`

A many-to-one `f` must fail inverse verification even if both functions separately Bennett-compile.

`M9.INPLACE.GENERIC-WIDE-NEEDS-PROOF`

At `W=17`, an arbitrary function pair is rejected rather than sampled.

`M9.INPLACE.CLEAN-SCRATCH`

For every basis input and several coherent inputs, apply the compiled artifact and assert all semantic scratch is exactly clean before release.

`M9.INPLACE.SHARED-ANCILLA-POOL`

Assert compiled width is exactly:

\[
2W+\max(A_f,A_{f^{-1}}),
\]

not the sum of both ancilla counts.

`M9.INPLACE.BIT-ORDER-TRIPWIRE`

Use an asymmetric carry permutation so reversal of either M7 role table changes the realized mapping.

### 7.3 Channel and control tests

`M9.MULMOD.CHOI`

Where the complete internal width fits the memory budget, compare the external channel Choi matrix with the exact permutation matrix induced by (1). Include a padded modulus such as `N=3` or `N=5`.

For larger Bennett artifacts, exhaustive phase-free basis replay is a complete process proof: a `Perm` is a canonical 0/1 matrix, so identical images establish identical matrices. Supplement with randomized reference-assisted coherent probes.

`M9.MULMOD.CONTROLLED-CHOI`

Compare:

```julia
when(control) do
    mulmod!(y, c)
end
```

against the mathematically controlled full-space permutation. Probe a superposed control so loss of coherence or a spurious phase is visible.

`M9.MULMOD.MBU-EXCLUDED`

Assert the recorded value is a `Perm`, contains no observation/classical nodes, and receives `PermClean` under a nonzero control stack.

`M9.MULMOD.TAIL-COHERENCE`

Prepare coherence between a valid residue and a padded basis state, apply `mulmod!`, and compare the full state/channel. This directly detects accidental collapse or modification of the tail.

### 7.4 Order-finding post-processing

`M9.SHOR.ZERO-SAMPLE-IGNORED`

Feed `z=0`; assert it contributes no candidate and never returns order 1 unless the true order is actually 1.

`M9.SHOR.LCM-PROPER-DIVISORS`

For an order-six case, feed deterministic samples yielding denominators 2 and 3; assert `lcm` produces 6 and verification succeeds.

`M9.SHOR.SPURIOUS-CANDIDATE-NEVER-RETURNED`

Inject a denominator not dividing the order; assert no return occurs without equation (10).

`M9.SHOR.MINIMIZE-VERIFIED-MULTIPLE`

Give a verified multiple such as `2r`; assert prime stripping returns `r`.

`M9.SHOR.NONCOPRIME-REPORTS-FACTOR`

For `a=3, N=15`, assert `NonCoprimeBaseError.factor == 3` before allocation.

`M9.SHOR.EXHAUSTION-LOUD`

Force uninformative samples through `max_samples`; assert `OrderFindingFailure`, not `nothing` or a raw denominator.

### 7.5 End-to-end statistical test

`M9.SHOR.END-TO-END-STATISTICAL`

For both:

```text
(N,a,r) = (15,2,4)
(N,a,r) = (21,2,6)
```

run at least 1000 independently seeded driver trials with a fixed documented `max_samples`, initially 32.

Assertions:

- every successful return equals the exact classical order;
- no incorrect order is ever returned;
- explicit `OrderFindingFailure`s are counted separately;
- the one-sided 99% binomial lower confidence bound on success probability is at least 0.95.

The threshold should be justified in the Shor distillation from the good-approximation and coprime-numerator probabilities, not selected after observing the test.

Compiled modular permutations should be cached by immutable value keys during this test so the 1000 trials test sampling, not repeated compiler setup.

### 7.6 Overflow boundaries

`M9.INT.WIDTH-BOUNDARY`

Test the preflight directly:

- `W = Sys.WORD_SIZE-1` is admitted;
- `W = Sys.WORD_SIZE` is rejected.

`M9.INT.DUAL-FAILS-BEFORE-TRANSFORM`

Assert the wide `Int(dual(x))` path rejects before emitting its basis transform.

`M9.SHOR.PHASE-WIDTH-BOUNDARY`

On a 64-bit host:

- `W=31` passes the arithmetic preflight;
- `W=32` throws before allocation.

Write the test in terms of `Sys.WORD_SIZE` so it remains correct on 32-bit CI.

`M9.NO-OVERFLOWING-POWER`

Assert the implementation contains no `4^W` or signed `1 << W` range calculation at the affected paths.

### 7.7 Inference tests

`M9.QMOD.INFERENCE`

Under each implemented context:

```julia
@inferred QMod{15}(1)
@inferred QMod(Val(15), 1)
```

must return a concrete `QMod{15,BinaryPadded{4},C}`.

`M9.QMOD.MULMOD-INFERENCE`

```julia
y2 = @inferred mulmod!(y, 2)
@test y2 === y
@test typeof(y2) === typeof(y)
```

`M9.QMOD.STATIC-MODULUS-ONLY`

Assert `QMod(15, 1)` has no method and that `QMod{15}` and `QMod{21}` reach distinct modulus-specialized methods.

`M9.SHOR.POSTPROCESS-INFERENCE`

The deterministic continued-fraction/LCM helper and the successful `shor_order` return path must be `@inferred` as `Int`. Run `@code_warntype` on `mulmod!` and the post-processing loop and reject `Any` in hot paths.

---

## 8. Risks, rejected alternatives, and human rulings

### 8.1 Principal risks

1. **Bennett compatibility of overflow-free modular multiplication.** The fixed-loop comparison/addition helper must be probed before implementation. If unsupported, M9 needs a different fixed reversible arithmetic implementation, not overflowing multiplication.
2. **Compiler size.** Compiling both directions roughly doubles arithmetic compilation and gate storage before sharing ancilla. Resource estimation should be exposed on `CompiledInplacePerm`.
3. **Per-modulus specialization.** `Val(N)` is correct for the algebra but can create many specializations in workloads processing thousands of unrelated moduli.
4. **Generic inverse cutoff.** `W=16` is a conservative engineering bound, not a mathematical one. Exact replay cost also depends on compiled gate count.
5. **M8 integration.** `PermClean` must recognize the private in-place compiler origin without creating a general “trust this Perm” escape hatch.
6. **Statistical runtime.** One thousand complete order-finding trials may be expensive with large Bennett ancillas. The suite needs safe value-keyed reuse of compiled artifacts, while still recreating quantum state for every sample.
7. **Candidate poisoning.** Continued-fraction outliers can contaminate an LCM accumulator. The bounded/reset rule affects success rate, but modular verification and final minimization preserve correctness.
8. **Classical minimization cost.** Trial-factorization of a verified exponent is suitable for the M9 examples but is not a scalable factoring primitive.

### 8.2 Alternatives considered and rejected

- **Apply `v ↦ c*v % N` to all padded states:** many-to-one whenever padding exists.
- **Drop or trace the original input after M7 accumulation:** dephases superpositions because the discarded input remains correlated with the output.
- **Use `adjoint(B_f)` after swapping:** computes with `f`, not `f⁻¹`.
- **Apply compute, swap, and inverse as separate surface actions:** complicates control, structural certification, and scratch ownership; one compiler-produced `Perm` is the correct boundary.
- **Store an explicit permutation table:** exponential storage and incompatible with the compact `Perm` representation.
- **Trust a user-provided inverse:** violates fail-fast and lets a dirty scratch theorem become an assertion.
- **Use sampled inverse tests above a cutoff:** samples are diagnostics, not proofs.
- **Permit arbitrary user-defined inverse-witness subtypes:** an open proof hierarchy defeats M8’s closed certificate discipline.
- **Measurement-based uncompute:** excluded under coherent control and unnecessary here.
- **Use one continued-fraction denominator:** returns proper divisors and returns 1 for `s=0`.
- **Return the first verified exponent without minimization:** can return a multiple of the order after a spurious candidate.
- **Runtime modulus field in `QMod`:** erases the symmetry structure from dispatch and makes mixed-modulus errors runtime-dependent.
- **Automatic `BigInt` from `Int(x)`:** makes the eager `Int` constructor return something other than `Int`.
- **Silent overflow or wrapping:** rejected categorically.

### 8.3 Questions requiring human ruling

1. Is `INPLACE_EXHAUSTIVE_MAXW = 16` the accepted generic proof boundary, or should the generic contract admit only closed certified specifications at every width?
2. Should `CompiledInplacePerm` be `public` for library authors, or remain entirely internal to modular arithmetic in M9?
3. Is a typed non-coprime exception carrying the discovered factor preferred over an explicit sum type such as `OrderResult | FactorResult`?
4. Is the static-modulus specialization cost acceptable for the intended `QMod` workload, or should a separately named dynamic representation be scheduled now?
5. Should M9 ship a safe value-keyed cache for `(N,c,W,compiler_kwargs)`, or defer caching until profiling? An `objectid(f)` cache remains forbidden.
6. Is trial-factorization of verified order multiples acceptable as the production §7.7 contract, or should minimization be scoped explicitly to the small-N capstone?
7. Does the M8 reviewer agree that extending `PermClean`’s trusted origins is sufficient, rather than adding a new `InplacePermClean` constructor?
8. What local Shor source should be canonicalized for `docs/physics/shor_order_finding.md` before implementation?

Subject to those rulings, this design removes the F7 nonunitarity, gives the Bennett bridge an explicit in-place contract, makes every successful `shor_order` return exact, resolves both overflow sites loudly, and keeps `QMod` aligned with Julia inference and P7 parametricity.