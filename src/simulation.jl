# simulation.jl
# Julia Script

#=
Description: Builds the market out of the agents, the items and the order book and runs it.
Author: matthiasdejong
Date: 26.08.26
=#

const SCRIPT_VERSION = "1.2.1"

include("Item.jl")
include("orderbook.jl")
include("Agents/market_agent.jl")
include("Agents/noise_agent.jl")
include("Agents/informed_agent.jl")
include("Agents/momentum_agent.jl")
include("Agents/reverse_momentum_agent.jl")

using UUIDs
using Random
using Statistics

const AGENT_TYPES = (MarketAgent, NoiseAgent, InformedAgent, MomentumAgent, ReverseMomentumAgent)

"""
    configurations for the market simulation.

# Fields
- `max_agents_per_type`
- `max_start_money_per_agent`
- `max_start_items_total`: How many items there is to start total, these are randomly distributed among the agents
- `item_base_value`
- `ticker_limit`: For how many ticks the simulation runs
- `momentum_trade_window`: how many ticks the market has to go into one direction for him to start buying.
- `reprice_tick`: how many ticks it takes for the market agent to have a now price.
"""
struct SimulationConfig
    max_agents_per_type::Int
    max_start_money_per_agent::Float64
    max_start_items_total::Int
    item_base_value::Float64
    ticker_limit::Int
    momentum_trade_window::Int
    reprice_tick::Int
end

SimulationConfig() = SimulationConfig(100, 10000.0, 10000, 30.0, 1000000, 10, 1)

"""
    Holds everything one simulation run needs.

#Fields
- `config`
- `book`
- `agents`
- `items`: all items in the market, looked up by their id
- `agent_index`: used for the trades, looks up an agent by his id
"""
struct Simulation
    config::SimulationConfig
    book::OrderBook
    agents::Vector{AbstractMarketAgent}
    items::Dict{UUID, Item}
    agent_index::Dict{Int, AbstractMarketAgent}
end

# all constructors for making agents
function make_agent(::Type{MarketAgent}, id::Int, config::SimulationConfig)
    base_item_price = config.item_base_value
    starting_cash_sim = rand() * config.max_start_money_per_agent
    MarketAgent(id = id, cash = starting_cash_sim, buy_price = config.item_base_value * 0.95,
        sell_price = config.item_base_value * 1.05, starting_cash = starting_cash_sim)
end

