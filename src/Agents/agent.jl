# agent.jl
# Julia Script

#=
Description: The agent has the purpose of being the structure for other agents.
             It contains all shared fields.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"

using Agents
include("../Item.jl")

abstract type AbstractMarketAgent <: AbstractAgent end


"""
    The generic agent with no behaviour,
    it contains all shared fields.

- `net_worth`: worth of all assets `assets + cash`
- `cash`: cash on hand to buy the items
- `assets`: all items the agent owns
- `shares_bought`: How many shares the agent has bought
- `shares_sold`: how many shares the agent has sold
- `volume_bought`: shares the agent has bought as price
- `volume_sold`: shares the agent has sold as price
- `force_sell`: hwo often the agent was forced to sell
- `avg_time_between_trades`: The average time it takes the agent to do 1 trade
"""
@agent struct Agent(NoSpaceAgent) <: AbstractMarketAgent
    net_worth::Flaot64 = 0.0
    cash::Float64 = 0.0
    assets::Vector{Item} = Item[]
    shares_bought::Int = 0
    shares_sold::Int = 0
    volume_bought::Float64 = 0.0
    volume_sold::Float64 = 0.0
    force_sell::Int = 0
    avg_time_between_trades = 0.0
end
