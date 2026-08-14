# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Tobias Osborne
#
# Documenter.jl wiring for Sturm.jl. Builds the Diátaxis-structured site under
# docs/src/ (getting_started / tutorials / howto / explanation / reference).
#
# Build:
#   julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#   julia --project=docs docs/make.jl
#   # -> open docs/build/index.html
#
# Notes on the settings below:
#
#   prettyurls = false — the site is browsed locally off the filesystem
#     (file://.../docs/build/index.html). Extensionless "pretty" URLs break
#     file:// navigation.
#
#   doctest = false — prose pages show live-verified output as plain ```julia
#     fences annotated `# =>`, not executed ```jldoctest fences. Every such
#     block was run against the real library before being pasted. Executing
#     them at build time would additionally require a built liborkan on the
#     machine doing the build, which the docs deliberately do not assume.
#
#   no deploydocs(...) — the build is local-only; this repo has no CI.
#
# Only docs/src/ is read. The sibling docs/design/, docs/physics/ and
# docs/literature/ directories are source material for maintainers and are
# untouched by this build.

using Documenter
using Sturm

DocMeta.setdocmeta!(Sturm, :DocTestSetup, :(using Sturm); recursive = true)

makedocs(
    sitename = "Sturm.jl",
    modules = [Sturm],
    authors = "Tobias Osborne",
    pages = [
        "Home" => "index.md",
        "Getting started" => [
            "Installation" => "getting_started/installation.md",
            "Your first program" => "getting_started/first_program.md",
            "Choosing a context" => "getting_started/choosing_a_context.md",
        ],
        "Tutorials" => [
            "Teleportation" => "tutorials/teleportation.md",
            "Deutsch–Jozsa & Bernstein–Vazirani" => "tutorials/deutsch_jozsa.md",
            "Grover search" => "tutorials/grover.md",
            "Shor order finding" => "tutorials/shor.md",
            "Hamiltonian simulation" => "tutorials/hamiltonian_simulation.md",
            "Error correction" => "tutorials/error_correction.md",
        ],
        "How-to guides" => [
            "Measure statistics" => "howto/measure_statistics.md",
            "Write oracles" => "howto/write_oracles.md",
        ],
        "Explanation" => [
            "Functions are channels" => "explanation/functions_are_channels.md",
            "The seven constructs" => "explanation/seven_constructs.md",
            "Views and duality" => "explanation/views_and_duality.md",
            "Contexts and scope" => "explanation/contexts_and_scope.md",
            "Phase discipline" => "explanation/phase_discipline.md",
            "Gotchas" => "explanation/gotchas.md",
        ],
        "Reference" => [
            "Surface" => "reference/surface.md",
            "Contexts" => "reference/contexts.md",
            "Kernel" => "reference/kernel.md",
            "Channels" => "reference/channels.md",
            "Library" => "reference/library.md",
            "QECC" => "reference/qecc.md",
            "Oracle" => "reference/oracle.md",
        ],
    ],
    doctest = false,
    checkdocs = :none,
    warnonly = [:missing_docs, :cross_references, :docs_block],
    format = Documenter.HTML(prettyurls = false),
)
