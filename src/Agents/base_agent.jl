# base_agent.jl
# Julia Script

#=
Description: 
Author: matthiasdejong
Date: 15.08.26
=#

using UUID

mutable struct base_agent
    id::UUID
    money::Float64
    inventory::Vector{Item}
end

function main()
    println("Hello, Julia!")
end

main()
