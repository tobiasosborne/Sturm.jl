using Sturm
using Sturm: plus_equal_product!

_t0 = time_ns()
_ms() = round((time_ns() - _t0) / 1e6, digits=1)
_log(msg) = (println("[$(rpad(_ms(), 8)) ms] $msg"); flush(stdout))
_log("ENTER probe_pep_timing")

# Warm-up Bennett JIT with one oracle_table call
_log("warmup: small oracle_table")
@context EagerContext() begin
    x = QInt{2}(1)
    y = oracle_table(j -> j + 1, x, Val(2))
    _log("  oracle_table built; Int(y)=$(Int(y)), Int(x)=$(Int(x))")
end
_log("warmup done")

# Probe 1: minimal plus_equal_product, 1 iteration (Lt=3, Ly=1, window=1)
_log("probe 1: Lt=3 Ly=1 window=1 (single iteration)")
@context EagerContext() begin
    target = QInt{3}(0)
    y = QInt{1}(1)
    plus_equal_product!(target, 3, y; window=1)
    r = Int(target); yv = Int(y)
    _log("  result=$r expected=3; y=$yv")
end
_log("probe 1 done")

# Probe 2: Lt=6 Ly=4 window=1 (4 iterations)
_log("probe 2: Lt=6 Ly=4 window=1 (4 iterations)")
@context EagerContext() begin
    target = QInt{6}(0)
    y = QInt{4}(5)
    plus_equal_product!(target, 3, y; window=1)
    r = Int(target); yv = Int(y)
    _log("  result=$r expected=15; y=$yv")
end
_log("probe 2 done")

_log("EXIT probe_pep_timing")
