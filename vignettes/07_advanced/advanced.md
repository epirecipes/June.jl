# Advanced: Simulation Walkthrough in June.jl


- [Advanced: Simulation Walkthrough](#advanced-simulation-walkthrough)
  - [The Timer](#the-timer)
    - [Creating a Timer](#creating-a-timer)
    - [Day Type Detection](#day-type-detection)
    - [Step Duration](#step-duration)
    - [Advancing Through Time](#advancing-through-time)
    - [Timer as an Iterator](#timer-as-an-iterator)
  - [The World](#the-world)
    - [Populating a World Manually](#populating-a-world-manually)
  - [The Interaction Model](#the-interaction-model)
  - [The Record](#the-record)
  - [Mini Simulation Loop](#mini-simulation-loop)
  - [Full Simulation Architecture](#full-simulation-architecture)
  - [Weekday vs Weekend Step Counts](#weekday-vs-weekend-step-counts)

# Advanced: Simulation Walkthrough

This vignette ties together all the building blocks — Timer, World,
Interaction, Epidemiology, and Records — into a complete end-to-end
simulation.

## The Timer

The `Timer` drives the simulation clock. It manages weekday/weekend
schedules, time steps of varying duration, and tracks the progression of
simulated days.

### Creating a Timer

``` julia
using June
using Dates
import June: Timer as JTimer

initial_day = DateTime("2020-03-02", dateformat"yyyy-mm-dd")
total_days = 7
final_date = initial_day + Day(total_days)

weekday_step = [8.0, 8.0, 8.0]   # 3 steps per weekday (8h each = 24h)
weekend_step = [12.0, 12.0]       # 2 steps per weekend day (12h each = 24h)
weekday_activities = [String[] for _ in 1:3]
weekend_activities = [String[] for _ in 1:2]

timer = JTimer(
    initial_day, total_days,
    initial_day, initial_day,     # date, previous_date
    final_date,
    0, 0.0,                       # shift, now
    weekday_step, weekend_step,
    weekday_activities, weekend_activities,
    Millisecond(0), 0.0           # delta_time, duration
)
println(timer)
println("  Initial date: $(timer.date)")
println("  Final date:   $(timer.final_date)")
println("  Total days:   $(timer.total_days)")
```

    Timer(date=2020-03-02T00:00:00, day=0.0, shift=0)
      Initial date: 2020-03-02T00:00:00
      Final date:   2020-03-09T00:00:00
      Total days:   7

### Day Type Detection

The timer knows whether the current date is a weekday or weekend.

``` julia
println("Date: $(timer.date) ($(Dates.dayname(timer.date)))")
println("  Is weekend: $(is_weekend(timer))")
println("  Day type: $(day_type(timer))")
```

    Date: 2020-03-02T00:00:00 (Monday)
      Is weekend: false
      Day type: weekday

### Step Duration

Weekdays have 3 steps of 8 hours; weekends have 2 steps of 12 hours.

``` julia
println("Weekday steps: $(timer.weekday_step_duration) hours  ($(sum(timer.weekday_step_duration))h total)")
println("Weekend steps: $(timer.weekend_step_duration) hours  ($(sum(timer.weekend_step_duration))h total)")
```

    Weekday steps: [8.0, 8.0, 8.0] hours  (24.0h total)
    Weekend steps: [12.0, 12.0] hours  (24.0h total)

### Advancing Through Time

Each call to `advance!` moves the timer forward by one step. The shift
counter cycles through the steps for the current day type.

``` julia
println("Step | Date                | Day       | Shift | Elapsed (days) | Duration (h)")
println("─────|─────────────────────|───────────|───────|────────────────|─────────────")
step = 0
while advance!(timer)
    step += 1
    d = Dates.format(timer.date, "yyyy-mm-dd HH:MM")
    dn = rpad(Dates.dayname(timer.date), 9)
    elapsed = round(timer.now, digits=3)
    dur_h = round(timer.duration * 24, digits=1)
    println(lpad(step, 4), " | ", d, " | ", dn, " | ", lpad(timer.shift, 5),
            " | ", lpad(elapsed, 14), " | ", lpad(dur_h, 11))
    if step >= 25
        println("  ... (truncated)")
        break
    end
end
```

    Step | Date                | Day       | Shift | Elapsed (days) | Duration (h)
    ─────|─────────────────────|───────────|───────|────────────────|─────────────
       1 | 2020-03-02 08:00 | Monday    |     1 |          0.333 |         8.0
       2 | 2020-03-02 16:00 | Monday    |     2 |          0.667 |         8.0
       3 | 2020-03-03 00:00 | Tuesday   |     0 |            1.0 |         8.0
       4 | 2020-03-03 08:00 | Tuesday   |     1 |          1.333 |         8.0
       5 | 2020-03-03 16:00 | Tuesday   |     2 |          1.667 |         8.0
       6 | 2020-03-04 00:00 | Wednesday |     0 |            2.0 |         8.0
       7 | 2020-03-04 08:00 | Wednesday |     1 |          2.333 |         8.0
       8 | 2020-03-04 16:00 | Wednesday |     2 |          2.667 |         8.0
       9 | 2020-03-05 00:00 | Thursday  |     0 |            3.0 |         8.0
      10 | 2020-03-05 08:00 | Thursday  |     1 |          3.333 |         8.0
      11 | 2020-03-05 16:00 | Thursday  |     2 |          3.667 |         8.0
      12 | 2020-03-06 00:00 | Friday    |     0 |            4.0 |         8.0
      13 | 2020-03-06 08:00 | Friday    |     1 |          4.333 |         8.0
      14 | 2020-03-06 16:00 | Friday    |     2 |          4.667 |         8.0
      15 | 2020-03-07 00:00 | Saturday  |     0 |            5.0 |         8.0
      16 | 2020-03-07 12:00 | Saturday  |     1 |            5.5 |        12.0
      17 | 2020-03-08 00:00 | Sunday    |     0 |            6.0 |        12.0
      18 | 2020-03-08 12:00 | Sunday    |     1 |            6.5 |        12.0
      19 | 2020-03-09 00:00 | Monday    |     0 |            7.0 |        12.0

### Timer as an Iterator

The `Timer` implements Julia’s iteration protocol, so you can use it in
a `for` loop.

``` julia
timer2 = JTimer(
    DateTime("2020-03-07"), 3,
    DateTime("2020-03-07"), DateTime("2020-03-07"),
    DateTime("2020-03-10"),
    0, 0.0,
    [8.0, 8.0, 8.0], [12.0, 12.0],
    [String[] for _ in 1:3], [String[] for _ in 1:2],
    Millisecond(0), 0.0,
)

println("Iterating over a 3-day timer (starting Saturday):")
step = 0
for t in timer2
    step += 1
    println("  Step $step: $(Dates.format(t.date, "yyyy-mm-dd HH:MM")) " *
            "($(Dates.dayname(t.date)), shift=$(t.shift))")
end
println("Total steps: $step")
```

    Iterating over a 3-day timer (starting Saturday):
      Step 1: 2020-03-07 12:00 (Saturday, shift=1)
      Step 2: 2020-03-08 00:00 (Sunday, shift=0)
      Step 3: 2020-03-08 12:00 (Sunday, shift=1)
      Step 4: 2020-03-09 00:00 (Monday, shift=0)
      Step 5: 2020-03-09 08:00 (Monday, shift=1)
      Step 6: 2020-03-09 16:00 (Monday, shift=2)
      Step 7: 2020-03-10 00:00 (Tuesday, shift=0)
    Total steps: 7

## The World

A `World` holds the entire simulation state: people, geography, and
groups.

``` julia
world = World()
println("Empty world created")
println("  People: $(isnothing(world.people) ? 0 : length(world.people))")
```

    Empty world created
      People: 0

### Populating a World Manually

We can build a small world by hand for demonstration purposes.

``` julia
reset_person_ids!()
reset_group_ids!()
reset_geography_counters!()

# Geography
area1 = Area(; name="E00001", coordinates=(51.5, -0.12))
area2 = Area(; name="E00002", coordinates=(51.51, -0.11))
sa = SuperArea(; name="E02000001", coordinates=(51.505, -0.115), areas=[area1, area2])
area1.super_area = sa
area2.super_area = sa
region = Region(; name="London", super_areas=[sa])
sa.region = region

# Population
pop = Population()
people_list = Person[]
ages = [5, 8, 32, 35, 42, 55, 68, 75]
for (i, age) in enumerate(ages)
    p = Person(; sex=i % 2 == 0 ? 'f' : 'm', age=age)
    add!(pop, p)
    push!(people_list, p)
    add!(area1, p)
end

# Groups
h1 = Household()
add!(h1, people_list[1])  # child (5)
add!(h1, people_list[3])  # parent (32)
add!(h1, people_list[4])  # parent (35)

h2 = Household()
add!(h2, people_list[5])  # adult (42)
add!(h2, people_list[6])  # adult (55)

h3 = Household()
add!(h3, people_list[7])  # elderly (68)
add!(h3, people_list[8])  # elderly (75)

school = School((51.5, -0.12), 200, 5, 11, "primary")
add!(school, people_list[1])
add!(school, people_list[2])

company = Company(; sector="Q", n_workers_max=20)
add!(company, people_list[5])
add!(company, people_list[6])

println("Mini-world summary:")
println("  Region: $(region.name)")
println("  Areas: 2")
println("  People: $(length(members(pop)))")
println("  Households: 3 ($(n_residents(h1))+$(n_residents(h2))+$(n_residents(h3)) residents)")
println("  School: $(length(people(school))) pupils")
println("  Company: $(length(people(company))) workers")
```

    Mini-world summary:
      Region: London
      Areas: 2
      People: 8
      Households: 3 (3+2+2 residents)
      School: 2 pupils
      Company: 2 workers

## The Interaction Model

The `Interaction` type controls how disease spreads within groups.

``` julia
betas = Dict(
    "household" => 0.208,
    "school" => 0.070,
    "company" => 0.371,
)
contact_matrices = Dict(
    "household" => Float64[1.0 0.5 0.3 0.2; 0.5 1.0 0.5 0.3; 0.3 0.5 1.0 0.5; 0.2 0.3 0.5 1.0],
    "school" => Float64[1.0 0.3; 0.3 1.0],
    "company" => ones(1, 1),
)
interaction = Interaction(2.0, betas, contact_matrices, Dict{String, Float64}())
println("Interaction model:")
println("  alpha_physical = $(interaction.alpha_physical)")
for (g, b) in sort(collect(interaction.betas), by=x->x[2], rev=true)
    bar = repeat("█", round(Int, b * 40))
    println("  $(rpad(g, 12)) β = $b  $bar")
end
```

    Interaction model:
      alpha_physical = 2.0
      company      β = 0.371  ███████████████
      household    β = 0.208  ████████
      school       β = 0.07  ███

## The Record

A `Record` accumulates simulation output — infections, recoveries,
deaths, hospitalisations.

``` julia
record = Record(; record_path=tempdir())
println("Record created")
println("  Path: $(record.record_path)")

# Record some events
accumulate_infection!(record; person_id=1, time=0.5, infection_id=0)
accumulate_infection!(record; person_id=3, time=1.0, infection_id=0)
println("  Infection events: $(length(record.infection_buffer))")
for evt in record.infection_buffer
    println("    person_id=$(evt.person_id), time=$(evt.time)")
end
```

    Record created
      Path: /var/folders/yh/30rj513j6mn1n7x556c2v4w80000gn/T
      Infection events: 2
        person_id=1, time=0.5
        person_id=3, time=1.0

## Mini Simulation Loop

In a full simulation, the `Simulator` struct wires together `World`,
`Interaction`, `Timer`, `ActivityManager`, and `Epidemiology`, typically
configured from YAML files via `simulator_from_file`. Here we sketch the
core simulation loop to illustrate the mechanics.

``` julia
using Random

println("=== Mini SIR Simulation ===")
println()

# Parameters
n_people = 200
n_days = 30
beta = 0.3
gamma = 0.1   # recovery probability per day
n_initial = 5

rng = MersenneTwister(42)

# Population with households
reset_person_ids!()
reset_group_ids!()
pop = Population()
all_people = Person[]
for i in 1:n_people
    p = Person(; sex=rand(rng, ['m','f']), age=rand(rng, 5:80))
    add!(pop, p)
    push!(all_people, p)
end

# Create households (groups of 2-5)
households = Household[]
idx = 1
while idx <= n_people
    hh = Household()
    hh_size = min(rand(rng, 2:5), n_people - idx + 1)
    for j in 0:hh_size-1
        add!(hh, all_people[idx + j])
    end
    push!(households, hh)
    idx += hh_size
end

# State tracking: S=0, I=1, R=2
state = zeros(Int, n_people)
infected_day = zeros(Int, n_people)

# Seed infections
seeds = randperm(rng, n_people)[1:n_initial]
for s in seeds
    state[s] = 1
    infected_day[s] = 0
end

# Run simulation
S_counts = [count(==(0), state)]
I_counts = [count(==(1), state)]
R_counts = [count(==(2), state)]

for day in 1:n_days
    # Transmission within households
    for hh in households
        members_list = collect(people(hh))
        n_inf = count(p -> state[p.id] == 1, members_list)
        n_inf == 0 && continue
        for p in members_list
            state[p.id] == 0 || continue
            # Each infected housemate has beta chance of transmitting
            prob = 1.0 - (1.0 - beta / length(members_list))^n_inf
            if rand(rng) < prob
                state[p.id] = 1
                infected_day[p.id] = day
            end
        end
    end

    # Recovery
    for i in 1:n_people
        if state[i] == 1 && (day - infected_day[i]) >= 3
            if rand(rng) < gamma
                state[i] = 2
            end
        end
    end

    push!(S_counts, count(==(0), state))
    push!(I_counts, count(==(1), state))
    push!(R_counts, count(==(2), state))
end

# Display trajectory
println("Day | Susceptible | Infected | Recovered")
println("────|─────────────|──────────|──────────")
for d in [0, 5, 10, 15, 20, 25, 30]
    i = d + 1
    bar_s = repeat("░", max(0, div(S_counts[i], 5)))
    bar_i = repeat("█", max(0, div(I_counts[i], 5)))
    bar_r = repeat("▓", max(0, div(R_counts[i], 5)))
    println(lpad(d, 3), " | ", lpad(S_counts[i], 11), " | ",
            lpad(I_counts[i], 8), " | ", lpad(R_counts[i], 8),
            "  ", bar_s, bar_i, bar_r)
end
println()
println("Final: S=$(S_counts[end]) I=$(I_counts[end]) R=$(R_counts[end])")
println("Attack rate: $(round(100 * R_counts[end] / n_people, digits=1))%")
```

    === Mini SIR Simulation ===

    Day | Susceptible | Infected | Recovered
    ────|─────────────|──────────|──────────
      0 |         195 |        5 |        0  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█
      5 |         189 |        7 |        4  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█
     10 |         188 |        5 |        7  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█▓
     15 |         188 |        3 |        9  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓
     20 |         187 |        3 |       10  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓
     25 |         187 |        2 |       11  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓
     30 |         187 |        2 |       11  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓

    Final: S=187 I=2 R=11
    Attack rate: 5.5%

## Full Simulation Architecture

In practice, a full JUNE simulation uses config-driven setup:

``` julia
println("Full JUNE Simulation Architecture")
println("═" ^ 50)
println()
println("  ┌─────────────┐   YAML configs")
println("  │  Geography   │ ← area coordinates, population data")
println("  │  Demography  │ ← age/sex distributions, comorbidities")
println("  └──────┬──────┘")
println("         │ generate_world_from_geography()")
println("         ▼")
println("  ┌─────────────┐")
println("  │    World     │  people, households, schools,")
println("  │              │  companies, hospitals, leisure…")
println("  └──────┬──────┘")
println("         │ simulator_from_file(world, interaction)")
println("         ▼")
println("  ┌─────────────┐   ┌──────────────┐")
println("  │  Simulator   │──▶│  Each step:   │")
println("  │              │   │  1. Policies  │")
println("  │  timer       │   │  2. Activities│")
println("  │  interaction │   │  3. Transmit  │")
println("  │  epidemiology│   │  4. Progress  │")
println("  │  policies    │   │  5. Record    │")
println("  │  record      │   └──────────────┘")
println("  └─────────────┘")
println()
println("Key functions:")
println("  simulator_from_file()  — wire up all subsystems")
println("  run!(sim)              — execute full simulation")
println("  do_timestep!(sim)      — single step for debugging")
```

    Full JUNE Simulation Architecture
    ══════════════════════════════════════════════════

      ┌─────────────┐   YAML configs
      │  Geography   │ ← area coordinates, population data
      │  Demography  │ ← age/sex distributions, comorbidities
      └──────┬──────┘
             │ generate_world_from_geography()
             ▼
      ┌─────────────┐
      │    World     │  people, households, schools,
      │              │  companies, hospitals, leisure…
      └──────┬──────┘
             │ simulator_from_file(world, interaction)
             ▼
      ┌─────────────┐   ┌──────────────┐
      │  Simulator   │──▶│  Each step:   │
      │              │   │  1. Policies  │
      │  timer       │   │  2. Activities│
      │  interaction │   │  3. Transmit  │
      │  epidemiology│   │  4. Progress  │
      │  policies    │   │  5. Record    │
      │  record      │   └──────────────┘
      └─────────────┘

    Key functions:
      simulator_from_file()  — wire up all subsystems
      run!(sim)              — execute full simulation
      do_timestep!(sim)      — single step for debugging

## Weekday vs Weekend Step Counts

``` julia
timer3 = JTimer(
    DateTime("2020-03-02"), 7,
    DateTime("2020-03-02"), DateTime("2020-03-02"),
    DateTime("2020-03-09"),
    0, 0.0,
    [8.0, 8.0, 8.0], [12.0, 12.0],
    [String[] for _ in 1:3], [String[] for _ in 1:2],
    Millisecond(0), 0.0,
)

weekday_steps = 0
weekend_steps = 0
for t in timer3
    if is_weekend(t)
        weekend_steps += 1
    else
        weekday_steps += 1
    end
end
println("Over 7 days (Mon 2 Mar – Sun 8 Mar 2020):")
println("  Weekday steps: $weekday_steps  (5 days × 3 steps)")
println("  Weekend steps: $weekend_steps  (2 days × 2 steps)")
println("  Total steps:   $(weekday_steps + weekend_steps)")
```

    Over 7 days (Mon 2 Mar – Sun 8 Mar 2020):
      Weekday steps: 15  (5 days × 3 steps)
      Weekend steps: 4  (2 days × 2 steps)
      Total steps:   19
