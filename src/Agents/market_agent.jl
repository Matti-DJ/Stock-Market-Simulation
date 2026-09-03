# market_agent.jl
# Julia Script

#=
Description: The market agent acts like a shop which will always buy at a
             specific price and sell for a specific price, per asset.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "2.0.0"
using Agents

"""
    The market agent will always buy and sell at a specific price per asset.
    The prices get updated every few ticks by `reprice_market_agents!`.

- `buy_price`: price the agent will buy each asset for, keyed by symbol
- `sell_price`: price the agent will sell each asset for, keyed by symbol
"""
@agent struct MarketAgent(Agent) <: AbstractMarketAgent
    buy_price::Dict{Symbol, Float64} = Dict{Symbol, Float64}()
    sell_price::Dict{Symbol, Float64} = Dict{Symbol, Float64}()
end
