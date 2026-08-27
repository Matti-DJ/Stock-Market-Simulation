# Item.jl
# Julia Script

#=
Description: 
Author: matthiasdejong
Date: 24.08.26
=#

const SCRIPT_VERSION = "1.0.0"
using UUIDs

"""
    A generic Item which can be anything,
    and will be traded among the agents.

- `ID`: unique id for each item
- `latest_value`: current value of the item
- `times_traded`: how often the item was traded
- `owners`: all of the owners the item had, also duplicates
- `lowest_value`: lowest price the Item was sold for
- `highest_value`: highest price the Item was sold for
"""
mutable struct Item
    ID::UUID
    latest_value::Float64
    times_traded::Int
    Owners::Vector{Int}
    lowest_value::Float64
    highest_value::Float64
end

#simplified constructor
Item(value::Float64) = Item(uuid4(), value, 0, Int[], value, value)

"""
    It updates the `Owners` field for the Item but not the assets field on the Agents side.
    This function also updates all the `value` fields and checks for highs / lows.

#Params
- `item`
- `new_owner_id`
- `item_value`: At which price the Item was traded

THIS ONLY RECORDS THE TRADE ORDER ON THE ITEM SIDE.
"""
function record_trade!(item::Item, new_owner_id::Int, item_value::Float64)::Item

    #assign a new owner to the item
    push!(item.Owners, new_owner_id)

    #assign a new value to the item
    !(item_value < 0) ?  item.latest_value = item_value : error("value can't be negative")

    #checks for new highest and lowest values
    item.lowest_value = min(item.lowest_value, item_value)
    item.highest_value = max(item.highest_value, item_value)

    item.times_traded += 1
    return item
end