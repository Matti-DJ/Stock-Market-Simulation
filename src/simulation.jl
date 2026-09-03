# simulation.jl
# Julia Script

#=
Description: Builds the market out of the agents, the assets and one order book
             per asset and runs it.
Author: matthiasdejong
Date: 26.08.26
=#

const SCRIPT_VERSION = "2.1.0"

include("Asset.jl")
include("orderbook.jl")
include("Agents/market_agent.jl")
include("Agents/noise_agent.jl")
include("Agents/informed_agent.jl")
include("Agents/momentum_agent.jl")
include("Agents/reverse_momentum_agent.jl")

using UUIDs
using Random
using Statistics
using Plots
plotlyjs()

const AGENT_TYPES = (MarketAgent, NoiseAgent, InformedAgent, MomentumAgent, ReverseMomentumAgent)

"""
    Rough real-market composition by head count. Real order flow is dominated by
    uninformed / retail traders, with a smaller slice of fundamental traders,
    fewer trend followers and contrarians, and only a handful of designated
    market makers. The weights are fractions of `config.max_agents_per_type`,
    so that field scales the whole crowd while keeping the mix realistic.
"""
const AGENT_MIX = Dict{DataType, Float64}(
    NoiseAgent           => 1.0,
    InformedAgent        => 0.15,
    MomentumAgent        => 0.08,
    ReverseMomentumAgent => 0.04,
    MarketAgent          => 0.01,
)

"""
    asset has no name a user can assign they are just ASSET1:ASSETn
"""
asset_symbol_list(n::Integer) = [Symbol("ASSET", i) for i in 1:n]

"""
    configurations for the market simulation.

# Fields
- `max_agents_per_type`
- `max_start_money_per_agent`
- `max_start_items_total`: how many units exist in total across all assets, randomly distributed among the agents
- `item_base_value`: starting price of every asset
- `ticker_limit`: for how many ticks the simulation runs
- `momentum_trade_window`: how many ticks the market has to go into one direction for a momentum agent to act
- `reprice_tick`: how many ticks it takes for the market agents to requote
- `asset_symbols`: the tradeable assets, one order book is created per symbol
"""
struct SimulationConfig
    max_agents_per_type::Int
    max_start_money_per_agent::Float64
    max_start_items_total::Int
    item_base_value::Float64
    ticker_limit::Int
    momentum_trade_window::Int
    reprice_tick::Int
    asset_symbols::Vector{Symbol}
end

SimulationConfig() = SimulationConfig(
    8_000,                  # max_agents_per_type
    250_000.0,              # max_start_money_per_agent
    40_000_000,               # max_start_items_total
    100.0,                  # item_base_value
    100_000_000,             # ticker_limit
    50,                     # momentum_trade_window
    250,                      # reprice_tick
    asset_symbol_list(100),   # asset_symbols
)

# A larger, longer scenario: 100 moderately liquid mid-cap assets (~$100 / share)
# with ~10,000 retail-heavy participants (see `AGENT_MIX`), run for a long stretch
# of order flow. The ratios are kept realistic:
#   - ~10,000 participants for 100 names   -> a small-exchange-segment crowd
#   - ~40 units per agent per asset        -> ~410k free float per asset, deep books
#   - 100M ticks -> ~10k actions / agent   -> ~100 actions per agent per asset, and
#                                             hundreds of thousands of trades per asset
#   - reprice every 250 ticks              -> a market maker acts ~every 130 ticks,
#                                             so its quotes stay fresh between turns
#
# Cost: expect this to run for minutes, not seconds, and to hold a few GB of RAM.
# `all_trades` (per book) and `Asset.price_history` grow one entry per trade and
# are never pruned, so peak memory scales with `ticker_limit`. To run even longer,
# drop `ticker_limit` and raise the run count, or add trade-log pruning.
large_market_config() = SimulationConfig(
    8_000,                    # max_agents_per_type -> ~10,240 agents via AGENT_MIX
    250_000.0,                # max_start_money_per_agent (log-normal, retail-heavy)
    40_000_000,               # max_start_items_total (~40 units / agent / asset)
    100.0,                    # item_base_value
    100_000_000,              # ticker_limit (~10k actions / agent)
    50,                       # momentum_trade_window (classic ~50-trade lookback)
    250,                      # reprice_tick
    asset_symbol_list(100),   # asset_symbols
)

