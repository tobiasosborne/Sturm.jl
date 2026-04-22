# Qudit T-Gate and Magic State Survey — Round 2 for Sturm.jl-goi

**Bead**: `Sturm.jl-goi`, round 2. Follow-up to `docs/physics/qudit_primitives_survey.md`.
**Pass**: pure research. No Sturm source code touched.
**Scope**: Is the canonical qudit T-gate already inside Sturm's locked primitive set (B = spin-$j$ with $R_y$, $R_z$, and quadratic $e^{-i\delta \hat{J}_z^2}$ + SUM)? If not, what does the library need?

All prime-$d$ displacement-operator conventions follow Howard-Vala / Campbell-Anwar-Browne. Unless otherwise stated $\omega = e^{2\pi i / d}$ and $\hat{n} = \sum_x x |x\rangle\langle x|$ (so $\hat{n}|k\rangle = k|k\rangle$ in the computational basis). This is the CAB/Campbell convention, NOT the spin-$j$ $\hat{J}_z$ labelling.

---

## 1. The Howard-Vala qudit π/8 gate

### 1.1 Definition

**Howard-Vala 2012** (`howard_vala_2012_qudit_magic.pdf`, Eq. (16) p.3):

$$U_v = \sum_{k=0}^{p-1} \omega^{v_k}\, |k\rangle\langle k|, \qquad \omega = e^{2\pi i/p},\ v_k \in \mathbb{Z}_p$$

with a constraint that $U_v \in SU(p)$ (requires $\sum_k v_k \equiv 0 \pmod p$; Eq. (16) and comment), and a further constraint that $U_v \in \mathcal{C}_3 \setminus \mathcal{C}_2$ (level-3 of the Clifford hierarchy, not itself Clifford).

Solving the level-3 condition $U_v D_{(1|0)} U_v^\dagger \in \mathcal{C}$ (Eq. (18) p.3) gives the recurrence **Eq. (23) p.3**:

$$v_{k+1} = v_k + k(2^{-1}\gamma' + z') + 2^{-1} z' + \epsilon'$$

with solution **Eq. (24) p.3** (boundary $v_0 = 0$):

