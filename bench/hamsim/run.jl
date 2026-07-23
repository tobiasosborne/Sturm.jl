# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# bench/hamsim/run.jl — CLI entry for the M12 ham-sim frontier bench
# (bead Sturm.jl-gmx0).
#
#   julia --project=bench bench/hamsim/run.jl [--fast] [--only=exec|analytic]
#
#   --fast            4-family smoke subset (~2 min including compile)
#   --only=exec       executed tier only (W ≤ 3: measured frontier + slack)
#   --only=analytic   analytic tier only (certified cost curves, all L)
#
# Output: bench/out/{frontier,auto,alpha}-<tag>.csv + a printed summary.
# Everything is seeded; two runs of the same command emit identical CSVs.

include(joinpath(@__DIR__, "families.jl"))
include(joinpath(@__DIR__, "groundtruth.jl"))
include(joinpath(@__DIR__, "frontier.jl"))

function main(args)
    fast = "--fast" in args
    only = "--only=exec" in args ? :exec :
           "--only=analytic" in args ? :analytic : :all
    for a in args
        a in ("--fast", "--only=exec", "--only=analytic") || error(
            "run.jl: unknown argument $a (see the file header for usage).")
    end
    println("M12 ham-sim frontier bench — fast=$fast only=$only")
    println("Sturm ", pkgversion(Sturm), ", Julia ", VERSION)
    run_frontier(; fast, only)
end

main(ARGS)
