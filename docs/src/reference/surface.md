# Reference — the surface language

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. If you are learning the language, start at
[the seven constructs](../explanation/seven_constructs.md) instead.*

Everything on this page except the view machinery and the outcome tokens is
**exported** — `using Sturm` puts it in your namespace. The view types and the
tokens are `public` but not exported, reachable as `Sturm.DualView`,
`Sturm.select`, and so on.

Several surface forms are extensions of `Base` methods on Sturm's own types
and therefore have no name of their own to look up. They are listed here for
completeness:

| Form | What it is | Explained in |
|---|---|---|
| `Bool(q)`, `Int(x)`, `BigInt(x)` | the consuming measurement cast | [seven constructs](../explanation/seven_constructs.md) |
| `convert(Bool, q)` | the implicit measurement cast — warns, then measures | [contexts and scope](../explanation/contexts_and_scope.md) |
| `a ⊻= b`, `q ⊻= b::Bool`, `x ⊻= y` | the xor action family | [seven constructs](../explanation/seven_constructs.md) |
| `q̂ ⊻= r`, `x̂ += a` | bound-view modulations | [views and duality](../explanation/views_and_duality.md) |
| `x[i]` | a borrowed single-wire slice (`WireRef`) | below |
| `x + a`, `x + y` | value-world arithmetic: fresh output, inputs stay live | [views and duality](../explanation/views_and_duality.md) |

---

## Register types

A register is a **handle into a context that owns the state** — not a number,
not a `Number` subtype. `WireID` is the identity core every typed handle wraps;
`AbstractQubit` is the supertype of every single-wire handle, which is why the
whole single-wire action family is written once.

```@docs
WireID
AbstractQRegister
AbstractQubit
QBool
QInt
QMod
WireRef
modulus
contextof
contexttype
RegisterStyle
_modwidth
```

## Preparation literals

`plus()`, `minus()` and `magic_T()` are thin named sugar over the `QBool(p, φ)`
preparation cast. They share one docstring.

```@docs
plus
```

## The action family

In-place operations that mutate a register and return the same handle — which
is what makes `a ⊻= b` a physical operation rather than a rebinding. `add!`
wraps on overflow by design; a preparation *literal* outside the ring is an
error.

```@docs
not!
add!
sub!
superpose!
mulmod!
```

## Views: `dual` and the general mechanism

`dual` is the surface's unique no-argument view and the only one that
*unwraps*; the general `view(V, q)` **composes** its transforms and is a
kernel/library tool. The duality traits declare each register type's pairing
structure — they are declared facts, never inferred from a matrix.

```@docs
dual
view
View
DualView
duality
DualitySpec
bicharacter
pairing_exponent
action_group
ActionFamily
```

## Control and branching

`when` is coherent: nothing collapses, and the body must be unitary.
`cases`/`@cases` are classical: they branch on an outcome that already exists.

```@docs
when
cases
@cases
```

## Outcome tokens and the classical library

What a measurement cast returns under the density and tracing contexts, plus
the small classical toolkit that goes with it. `select` is a multiplexer, not a
branch; `shots` is the sampling entry point; `discard!` closes a record early.

```@docs
ClassicalBit
ClassicalWord
ClassicalTable
select
shots
discard!
width
zext
truncate_word
```

## See also

- [The seven constructs](../explanation/seven_constructs.md) — the same
  material as a language map.
- [Views and duality](../explanation/views_and_duality.md).
- [Reference: contexts](contexts.md) — `@context`, `region`, `ptrace!` and the
  three execution contexts.
- [Reference: the oracle bridge](oracle.md) — surface construct 7.
