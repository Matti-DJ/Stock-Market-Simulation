# informed_agent.jl
# Julia Script

#=
Description: Agent has a strategy behind trading.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"

using Agents

"""
    The informed agents uses algorithm to figure out where the market is heading

    The predicted high and low are both a prediction using an algorithm which try to guess the
    market high and lows. These values will update each time the agent is called
    (each trade it is involved in). At the end we can see how close it got to predicting the market.

- `predicted_high`: What the agent thinks the market value will reach
- `predicted_high`: What the agent thinks the market value will drop to
"""
@agent struct InformedAgent(Agent) <: AbstractMarketAgent
    predicted_high::Float64
    predicted_low::FLoat64
end
