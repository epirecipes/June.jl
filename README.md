# June.jl

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docs: dev](https://img.shields.io/badge/docs-dev-blue.svg)](http://epirecip.es/June.jl/dev)

A Julia port of [JUNE](https://github.com/IDAS-Durham/JUNE), the open-source individual-based epidemiology simulation framework named after virologist [June Almeida](https://en.wikipedia.org/wiki/June_Almeida).

June.jl models disease spread by simulating millions of individual agents moving through real-world locations (households, schools, workplaces, hospitals, leisure venues, transport) across discrete time steps. It was originally developed to model COVID-19 spread in England.

## Installation

```julia
using Pkg
Pkg.develop(path="/path/to/June.jl")
```

File-based loaders look for input data in a local `data/` directory by default. If you are working from this repository checkout, that directory is already part of the project tree.

## Quick Start

```julia
using June
using Dates

# Build a tiny household world by hand
adult = Person(; age=40)
child = Person(; age=12)

household = Household(; type="family")
add!(household, adult; activity=:residence)
add!(household, child; activity=:residence)

world = World()
world.people = Population()
push!(world.people, adult)
push!(world.people, child)
world.households = Supergroup("households", [household.group])
world.cemeteries = Cemeteries()

interaction = Interaction(
    0.5,
    Dict("household" => 3.0),
    Dict("household" => ones(4, 4)),
    Dict{String, Float64}(),
)

timer = June.Timer(
    DateTime(2020, 3, 2, 9),
    1,
    DateTime(2020, 3, 2, 9),
    DateTime(2020, 3, 2, 9),
    DateTime(2020, 3, 3, 9),
    0,
    0.0,
    [12.0, 12.0],
    [12.0, 12.0],
    [["residence", "primary_activity"], ["residence", "leisure"]],
    [["residence", "leisure"], ["residence", "leisure"]],
    Millisecond(0),
    0.5,
)

activity_manager = ActivityManager(
    Dict("residence" => ["households"]),
    ["households"],
    String[],
    nothing,
    nothing,
    nothing,
)

simulator = Simulator(
    world,
    interaction,
    timer,
    activity_manager,
    nothing,
    nothing,
    nothing,
    nothing,
    Date[],
    "",
)

do_timestep!(simulator)
```

For geography-driven workflows, epidemiology configuration, vaccinations, policies, and Python/Julia side-by-side examples, see the numbered vignettes in `vignettes/`.

## Citation

If you use June.jl in your research, please cite the original JUNE paper:

```bibtex
@article{doi:10.1098/rsos.210506,
  author = {Aylett-Bullock, Joseph and Cuesta-Lazaro, Carolina and Quera-Bofarull, Arnau and others},
  title = {June: open-source individual-based epidemiology simulation},
  journal = {Royal Society Open Science},
  volume = {8},
  number = {7},
  pages = {210506},
  year = {2021},
  doi = {10.1098/rsos.210506},
}
```

## License

MIT License — see [LICENSE](LICENSE).
