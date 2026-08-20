# market_agent.jl
# Julia Script

#=
Description: The market agents acts like a shop which will always buy at a specific price and sell for a specific price.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"

using Agents

"""
    The market agent will always buy and sell at a specific price.
    The price will be updated every few trades.

- `buy_price`: price the agent will always buy for -> item value x 0.95
- `sell_price`: Price which he will always sel for -> item value x 1.05
"""
@agent struct MarketAgent(Agent) <: AbstractMarketAgent
    buy_price::Float64
    sell_price::Float64
end