"""
    Holds everything one simulation run needs.

#Fields
- `config`
- `books`: one `OrderBook` per asset symbol
- `agents`
- `assets`: every asset in the market, looked up by its symbol
- `agent_index`: used for the trades, looks up an agent by his id
"""
struct Simulation
    config::SimulationConfig
    books::Dict{Symbol, OrderBook}
    agents::Vector{AbstractMarketAgent}
    assets::Dict{Symbol, Asset}
    agent_index::Dict{Int, AbstractMarketAgent}
end

"""
    A log-normal starting-cash draw. Real account sizes are heavily right skewed:
    most participants are small retail accounts and a few are large institutions,
    which a uniform `rand()` never captures. `config.max_start_money_per_agent`
    sets the scale (roughly the upper end of the retail bulk); the tail can run
    above it and is clamped to keep a single whale from owning the whole float.
"""
function draw_starting_cash(config::SimulationConfig)
    scale = config.max_start_money_per_agent
    cash = (scale / 16) * exp(1.4 * randn())
    return clamp(cash, 500.0, scale * 50)
end

# all constructors for making agents
function make_agent(::Type{MarketAgent}, id::Int, config::SimulationConfig)
    # market makers are well capitalised so they can hold inventory through swings
    starting_cash_sim = config.max_start_money_per_agent * (5.0 + 5.0rand())
    base = config.item_base_value
    buy_price  = Dict(s => base * 0.999 for s in config.asset_symbols)
    sell_price = Dict(s => base * 1.001 for s in config.asset_symbols)
    MarketAgent(id = id, cash = starting_cash_sim, buy_price = buy_price,
                sell_price = sell_price, starting_cash = starting_cash_sim)
end

