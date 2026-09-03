# Asset.jl
# Julia Script

#=
Description: An Asset is one tradeable type in the market (think one stock /
             ticker). Every unit of the same Asset is fungible and shares a
             single price, so an Asset is stored once per simulation and the
             agents only track how many units of it they hold.
Author: matthiasdejong
Date: 03.09.26
=#

const SCRIPT_VERSION = "2.0.0"

"""
    One tradeable asset type in the market.

    Every unit of an asset shares the same price, so the asset lives once in the
    simulation (`sim.assets`) and agents only keep a per-symbol count of the
    units they own (`holdings` on the agent side).

- `symbol`: the asset's ticker, e.g. `:ASSET1`
- `latest_value`: current price of one unit (the price of the last trade)
- `times_traded`: how many trades have touched this asset
- `lowest_value`: lowest price the asset has ever traded at
- `highest_value`: highest price the asset has ever traded at
- `price_history`: every recorded price, oldest first (seeded with the base value)
"""
mutable struct Asset
    symbol::Symbol
    latest_value::Float64
    times_traded::Int
    lowest_value::Float64
    highest_value::Float64
    price_history::Vector{Float64}
end

# simplified constructor: a fresh asset that has never traded
Asset(symbol::Symbol, value::Float64) = Asset(symbol, value, 0, value, value, Float64[value])

"""
    Records a trade against the asset: updates the latest price, the all-time
    low / high, the trade counter and the price history.

    THIS ONLY UPDATES THE ASSET SIDE. Cash and unit counts are settled on the
    agent side (`record_buy_order!` / `record_sell_order!`).

# Params
- `asset`
- `item_value`: the price one unit traded at
"""
function record_trade!(asset::Asset, item_value::Float64)::Asset
    item_value < 0 && error("value can't be negative")

    asset.latest_value = item_value
    asset.lowest_value = min(asset.lowest_value, item_value)
    asset.highest_value = max(asset.highest_value, item_value)
    asset.times_traded += 1
    push!(asset.price_history, item_value)
    return asset
end
