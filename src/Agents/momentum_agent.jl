# momentum_agent.jl
# Julia Script

#=
Description: The agent trades based on where the market is heading.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"
using Agents


"""
    The momentum trades moves with the market meaning:
        -> if the market goes up for for a set amount of times consecutively then it buys in
        -> if the market goes down for a set amount of times then it sells
            -> the agents get teh information through the order book

- `times_waited`: Tracks how often the agent had to wait for the market to go up / down
- `avg_time_between_trades`: tracks the avg time between 2 trades
"""
@agent struct MomentumAgent(Agent) <: AbstractMarketAgent
    times_waited::Int
    avg_time_between_trades::Float64
end