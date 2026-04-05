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
    include("test_memory_safety.jl")
end
