# probe_qrom_cold.jl — Time `qrom_lookup_xor!` on FRESH tables that match
# the actual N=15 c_mul=2 mulmod. Each fresh table is a Bennett.jl cache
# miss → fresh `bennett(lr)` compile. Bead Sturm.jl-059 Stage A0 (real
# bottleneck hunt).

using Sturm
using Sturm: qrom_lookup_xor!, QROMTable
using Sturm: EagerContext

_t0 = time_ns()
_elapsed() = round((time_ns() - _t0) / 1e9, digits=2)
_log(msg) = (println("[$(rpad(_elapsed(), 7))s] $msg"); flush(stdout))

_log("ENTER probe_qrom_cold")

# Mirror the tables that _pep_mod_iter! would build for N=15 c_mul=2.
# In the second pep call k = -a_inv = N - a_inv. With a=4, N=15: a_inv=4
# (since 4*4=16≡1 mod 15), so -a_inv = 11.
# Iters use 2^i mod N at i=0,2,4 (first pep at c_mul=2 with Wtot=5 → 3 iters
# with windows w=2,2,1).
const N_mod = 15
const Wtot = 5

function build_table(k::Int, i::Int, w::Int)
    n = 1 << w
    two_pow_i = powermod(2, i, N_mod)
    entries = Vector{UInt64}(undef, n)
    for j in 0:(n-1)
        v = mod(j * k % N_mod * two_pow_i, N_mod)
        entries[j+1] = UInt64(v)
    end
    return entries, w
end

# Warm a tiny QROM first to force any one-time JIT.
_log("warmup: tiny qrom_lookup_xor! at w=2")
@context EagerContext() begin
    addr = QInt{2}(1)
    target = QInt{Wtot}(0)
    tbl = QROMTable{2, Wtot}(UInt64[1, 2, 3, 4], N_mod)
    qrom_lookup_xor!(target, addr, tbl)
end
_log("warmup done")

# Six fresh tables matching a mulmod c_mul=2 at N=15, a=4.
configs = [
    (k =  4, i = 0, w = 2),   # iter 0 first pep
    (k =  4, i = 2, w = 2),   # iter 1
    (k =  4, i = 4, w = 1),   # iter 2 (ragged)
    (k = 11, i = 0, w = 2),   # iter 0 second pep
    (k = 11, i = 2, w = 2),
    (k = 11, i = 4, w = 1),
]

for (idx, cfg) in enumerate(configs)
    entries, w = build_table(cfg.k, cfg.i, cfg.w)
    _log("call $idx: k=$(cfg.k), i=$(cfg.i), w=$w, entries=$entries")
    if w == 1
        @context EagerContext() begin
            addr = QInt{1}(0)
            target = QInt{Wtot}(0)
            tbl = QROMTable{1, Wtot}(entries, N_mod)
            t = time_ns()
            qrom_lookup_xor!(target, addr, tbl)
            dt = round((time_ns() - t) / 1e6, digits=1)
            _log("  call $idx: $(dt) ms")
        end
    else
        @context EagerContext() begin
            addr = QInt{2}(0)
            target = QInt{Wtot}(0)
            tbl = QROMTable{2, Wtot}(entries, N_mod)
            t = time_ns()
            qrom_lookup_xor!(target, addr, tbl)
            dt = round((time_ns() - t) / 1e6, digits=1)
            _log("  call $idx: $(dt) ms")
        end
    end
end

# Re-call call 1 — cache hit, should be <<1 ms.
_log("re-call 1 (cache hit)")
let cfg = configs[1]
    entries, w = build_table(cfg.k, cfg.i, cfg.w)
    @context EagerContext() begin
        addr = QInt{2}(0)
        target = QInt{Wtot}(0)
        tbl = QROMTable{2, Wtot}(entries, N_mod)
        t = time_ns()
        qrom_lookup_xor!(target, addr, tbl)
        dt = round((time_ns() - t) / 1e6, digits=1)
        _log("  re-call 1: $(dt) ms")
    end
end

_log("EXIT probe_qrom_cold")
