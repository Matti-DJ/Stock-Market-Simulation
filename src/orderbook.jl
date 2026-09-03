# orderbook.jl
# Julia Script

#=
Description: The orderbook hosts and matches all trades which agents put up.
             There is one order book per asset symbol.
Author: matthiasdejong
Date: 24.08.26
=#

const SCRIPT_VERSION = "2.0.0"

using DataStructures
using UUIDs
include("Agents/agent.jl")

"""
    A basic struct for a Trade

# Fields
- `id`
- `symbol`: which asset was traded
- `quantity`: how many units changed hands
- `item_price`: price of a single unit
- `tick`: at which orderbook-tick this trade was executed
- `seller_id`
- `buyer_id`
"""
mutable struct Trade
    id::UUID
    symbol::Symbol
    quantity::Int
    item_price::Float64
    tick::Int
    seller_id::Int
    buyer_id::Int
end

"""
    The sell order which an agent puts up.

#Fields
- `id`
- `seller_id`
- `symbol`: which asset is offered
- `quantity`: units still open on this order
- `item_price`
- `tick`: at which tick in the simulation the order was placed
"""
mutable struct SellOrder
    id::UUID
    seller_id::Int
    symbol::Symbol
    quantity::Int
    item_price::Float64
    tick::Int
end

"""
    The buy order which an agent puts up.

#Fields
- `id`
- `buyer_id`
- `symbol`: which asset is wanted
- `quantity`: units still open on this order
- `item_price`
- `tick`: at which tick in the simulation the order was placed
"""
mutable struct BuyOrder
    id::UUID
    buyer_id::Int
    symbol::Symbol
    quantity::Int
    item_price::Float64
    tick::Int
end


"""
    The order book keeps track of all Sell- and Buy-Orders for a single asset.
    It also is responsible for matching these orders.
"""
mutable struct OrderBook
    symbol::Symbol
    sell_orders::SortedDict{Tuple{Float64, Int}, SellOrder}
    buy_orders::SortedDict{Tuple{Float64, Int}, BuyOrder}
    ticker::Int
    total_items_traded::Int
    total_value_traded::Float64
    all_trades::Vector{Trade}
end

OrderBook(symbol::Symbol) = OrderBook(symbol, SortedDict{Tuple{Float64, Int}, SellOrder}(), SortedDict{Tuple{Float64, Int}, BuyOrder}(), 0, 0, 0.0, Trade[])

function get_total_trades(book::OrderBook)::Int
    return length(book.all_trades)
end

function avg_item_per_trade(book::OrderBook)::Number
    if isempty(book.all_trades); return 0.0; end
    return book.total_items_traded / get_total_trades(book)
end

function avg_volume_per_trade(book::OrderBook)::Number
    if isempty(book.all_trades); return 0.0; end
    return book.total_value_traded / get_total_trades(book)
end

#gets the cheapest sell order, only used buy momentum agents
function get_price_of_cheapest_sellorder(book::OrderBook)
    if isempty(book.sell_orders); return nothing; end
    return first(book.sell_orders)[2].item_price
end

#gets the most expensive buy order, only used by momentum agents
function get_price_of_highest_buyorder(book::OrderBook)
    if isempty(book.buy_orders); return nothing; end
    #only the key stores the negated price, the order itself holds the real price
    return first(book.buy_orders)[2].item_price
end

"""
    Removes all open orders of one agent from the book.
    Nothing has to be given back because the book never holds
    the cash or the units of an open order, only the agent does.

#Params
- `book`
- `agent_id`
"""
function cancel_orders!(book::OrderBook, agent_id::Int)::OrderBook
    for (key, order) in collect(book.sell_orders)
        if order.seller_id == agent_id; delete!(book.sell_orders, key); end
    end
    for (key, order) in collect(book.buy_orders)
        if order.buyer_id == agent_id; delete!(book.buy_orders, key); end
    end
    return book
end

