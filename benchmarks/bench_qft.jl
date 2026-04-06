#!/usr/bin/env julia
# QFT circuit-generation benchmark for Sturm.jl
# Measures: DAG construction time/memory, gate_cancel, QASM export
# Comparable to Wilkening's speed-oriented-quantum-circuit-backend/circuit-gen-results/
#
# Usage: julia --project benchmarks/bench_qft.jl

using Sturm

# ── QFT DAG construction (bypasses trace() NTuple specialisation) ─────

"""
Build an n-qubit QFT DAG using TracingContext directly.
Returns (dag, wires) — avoids NTuple{n} type explosion for large n.
"""
function build_qft_dag(n::Int)
    ctx = Sturm.TracingContext()
    wires = Vector{Sturm.WireID}(undef, n)
    for i in 1:n
        wires[i] = Sturm.allocate!(ctx)
    end
    qubits = [QBool(wires[i], ctx, false) for i in 1:n]

    task_local_storage(:sturm_context, ctx) do
        for j in 1:n
            H!(qubits[j])
            for k in (j+1):n
                when(qubits[k]) do
                    qubits[j].φ += π / 2^(k - j)
                end
            end
        end
        for i in 1:(n ÷ 2)
            swap!(qubits[i], qubits[n - i + 1])
        end
    end

    return ctx.dag, wires
end

# ── Helpers ───────────────────────────────────────────────────────────

function node_type_counts(dag::Vector{Sturm.DAGNode})
    ry = rz = cx = other = 0
    for n in dag
        if n isa Sturm.RyNode;      ry += 1
        elseif n isa Sturm.RzNode;  rz += 1
        elseif n isa Sturm.CXNode;  cx += 1
        else;                        other += 1
        end
    end
    (ry=ry, rz=rz, cx=cx, other=other)
end

function fmt_bytes(b)
    b < 1024       && return "$(b) B"
    b < 1024^2     && return "$(round(b/1024, digits=1)) KB"
    b < 1024^3     && return "$(round(b/1024^2, digits=1)) MB"
    return "$(round(b/1024^3, digits=2)) GB"
end

function fmt_time(t)
    t < 1e-3   && return "$(round(t*1e6, digits=1)) µs"
    t < 1.0    && return "$(round(t*1e3, digits=2)) ms"
    return "$(round(t, digits=3)) s"
end

# ── Wilkening reference data (2000-qubit QFT, from results.csv) ──────

const WILKENING_2000 = Dict(
    "cq_impr"   => (t=0.065,    m=100_040_704),
    "cq"        => (t=0.434,    m=372_199_424),
    "ket"       => (t=27.27,    m=189_083_648),
    "pytket"    => (t=13.77,    m=1_510_604_800),
    "qiskit"    => (t=124.92,   m=5_016_309_760),
    "cirq"      => (t=1329.53,  m=1_333_444_608),
    "pennylane" => (t=58.16,    m=1_452_138_496),
)

# ── Main benchmark ───────────────────────────────────────────────────

