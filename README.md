# Stock Market Simulation

An Agent based Stock market where different types of agents trade units of one
or more `Asset`s. The orders are matched through a price/time based orderbook,
one per asset.

## How it works

- **[`Asset`](src/Asset.jl)** — one tradeable asset type (think a single stock /
  ticker). Every unit of an asset is fungible and shares one price, so an asset
  is stored once and agents only track how many units of it they hold. Tracks
  its current value, lowest/highest traded value, trade count and price history.


- **[`OrderBook`](src/orderbook.jl)** — one per asset. Collects buy and sell
  orders in two `SortedDict`s (best price first) and tries to match them
  immediately when a buy order crosses a resting sell order or vice versa.
  Unmatched orders rest in the orderbook until they are matched.


- **Agents** ([`src/Agents/`](src/Agents)) — every agent type is built on a
  shared base [`Agent`](src/Agents/agent.jl) (cash, per-asset unit `holdings`,
  trade counters) via
  [Agents.jl](https://juliadynamics.github.io/Agents.jl/stable/)'s `@agent`
  macro. Each step an agent picks a random asset to act on:

  - **`MarketAgent`** a market maker: quotes a fixed buy price and sell price
    per asset, recalculated every set amount of ticks.
  - **`NoiseAgent`** trades randomly around the current market price.
  - **`InformedAgent`** maintains a predicted low/high band that drifts
    toward the market price each tick, buys when the price falls to or below
    its predicted low, sells when it rises to or above its predicted high.
  - **`MomentumAgent`** buys after the market has trended up over a
    window of recent trades, sells after it has trended down.
  - **`ReverseMomentumAgent`** — the same signal as `MomentumAgent`, but
    trades against the trend instead of with it.
  
  - **[`Simulation`](src/simulation.jl)** puts everything together:
    creates a random number of agents per type, builds one order book per
    asset, and distributes a pool of units among the agents (random agent,
    random asset, one unit at a time). While running, each tick a random agent
    gets its turn. Each agent cancels its own resting orders every turn, which
    keeps it from putting up more units than it owns.

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

config = SimulationConfig(10, 1000.0, 10_000, 30.0, 100_000, 10, 100, asset_symbol_list(2))
sim = Simulation(config)
run!(sim)
print_summary(sim)
```

### Configuration

[`SimulationConfig`](src/simulation.jl) controls the run:

| Field                     | Meaning                                                              |
|---------------------------|-----------------------------------------------------------------------|
| `max_agents_per_type`     | Size of the largest cohort; each type is scaled from it by `AGENT_MIX` (retail-heavy, ~1% market makers) |
| `max_start_money_per_agent` | Scale of the log-normal starting-cash draw (most agents small, a heavy tail of large accounts); market makers start much richer |
| `max_start_items_total`   | How many units exist in total across all assets (the free float), handed out one at a time to a random agent and a random asset |
| `item_base_value`         | Starting price of every asset, the market price before any trade, and the fair value the informed agents anchor to |
| `ticker_limit`            | How many ticks the simulation runs for (one agent acts per tick)     |
| `momentum_trade_window`   | How many recent trades the momentum agents compare to detect a trend |
| `reprice_tick`            | How often (in ticks) market agents recompute their buy/sell quotes (1 = every tick) |
| `asset_symbols`           | The tradeable assets; one order book is created per symbol. `asset_symbol_list(n)` builds `:ASSET1 … :ASSETn` |

Each agent acts on one randomly chosen asset per turn. Market makers quote a
~20 bps spread around each asset's last price and noise traders place limit
prices within ~1% of the mid.

Two ready-made configs:

- **`SimulationConfig()`** — the quick scratch scenario for iterating on the
  model (~$100/share assets, ~2,500 participants, 2M ticks).
- **`large_market_config()`** — a longer, larger run: 100 mid-cap assets,
  ~10,000 retail-heavy participants, ~40 units per agent per asset (deep books),
  100M ticks. Expect it to run for tens of minutes and hold a few GB of RAM —
  `all_trades` and `Asset.price_history` grow one entry per trade and are never
  pruned, so peak memory scales with `ticker_limit`.

```julia
sim = Simulation(large_market_config())
run!(sim)
print_summary(sim)
```

## Project layout

```
src/
├── Asset.jl                         # tradeable asset type (one price per symbol)
├── orderbook.jl                     # order matching engine (one book per asset)
├── simulation.jl                    # config, agent construction, agent behavior, run loop
└── Agents/
    ├── agent.jl                     # shared base agent + trade settlement
    ├── market_agent.jl
    ├── noise_agent.jl
    ├── informed_agent.jl
    ├── momentum_agent.jl
    └── reverse_momentum_agent.jl
```

## License

[MIT](LICENSE)
