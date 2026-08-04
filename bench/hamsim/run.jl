# SPDX-License-Identifier: AGPL-3.0-only
#
# Copyright (C) 2026 Tobias Osborne
#
# bench/hamsim/run.jl — CLI entry for the M12 ham-sim frontier bench
# (bead Sturm.jl-gmx0).
#
#   julia --project=bench bench/hamsim/run.jl [--fast] [--only=exec|analytic]
#                                             [--alpha=exact|budgeted|norm1]
#
#   --fast            4-family smoke subset (~2 min including compile)
#   --only=exec       executed tier only (W ≤ 3: measured frontier + slack)
#   --only=analytic   analytic tier only (certified cost curves, all L)
#   --alpha=...       α-mode policy (default budgeted): how grid rows pick
#                     :exact vs :norm1 α — an EXPLICIT run configuration,
#                     deterministic per family, never wall-clock (c8rx).
#                     Non-default policies get their own CSV file tag.
#
# Output: bench/out/{frontier,auto,alpha}-<tag>.csv + a printed summary.
# DETERMINISM (c8rx): given the same command (thus the same --alpha policy),
# two runs on ANY machine at ANY load emit identical CSVs, except the
# `probe_seconds` diagnostic column in alpha-<tag>.csv (wall-clock, recorded
# for calibration only; it influences nothing). Wall-clock can only ABORT a
# run loudly (PROBE_TIMEBOX_S under --alpha=exact), never change modes.

include(joinpath(@__DIR__, "families.jl"))
include(joinpath(@__DIR__, "groundtruth.jl"))
include(joinpath(@__DIR__, "frontier.jl"))

function main(args)
    fast = "--fast" in args
    only = "--only=exec" in args ? :exec :
           "--only=analytic" in args ? :analytic : :all
    alpha_policy = :budgeted
    for a in args
        if startswith(a, "--alpha=")
            alpha_policy = Symbol(chopprefix(a, "--alpha="))
        elseif a ∉ ("--fast", "--only=exec", "--only=analytic")
            error("run.jl: unknown argument $a (see the file header for usage).")
        end
    end
    println("M12 ham-sim frontier bench — fast=$fast only=$only alpha=$alpha_policy")
    println("Sturm ", pkgversion(Sturm), ", Julia ", VERSION)
    run_frontier(; fast, only, alpha_policy)
end

main(ARGS)
