# Views and duality

*This is the "why" for surface construct 4. It explains what `dual` is, why it
is a view rather than an operation, and the two ways people write it wrong.*

Position and momentum are conjugate: sharpen one and you blur the other, and
the transform that takes you between them is a Fourier transform. Every
register in Sturm has the same structure — a value picture and a conjugate
picture — and `dual(q)` is how you name the second one.

The crucial word is **name**. `dual` does not do anything to the register. It
is an *addressing mode*: a free, lazy wrapper that says "for the next
operation, treat this register in its conjugate basis." Exactly like Julia's
own `transpose(A)`, which does not move any memory.

```julia
using Sturm

Sturm.eager(2) do ctx
    q = QBool(false)
    (dual(dual(q)) === q,      # unwrapping returns the literal same object
     dual(q) === dual(q))      # but each call builds a fresh wrapper
end
# => (true, false)
```

---

## The Pontryagin swap: translation becomes modulation

Here is the whole physical content of the construct. Going through the view
swaps two families of operation:

| In the value picture | Through `dual` |
|---|---|
| `not!(q)` — flip the bit | flip the **sign** |
| `add!(x, a)` — translate by `a` | modulate: attach a phase that varies with the value |
| `q ⊻= r` — a controlled flip | `q̂ ⊻= r` — a controlled **phase** |

The single-qubit case is the easiest to see. `not!` on a register flips its
value; `not!` through the view leaves the value alone entirely and flips the
relative sign instead:

```julia
using Sturm

Sturm.eager(2) do ctx
    q = QBool(false)
    not!(dual(q))
    Bool(q)
end
# => false        -- the value is untouched

Sturm.eager(2) do ctx
    q = plus()     # |+⟩ — definite in the conjugate picture
    not!(dual(q))
    Bool(dual(q))
end
# => true         -- but |+⟩ became |−⟩
```

Reading works the same way round: `Bool(dual(q))` measures in the conjugate
basis. That is the single construct whose absence made version 0.1's
teleportation quietly wrong — see
[why marginal tests lie](functions_are_channels.md).

### For integers: `add!(x, a)` and `x̂ += a` are not the same operation

This is the sharpest instance, and it is easy to misread because both spellings
say "add `a`".

`add!(x, a)` is a **translation**: it moves the value.

```julia
using Sturm

Sturm.eager(6) do ctx
    x = QInt{3}(2); add!(x, 3); Int(x)
end
# => 5

Sturm.eager(6) do ctx
    x = QInt{3}(6); add!(x, 5); Int(x)   # wraps mod 2^3
end
# => 3
```

`x̂ += a`, on a bound dual view, is a **modulation**: it attaches
value-dependent phases and never moves the value at all.

```julia
using Sturm

Sturm.eager(6) do ctx
    x = QInt{3}(2)
    x̂ = dual(x)
    x̂ += 3
    Int(x)
end
# => 2          -- Int(x) is completely unchanged
```

Where it *does* show up is in the conjugate reading. Start from a uniform
superposition (which is a definite state in the conjugate picture) and watch
the two operations do opposite things:

```julia
using Sturm

Sturm.eager(3) do ctx
    x = QInt{3}(0); superpose!(x)
    x̂ = dual(x); x̂ += 1
    Int(dual(x))
end
# => 1        -- modulation shifted the conjugate value

Sturm.eager(3) do ctx
    x = QInt{3}(0); superpose!(x)
    add!(x, 1)
    Int(dual(x))
end
# => 0        -- translation left the conjugate value alone
```

If you ever find yourself writing `x̂ += a` and expecting `Int(x)` to change,
you wanted `add!(x, a)`. If you are writing a phase-kickback program — phase
estimation, order finding — the modulation is exactly what you want.

## Symmetry: `q̂ ⊻= r` and `r̂ ⊻= q` are the same operation

The controlled-phase interaction is symmetric in its two registers. That is a
theorem about the pairing between a group and its dual, not a coincidence of
one implementation, and both spellings are equally correct:

```julia
using Sturm

Sturm.eager(4) do ctx
    q = plus(); r = QBool(true)
    q̂ = dual(q); q̂ ⊻= r
    (Bool(dual(q)), Bool(r))
end
# => (true, true)

Sturm.eager(4) do ctx
    q = plus(); r = QBool(true)
    r̂ = dual(r); r̂ ⊻= q       # the other spelling — same channel
    (Bool(dual(q)), Bool(r))
end
# => (true, true)

Sturm.eager(4) do ctx
    q = plus(); r = QBool(false)   # control is |0⟩, so nothing happens
    q̂ = dual(q); q̂ ⊻= r
    (Bool(dual(q)), Bool(r))
end
# => (false, false)
```

A third spelling of the same thing, using [coherent control](seven_constructs.md):

```julia
using Sturm

Sturm.eager(4) do ctx
    q = plus(); r = QBool(true)
    when(r) do
        not!(dual(q))
    end
    (Bool(dual(q)), Bool(r))
end
# => (true, true)
```

Three spellings, one channel. None of them is a gate.

