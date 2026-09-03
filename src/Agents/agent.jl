# agent.jl
# Julia Script

#=
Description: The agent has the purpose of being the structure for other agents.
             It contains all shared fields.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "2.0.0"
using Agents

abstract type AbstractMarketAgent <: AbstractAgent end


"""
    The generic agent with no behaviour,
    it contains all shared fields.

- `cash`: cash on hand to buy assets
- `holdings`: how many units of each asset the agent owns, keyed by symbol
- `items_bought`: how many units the agent has bought in total
- `items_sold`: how many units the agent has sold in total
- `volume_bought`: units bought valued at their trade price
- `volume_sold`: units sold valued at their trade price
- `ticks_of_trades`: the tick of each trade
- `buy_orders`
- `sell_orders`
- `starting_cash`
- `starting_holdings`: units of each asset the agent was handed at the start
"""
@agent struct Agent(NoSpaceAgent) <: AbstractMarketAgent
    cash::Float64 = 0.0
    holdings::Dict{Symbol, Int} = Dict{Symbol, Int}()
    items_bought::Int = 0
    items_sold::Int = 0
    volume_bought::Float64 = 0.0
    volume_sold::Float64 = 0.0
    ticks_of_trades::Vector{Int} = Int[]
    buy_orders::Int = 0
    sell_orders::Int = 0
    starting_cash::Float64 = 0.0
    starting_holdings::Dict{Symbol, Int} = Dict{Symbol, Int}()
end

"""
    How many units of `sym` the agent currently holds (0 if it holds none).
"""
holding(agent::AbstractMarketAgent, sym::Symbol) = get(agent.holdings, sym, 0)

"""
    Total number of units the agent holds across every asset.
"""
total_units(agent::AbstractMarketAgent) = sum(values(agent.holdings); init = 0)

"""
    Settles a buy on the agent side: pays the cash and adds the units.

# Params
- `agent`: the agent who bought
- `sym`: which asset was bought
- `quantity`: how many units
- `item_value`: price per unit
- `tick`: the tick at which the trade was done
"""
function record_buy_order!(agent::AbstractMarketAgent, sym::Symbol, quantity::Int, item_value::Float64, tick::Int)::AbstractMarketAgent
    cost = quantity * item_value
    (agent.cash - cost >= 0) ? agent.cash -= cost : error("Not enough Money")
    agent.holdings[sym] = holding(agent, sym) + quantity

    agent.items_bought += quantity
    agent.volume_bought += cost

    push!(agent.ticks_of_trades, tick)
    agent.buy_orders += 1

    return agent
end

"""
    Settles a sell on the agent side: removes the units and takes in the cash.

# Params
- `agent`: the agent who sold
- `sym`: which asset was sold
- `quantity`: how many units
- `item_value`: price per unit
- `tick`: the tick at which the trade was done
"""
function record_sell_order!(agent::AbstractMarketAgent, sym::Symbol, quantity::Int, item_value::Float64, tick::Int)::AbstractMarketAgent
    holding(agent, sym) >= quantity || error("Not enough items to sell")
    agent.holdings[sym] -= quantity

    proceeds = quantity * item_value
    agent.cash += proceeds

    agent.items_sold += quantity
    agent.volume_sold += proceeds

    push!(agent.ticks_of_trades, tick)
    agent.sell_orders += 1

    return agent
end