function make_agent(::Type{NoiseAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = draw_starting_cash(config)
    NoiseAgent(id = id, cash = starting_cash_sim, starting_cash = starting_cash_sim)
end

function make_agent(::Type{InformedAgent}, id::Int, config::SimulationConfig)
    base = config.item_base_value
    starting_cash_sim = draw_starting_cash(config)
    InformedAgent(id = id, cash = starting_cash_sim,
                  predicted_low = base * (0.90 + 0.05rand()),
                  predicted_high = base * (1.05 + 0.05rand()),
                  starting_cash = starting_cash_sim)
end

function make_agent(::Type{MomentumAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = draw_starting_cash(config)
    MomentumAgent(id = id, cash = starting_cash_sim,
                  times_waited = 0, avg_time_between_trades = 0.0, starting_cash = starting_cash_sim)
end

function make_agent(::Type{ReverseMomentumAgent}, id::Int, config::SimulationConfig)
    starting_cash_sim = draw_starting_cash(config)
    ReverseMomentumAgent(id = id, cash = starting_cash_sim,
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
        weight = get(AGENT_MIX, AT, 1.0)
        count = max(1, round(Int, config.max_agents_per_type * weight))
        for _ in 1:count
            push!(agents, make_agent(AT, next_id, config))
            next_id += 1
        end
    end

    return agents
end

"""
    The current market price of `sym`: its last traded price, or the base value
    it was created at before it has traded.
"""
market_price(sim::Simulation, sym::Symbol) = sim.assets[sym].latest_value

"""
    Picks a random asset symbol for an agent to act on this step.
"""
random_symbol(sim::Simulation) = rand(sim.config.asset_symbols)

"""
    returns the current net worth of an agent: cash plus every held unit valued
    at its asset's current market price.
"""
wealth(sim::Simulation, a::AbstractMarketAgent) =
    a.cash + sum(qty * market_price(sim, s) for (s, qty) in a.holdings; init = 0.0)

"""
    Distributes the total pool of units among all the agents, one unit at a time,
    each to a random agent and a random asset. It does not guarantee that every
    agent gets units. Returns the freshly created assets keyed by symbol.

# Params
- `agents`
- `config`
"""
function distribute_holdings!(agents::Vector{AbstractMarketAgent}, config::SimulationConfig)
    assets = Dict{Symbol, Asset}(s => Asset(s, config.item_base_value) for s in config.asset_symbols)

    for _ in 1:config.max_start_items_total
        sym = rand(config.asset_symbols)
        agent = rand(agents)

        agent.holdings[sym]          = get(agent.holdings, sym, 0) + 1
        agent.starting_holdings[sym] = get(agent.starting_holdings, sym, 0) + 1
    end

    return assets
end

# simplified constructor for the Simulation
function Simulation(config::SimulationConfig = SimulationConfig())
    agents = create_agents(config)
    assets = distribute_holdings!(agents, config)
    books = Dict{Symbol, OrderBook}(s => OrderBook(s) for s in config.asset_symbols)
    agent_index = Dict(a.id => a for a in agents)
    return Simulation(config, books, agents, assets, agent_index)
end

"""
    Compares the average trade price of the last `window` trades to the `window`
    before it, to decide whether the market is trending up or down.
    Returns `:up`, `:down` or `:flat`.

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
    Cancels every resting order the agent has, across all asset books.
"""
function cancel_all_orders!(sim::Simulation, agent_id::Int)
    for book in values(sim.books)
        cancel_orders!(book, agent_id)
    end
    return sim
end

"""
    Lets the agent put up a sell order for a random amount of the units it holds
    of `sym`.

# Params
- `sim`
- `agent`
- `sym`
- `item_price`
"""
function sell_random_amount!(sim::Simulation, agent::AbstractMarketAgent, sym::Symbol, item_price::Float64)
    have = holding(agent, sym)
    have < 1 && return sim
    #real orders move a small slice of a position, not the whole book at once;
    #cap at 3 to mirror the buy side
    quantity = rand(1:min(3, have))
    put_up_sell_order!(sim.books[sym], sim.agent_index, sim.assets[sym], agent.id, quantity, item_price)
end

"""
    Lets the agent put up a buy order for a random amount of `sym`,
    but never for more than his cash can pay for.

# Params
- `sim`
- `agent`
- `sym`
- `item_price`
"""
function buy_random_amount!(sim::Simulation, agent::AbstractMarketAgent, sym::Symbol, item_price::Float64)
    item_price <= 0 && return sim.books[sym]
    max_quantity = floor(agent.cash / item_price)
    max_quantity < 1 && return sim.books[sym]
    #the cap to 3 also keeps the quantity safely inside the Int range for very low prices
    quantity = rand(1:Int(min(3.0, max_quantity)))
    put_up_buy_order!(sim.books[sym], sim.agent_index, sim.assets[sym], agent.id, quantity, item_price)
end

"""
    The noise agent trades randomly: it picks a random asset, then a coin flip
    decides between selling some of its units of that asset or buying more,
    at a random price around that asset's market price.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::NoiseAgent)
    cancel_all_orders!(sim, agent.id)
    sym = random_symbol(sim)
    #limit prices cluster within ~1% of the mid, not ±10%
    item_price = market_price(sim, sym) * (0.99 + 0.02rand())

    if holding(agent, sym) > 0 && rand(Bool)
        sell_random_amount!(sim, agent, sym, item_price)
    else
        buy_random_amount!(sim, agent, sym, item_price)
    end
end

"""
    The market agent picks a random asset and always sells at its `sell_price`
    and buys at its `buy_price`. Both are refreshed every `reprice_tick` ticks
    by `reprice_market_agents!`.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::MarketAgent)
    cancel_all_orders!(sim, agent.id)
    sym = random_symbol(sim)

    if holding(agent, sym) > 0 && rand(Bool)
        sell_random_amount!(sim, agent, sym, agent.sell_price[sym])
    else
        buy_random_amount!(sim, agent, sym, agent.buy_price[sym])
    end
end

"""
    The informed agent picks a random asset, updates its predicted low/high band
    with that asset's price, buys when the price drops under its predicted low
    and sells when it rises over its predicted high. The UCB1 bandit picks the
    action type (buy / sell / hold) and is shared across assets.

# Params
- `sim`
- `agent`
"""
function agent_step!(sim::Simulation, agent::InformedAgent)
    cancel_all_orders!(sim, agent.id)
    sym = random_symbol(sim)
    price = market_price(sim, sym)

    #A fundamental trader anchors to intrinsic value, not to price. The band is
    #pulled mostly toward `item_base_value` (fair value) and only slightly toward
    #the current price, so the informed crowd leans against big dislocations and
    #the market keeps a value anchor instead of a free random walk. The agent
    #then acts on a ~5% mispricing.
    fair = sim.config.item_base_value
    target = 0.8 * fair + 0.2 * price
    agent.predicted_high = (agent.predicted_high + target * 1.05) / 2
    agent.predicted_low = (agent.predicted_low + target * 0.95) / 2

    if agent.last_arm != 0
        r = wealth(sim, agent) - agent.last_wealth
        la = agent.last_arm
        agent.arm_visits[la] += 1
        agent.arm_reward[la] += (r - agent.arm_reward[la]) / agent.arm_visits[la]
    end

    arm = if any(agent.arm_visits .== 0)
        findfirst(agent.arm_visits .== 0)
    else
        ucb = agent.arm_reward .+ 2 .* sqrt.(log(agent.total_pulls) ./ agent.arm_visits)
        argmax(ucb)
    end

    play_arm!(sim, agent, sym, arm)
    agent.total_pulls += 1
    agent.last_arm = arm
    agent.last_wealth = wealth(sim, agent)
end

"""
    plays an arm for the informed agent on asset `sym`

# Param
- `sim`
- `agent`
- `sym`: which asset the action applies to
- `arm`: the action it should do (1 = buy low, 2 = sell high, 3 = hold)
"""
function play_arm!(sim::Simulation, agent::InformedAgent, sym::Symbol, arm::Int)
    price = market_price(sim, sym)
    if arm == 1
        if price <= agent.predicted_low; buy_random_amount!(sim, agent, sym, price); end
    elseif arm == 2
        if price >= agent.predicted_high && holding(agent, sym) >= 1
            put_up_sell_order!(sim.books[sym], sim.agent_index, sim.assets[sym], agent.id, 1, price)
        end
    else
        # arm 3: hold
    end
end

"""
    Shared behaviour for the momentum agents: `reversed = false` goes with the
    market, `reversed = true` goes against it. Otherwise the agent just waits.
    The agent picks a random asset and reads that asset's book for the trend.

# Params
- `sim`
- `agent`
- `reversed`
"""
function momentum_step!(sim::Simulation, agent::AbstractMarketAgent, reversed::Bool)
    cancel_all_orders!(sim, agent.id)
    sym = random_symbol(sim)
    book = sim.books[sym]
    trend = recent_trend(book, sim.config.momentum_trade_window)
    buy_signal = reversed ? trend === :down : trend === :up
    sell_signal = reversed ? trend === :up : trend === :down

    if buy_signal && agent.cash > 0
        ask = get_price_of_cheapest_sellorder(book)
        buy_random_amount!(sim, agent, sym, ask === nothing ? market_price(sim, sym) : ask)
        update_avg_trade_time!(agent)
    elseif sell_signal && holding(agent, sym) > 0
        bid = get_price_of_highest_buyorder(book)
        sell_random_amount!(sim, agent, sym, bid === nothing ? market_price(sim, sym) : bid)
        update_avg_trade_time!(agent)
    else
        agent.times_waited += 1
    end
end

agent_step!(sim::Simulation, agent::MomentumAgent) = momentum_step!(sim, agent, false)
agent_step!(sim::Simulation, agent::ReverseMomentumAgent) = momentum_step!(sim, agent, true)

"""
    Gives all market agents a new buy and sell price around the current market
    price of every asset. Gets called every `reprice_tick` ticks.

# Param
- `sim`
"""
function reprice_market_agents!(sim::Simulation)
    #quote ~10 bps either side of the last price -> a ~20 bps spread, in line with
    #a liquid mid-cap. `market_price` already falls back to the base value before
    #the first trade, so no separate empty-book branch is needed.
    half_spread = 0.001
    for agent in sim.agents
        agent isa MarketAgent || continue
        for sym in sim.config.asset_symbols
            price = market_price(sim, sym)
            agent.buy_price[sym]  = price * (1 - half_spread)
            agent.sell_price[sym] = price * (1 + half_spread)
        end
    end
    return sim
end

"""
    plots each asset's traded price over the ticks in the simulation.

# Params
- `sim`
- `percent_to_plot`: how many percent of the trades should be plotted
"""
function plot_item_price(sim::Simulation, percent_to_plot::Float64)
    ticks_between_point = max(1, round(Int, 100.0 / percent_to_plot))
    p = plot(title = "Asset value in the simulation", xlabel = "tick", ylabel = "asset value")
    for sym in sim.config.asset_symbols
        trades = sim.books[sym].all_trades
        isempty(trades) && continue
        x = [trade.tick for trade in trades][1:ticks_between_point:end]
        y = [trade.item_price for trade in trades][1:ticks_between_point:end]
        plot!(p, x, y, label = string(sym))
    end
    return p
end

"""
    returns the current net worth of an agent (cash + held units at market).
    Non-mutating.
"""
get_current_agent_net_worth(sim::Simulation, agent::AbstractMarketAgent) = wealth(sim, agent)

"""
    gets the net worth the agent started with: starting cash plus every unit it
    was handed, valued at the asset base value.
"""
function get_starting_net_worth(sim::Simulation, agent::AbstractMarketAgent)
    units = sum(values(agent.starting_holdings); init = 0)
    return agent.starting_cash + units * sim.config.item_base_value
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
    the agents, the order book totals and per-asset price extremes.

# Param
- `sim`
"""
function print_summary(sim::Simulation)
    println("Simulation Summary")
    println("Agents: ", length(sim.agents))
    for AT in AGENT_TYPES
        agents_of_type = filter(a -> a isa AT, sim.agents)
        avg_starting_net_worth = sum(get_starting_net_worth(sim, agent) for agent in agents_of_type) / length(agents_of_type)
        avg_current_net_worth = sum(get_current_agent_net_worth(sim, agent) for agent in agents_of_type) / length(agents_of_type)
        println("  ", nameof(AT), ": ", length(agents_of_type))
        println("       avg starting net worth: ", round(avg_starting_net_worth, digits=2))
        println("       avg current net worth: ", round(avg_current_net_worth, digits=2))
        println("       avg profit/loss: ", round(avg_current_net_worth - avg_starting_net_worth, digits=2))
        println("   ")
    end

    total_trades = sum(get_total_trades(b) for b in values(sim.books))
    total_items_traded = sum(b.total_items_traded for b in values(sim.books))
    total_value_traded = sum(b.total_value_traded for b in values(sim.books))

    println()
    println("Order books: ", length(sim.books))
    println("  total trades: ", total_trades)
    println("  total units traded: ", total_items_traded)
    println("  total value traded: ", round(total_value_traded, digits = 2))
    println("  avg units/trade: ", total_trades == 0 ? 0.0 : round(total_items_traded / total_trades, digits = 2))
    println("  avg volume/trade: ", total_trades == 0 ? 0.0 : round(total_value_traded / total_trades, digits = 2))

    println()
    println("Assets tracked: ", length(sim.assets))
    for sym in sim.config.asset_symbols
        a = sim.assets[sym]
        println("  ", sym,
                ": price ", round(a.latest_value, digits = 2),
                " | low ", round(a.lowest_value, digits = 2),
                " | high ", round(a.highest_value, digits = 2),
                " | trades ", a.times_traded)
    end

    if any(!isempty(b.all_trades) for b in values(sim.books))
        display(plot_item_price(sim, 0.01))
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

readline()
