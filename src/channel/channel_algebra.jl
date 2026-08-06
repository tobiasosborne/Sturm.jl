# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# This file is part of Sturm.jl. Milestone M11 (bead Sturm.jl-qmpo), design
# `docs/design/m11-82su-synthesis.md` S1/S2: the `⊗` methods for channel values.
# Split from `channel/channel_values.jl` for include-order only (the shipped
# structs-early/methods-late pattern): `⊗` is BORN in `kernel/algebra.jl`, so
# methods on it must come after. Everything else channel-value lives in
# `channel_values.jl`.
#
# Deliberately absent, BY CONSTRUCTION (S7, §4.4): no `⊗`/`∘` method mixes a
# `ProcessValue` with a `ChannelValue` — the denotation quotient is crossed
# explicitly (`channel(v) ⊗ 𝓝`), never coerced.

"""
    ⊗(a::ChannelValue, b::ChannelValue) -> ChannelValue

Parallel composition — `a` on the leading (MSB) wire block, the kernel `Tensor`
convention. Lazy `ChannelTensor` in general (LOAD-BEARING: Orkan's channel
entry is 1-local, so i.i.d. noise must stay a tensor of 1-local factors — S1/V3);
two `MixedUnitary`s fuse exactly (S2 closure):
`(Σᵢ wᵢ Ad_{Uᵢ}) ⊗ (Σⱼ vⱼ Ad_{Vⱼ}) = Σᵢⱼ wᵢvⱼ Ad_{Uᵢ⊗Vⱼ}`.
"""
⊗(a::ChannelValue, b::ChannelValue) = ChannelTensor(a, b)

function ⊗(a::MixedUnitary{Wa,Ra}, b::MixedUnitary{Wb,Rb}) where {Wa,Ra,Wb,Rb}
    weights = Float64[a.weights[i] * b.weights[j] for i in 1:Ra for j in 1:Rb]
    unitaries = ProcessValue[a.unitaries[i] ⊗ b.unitaries[j] for i in 1:Ra for j in 1:Rb]
    return MixedUnitary(weights, unitaries)
end