---

## Two traps

They look alike and they fail in opposite ways, which is exactly why they are
documented side by side.

### Trap 1: `dual(q) ⊻= r` is not writable Julia

Julia's compound-assignment operators need an *assignable location* on the
left. A function call is not one, so the language itself rejects it:

```julia
# WRONG — for illustration; this is a syntax error, not a Sturm error
dual(q) ⊻= r
```

```
syntax: invalid assignment location "dual(q)"
```

The fix is to bind the view first. That is the canonical spelling everywhere
in this documentation:

```julia
# RIGHT
q̂ = dual(q)
q̂ ⊻= r
```

This is loud and immediate — you cannot ship it. The next one, you can.

### Trap 2: `dual(x) = y` silently defines a local function

The same expression with `=` instead of `⊻=` is perfectly valid Julia, and it
does something you almost certainly did not mean: inside a function body,
`dual(x) = y` is a **short-form method definition**. It shadows `dual` for the
whole body.

```julia
# WRONG — for illustration
function trap(q)
    dual(x) = 7        # this defines a local function named `dual`
    return dual(q)     # ... so this calls it, not Sturm's dual
end

trap(3)
# => 7
```

No error. No warning. Every later `dual` in that function silently means your
one-line local instead of the conjugate view, and the failure surfaces
somewhere else entirely. This is a genuine Julia footgun, not a Sturm bug —
but it bites hardest in code that uses `dual` a lot, so it is worth knowing by
name.

### Trap 3: `x += a` on a bare register drops it

Not about views, but it lives in the same neighbourhood. `x + a` is
*value-world* arithmetic: it allocates a **fresh** register holding the sum and
leaves `x` alive. So `x += a`, which Julia lowers to `x = x + a`, rebinds `x`
to the new register and drops the old handle — which is still live, still
entangled with the sum, and now unreachable.

```julia
# WRONG — for illustration
x = QInt{2}(1)
x = x + 1          # drops the original handle
```

There is an opt-in detector. Pass `strict = true` and it names the problem and
the fix:

```
lost binding (strict): register wire(s) [WireID(1)] are being traced at region
exit, but a fresh value-world output (wire WireID(3)) derived from them by a
ring op (`x + a` / `x + y`) survives and is entangled with them — the sum has
decohered. You likely wrote `x = x + a`, which rebinds `x` to the fresh sum and
drops the original handle. Use `add!(x, a)` for in-place addition, `x̂ += a` for
a dual-view modulation, or keep BOTH handles live (return/consume the input).
```

```julia
# RIGHT — in-place, no rebinding
using Sturm

Sturm.eager(8) do ctx
    x = QInt{2}(1); add!(x, 1); Int(x)
end
# => 2
```

Value-world arithmetic is not wrong, it is just a different thing. Used
deliberately it keeps both registers:

```julia
using Sturm

Sturm.eager(8) do ctx
    x = QInt{2}(1)
    s = x + 1              # fresh output; x stays live
    (Int(x), Int(s))
end
# => (1, 2)
```

---

## Why `dual` unwraps instead of applying a transform

There is an implementation choice hiding under `dual(dual(q)) === q`, and it is
load-bearing.

The transform that relates a register to its conjugate picture is a Fourier
transform. Applied *twice*, a Fourier transform is not the identity — it is the
parity map, which negates. So an implementation that lowered `dual` by
literally applying the transform would make every integer come out negated
under a double `dual`. The bug's signature would be silent sign errors deep
inside phase-estimation code.

Sturm avoids it structurally: `dual` of a view **unwraps** — it returns the
stored parent object by dispatch, so nothing is ever applied twice. Julia
itself repaired an analogous bug in its own `transpose`/`adjoint` machinery
before 1.0, at real cost, which is why the pattern here is deliberately the
same one Base uses.

The general machinery underneath (`Sturm.view(V, q)`, for library authors) does
the opposite and **composes** its transforms rather than unwrapping — stacked
general views multiply. `dual` is the surface's single, self-inverse view; the
general form is a kernel tool and never appears in surface code.

## Views are addressing modes, not numbers

A register is a number-like handle: it rides arithmetic overloads, it has a
width, `x + 1` means something. A **view is not**. It carries no value of its
own — it is a lens on someone else's — so it deliberately does not participate
in the numeric overload machinery at all.

```julia
using Sturm

Sturm.eager(2) do ctx
    q = QBool(false); v = dual(q)
    s = Sturm.register_style(typeof(v))
    Bool(q); s
end
# => Sturm.AddressingModeStyle()
```

Hand a view to generic numeric code and you get an honest `MethodError`, the
same wall as any other type mismatch — not a plausible-looking wrong answer.

## Where next

- [The seven constructs](seven_constructs.md) — where `dual` sits.
- [Functions are channels](functions_are_channels.md) — why conjugate-basis
  readout is not optional.
- [Common gotchas](gotchas.md) — this page's traps, plus the rest.
- [Reference: the surface](../reference/surface.md) — `dual`, `view`,
  `DualView`, and the duality traits.
