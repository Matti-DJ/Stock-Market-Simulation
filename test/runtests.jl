using Test
using Stock_Market_Simulation

@testset "Stock_Market_Simulation tests" begin
    @test Stock_Market_Simulation.greet() === nothing
end
