# Reference — error correction

```@meta
CurrentModule = Sturm
```

*Dry, exhaustive lookup. The worked example lives in
[the error-correction tutorial](../tutorials/error_correction.md).*

> **Read this before anything else on the page.** Sturm implements the
> **code-capacity model only**. Encoder, recovery and decoder are assumed
> noiseless and syndrome extraction is assumed perfect. There is **no
> fault-tolerance claim and no threshold claim** here. A logical error rate
> below the physical one is a code-capacity statement and nothing more.

The design idea is that error correction transforms *programs*, not gates: a
protected program is a function from channels to channels. `Protect(enc)` is
literally a callable value of that kind.

`encode_state` and `decode_state` are **exported** — a program genuinely
encodes its own state. Everything else here is `public` but not exported.

---

## Codes and encodings

A `StabilizerCode` is validated over GF(2) at construction: generator count,
no identity generator, pairwise commutativity, independence, normalizer
membership of every logical operator, and that no logical lies in the
stabilizer group. The declared distance is an **honest declaration**, not a
computed value — use `verify_distance` in tests rather than trusting the field.

A `CodeEncoding` pairs a code with a concrete certified encoder (the decoder is
its adjoint, so an encode/decode mismatch is unrepresentable) and a syndrome
correction table that self-validates at construction.

```@docs
StabilizerCode
CodeEncoding
decoder
syndrome
verify_distance
```

### The bit-flip code

`bit_flip_code()` is the three-wire repetition code, and its docstring is blunt
about what that means: its true distance is **1, not 3**. A single `Z` is
already a weight-one logical operator, so the code corrects no phase errors at
all and actively *amplifies* phase noise. It is a bit-flip code; that is the
whole content of the name.

```@docs
bit_flip_code
```

## Encoded state

`encode_state` takes **ownership** of the logical input handles — an affine
transfer, not a copy, so the old handles die loudly on any further use.
`decode_state` applies the adjoint encoder, discards the scratch and hands back
fresh logical handles.

A `CodeBlock` deliberately supports almost nothing else. `not!`, `Bool`, `⊻=`,
`dual`, `when` and `oracle` on a block are all loud refusals, each explaining
what a real implementation would need — a declared transversal gadget under an
explicit fault model, a readout protocol ruling, and so on. That is a design
decision, not a gap: on a noisy block, "transversal-measure-then-vote" and
"decode-then-measure" are genuinely different channels, and Sturm will not
guess which one you meant.

```@docs
encode_state
decode_state
CodeBlock
```

## The superchannel

`PhysicalChannel` and `LogicalChannel` are typed wrappers around a validated
DAG on the code's physical or logical wires; both reject classical outputs,
because an instrument is not a noise model.

`Protect(enc)` is a **callable value**: apply it to a physical channel and you
get the effective logical channel, spliced as decoder ∘ recovery ∘ noise ∘
encoder. `physical_iid` is the easiest way to build the physical noise model in
the first place. Handing `effective_logical_noise` a bare channel *value* is a
loud refusal pointing at `physical_iid` — a channel value says *what* the noise
is, not *where* it acts.

```@docs
PhysicalChannel
LogicalChannel
ChannelTransform
RecoveryPolicy
TableDecoder
NoRecovery
Protect
effective_logical_noise
physical_iid
TRANSFORM_REGISTRY
trace_record!
```

## Fault tolerance: an honest refusal

`fault_tolerant_lift` exists in order to refuse, and to name exactly what a
real lift would require: a fault model, a gadget set with per-code
transversality declarations, a protocol for the non-transversal remainder,
a syndrome-extraction schedule sound under noisy syndromes, and threshold
accounting. The no-go theorem that makes the third item unavoidable is
[Eastin–Knill](https://github.com/tobiasosborne/Sturm.jl/blob/main/docs/physics/eastin_knill_2009_no_universal_transversal.md).

```@docs
FaultModel
GadgetSet
FTImplementation
fault_tolerant_lift
```

## See also

- [Error correction tutorial](../tutorials/error_correction.md).
- [Reference: channels](channels.md) — the channel values and IR this layer
  is built on.
- [Functions are channels](../explanation/functions_are_channels.md) — why
  "QECC is a higher-order function" is the natural spelling.
