# agent.jl
# Julia Script

#=
Description: The agent has the purpose of being the structure for other agents.
             It contains all shared fields.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.2.0"
using Agents

abstract type AbstractMarketAgent <: AbstractAgent end


"""
    The generic agent with no behaviour,
    it contains all shared fields.

- `cash`: cash on hand to buy the items
- `assets`: all items the agent owns
- `items_bought`: How many items the agent has bought
- `items_sold`: how many items the agent has sold
- `volume_bought`: items the agent has bought as price
- `volume_sold`: items the agent has sold as price
- `ticks_of_trades`: The tick of each trade
- `buy_orders`
- `sell_orders`
"""
@agent struct Agent(NoSpaceAgent) <: AbstractMarketAgent
    cash::Float64 = 0.0
    assets::Vector{Item} = Item[]
    items_bought::Int = 0
    items_sold::Int = 0
    volume_bought::Float64 = 0.0
    volume_sold::Float64 = 0.0
    ticks_of_trades::Vector{Int} = Int[]
    buy_orders::Int = 0
    sell_orders::Int = 0
    starting_cash::Float64 = 0.0
    starting_assets::Vector{Item} = Item[]
end

"""
    Adds the new Items to the agent and updates other fields.

# Params
- `agent`: the agent who bought the items.
- `items`
- `item_value`
- `tick`: The tick at which the trade was done
"""
function record_buy_order!(agent::AbstractMarketAgent, items::Vector{Item}, item_value::Float64, tick::Int)::AbstractMarketAgent
    (agent.cash - (length(items)*item_value) >= 0) ? agent.cash -= (length(items)*item_value) : error("Not enough Money")
    append!(agent.assets, items)


    agent.items_bought += length(items)
    agent.volume_bought += (length(items)*item_value)

    push!(agent.ticks_of_trades, tick)
    agent.buy_orders += 1

    return agent
end

"""
    Removes the sold items from the agent and updates other fields

# Params
- `agent`: the agent who sold the items
- `items`: the items sold
- `item_value`: the price at which the items were sold
- `tick`: The tick at which the trade was done
"""
function record_sell_order!(agent::AbstractMarketAgent, items::Vector{Item}, item_value::Float64, tick::Int)::AbstractMarketAgent
    quantity = length(items)
    all(item -> item in agent.assets, items) ? filter!(a -> !(a in items), agent.assets) : error("Not enough items to sell")

    agent.cash += (quantity * item_value)

    agent.items_sold += quantity
    agent.volume_sold += (quantity * item_value)

    push!(agent.ticks_of_trades, tick)
    agent.sell_orders += 1

    return agent
end

"""
    gets the net_worth with which the agent started with.
"""
function get_starting_net_worth(agent::AbstractMarketAgent)
    starting_assets_value = 0.0
    for starting_asset in agent.starting_assets
        starting_assets_value += starting_asset.latest_value
    end

    return (starting_assets_value + agent.starting_cash)
end

"""
    returns current net worth of agent
"""
function get_current_net_worth(agent::AbstractMarketAgent)
    asset_value = 0.0
    for asset in agent.assets
        asset_value += asset.latest_value
    end

    return (asset_value + agent.cash)
end