"""
    Records a trade that was triggered by a buy order and logs it.
    On the asset side the price tracking is updated, the buyer gets the units
    added to his holdings and the seller gets them removed.

#Params
- `book`: order book for `asset`
- `model`: the agent based model, used to look up the agents by their id
- `asset`: the asset being traded
- `buyer_id`
- `seller_id`
- `quantity`
- `item_price`
"""
function execute_buy_order!(book::OrderBook, model, asset::Asset, buyer_id::Int, seller_id::Int, quantity::Int, item_price::Float64)::OrderBook
    trade = Trade(uuid4(), asset.symbol, quantity, item_price, book.ticker, seller_id, buyer_id)
    push!(book.all_trades, trade)

    book.total_items_traded += quantity
    book.total_value_traded += quantity * item_price

    #record trade on the asset side
    record_trade!(asset, item_price)

    #record trade on agent side (both counterparties)
    record_sell_order!(model[seller_id], asset.symbol, quantity, item_price, book.ticker)
    record_buy_order!(model[buyer_id], asset.symbol, quantity, item_price, book.ticker)

    book.ticker += 1
    return book
end

"""
    Records a trade that was triggered by a sell order and logs it.
    On the asset side the price tracking is updated, the buyer gets the units
    added to his holdings and the seller gets them removed.

#Params
- `book`: order book for `asset`
- `model`: the agent based model, used to look up the agents by their id
- `asset`: the asset being traded
- `buyer_id`
- `seller_id`
- `quantity`
- `item_price`
"""
function execute_sell_order!(book::OrderBook, model, asset::Asset, buyer_id::Int, seller_id::Int, quantity::Int, item_price::Float64)::OrderBook
    trade = Trade(uuid4(), asset.symbol, quantity, item_price, book.ticker, seller_id, buyer_id)
    push!(book.all_trades, trade)

    book.total_items_traded += quantity
    book.total_value_traded += quantity * item_price

    #record trade on the asset side
    record_trade!(asset, item_price)

    #record trade on agent side (both counterparties)
    record_sell_order!(model[seller_id], asset.symbol, quantity, item_price, book.ticker)
    record_buy_order!(model[buyer_id], asset.symbol, quantity, item_price, book.ticker)

    book.ticker += 1
    return book
end

"""
    Puts a buy order up and tries to match it immediately.
    updates fields for tracking.

#Params
- `book`: order book for `asset`
- `model`: the agent based model, used to look up the agents by their id
- `asset`: the asset being bought
- `buyer_id`
- `quantity`
- `item_price`
"""
function put_up_buy_order!(book::OrderBook, model, asset::Asset, buyer_id, quantity::Int, item_price::Float64)::OrderBook
    order = BuyOrder(uuid4(), buyer_id, asset.symbol, quantity, item_price, book.ticker)

    #find fitting sell orders
    remaining = order.quantity
    while remaining > 0 && !isempty(book.sell_orders)
        key, sell_order = first(book.sell_orders)
        if sell_order.item_price > order.item_price; break; end
        fill_qty = min(remaining, sell_order.quantity)
        execute_buy_order!(book, model, asset, buyer_id, sell_order.seller_id, fill_qty, item_price)
        sell_order.quantity -= fill_qty
        remaining -= fill_qty
        if sell_order.quantity == 0; delete!(book.sell_orders, key); end
    end

    order.quantity = remaining
    #adds the order to buy orders if it can't be completed immediately
    if order.quantity > 0; book.buy_orders[(-order.item_price, order.tick)] = order; end

    book.ticker += 1
    return book
end

"""
    Puts the sell order up and tries to immediately match it to a buy order.
    If it can't find a match it will add it to the `sell_orders` in the book.

#Params
- `book`: order book for `asset`
- `model`: the agent based model, used to look up the agents by their id
- `asset`: the asset being sold
- `seller_id`
- `quantity`
- `item_price`
"""
function put_up_sell_order!(book::OrderBook, model, asset::Asset, seller_id, quantity::Int, item_price::Float64)::OrderBook
    order = SellOrder(uuid4(), seller_id, asset.symbol, quantity, item_price, book.ticker)

    #find fitting buy orders
    while order.quantity > 0 && !isempty(book.buy_orders)
        key, buy_order = first(book.buy_orders)
        if buy_order.item_price < order.item_price; break; end
        fill_qty = min(order.quantity, buy_order.quantity)
        execute_sell_order!(book, model, asset, buy_order.buyer_id, seller_id, fill_qty, item_price)
        order.quantity -= fill_qty
        buy_order.quantity -= fill_qty
        if buy_order.quantity == 0; delete!(book.buy_orders, key); end
    end

    #adds the sell order to the DICT if it can't be filled immediately
    if order.quantity > 0; book.sell_orders[(order.item_price, order.tick)] = order; end

    book.ticker += 1
    return book
end
