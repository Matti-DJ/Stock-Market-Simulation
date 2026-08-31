# informed_agent.jl
# Julia Script

#=
Description: Agent has a strategy behind trading.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "2.0.0"
using Agents

"""
    The informed agents uses algorithm to figure out where the market is heading

    It uses UCB1 to try and get the best profit.

- `predicted_high`: What the agent thinks the market value will reach
- `predicted_low`: What the agent thinks the market value will drop to
- `arm_reward`: how much each arm has payed of so far
- `arm_visits`: how often each arm has been chosen
- `total_pulls`: How often all arms were pulled in total
- `last_arm`: what arm was pulled last
- `last_wealth`: agents total wealth
"""
@agent struct InformedAgent(Agent) <: AbstractMarketAgent
    predicted_high::Float64
    predicted_low::Float64
    arm_reward::Vector{Float64} = zeros(3)
    arm_visits::Vector{Int} = zeros(Int, 3)
    total_pulls::Int = 0
    last_arm::Int = 0
    last_wealth::Float64 = 0.0
end