function run_benchmarks()
    sizes = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000]

    println("=" ^ 120)
    println("Sturm.jl QFT Circuit-Generation Benchmark")
    println("Comparable to Wilkening et al. speed-oriented-quantum-circuit-backend")
    println("=" ^ 120)

    # Header
    println()
    println(rpad("n", 6),
            rpad("nodes", 10),
            rpad("Ry", 8), rpad("Rz", 8), rpad("CX", 8),
            rpad("trace_t", 12),
            rpad("trace_alloc", 14),
            rpad("dag_live", 14),
            rpad("cancel_t", 12),
            rpad("cancel_Δ", 10),
            rpad("bytes/node", 12))
    println("-" ^ 120)

    results = []

    for n in sizes
        # ── Warmup (first call compiles) ──
        GC.gc(true)
        build_qft_dag(min(n, 5))
        GC.gc(true)

        # ── Trace: build QFT DAG ──
        local dag, wires
        alloc_trace = @allocated begin
            t_trace = @elapsed begin
                dag, wires = build_qft_dag(n)
            end
        end
        dag_live = Base.summarysize(dag)
        n_nodes = length(dag)
        counts = node_type_counts(dag)
        bytes_per_node = n_nodes > 0 ? round(dag_live / n_nodes, digits=1) : 0

        # ── Gate cancel ──
        GC.gc(true)
        local opt_dag
        alloc_cancel = @allocated begin
            t_cancel = @elapsed begin
                opt_dag = gate_cancel(dag)
            end
        end
        n_opt = length(opt_dag)
        delta = n_nodes - n_opt

        push!(results, (n=n, nodes=n_nodes, t_trace=t_trace, alloc_trace=alloc_trace,
                        dag_live=dag_live, t_cancel=t_cancel, n_opt=n_opt,
                        counts=counts, bytes_per_node=bytes_per_node))

        println(rpad(n, 6),
                rpad(n_nodes, 10),
                rpad(counts.ry, 8), rpad(counts.rz, 8), rpad(counts.cx, 8),
                rpad(fmt_time(t_trace), 12),
                rpad(fmt_bytes(alloc_trace), 14),
                rpad(fmt_bytes(dag_live), 14),
                rpad(fmt_time(t_cancel), 12),
                rpad("-$delta", 10),
                rpad(bytes_per_node, 12))
    end

    # ── QASM export benchmark (only for manageable sizes) ──
    println()
    println("QASM export (Channel construction + to_openqasm):")
    println(rpad("n", 6), rpad("qasm_t", 12), rpad("qasm_len", 12), rpad("qasm_alloc", 14))
    println("-" ^ 50)

    for n in [1, 5, 10, 20, 50, 100, 200]
        GC.gc(true)
        dag, wires = build_qft_dag(n)
        iw = ntuple(i -> wires[i], n)
        ow = ntuple(i -> wires[i], n)
        ch = Sturm.Channel{n, n}(dag, iw, ow)

        GC.gc(true)
        local qasm_str
        alloc_qasm = @allocated begin
            t_qasm = @elapsed begin
                qasm_str = to_openqasm(ch)
            end
        end
        println(rpad(n, 6),
                rpad(fmt_time(t_qasm), 12),
                rpad(fmt_bytes(sizeof(qasm_str)), 12),
                rpad(fmt_bytes(alloc_qasm), 14))
    end

    # ── Comparison with Wilkening data ──
    println()
    println("=" ^ 90)
    println("Comparison with Wilkening benchmarks (2000-qubit QFT circuit generation)")
    println("=" ^ 90)
    println()

    r2000 = filter(r -> r.n == 2000, results)
    if !isempty(r2000)
        r = r2000[1]
        println(rpad("Framework", 16), rpad("Time", 14), rpad("Memory", 16), rpad("Nodes", 10))
        println("-" ^ 56)
        println(rpad("Sturm.jl", 16),
                rpad(fmt_time(r.t_trace), 14),
                rpad(fmt_bytes(r.dag_live), 16),
                rpad(r.nodes, 10))
        println(rpad("  (allocated)", 16),
                rpad("", 14),
                rpad(fmt_bytes(r.alloc_trace), 16))
        println()
        for (name, ref) in sort(collect(WILKENING_2000), by=x->x[2].m)
            println(rpad(name, 16),
                    rpad(fmt_time(ref.t), 14),
                    rpad(fmt_bytes(ref.m), 16))
        end
    end

    # ── Scaling analysis ──
    println()
    println("=" ^ 70)
    println("Scaling analysis")
    println("=" ^ 70)
    println()

    # Theoretical: QFT has n H-gates + n(n-1)/2 controlled-Rz + n÷2 swaps
    # H = 2 nodes (Rz + Ry), CRz = 1 node, swap = 3 CX nodes
    # Total = 2n + n(n-1)/2 + 3(n÷2) ≈ n²/2 for large n
    for r in results
        n = r.n
        theoretical = 2n + n*(n-1)÷2 + 3*(n÷2)
        overhead = r.bytes_per_node
        println("n=$(rpad(n, 5))  nodes=$(rpad(r.nodes, 8))  " *
                "theory=$(rpad(theoretical, 8))  " *
                "bytes/node=$(rpad(overhead, 6))  " *
                "total=$(rpad(fmt_bytes(r.dag_live), 12))  " *
                "alloc=$(fmt_bytes(r.alloc_trace))")
    end

    println()
    println("Theoretical node count: 2n + n(n-1)/2 + 3⌊n/2⌋")
    println("Memory lower bound at 16 bytes/node (wire+angle+tag): ",
            fmt_bytes(16 * (2*2000 + 2000*1999÷2 + 3*1000)))
    println("Qiskit at 2000 qubits: ", fmt_bytes(5_016_309_760))
end

run_benchmarks()
