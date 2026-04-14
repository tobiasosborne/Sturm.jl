using Bennett: gate_count

# Multi-path arithmetic Phase 1 (Sturm.jl-v51):
# (a) oracle(f, x; kw...) passes strategy kwargs through to Bennett.
# (b) QuantumOracle must NOT cache-collide when the same (f, W) is called
#     with different strategy kwargs — the cache key must include the kwargs.

@testset verbose=true "Multi-path arithmetic (Phase 1)" begin

@testset "oracle(f, x; kw...) passes strategy kwargs through to Bennett" begin
    # Regression lock: users can write oracle(f, x; add=:qcla) today and
    # get the carry-lookahead adder; semantics must round-trip through
    # the quantum context. (+1) mod 8 must return 6 from input 5.
    @context EagerContext(capacity=25) begin
        x = QInt{3}(5)
        y = oracle(q -> q + Int8(1), x; add=:qcla)
        @test Int(y) == 6
        @test Int(x) == 5        # Bennett preserves inputs
    end

    # Pass-through is observable in the resource estimator — different
    # strategies yield different Toffoli counts at fixed width.
    r_ripple = estimate_oracle_resources(q -> q + Int8(1), Int8;
                                         bit_width=3, add=:ripple)
    r_qcla   = estimate_oracle_resources(q -> q + Int8(1), Int8;
                                         bit_width=3, add=:qcla)
    @test r_ripple.toffoli == 8
    @test r_qcla.toffoli   == 10
end

@testset "QuantumOracle cache key distinguishes strategy kwargs" begin
    # f(x) = x*x at bit_width=2:
    #   mul=:shift_add  → 14 Toffoli, 19 wires
    #   mul=:qcla_tree  → 36 Toffoli, 29 wires
    # If the cache keys only on W, the second call returns the first
    # circuit and the strategy kwarg is silently ignored.
    qf = quantum(x -> x * x)

    @context EagerContext(capacity=30) begin
        x = QInt{2}(3)
        _ = qf(x; mul=:shift_add)
    end

    @context EagerContext(capacity=30) begin
        x = QInt{2}(3)
        _ = qf(x; mul=:qcla_tree)
    end

    # Expect TWO distinct cached circuits, one per strategy.
    cached_circuits = collect(values(qf.cache))
    toffoli_counts = sort!([gate_count(c).Toffoli for c in cached_circuits])
    @test length(cached_circuits) == 2
    @test toffoli_counts == [14, 36]
end

@testset "QuantumOracle hits cache on repeat calls with identical kwargs" begin
    # Canonicalisation: the same kwargs (in any order) must produce the
    # same key, so the second call reuses the cached circuit.
    qf = quantum(q -> q + Int8(1))

    @context EagerContext(capacity=25) begin
        x = QInt{3}(5)
        _ = qf(x; add=:ripple)
    end

    @context EagerContext(capacity=25) begin
        x = QInt{3}(5)
        _ = qf(x; add=:ripple)
    end

    @test length(qf.cache) == 1   # cache hit, not a second compile
end

@testset "QuantumOracle cache key is invariant under kwarg ordering" begin
    # The canonical cache key sorts kwargs by name, so (add=, mul=) and
    # (mul=, add=) must resolve to the same entry.
    qf = quantum(q -> q + Int8(1))

    @context EagerContext(capacity=25) begin
        x = QInt{3}(5)
        _ = qf(x; add=:qcla, optimize=true)
    end

    @context EagerContext(capacity=25) begin
        x = QInt{3}(5)
        _ = qf(x; optimize=true, add=:qcla)
    end

    @test length(qf.cache) == 1
end

end  # testset
