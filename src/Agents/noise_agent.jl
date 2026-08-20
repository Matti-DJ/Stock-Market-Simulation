# noise_agent.jl
# Julia Script

#=
Description: The noise agent trades randomly without any stetegy or algorithm.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"

using Agents

"""
    The noise agent trades randomly.
    It has no unique / specific fields.
"""
@agent struct NoiseAgent(Agent) <: AbstractMarketAgent end
