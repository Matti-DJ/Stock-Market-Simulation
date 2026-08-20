# Item.jl
# Julia Script

#=
Description: The Item which will be traded in the simulation.
Author: matthiasdejong
Date: 20.08.26
=#

const SCRIPT_VERSION = "1.0.0"

using UUIDs


"""
    A generic Item which can be anything,
    and will be traded among the agents.

- `ID`: unique id for each item
- `value`: current value of the item
- `times_traded`: how often the item was traded
- `unique_owners`: how many unique owners the item had
- `owners`: all of the owners the item had, also duplicates
- `lowest_price`: lowest price the Item was sold for
- `highest_price`: highest price the Item was sold for
"""
mutable struct Item
    ID::UUID
    value::Float64
    times_traded::Int
    unique_owners:Int
    owners::Vecotr{Int}
    lowest_price::Float64
    highest_price::Float64
end

#custom constructor with values that stay the same already filled in
Item(value::Float64) = Item(uuid4(), value, 0, Int[], 0, value, value)


"""
    Assigns owners to the specific instance of the Item.
    -> checks if there already was that owner, if not then adds them to owners and increments unique_owners by 1.

# Params
- `item`: the item which the owners gets assigned to
- `owner_id`: the owner id to check for in item.owners

# return
- `item`: returns the item wth the changed fields
"""
function assign_owner!(item::Item, owner_id::Int)::Item
    if owner_id ∉ item.owners
        push!(item.owners, owner_id)
        item.unique_owners += 1
    end
    return item
end

"""
    Records the trade of an Item
    -> assigns a new owner to the item
    -> assigns the price it was traded as to the item

# Params
- `item`: Item which is traded
- `price`: the price it was bought for
- `buyer_id`: buyer of the item

# Return
- `item`: returns the item which was bought
"""
function record_trade!(item::Item, price::Float64, buyer_id::int)::Item
    item.times_traded += 1
    item.value = price

    item.highest_price < price ? item.highest_price = price
    item.lowest_price > price ? item.lowest_price = price

    assign_owner!(item, buyer_id)
    return item
end
