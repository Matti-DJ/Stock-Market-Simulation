# Stock Market Simulation

An Agent based Stock market where different types of agents trade an amount of 
`Item:s`. The orders are matched though a price/time based orderbook.

## How it works

- **[`Item`](src/Item.jl)** — a generic tradeable asset. Tracks its current
  value, every owner it has ever had, and its lowest/highest traded value.


- **[`OrderBook`](src/orderbook.jl)** — collects buy and sell orders in two
  `SortedDict`s (best price first) and tries to match them immediately when a buy
  order crosses a resting sell order or vice versa. Unmatched order rest in the orderbook 
  until they are matched.


- **Agents** ([`src/Agents/`](src/Agents)) — every agent type is built on a
  shared base [`Agent`](src/Agents/agent.jl) (cash, held items, trade
  counters) via [Agents.jl](https://juliadynamics.github.io/Agents.jl/stable/)'s
  `@agent` macro:

  - **`MarketAgent`** a market maker: always quotes a fixed buy price and
    sell price this price is calculated new every set amount of ticks.
  - **`NoiseAgent`** trades randomly around the current market price.
  - **`InformedAgent`** maintains a predicted low/high band that drifts
    toward the market price each tick, buys when the price falls to or below
    its predicted low, sells when it rises to or above its predicted high.
  - **`MomentumAgent`** buys after the market has trended up over a
    window of recent trades, sells after it has trended down.
  - **`ReverseMomentumAgent`** — the same signal as `MomentumAgent`, but
    trades against the trend instead of with it.
  
  - **[`Simulation`](src/simulation.jl)** puts everything together:
    creates a random number of agents per type, distributes a pool of items
    among them. While runnnign each tick a random agent gets its turn
    Each agent replaces its own resting order every turn, which keeps it from
    putting up more items than it owns.

## Requirements

- [Julia](https://julialang.org/) 1.x
- Dependencies (see [`Project.toml`](Project.toml)): `Agents`, `DataStructures`,
  `Revise`

## Running it

Instantiate the project's dependencies once:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

> This may print a "failed to precompile Stock_Market_Simulation" error —
> that's harmless noise (see [Status](#status) below), not a sign that
> something went wrong. The actual dependencies (`Agents`, `DataStructures`,
> `Revise`) still get resolved and installed.

Then run the simulation from the repository root:

```bash
julia --project=. src/simulation.jl
```

This runs a full simulation with the default `SimulationConfig` and prints a
summary — agent counts and average cash per type, order book totals, and
item value statistics.

> **Note:** `--project=.` (or activating the project in a Julia session with
> `Pkg.activate(".")` before `include`-ing the file) is required. Running
> `julia src/simulation.jl` from inside `src/` without it uses your default
> global environment instead of this project's, and will fail to find
> `Agents` even if it's already installed there.

To run it interactively, or with a different configuration:

```julia
using Pkg; Pkg.activate(".")
include("src/simulation.jl")

config = SimulationConfig(10, 1000.0, 10_000, 30.0, 100_000, 10, 100)
sim = Simulation(config)
run!(sim)
print_summary(sim)
```

### Configuration

[`SimulationConfig`](src/simulation.jl) controls the run:

| Field                     | Meaning                                                              |
|---------------------------|-----------------------------------------------------------------------|
| `max_agents_per_type`     | Upper bound on how many agents of each type get created (at least 1) |
| `max_start_money_per_agent` | Upper bound on each agent's starting cash                          |
| `max_start_items_total`   | How many items exist in total, randomly handed out to agents         |
| `item_base_value`         | Starting value of every item, and the market price before any trade  |
| `ticker_limit`            | How many ticks the simulation runs for                               |
| `momentum_trade_window`   | How many recent trades the momentum agents compare to detect a trend |
| `reprice_tick`            | How often (in ticks) market agents recompute their buy/sell price    |

## Project layout

```
src/
├── Item.jl                          # tradeable asset
├── orderbook.jl                     # order matching engine
├── simulation.jl                    # config, agent construction, agent behavior, run loop
└── Agents/
    ├── agent.jl                     # shared base agent + trade settlement
    ├── market_agent.jl
    ├── noise_agent.jl
    ├── informed_agent.jl
    ├── momentum_agent.jl
    └── reverse_momentum_agent.jl
```

## Future Ideas

#### _Item_

#### _Agent_
  - Add a strategy / algorythm to the informed traded.

#### _OrderBook_
  - upgrade the order matching to something more advanced.

#### _Simulation_
  - improve tracking of fields
  - add feature to trade multiple items / stocks.

## License

[MIT](LICENSE)