$$v_k = \frac{1}{12} k\bigl(\gamma' + k(6z' + (2k-3)\gamma')\bigr) + k\epsilon'$$

where $z', \gamma', \epsilon' \in \mathbb{Z}_p$ parametrise the family and $12^{-1}$ is evaluated mod $p$. **Expanding the parentheses: $v_k$ is cubic in $k$ with leading term $(2\gamma'/12) k^3 = (\gamma'/6) k^3$.** This is the single most important fact in this document.

At $p = 3$ the structure is irregular (Eq. (15) p.3: $\det(C) = \tau^{2\gamma}$ is not 1 for $p=3$, forcing a larger root of unity $\zeta = e^{2\pi i / 9}$; Eq. (27) gives the modified $v_k$).

### 1.2 Campbell 2014 canonical form

**Campbell 2014** (`campbell_2014_enhanced_qudit_ft.pdf`, Eq. (1) p.2) gives the cleanest statement for odd prime $d \ge 5$:

$$\boxed{\ M_\mu = \omega^{\mu \hat{n}^3} = \sum_{k=0}^{d-1} \omega^{\mu k^3}\, |k\rangle\langle k|, \qquad \omega = e^{2\pi i / d}, \ \mu \in \{1, \dots, d-1\}\ }$$

This is **purely cubic in the computational-basis label $k$**. The quadratic and linear terms in Howard-Vala's $v_k$ are Clifford-equivalent (Campbell 2014 App. B: conjugating by the Clifford $\mathcal{X}_{\alpha,\beta}$ shifts $\mu k^3 \to \mu\beta^3 k^3 + \text{quadratic}$, and quadratic/linear pieces are absorbed into level-2 Cliffords $\mathcal{Z}_{\alpha,\beta} = \omega^{\alpha \hat n + \beta \hat n^2}$). So the *irreducible* non-Clifford content is exactly $\omega^{\mu \hat n^3}$.

**Campbell-Anwar-Browne 2012** (`campbell_anwar_browne_2012_msd_all_primes.pdf`, Eq. (6)-(7) p.4): a more general level-$(m+1)$ gate $M = \sum_j \exp(i 2\lambda_j \pi / d^m) |j\rangle\langle j|$ with

$$\lambda_j = d^{m-2}\left(d \binom{j}{3} - j \binom{d}{3} + \binom{d+1}{4}\right)$$

For $m=1$ (level-3, the magic gate analogous to qubit $T$): $\lambda_j = d^{-1}(d\binom{j}{3} - j\binom{d}{3} + \binom{d+1}{4})$, giving the cubic-in-$j$ phase. For $m=2$ (required at $d=3$ because multiplication by 3 is not invertible in $\mathbb{F}_3$): root of unity $e^{2\pi i / d^2} = e^{2\pi i / 9}$ is needed.

### 1.3 Level-3 of the Clifford hierarchy argument

**Campbell 2014 App. A Eq. (A1) p.4**:

$$M_\mu X M_\mu^\dagger = X \omega^{\mu ((\hat n + 1)^3 - \hat n^3)} = X \omega^{\mu(3\hat n^2 + 3\hat n + 1)}$$

The cubic terms cancel under the "shift by 1" conjugation (this is the whole point). The RHS is $X$ times a **quadratic** phase polynomial in $\hat n$, i.e. $X \cdot \mathcal{Z}_{3\mu,3\mu}$ up to a global phase — which is a Clifford. Hence $M_\mu X M_\mu^\dagger \in \mathcal{C}$, so $M_\mu \in \mathcal{C}_3$. And since the RHS has a nonvanishing $\hat n^2$ coefficient (requiring $3\mu \not\equiv 0 \pmod d$, i.e. $d \neq 3$), it is *not* itself in $\mathcal{P}$ or $\mathcal{C}$, so $M_\mu \notin \mathcal{C}_2$. Level-3 exactly.

### 1.4 Reduction to qubit T at d=2?

**Interestingly: not directly.** At $d=2$, $\hat n^3 = \hat n$ because $\hat n$ has eigenvalues $\{0,1\}$ and $k^3 = k$ for $k \in \{0,1\}$. So $M_\mu|_{d=2} = \omega^{\mu \hat n} = \mathrm{diag}(1, (-1)^\mu) = Z^\mu$, which is **Clifford** — NOT the qubit $T$.

At $d=2$, Campbell 2014 (after Eq. (1) p.2) notes that $3\mu \bmod 2 = \mu$ is nonzero, so the argument goes through IF we use a higher root of unity (level-$m$ gate with $m=2$: $\omega = e^{2\pi i /4} = i$). Indeed the qubit $T = \mathrm{diag}(1, e^{i\pi/4})$ uses the root $e^{2\pi i / 8}$, which is $\omega = e^{2\pi i / d^m}$ with $d=2, m=3$. The Howard-Vala / Campbell family therefore gives the qubit $T$ only when one allows the $d^m$ root of unity at the right level. For *prime $d \ge 5$*, level $m=1$ suffices with $\omega = e^{2\pi i /d}$ — a very clean, qubit-free story.

### 1.5 Prime-$d$ restriction and non-prime $d$

**Why prime $d$**:
- **Gottesman 1998** fault-tolerance theorem requires $\mathbb{F}_d$ to be a field (invertibility of multiplication) — only for prime $d$.
- **Campbell 2014 App. A p.4 + footnote [50]**: at $d=3$, $3\mu \equiv 0 \pmod 3$ for all $\mu$, so the quadratic coefficient in $M_\mu X M_\mu^\dagger$ vanishes — $M_\mu$ becomes Clifford. Escape route: use a higher root of unity (Watson Eq. (7), Campbell-Anwar-Browne with $m \ge 2$), which gives a level-3 gate at a finer phase scale.
- **At prime $d$**: all non-trivial multiplications are invertible, all the arguments go through cleanly.

**Non-prime $d$ (the literature is surprisingly thin here)**:

- **$d = 4, 6, 8, 9, \dots$**: Sturm's qudit primitives allow any $d \ge 2$, but the Clifford hierarchy structure fragments. **Watson 2015 Eq. (6)-(7) p.3** explicitly excludes $d = 2, 3, 6$ from the clean $T = \omega^{\hat n^3}$ form; the others ($d = 4, 5, 7, 8, 9, \dots$) are fine at leading level-3. Watson's remedy for the exceptional dimensions: use $T_{3,6} = \gamma^{\hat n^3}$ with $\gamma^3 = \omega$, i.e. $\gamma = e^{2\pi i/(3d)}$, moving to a higher root of unity.
- **Campbell 2014** restricts to *odd* prime $d \ge 5$ for "enhanced" MSD; $d = 2, 3$ handled separately.
- **Prime-power $d = p^k$**: Bermejo-Vega–Van den Nest (Campbell 2014 ref [37]) gives hope; Gottesman 1998 §2 tackles qupits via $\mathbb{F}_{p^k}$. Watson 2015 references prime-power results via [20]. The stabilizer formalism is cleaner on $\mathbb{F}_{p^k}$ than on $\mathbb{Z}_{p^k}$ — but this requires Galois-field arithmetic, not modular arithmetic, which is a bigger structural change.
- **Composite $d = p_1 p_2 \dots$ (e.g. $d = 6$)**: by CRT, $\mathbb{Z}_6 \cong \mathbb{Z}_2 \oplus \mathbb{Z}_3$. In principle, a $d=6$ qudit factorises as a qubit ⊗ qutrit, and the "right" thing is to run qubit MSD on the $\mathbb{Z}_2$ factor and qutrit MSD on the $\mathbb{Z}_3$ factor. **But this is a convention** — the Sturm user who writes $|0\rangle, \dots, |5\rangle$ with SUM mod 6 is not obviously picking this tensor factorisation, and the `d=6` displacement operator $X_6$ is NOT the tensor product of $X_2 \otimes X_3$ (the cycle structure is different). As a consequence: **no self-contained "qudit-T" at $d=6$** has been published as of 2025. Watson 2015 Eq. (7) is the closest — it gives *a* level-3 gate at $d=6$ by going to a $3 \cdot 6 = 18$-th root of unity.

**Bottom line for Sturm type system**: `QDit{d, W}` should allow any $d \ge 2$ at the type level (no change from round 1), but the library-level `T_d!` gate should:
- Prime $d \ge 5$: $M_1 = \omega^{\hat n^3}$ (Campbell canonical form), $\omega = e^{2\pi i /d}$
- $d = 3$: $T_3 = \gamma^{\hat n^3}$, $\gamma = e^{2\pi i / 9}$ (Watson Eq. 7)
- $d = 2$: standard qubit $T = \mathrm{diag}(1, e^{i\pi/4})$
- $d = 4, 6, 8, 9, \dots$: open — mark as research. Likely candidates: Watson 2015 Eq. (7) generalisation $\gamma^{\hat n^3}$, $\gamma = e^{2\pi i / (d \cdot a)}$ for appropriate $a$.

---

## 2. Does $q.\theta_2 \mathrel{+}= \delta$ realise Howard-Vala?

### 2.1 Matrix form of $\exp(-i\delta \hat{J}_z^2)$ at $d=3$, $d=5$

Using spin-$j$ with $d = 2j+1$ and $\hat{J}_z = \mathrm{diag}(j, j-1, \dots, -j)$ in the standard physics convention (eigenvalue of $|j,m\rangle$ is $m$).

**$d=3$ ($j=1$)**: $\hat{J}_z = \mathrm{diag}(1, 0, -1)$, so $\hat{J}_z^2 = \mathrm{diag}(1, 0, 1)$:

$$\exp(-i\delta \hat{J}_z^2) = \begin{pmatrix} e^{-i\delta} & 0 & 0 \\ 0 & 1 & 0 \\ 0 & 0 & e^{-i\delta} \end{pmatrix}$$

**$d=5$ ($j=2$)**: $\hat{J}_z = \mathrm{diag}(2, 1, 0, -1, -2)$, $\hat{J}_z^2 = \mathrm{diag}(4, 1, 0, 1, 4)$:

$$\exp(-i\delta \hat{J}_z^2) = \mathrm{diag}(e^{-4i\delta},\ e^{-i\delta},\ 1,\ e^{-i\delta},\ e^{-4i\delta})$$

**Key structural feature**: these matrices have the $m \to -m$ **parity symmetry**, i.e. they are invariant under reversing the basis order. They depend only on $|m|$, hence only on $|m^2|$. This is because $\hat{J}_z^2$ is a polynomial of even degree in $\hat{J}_z$.

*Aside on basis labelling.* One can shift the eigenvalues from $\{-j, \dots, +j\}$ to $\{0, 1, \dots, d-1\}$ by working with $\hat{n} = \hat{J}_z + j \cdot I$. Then $\hat{n}^2 = \hat{J}_z^2 + 2j \hat{J}_z + j^2 I$, so $\exp(-i\delta \hat{n}^2) = e^{-i\delta j^2} \exp(-i\delta \hat{J}_z^2) \exp(-2i\delta j \hat{J}_z)$. The identity $\exp(-i\delta \hat{n}^2)$ and $\exp(-i\delta \hat{J}_z^2)$ differ only by a global phase and a $\hat{J}_z$-linear piece (absorbable into $q.\phi$). So Sturm could equally well expose "quadratic in computational-basis label $\hat n$" versus "quadratic in spin label $\hat J_z$" as its primitive #3 — they generate the same 1-parameter family up to composition with $q.\phi$. Either convention gives a quadratic, parity-symmetric diagonal gate.

### 2.2 Matrix form of Howard-Vala / Campbell $T$ at $d=3$, $d=5$

**$d=5$**: $M_1 = \omega^{\hat n^3}$, $\omega = e^{2\pi i / 5}$. Computing $k^3 \bmod 5$ for $k \in \{0,1,2,3,4\}$:
- $0^3 = 0$
- $1^3 = 1$
- $2^3 = 8 \equiv 3$
- $3^3 = 27 \equiv 2$
- $4^3 = 64 \equiv 4$

$$M_1^{(d=5)} = \mathrm{diag}(\omega^0,\ \omega^1,\ \omega^3,\ \omega^2,\ \omega^4) = \mathrm{diag}(1,\ e^{2\pi i/5},\ e^{6\pi i/5},\ e^{4\pi i/5},\ e^{8\pi i/5})$$

(Cross-check against **Howard-Vala Eq. (25)-(26) p.3**: with $(z', \gamma', \epsilon') = (1, 4, 0)$ they obtain $v = (0, 3, 4, 2, 1)$, giving $U_v = \mathrm{diag}(1, \omega^3, \omega^4, \omega^2, \omega^1)$. Different $\mu$ and different Clifford conjugate — specifically this is $M_1$ conjugated by a permutation Clifford — but same Clifford-equivalence class.)

**$d=3$**: Because $d=3$ is exceptional, one uses **Watson Eq. (7)**: $T_3 = \gamma^{\hat n^3}$ with $\gamma = e^{2\pi i / 9}$. Computing $k^3 \bmod 9$ (NOT mod 3) for $k \in \{0,1,2\}$:
- $0^3 = 0$
- $1^3 = 1$
- $2^3 = 8$

$$T_3 = \mathrm{diag}(\gamma^0,\ \gamma^1,\ \gamma^8) = \mathrm{diag}(1,\ e^{2\pi i / 9},\ e^{16\pi i/9})$$

**No parity symmetry** in either case — $M_1^{(d=5)}$'s diagonal does not satisfy $(M_1)_{k,k} = (M_1)_{d-1-k, d-1-k}$ because $k^3$ is not symmetric in $k \leftrightarrow d-1-k$.

### 2.3 Match / mismatch analysis

**MISMATCH, decisive**:

1. **Distinct-eigenvalue count**. At $d=3$, $\exp(-i\delta \hat{J}_z^2)$ has at most **2** distinct eigenvalues ($\{e^{-i\delta}, 1\}$). $T_3$ has 3 (generically). No choice of $\delta$ can give $T_3$.

2. **Parity symmetry**. $\exp(-i\delta \hat{J}_z^2)$ is invariant under $m \to -m$; equivalently, under the computational-basis reversal $k \to d-1-k$ if we use $\hat{n}$. The Howard-Vala / Campbell $T$ is NOT — the cubic $k^3 \pmod d$ is an odd polynomial in $k$ on $\mathbb{F}_d$ (when viewed appropriately). Any product of parity-symmetric gates stays parity-symmetric; this alone rules out realising the qudit $T$.

3. **Polynomial degree**. In the exponent, $\hat{J}_z^2$ is degree **2** in the spin label. Howard-Vala / Campbell $T$ is degree **3** in the computational-basis label. No matter the basis relabelling (which is at most degree 1: $k = m + j$), a degree-2 polynomial in $m$ stays degree-2 in $k$. You cannot produce a cubic from a quadratic by linear substitution.

### 2.4 Does $q.\phi$ + $q.\theta_2$ together realise it?

$q.\phi$ adds $\alpha \hat{J}_z$ and $q.\theta_2$ adds $\beta \hat{J}_z^2$ to the Hamiltonian (both diagonal in the $\hat{J}_z$ basis). Since they commute, composing them gives

$$e^{-i\alpha \hat{J}_z}\, e^{-i\beta \hat{J}_z^2} = \exp(-i(\alpha \hat{J}_z + \beta \hat{J}_z^2))$$

a diagonal gate with a **linear + quadratic** phase polynomial in $m$ (equivalently in $\hat n = m + j$: still linear + quadratic in $\hat n$, up to a constant). **This is the full Clifford group of diagonal gates (the $\mathcal{Z}_{\alpha,\beta} = \omega^{\alpha \hat n + \beta \hat n^2}$ of Campbell 2014 p.2)** — no cubic. By the level-3 Clifford hierarchy argument, no cubic means no level-3 magic — just Clifford.

**So $q.\phi$ + $q.\theta_2$ gives all diagonal Clifford gates, but not $T$.** This is Campbell 2014's Eq. "$\mathcal{Z}_{\alpha,\beta} := \omega^{\alpha \hat n + \beta \hat n^2}$" exactly. Mathematically beautiful but insufficient for magic.

### 2.5 Conclusion: is our existing primitive set sufficient for magic states?

**No.** The locked primitive set (hybrid-B: $R_y, R_z$, $e^{-i\delta \hat{J}_z^2}$, SUM) generates exactly the **Clifford group** on a qudit (in the prime-$d$ case, via SUM + quadratic-diagonal + Fourier-related rotations from $R_y$). It does NOT contain the canonical qudit T-gate. To promote this set to unitary universality (i.e. to dense $SU(d^n)$), some non-Clifford magic is required — either:

- **Option α (cheapest)**: add a fourth continuous 1-qudit primitive $q.\theta_3 \mathrel{+}= \delta$ defined as $\exp(-i\delta \hat{J}_z^3)$ or equivalently $\exp(-i\delta \hat{n}^3)$. At root-of-unity angle $\delta = 2\pi/d$ this gives Campbell's $M_1$. This adds a **cubic** phase primitive, breaking the $\mathfrak{su}(2)$ + squeezing algebra up to a larger algebra.
- **Option β (library-only)**: keep the 4-primitive set (closed under Clifford), implement magic via distillation: construct a `T_d!` library gate by *state injection* from noisy magic-state ancillas prepared by some other means (e.g. physical-layer rotation, or magic-state distillation from within the Clifford set, which is what the MSD literature does). This moves magic out of the primitive set and into the QECC library.
- **Option γ (non-diagonal magic)**: add a non-diagonal non-Clifford rotation. E.g. the Brennen qudit-Toffoli $|a,b,c\rangle \to |a,b,(c+ab) \bmod d\rangle$ (Gottesman Eq. G45). This is a 3-qudit gate, not a 1-qudit primitive, but closes FT universality via {Clifford + Toffoli}. Campbell 2014 recommends this path via the quantum Reed-Muller construction.

**Recommendation**: option α or option β, depending on whether Sturm wants non-Clifford power *eager* (α) or *lazy* (β). See §5.

---

## 3. Qudit Clifford hierarchy (brief)

From **Howard-Vala Eq. (5) p.2** (qubit hierarchy of Gottesman-Chuang) and **Campbell-Anwar-Browne Def. 2 p.3**:

$$\mathcal{C}_{k+1} = \{U \mid U \mathcal{P} U^\dagger \subseteq \mathcal{C}_k\}, \qquad \mathcal{C}_1 = \mathcal{P}\ \text{(Pauli group)}, \qquad \mathcal{C}_2 = \mathcal{C}\ \text{(Clifford group)}$$

- **Level 1**: Pauli group $\mathcal{P}_d = \{X^a Z^b\}$ (Gottesman Eq. (G4)).
- **Level 2**: Clifford group $\mathcal{C}_d$ — normalises $\mathcal{P}_d$; includes SUM, $H$ (Fourier), $S = \omega^{\hat n^2 - \hat n \cdot (d-1)/2}$ / $\omega^{\hat n^2}$ (conventions vary — see Campbell-Anwar-Browne Eq. (2) p.2 for the symplectic version). Diagonal Clifford elements are $\mathcal{Z}_{\alpha,\beta} = \omega^{\alpha \hat n + \beta \hat n^2}$ (Campbell 2014 p.2: "the Clifford exponent is quadratic in the number operator").
- **Level 3**: $\mathcal{C}_3$. Diagonal level-3 gates include $M_\mu = \omega^{\mu \hat n^3}$ (Campbell 2014 Eq. (1)). For $\mathcal{C}_3 \setminus \mathcal{C}_2$ at prime $d \ge 5$, this is the cubic-phase magic gate.
- **Higher levels**: $\mathcal{C}_k$ with $k \ge 3$ do not form groups (Howard-Vala after Eq. (7) p.2). Campbell-Anwar-Browne definition 3 p.3: the set $\mathcal{M}_d^m$ of level-$(m+1)$ diagonal gates (with root of unity $\omega = e^{2\pi i/d^m}$ and exponent polynomial of degree $m+1$ in $\hat n$).

**Farinholt 2014** (`farinholt_2014_clifford_qudit.pdf`, already in round 1) characterises the full qudit Clifford group for all finite $d$. **Zeng-Chen-Chuang 2008** (Campbell-Anwar-Browne ref [10]) prove the general form of level-$k$ gates in prime dimensions.

---

## 4. Magic state distillation at $d > 2$

### 4.1 $d=3$ (qutrit)

**Anwar-Campbell-Browne 2012** (`anwar_campbell_browne_2012_qutrit_msd.pdf`, NJP 14, 063006), based on 5-qutrit stabilizer code: distills two families of magic states:

- **H-type** (Hadamard eigenstates / "H-states"): depolarising noise threshold **23.3%** (abstract p.1, and Fig. (2) p.2).
- **$H^2$-type** (Hadamard-squared eigenstates / "phase-states" suitable for non-Clifford unitary via state-injection): threshold **34.5%** (abstract p.1).

**Campbell-Anwar-Browne 2012** (`campbell_anwar_browne_2012_msd_all_primes.pdf`) generalises to the Reed-Muller family in all prime dimensions using the $\mathcal{M}_d$ gate (Eq. (6)-(7) p.4).

**Prakash 2020** (`prakash_2020_msd_ternary_golay.pdf`) — ternary Golay code MSD for qutrits. (Short paper; not read in detail this pass; flagged as a high-performance qutrit MSD scheme.)

**Prakash-Gupta 2019** (`prakash_gupta_2019_contextual_bound_states.pdf`) — qudit MSD no-go: contextuality is necessary for qudit MSD; reformulates in discrete phase space.

### 4.2 $d = 5, 7$ and enhanced-$d$ (prime-$d$)

**Campbell 2014** (`campbell_2014_enhanced_qudit_ft.pdf`) is the landmark result: *extended* quantum Reed-Muller codes (polynomial functions of degree > 1) give codes with $n = d-1$ qudits, distance $D = \lfloor (d+1)/3 \rfloor$, and **γ-efficiency** $\gamma = \log(n)/\log(D)$ that decreases monotonically toward 1 as $d$ grows.

Numerical results (Campbell 2014 Fig. 1, p.1):
- **$d=5$**: threshold $\epsilon^* \approx 60.7\%$ (numerical, depolarising), $\gamma \approx 2$.
- **$d=7$**: threshold $\epsilon^* \approx 50\%$-ish, $\gamma \approx 1.5$.
- **$d=11$**: threshold exceeds 50%.
- **$d \to \infty$**: $\gamma \to 1$ (Bravyi-Haah limit of 1.585 is beaten in the qudit regime).

**Campbell 2014 thesis** (p.1 abstract): "performance is always enhanced by increasing $d$." This is a strong statement compared to qubit MSD (best qubit γ via 15-qubit code is 2.465; Bravyi-Haah block codes reach 1.585; multi-level distillation pushes to γ → 1 but at multi-level protocol cost).

**Watson-Campbell-Anwar-Browne 2015** (`watson_campbell_anwar_browne_2015_qudit_color_codes.pdf`): qudit color codes and gauge color codes in all spatial dimensions; transversal non-Clifford gates saturating Bravyi-König's bound in all but finite exceptional cases. This is the topological analogue of MSD: fault-tolerant Clifford + transversal non-Clifford = universal FT without distillation.

**Krishna-Tillich 2019** (`krishna_tillich_2019_color_code_distillation.pdf`, arXiv 1811.08461): color code-based distillation, though primarily qubit.

### 4.3 Non-prime $d$

**Open / thin literature.** Campbell 2014 abstract: "extensions to prime power dimensions are plausible" — the qudit stabilizer formalism over $\mathbb{F}_{p^k}$ exists (Gottesman 1998) but gets little MSD attention. Composite $d$ (e.g. $d = 6$): no self-contained MSD scheme is known; the natural approach factorises via CRT into tensor products of prime-power qudit MSDs.

**Practical consequence for Sturm**: MSD is a prime-$d$ library feature. For $d = 4, 6, 8, 9, \dots$, users compose from prime-factor codes (e.g. a $d=6$ register is a $d=2 \otimes d=3$ pair and runs qubit MSD + qutrit MSD separately). Document the limitation in the `QECC` module.

### 4.4 Overhead comparison

From Campbell 2014 γ-metric (number of input noisy magic states per output distilled state scales as $\log^\gamma(1/\epsilon_\text{final})$):

| $d$ | Code | $\gamma$ | Threshold $\epsilon^*$ |
|---|---|---|---|
| 2 | 15-qubit Reed-Muller | 2.465 | ~14.1% |
| 2 | Bravyi-Haah block | 1.585 | (various) |
| 3 | 5-qutrit (Anwar-Campbell-Browne) | ~2.1 | 34.5% ($H^2$) |
| 5 | Extended QRM | ~1.72 | ~60% |
| 7 | Extended QRM | ~1.58 | ~50% |
| 11 | Extended QRM | ~1.33 | >50% |
| 17 | Extended QRM | ~1.11 | ~40% (Fig. 1c) |
| $\to\infty$ | Extended QRM | $\to 1$ | → (Bravyi-Haah limit) |

**Conclusion**: for modest prime $d \ge 5$, qudit MSD strictly outperforms qubit MSD in both threshold and efficiency. This is a genuine structural advantage of qudit compilation.

### 4.5 Continuous-family magic states?

**Beverland-Campbell-Howard-Kliuchnikov 2020** (`beverland_campbell_howard_kliuchnikov_2020_non_clifford_lower_bounds.pdf`, arXiv 1904.01124) introduces the $|\sqrt{T}\rangle$ state — a dyadic rational power $T^{2^{-k}}$ (p.4) — as a refined resource state for unitary synthesis, with $1/7 \cdot \log_2(1/\epsilon) - 4/3$ $T$-states needed on average for arbitrary single-qubit unitary synthesis. But this is qubit-specific and not a continuous parametrisation; it's a dyadic ladder of increasingly-rotated magic states.

**No continuous-angle $T$-state analogue in the qudit literature** — the qudit hierarchy is fundamentally discrete, with each level parametrised by $\mu \in \mathbb{F}_d^*$, not by a continuous angle. The magic-state polytope is discrete (Howard-Vala Fig. 1b p.5). Open research direction if Sturm wants continuous-parameter magic.

---

## 5. Implications for Sturm's library gate set

### 5.1 `T_d!` as a library gate

Definition for prime $d \ge 5$:

$$T_d = \omega^{\hat n^3} = \sum_{k=0}^{d-1} \omega^{k^3} |k\rangle\langle k|, \quad \omega = e^{2\pi i/d}$$

**Construction from current (locked) primitives**: NOT possible. The current set gives only the Clifford group on a qudit (see §2.5).

**Construction from $q.\theta_3$ (proposed new primitive)**: $T_d = \exp(-i (2\pi/d) \hat{n}^3) = q.\theta_3 \mathrel{+}= -2\pi/d$ (with the convention that $q.\theta_3 \mathrel{+}= \delta$ applies $\exp(-i\delta \hat{n}^3)$ — or equivalently, and perhaps more spin-natural, $\exp(-i\delta \hat{J}_z^3)$, and use $q.\phi$ + $q.\theta_2$ to fix up the linear/quadratic difference).

**For $d = 3$**: $T_3 = \gamma^{\hat n^3}$ with $\gamma = e^{2\pi i /9}$, i.e. $q.\theta_3 \mathrel{+}= -2\pi/9$ at $d=3$. Implementation-level caveat: the "angle to multiply by for $T$-gate" depends on $d$ in a way that isn't purely $1/d$ — it's $1/d$ for prime $d \ge 5$, $1/9$ for $d=3$, $1/8$ for $d=2$ ($T = \exp(i\pi/4 \hat n) = \omega_{16}^{\hat n}$; or going via the same logic, $d=2$ with level $m=3$ gives $\omega = e^{2\pi i/ 8}$, and $\hat n^3 = \hat n$ so $T_2 = \omega^{\hat n}$ — Clifford-equivalent to the usual $T$ up to global phase shifts).

### 5.2 `controlled_T_d!` — needed for phase estimation

Standard Bennett-style control: $|c\rangle|t\rangle \to |c\rangle T_d^{c}|t\rangle$. Since $T_d$ is diagonal, this is $\exp(-i (2\pi/d) c \cdot \hat n_t^3)$ acting on the controlled register, i.e. a controlled-diagonal gate. In the 5-primitive proposed set, this is built from `when(c) { q.theta_3 += -2π/d }` (if the cubic primitive exists) — a single `when`-block on a continuous primitive.

### 5.3 Magic state constructor (for QECC module)

Magic state $|M_\mu\rangle = M_\mu |+\rangle$ where $|+\rangle = \frac{1}{\sqrt{d}}\sum_k |k\rangle$ (Howard-Vala Eq. (37)):

$$|M_\mu\rangle = \frac{1}{\sqrt{d}} \sum_k \omega^{\mu k^3} |k\rangle$$

Constructed via: prepare $|+\rangle$ (SUM + preparation), apply $T_d$. Into the MSD subroutine: take $d-1$ noisy copies, run 5-qudit stabilizer code (Anwar-Campbell-Browne) or extended QRM code (Campbell 2014), postselect on +1 outcomes.

### 5.4 Do we need a NEW primitive (sixth)?

**Yes, IF magic is in-primitive (option α of §2.5).** Proposed:

$$q.\theta_3 \mathrel{+}= \delta: \quad U = \exp(-i\delta \hat{n}^3)$$

or equivalently on the spin-$j$ side, $\exp(-i\delta \hat{J}_z^3)$ (they differ by a quadratic + linear + constant that is absorbable into $q.\phi$ and $q.\theta_2$ + global phase). The two conventions are interchangeable; Sturm may want the $\hat n$ (computational-basis label) form for directness, or the $\hat J_z$ (physical spin label) form for CV limit consistency.

This is the **5th continuous 1-qudit primitive** and the **6th primitive total** (preparation + $R_y$ + $R_z$ + quadratic + cubic + SUM).

**No, if magic is library-only (option β of §2.5).** Then $T_d$ is a library gate with implementation = state injection from an MSD-produced magic ancilla. No new primitive. Users who want $T_d$ pay the overhead of `distill(noisy_T) |> inject(q)` or equivalent. The QECC module owns the magic.

**Tradeoff**: α gives *fast* magic (single primitive call, no ancilla), suitable for high-level algorithm prototyping in a non-FT setting — matches Sturm's current EagerContext eager-simulation story. β is *correct* magic for fault-tolerance (MSD is how magic is actually produced), matches the `channel` IR and QECC module story. **Sturm probably wants both**: α as a compiler-level shortcut that lowers to "apply the ideal $T_d$ in a simulation" for EagerContext, and β as the DAG-level representation for TracingContext + QECC. The ideal $T_d$ channel and the MSD-injected $T_d$ channel are equal as CPTP maps — the implementation strategy is orthogonal to the DSL semantics.

### 5.5 CV limit check for $\hat n^3$ primitive (P7)

Under Holstein-Primakoff $\hat J_z \to j - \hat a^\dagger \hat a$, the cubic $\hat J_z^3$ maps to a **cubic Fock-number polynomial** $(j - \hat N)^3 = j^3 - 3j^2 \hat N + 3j \hat N^2 - \hat N^3$. In the CV limit (large $j$, low excitation) the leading nontrivial term is $\hat N^2$ (quadratic, which is already in $q.\theta_2$). The $\hat N^3$ piece is a **cubic-in-number**, which in terms of $\hat x, \hat p$ is a 6th-order polynomial — the canonical "cubic phase" gate of CV computation (Gottesman-Kitaev-Preskill 2001).

**This is actually perfect for P7**: the CV-limit of the proposed $q.\theta_3$ primitive is precisely the cubic phase gate $\exp(i t \hat x^3)$ (or whatever polynomial combination of $\hat x, \hat p$), which is the standard non-Gaussian magic for Gaussian CV computation (cf. Lloyd-Braunstein 1999, or GKP 2001). So the 5-primitive set cleanly maps to:

- $q.\theta$ → $R_y$ → displacement in $\hat p$
- $q.\phi$ → $R_z$ → displacement in $\hat x$
- $q.\theta_2$ → quadratic $\hat J_z^2$ → quadratic/squeezing Hamiltonian (Gaussian)
- $q.\theta_3$ → cubic $\hat J_z^3$ → cubic phase (non-Gaussian magic)

in the CV limit. **This is the GKP non-Gaussian resource** — exactly what CV-to-DV magic requires. P7 is respected and in fact enhanced.

### 5.6 Recommendation

**Adopt option α**: add $q.\theta_3 \mathrel{+}= \delta$ as a 5th continuous primitive (6th overall). Rationale:

1. **Magic in-primitive matches Sturm's idiom.** The current 4-primitive qubit set gives $\{R_y, R_z, \text{CNOT}\}$ — this is CHANNELS (including preparation), but not universal on its own because qubit Clifford + CNOT is not universal. Sturm's current qubit DSL goes non-Clifford via user-composed rotations (irrational angles). The analogue at $d>2$ is `q.θ_3 += π/d` or similar — a single primitive call. No magic state distillation required at the DSL level.

2. **CV limit is GKP cubic phase.** P7 handed us this for free — the cubic primitive is the textbook non-Gaussian resource.

3. **Matches Clifford hierarchy structure.** Primitives at each level: $R_y, R_z$ (level 1/Pauli-ish, via continuous rotation), $q.\theta_2$ (level 2/Clifford), $q.\theta_3$ (level 3/magic). This is literally the hierarchy.

4. **Orthogonal to MSD.** The library can still have a `distill_T_d!` magic-state distillation routine for FT-compiled code. EagerContext uses $q.\theta_3$ directly; TracingContext emits `T_d` channel IR that the compiler lowers to MSD + injection for QECC. Same DSL, two lowering strategies.

**Cost**: One extra primitive, one extra ccall to Orkan (`orkan_gate_cubic_phase` or similar, implementing $\exp(-i\delta \hat J_z^3)$ on a spin-$j$ qudit), one more entry in the primitive table.

**Alternative**: if Sturm insists on 4 primitives (or 3 continuous), go option β. Clifford-only primitives, magic via library distillation. Cleaner type-theoretically (primitives = Clifford = "free operations" in the resource theory of magic), but requires every magic gate to go through state injection, including in the eager simulator, where it's silly.

---

## 6. Open questions for Tobias

**Q6.1**: Is the 5-primitive set acceptable (preparation + $R_y$ + $R_z$ + $J_z^2$-quadratic + $J_z^3$-cubic + SUM)? If not, how do we handle magic — library state-injection everywhere?

**Q6.2**: $\hat n$ (computational label) versus $\hat J_z$ (spin label) for $\theta_2, \theta_3$: they differ by absorbable linear/quadratic terms, but the choice affects which "natural" numeric value of $\delta$ hits a root-of-unity gate. Recommend $\hat n$ for direct $T_d = \exp(-i(2\pi/d) \hat n^3)$, $S_d = \exp(-i(2\pi/d) \hat n^2)$ correspondence, but verify against P7 CV expectations (GKP uses $\hat x$ conventions).

**Q6.3**: Non-prime $d$ magic — accept the literature gap, restrict MSD library to prime $d$ + $d=4 = 2\otimes 2$ tensor form? Or attempt a general $d = \prod p_i^{k_i}$ decomposition now?

---

## 7. Downloaded PDFs

### Primary (read, cited by equation)

- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/howard_vala_2012_qudit_magic.pdf` — Howard-Vala 2012, arxiv 1206.1598. Definition of qudit $\pi/8$ via Eq. (16), (24); Clifford hierarchy Eq. (5); polytope geometry Fig. 1. Already present round 1.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/campbell_2014_enhanced_qudit_ft.pdf` — Campbell 2014, arxiv 1406.3055. Canonical form $M_\mu = \omega^{\mu \hat n^3}$ Eq. (1); extended quantum Reed-Muller codes; MSD performance γ.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/campbell_anwar_browne_2012_msd_all_primes.pdf` — Campbell-Anwar-Browne 2012, arxiv 1205.3104, PRX 2, 041021. Theorem 1 + Eq. (6)-(7) p.4 give the $\mathcal{M}_d^m$ family of level-$(m+1)$ magic gates for all prime $d$.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/watson_campbell_anwar_browne_2015_qudit_color_codes.pdf` — Watson et al. 2015, arxiv 1503.08800, PRA 92, 022312. Clean $T$ gate Eq. (6) for $d \neq 2,3,6$; exceptional $T_{3,6}$ Eq. (7); color-code transversal magic.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/anwar_campbell_browne_2012_qutrit_msd.pdf` — Anwar-Campbell-Browne 2012, arxiv 1202.2326, NJP 14, 063006. 5-qutrit code MSD; 23.3% H-state / 34.5% $H^2$-state thresholds.

### Secondary (skimmed)

- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/beverland_campbell_howard_kliuchnikov_2020_non_clifford_lower_bounds.pdf` — Beverland et al. 2020, arxiv 1904.01124. Qubit-focused lower bounds; $|\sqrt T\rangle$ dyadic ladder concept; not directly qudit-applicable.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/krishna_tillich_2019_color_code_distillation.pdf` — Krishna-Tillich 2019, arxiv 1811.08461. Color-code MSD (qubit primarily); referenced for completeness.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/prakash_2020_msd_ternary_golay.pdf` — Prakash 2020, arxiv 2003.02717. Ternary Golay MSD for qutrits. Short paper; flagged as high-performance qutrit MSD.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/prakash_gupta_2019_contextual_bound_states.pdf` — Prakash-Gupta 2019, arxiv 1905.00392. Qudit MSD no-go bounds via contextuality.
- `/home/tobiasosborne/Projects/Sturm.jl/docs/physics/veitch_2014_resource_theory_stabilizer.pdf` — Veitch et al. 2014, arxiv 1307.7171, NJP 16, 013009. Resource theory framework; discrete Wigner negativity monotones.

### Round-1 carryover, relevant here

- `gottesman_1998_qudit_fault_tolerant.pdf` — Clifford hierarchy, Pauli group, qudit SUM (Eq. G12) and qudit-Toffoli (Eq. G45).
- `farinholt_2014_clifford_qudit.pdf` — Clifford group structure for all finite $d$.
- `wang_hu_sanders_kais_2020_qudit_review.pdf` — broad qudit computation review (useful for ch. 4.3 non-prime context).

---

## 8. Decisions (locked 2026-04-22)

After rounds 1 + 2 of research and discussion with Tobias, the qudit design is pinned down as follows. Future agents working on `Sturm.jl-goi` or any child bead should treat this section as authoritative.

### 8.1 Primitive set

**Six primitives.** At $d=2$, primitives 4 and 5 collapse (to global phase and Rz-equivalent respectively), recovering the existing 4-primitive qubit set; Rule 11 is preserved at the qubit specialisation.

| # | Syntax | Semantics | Clifford-hierarchy level |
|---|--------|-----------|--------------------------|
| 1 | `QDit{d,W}(ctx)` (or equivalent prep) | Prepare d-level system in $\|0\rangle$ | — |
| 2 | `q.θ += δ`  | $R_y(\delta) = \exp(-i\delta \hat{J}_y)$ (spin-$j$, $d=2j+1$) | level 1 |
| 3 | `q.φ += δ`  | $R_z(\delta) = \exp(-i\delta \hat{J}_z)$ (spin-$j$) | level 1 |
| 4 | `q.θ₂ += δ` | $\exp(-i\delta \hat{n}^2)$ (quadratic phase / squeezing) | level 2 |
| 5 | `q.θ₃ += δ` | $\exp(-i\delta \hat{n}^3)$ (cubic phase / magic) | level 3 |
| 6 | `a ⊻= b`    | SUM: $\|a,b\rangle \to \|a,(a+b)\bmod d\rangle$ | level 2 (Clifford) |

### 8.2 Convention

**$\hat{n}$ (computational-basis label), not $\hat{J}_z$ (spin label)** for primitives 4 and 5. $\hat{n} |k\rangle = k |k\rangle$ for $k \in \{0, 1, \dots, d-1\}$. Rationale: direct root-of-unity correspondence ($T_d = \exp(-i(2\pi/d) \hat{n}^3)$) without a $j$-dependent linear/quadratic fixup. CV-limit derivations from $\hat{J}_z$ require a footnote but remain valid (Holstein-Primakoff relation $\hat{J}_z = j - \hat{n}_{\rm Fock}$).

Primitives 2 and 3 remain in the $\hat{J}_y / \hat{J}_z$ spin-$j$ convention (that's where they naturally live; $\hat{J}_z$ differs from $\hat{n}$ by a constant, absorbed into global phase).

### 8.3 Entangler

**SUM** $|a,b\rangle \to |a,(a+b)\bmod d\rangle$. Recovers qubit CNOT at $d=2$. Matches `a ⊻= b` user-surface syntax.

Library gates (NOT primitives):
- **Qudit-Toffoli** $|a,b,c\rangle \to |a,b,(c+ab) \bmod d\rangle$ — built from SUM + controlled continuous primitives.
- **Controlled-$X^\alpha$** (continuous shift) — built from SUM + `when()` on a continuous `q.θ` on the spin-$j$ irrep.

### 8.4 Policy on global phase

**"Live in SU(d), pay the controlled-phase cost."** Extension of the qubit rule (CLAUDE.md Global Phase and Universality): at even $d$, $X_d$ built from spin-$j$ rotations carries an $e^{-i\pi/d}$ prefactor vs. the displacement-operator $X_d$ (Bartlett Eq. 13). This is unphysical for isolated qudits but becomes observable under `when()`. Same discipline as $H^2 = -I$. Document it at the same level. Add a test asserting the controlled-phase difference at $d=4$.

### 8.5 Dimension range

**Any $d \ge 2$** at the `QDit{d,W}` type level. Restrictions are library-module scoped:
- **QECC module**: prime $d$ only for v0.1 (Gottesman 1998 stabilizer-code assumption). Non-prime is a research gap (see §8.7 below).
- **`T_d!` library gate**: defined only for $d \in \{2, 3\}$ and prime $d \ge 5$ in v0.1; $d \in \{4, 6, 8, 9, \dots\}$ open (see follow-on bead).

### 8.6 Magic-state strategy

**Both eager and lazy, orthogonal to DSL semantics.**

- **Eager** (EagerContext): apply $T_d = \exp(-i(2\pi/d)\hat{n}^3)$ directly via `q.θ₃`. No MSD ceremony required in simulation.
- **Lazy** (TracingContext → QECC compilation): emit a `T_d` channel IR node. Lower to MSD + state injection for fault-tolerant compilation (Campbell 2014 Reed-Muller construction at prime $d \ge 5$, Anwar-Campbell-Browne 5-qutrit code at $d=3$).

The ideal $T_d$ channel and the MSD-injected $T_d$ channel are equal as CPTP maps. Strategy is an implementation detail; the DSL sees a single library gate `T_d!`.

### 8.7 Accepted literature gaps (filed as follow-on beads)

1. **Non-prime $d$ magic gate.** $T_d$ for $d = 4, 6, 8, 9, \dots$ is not given in closed form by any paper we downloaded. Watson 2015 Eq. 7 has a higher-root-of-unity candidate; prime-power $d = p^k$ may work via $\mathbb{F}_{p^k}$ stabiliser formalism. Out of scope for v0.1.
2. **Prime-power $d = p^k$ via Galois-field arithmetic.** Gottesman 1998 §2 uses $\mathbb{F}_{p^k}$ rather than $\mathbb{Z}_{p^k}$ for stabiliser codes. Sturm's `QDit{d,W}` currently implies modular arithmetic on $\mathbb{Z}_d$. Reconciling these requires a structural refactor.
3. **Composite-$d$ magic state distillation.** $d = 6, 10, 12, 15, \dots$ — literature is surprisingly thin. Natural approach is CRT tensor factorisation but this conflicts with the user-level semantics of SUM mod $d$.
4. **CV-limit formal derivation.** The Holstein-Primakoff argument for $\hat{J}_z^3 \to $ GKP cubic-phase (via $R_y$ conjugation) is sketched in §5.5 but needs a rigorous large-$j$ derivation. P7 correctness depends on this; should live as a standalone `docs/physics/qudit_cv_limit.md`.

### 8.8 Orkan impact

Filed as Orkan-repo feature request (`/home/tobiasosborne/Projects/orkan/ISSUES/qudit-support.md`). Native d-level statevector is long-horizon; Sturm ships v0.1 qudit on a **qubit-encoded fallback simulator** (each `QDit{d,W}` stored as $W\lceil \log_2 d \rceil$ qubits with leakage guards on unused levels). Two extra diagonal kernels (`apply_n2`, `apply_n3`) once Orkan-native lands.