function make_agent(::Type{NoiseAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = rand() * config.max_start_money_per_agent
    NoiseAgent(id = id, cash = starting_cash_sim, starting_cash = starting_cash_sim)
end

function make_agent(::Type{InformedAgent}, id::Int, config::SimulationConfig)
    base = config.item_base_value
    starting_cash_sim = rand() * config.max_start_money_per_agent
    InformedAgent(id = id, cash = starting_cash_sim,
                  predicted_low = base * (0.7 + 0.2rand()),
                  predicted_high = base * (1.1 + 0.2rand()),
                  starting_cash = starting_cash_sim)
end

function make_agent(::Type{MomentumAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = rand() * config.max_start_money_per_agent
    MomentumAgent(id = id, cash = rand() * config.max_start_money_per_agent,
                  times_waited = 0, avg_time_between_trades = 0.0, starting_cash = starting_cash_sim)
end

function make_agent(::Type{ReverseMomentumAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = rand() * config.max_start_money_per_agent
    ReverseMomentumAgent(id = id, cash = rand() * config.max_start_money_per_agent,
                         times_waited = 0, avg_time_between_trades = 0.0,
                         starting_cash = starting_cash_sim)
end

"""
    Creates all agents and puts them into the list.

# Param
- `config`
"""
function create_agents(config::SimulationConfig)
    agents = AbstractMarketAgent[]
    next_id = 1
    for AT in AGENT_TYPES
        for _ in 1:rand(1:config.max_agents_per_type)
                push!(agents, make_agent(AT, next_id, config))
            next_id += 1
        end
    end

    return agents
end

"""
    Distributes the total amount of items among all the agents.
    It does not guarantee that all agents get items.

# Params
- `agents`
- `config`
"""
function distribute_items!(agents::Vector{AbstractMarketAgent}, config::SimulationConfig)
    items = Dict{UUID, Item}()

    for _ in 1:config.max_start_items_total
        item = Item(config.item_base_value)
        agent = rand(agents)

        #record the first owner on the item and give it to the agent
        push!(item.Owners, agent.id)
        push!(agent.assets, item)
        push!(agent.starting_assets, item)
        items[item.ID] = item
    end

    return items
end

# simplified constructor for the Simulation
function Simulation(config::SimulationConfig = SimulationConfig())
    agents = create_agents(config)
    items = distribute_items!(agents, config)
    agent_index = Dict(a.id => a for a in agents)
    return Simulation(config, OrderBook(), agents, items, agent_index)
end

"""
    The current market price of an item.
    It is the price of the last trade, before any trade it is the base value.

# Param
- `sim`
"""
function market_price(sim::Simulation)
    if isempty(sim.book.all_trades); return sim.config.item_base_value; end
    return sim.book.all_trades[end].item_price
end

"""
    Compares the average trade price of the last `window`, to decide whether the market is trending up or down.
    Returns up, down or flat

# Params
- `book`
- `window`: how many trades to look at
"""
function recent_trend(book::OrderBook, window::Int)
    if length(book.all_trades) < 2 * window; return :flat; end
    recent_avg = sum(t.item_price for t in book.all_trades[end-window+1:end]) / window
    prior_avg = sum(t.item_price for t in book.all_trades[end-2*window+1:end-window]) / window
    if recent_avg > prior_avg; return :up; end
    if recent_avg < prior_avg; return :down; end
    return :flat
end

"""
    Recalculates the average time between two trades from the recorded trade ticks.
    Only the momentum agents track this field.

# Param
- `agent`
"""
function update_avg_trade_time!(agent::AbstractMarketAgent)
    if length(agent.ticks_of_trades) >= 2
        agent.avg_time_between_trades = (agent.ticks_of_trades[end] - agent.ticks_of_trades[1]) / (length(agent.ticks_of_trades) - 1)
    end
    return agent
end

"""
    Lets the agent put up a sell order for a random amount of his items.

# Params
- `sim`
- `agent`
- `item_price`
"""
function sell_random_amount!(sim::Simulation, agent::AbstractMarketAgent, item_price::Float64)
    quantity = rand(1:length(agent.assets))
    #the slice makes a new vector, the order takes ownership of it
    put_up_sell_order!(sim.book, sim.agent_index, agent.id, agent.assets[1:quantity], item_price)
end

"""
    Lets the agent put up a buy order for a random amount of items,
    but never for more than his cash can pay for.

# Params
- `sim`
- `agent`
- `item_price`
"""
function buy_random_amount!(sim::Simulation, agent::AbstractMarketAgent, item_price::Float64)
    if item_price <= 0; return sim.book; end
    max_quantity = floor(agent.cash / item_price)
    if max_quantity < 1; return sim.book; end
    #the cap to 3 also keeps the quantity safely inside the Int range for very low prices
    quantity = rand(1:Int(min(3.0, max_quantity)))
    put_up_buy_order!(sim.book, sim.agent_index, agent.id, quantity, item_price)
end

"""
    The noise agent trades randomly:
    a coin flip decides between selling some of his items or buying,
    at a random price around the current market price.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::NoiseAgent)
    cancel_orders!(sim.book, agent.id)
    item_price = market_price(sim) * (0.9 + 0.2rand())

    if !isempty(agent.assets) && rand(Bool)
        sell_random_amount!(sim, agent, item_price)
    else
        buy_random_amount!(sim, agent, item_price)
    end
end

"""
    The market agent always sells at his `sell_price` and buys at his `buy_price`.
    Both prices get updated every `reprice_tick` ticks by `reprice_market_agents!`.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::MarketAgent)
    cancel_orders!(sim.book, agent.id)

    if !isempty(agent.assets) && rand(Bool)
        sell_random_amount!(sim, agent, agent.sell_price)
    else
        buy_random_amount!(sim, agent, agent.buy_price)
    end
end

"""
    The informed agent updates his predictions with the newest market price,
    buys when the market drops under his predicted low
    and sells when it rises over his predicted high.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::InformedAgent)
    cancel_orders!(sim.book, agent.id)
    price = market_price(sim)

    #the predictions drift towards the current market price
    agent.predicted_high = (agent.predicted_high + price * 1.1) / 2
    agent.predicted_low = (agent.predicted_low + price * 0.9) / 2

    if price <= agent.predicted_low
        ask = get_price_of_cheapest_sellorder(sim.book)
        buy_random_amount!(sim, agent, ask === nothing ? price : ask)
    elseif price >= agent.predicted_high && !isempty(agent.assets)
        bid = get_price_of_highest_buyorder(sim.book)
        sell_random_amount!(sim, agent, bid === nothing ? price : bid)
    end
end

"""
    Shared behaviour for the momentum agents: `reversed = false` goes with the
    market, `reversed = true` goes against it. Otherwise the agent just waits.

# Params
- `sim`
- `agent`
- `reversed`
"""
function momentum_step!(sim::Simulation, agent::AbstractMarketAgent, reversed::Bool)
    cancel_orders!(sim.book, agent.id)
    trend = recent_trend(sim.book, sim.config.momentum_trade_window)
    buy_signal = reversed ? trend === :down : trend === :up
    sell_signal = reversed ? trend === :up : trend === :down

    if buy_signal && agent.cash > 0
        ask = get_price_of_cheapest_sellorder(sim.book)
        buy_random_amount!(sim, agent, ask === nothing ? market_price(sim) : ask)
        update_avg_trade_time!(agent)
    elseif sell_signal && !isempty(agent.assets)
        bid = get_price_of_highest_buyorder(sim.book)
        sell_random_amount!(sim, agent, bid === nothing ? market_price(sim) : bid)
        update_avg_trade_time!(agent)
    else
        agent.times_waited += 1
    end
end

agent_step!(sim::Simulation, agent::MomentumAgent) = momentum_step!(sim, agent, false)
agent_step!(sim::Simulation, agent::ReverseMomentumAgent) = momentum_step!(sim, agent, true)

"""
    Gives all market agents a new buy and sell price around the current market price.
    Gets called every `reprice_tick` ticks.

# Param
- `sim`
"""
function reprice_market_agents!(sim::Simulation)
    price = market_price(sim)
    for agent in sim.agents
        if agent isa MarketAgent
            assets_buy_price = 0.0
            for item in agent.assets; assets_buy_price += item.latest_value; end
            avg_buy_price = assets_buy_price / length(agent.assets)
            agent.buy_price = isempty(sim.book.buy_orders) ? sim.config.item_base_value * 0.95 : price * 0.99
            agent.sell_price = isempty(sim.book.sell_orders) ? sim.config.item_base_value * 1.05 : avg_buy_price * 1.01
        end
    end
    return sim
end

"""
    Runs the simulation for `ticker_limit` ticks.
    Each tick one random agent gets to act.

# Param
- `sim`
"""
function run!(sim::Simulation)
    for tick in 1:sim.config.ticker_limit
        agent_step!(sim, rand(sim.agents))
        if tick % sim.config.reprice_tick == 0; reprice_market_agents!(sim); end
    end
    return sim
end

"""
    Prints an overview of the finished simulation:
    the agents, the order book totals and the item value extremes.

# Param
- `sim`
"""
function print_summary(sim::Simulation)
    println("Simulation Summary")
    println("Agents: ", length(sim.agents))
    for AT in AGENT_TYPES
        agents_of_type = filter(a -> a isa AT, sim.agents)
        avg_starting_net_worth = sum(get_starting_net_worth(agent) for agent in agents_of_type) / length(agents_of_type)
        avg_current_net_worth = sum(get_current_net_worth(agent) for agent in agents_of_type) / length(agents_of_type)
        println("  ", nameof(AT), ": ", length(agents_of_type))
        println("       avg starting net worth: ", round(avg_starting_net_worth, digits=2))
        println("       avg current net worth: ", round(avg_current_net_worth, digits=2))
        println("       avg profit/loss: ", round(avg_current_net_worth - avg_starting_net_worth, digits=2))
        println("   ")
    end

    println()
    println("Order book:")
    println("  total trades: ", get_total_trades(sim.book))
    println("  total items traded: ", sim.book.total_items_traded)
    println("  total value traded: ", round(sim.book.total_value_traded, digits = 2))
    println("  avg items/trade: ", round(avg_item_per_trade(sim.book), digits = 2))
    println("  avg volume/trade: ", round(avg_volume_per_trade(sim.book), digits = 2))
    println("  market price: ", round(market_price(sim), digits = 2))

    println()
    println("Items tracked: ", length(sim.items))
    if !isempty(sim.items)
        vals = collect(values(sim.items))
        println("  avg value: ", round(sum(item.latest_value for item in vals) / length(vals), digits = 2))
        println("  lowest ever: ", round(minimum(item.lowest_value for item in vals), digits = 2))
        println("  highest ever: ", round(maximum(item.highest_value for item in vals), digits = 2))
        println("  most traded: ", maximum(item.times_traded for item in vals), " times")
    end
end

function main()
    sim = Simulation()
    @time run!(sim)
    print_summary(sim)
end

#only runs when the script is started directly, not when it is included
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
