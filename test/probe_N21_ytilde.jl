# Dump ỹ histogram from shor_order_D(2, 21; t=6) to understand bug.
#
# True peaks for r=6 at t=6:          {0, 11, 21, 32, 43, 53}
# Bit-reversed peaks (if bug is that): {0, 52, 42, 1, 53, 43}
# Uniform would show spread over all 64 values.

const T0 = time_ns()
_log(s) = (println(stderr, "[", round((time_ns()-T0)/1e6; digits=1), " ms] ", s); flush(stderr))

_log("ENTER")
using Sturm
_log("using Sturm OK")

# Also exercise mulmod composition separately.
_log("COMPOSITION TEST: mulmod*mulmod at L=5 N=21")
let
    fails = 0; tests = 0
    for x0 in 0:20, (a, b) in [(2, 4), (4, 16), (2, 16), (16, 11)]
        gcd(a, 21) == 1 && gcd(b, 21) == 1 || continue
        @context EagerContext() begin
            x = QInt{5}(x0)
            c = QBool(1)
            mulmod_beauregard!(x, a, 21, c)
            mulmod_beauregard!(x, b, 21, c)
            got = Int(x)
            expected = ((a * b) * x0) % 21
            tests += 1
            if got != expected
                fails += 1
                _log("  FAIL x0=$x0 a=$a b=$b  got=$got  expect=$expected")
            end
        end
    end
    _log("composition: $fails/$tests fails")
end

_log("ỹ HISTOGRAM: shor_order_D(2, 21; t=6), 40 shots")
hist = Dict{Int, Int}()
for i in 1:40
    @context EagerContext() begin
        # Call into the code path but capture ỹ directly. Reuse shor_order_D's
        # body instead of monkey-patching.
        ctx = current_context()
        L = 5
        t = 6
        N = 21
        a = 2

        a_js = [powermod(a, 1 << (j - 1), N) for j in 1:t]
        c_reg = QInt{t}(0)
        superpose!(c_reg)
        y_reg = QInt{L}(ctx, 1)
        for j in 1:t
            a_j = a_js[j]
            a_j == 1 && continue
            ctrl = QBool(c_reg.wires[j], ctx, false)
            mulmod_beauregard!(y_reg, a_j, N, ctrl)
        end
        interfere!(c_reg)
        discard!(y_reg)
        yt = Int(c_reg)
        hist[yt] = get(hist, yt, 0) + 1
    end
end
sorted = sort(collect(hist); by=x->-x[2])
_log("ỹ:count (top 15 of $(length(hist)) distinct values):")
for (yt, n) in sorted[1:min(15, length(sorted))]
    _log("  ỹ=$yt  count=$n")
end
_log("EXIT")
