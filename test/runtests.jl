using Test
using Sturm

@testset "Sturm.jl" begin
    include("test_orkan_ffi.jl")
    include("test_primitives.jl")
    include("test_bell.jl")
    include("test_teleportation.jl")
    include("test_when.jl")
    include("test_gates.jl")
    include("test_rus.jl")
    include("test_qint.jl")
    include("test_patterns.jl")
    include("test_channel.jl")
    include("test_passes.jl")
    include("test_density_matrix.jl")
    include("test_noise.jl")
    include("test_qecc.jl")
    include("test_grover.jl")
    include("test_memory_safety.jl")
    include("test_simulation.jl")
    include("test_promotion.jl")
end
