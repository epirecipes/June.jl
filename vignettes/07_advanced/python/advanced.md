# Advanced: Simulation Walkthrough in JUNE (Python)


- [Advanced: Simulation Walkthrough](#advanced-simulation-walkthrough)
  - [Setup](#setup)
  - [The Timer](#the-timer)
    - [Creating a Timer](#creating-a-timer)
    - [Day Type Detection](#day-type-detection)
    - [Step Duration](#step-duration)
    - [Advancing Through Time](#advancing-through-time)
  - [Building a Mini World](#building-a-mini-world)
  - [The Interaction Model](#the-interaction-model)
  - [Mini Simulation Loop](#mini-simulation-loop)
  - [Full Simulation Architecture](#full-simulation-architecture)
  - [Weekday vs Weekend Step Counts](#weekday-vs-weekend-step-counts)

# Advanced: Simulation Walkthrough

This vignette ties together all the building blocks — Timer, World,
Interaction, Epidemiology, and Records — into a complete end-to-end
simulation overview.

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## The Timer

The `Timer` drives the simulation clock in JUNE.

### Creating a Timer

``` python
from june.time import Timer

timer = Timer(
    initial_day="2020-03-02",
    total_days=7,
    weekday_step_duration=[8, 8, 8],
    weekend_step_duration=[12, 12],
)
print(f"Timer created:")
print(f"  Initial date: {timer.date}")
print(f"  Total days:   7")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/07_advanced/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Timer created:
      Initial date: 2020-03-02 00:00:00
      Total days:   7

### Day Type Detection

``` python
print(f"Date: {timer.date} ({timer.date.strftime('%A')})")
print(f"  Is weekend: {timer.date.weekday() >= 5}")
day_type = "weekend" if timer.date.weekday() >= 5 else "weekday"
print(f"  Day type: {day_type}")
```

    Date: 2020-03-02 00:00:00 (Monday)
      Is weekend: False
      Day type: weekday

### Step Duration

Weekdays have 3 steps of 8 hours; weekends have 2 steps of 12 hours.

``` python
print(f"Weekday steps: {timer.weekday_step_duration} hours  ({sum(timer.weekday_step_duration)}h total)")
print(f"Weekend steps: {timer.weekend_step_duration} hours  ({sum(timer.weekend_step_duration)}h total)")
```

    Weekday steps: [8, 8, 8] hours  (24h total)
    Weekend steps: [12, 12] hours  (24h total)

### Advancing Through Time

Each call to `next(timer)` advances the timer by one step.

``` python
timer2 = Timer(
    initial_day="2020-03-02",
    total_days=7,
    weekday_step_duration=[8, 8, 8],
    weekend_step_duration=[12, 12],
)

print(f"{'Step':>4} | {'Date':<20} | {'Day':<10} | {'Shift':>5} | {'Duration (h)':>12}")
print("─" * 5 + "|" + "─" * 22 + "|" + "─" * 12 + "|" + "─" * 7 + "|" + "─" * 13)
for step_num in range(25):
    try:
        next(timer2)
    except StopIteration:
        break
    d = timer2.date.strftime("%Y-%m-%d %H:%M")
    dn = timer2.date.strftime("%A")
    dur_h = timer2.duration
    print(f"{step_num+1:4d} | {d:<20} | {dn:<10} | {timer2.shift:5d} | {dur_h:12.1f}")
```

    Step | Date                 | Day        | Shift | Duration (h)
    ─────|──────────────────────|────────────|───────|─────────────
       1 | 2020-03-02 08:00     | Monday     |     1 |          0.3
       2 | 2020-03-02 16:00     | Monday     |     2 |          0.3
       3 | 2020-03-03 00:00     | Tuesday    |     0 |          0.3
       4 | 2020-03-03 08:00     | Tuesday    |     1 |          0.3
       5 | 2020-03-03 16:00     | Tuesday    |     2 |          0.3
       6 | 2020-03-04 00:00     | Wednesday  |     0 |          0.3
       7 | 2020-03-04 08:00     | Wednesday  |     1 |          0.3
       8 | 2020-03-04 16:00     | Wednesday  |     2 |          0.3
       9 | 2020-03-05 00:00     | Thursday   |     0 |          0.3
      10 | 2020-03-05 08:00     | Thursday   |     1 |          0.3
      11 | 2020-03-05 16:00     | Thursday   |     2 |          0.3
      12 | 2020-03-06 00:00     | Friday     |     0 |          0.3
      13 | 2020-03-06 08:00     | Friday     |     1 |          0.3
      14 | 2020-03-06 16:00     | Friday     |     2 |          0.3
      15 | 2020-03-07 00:00     | Saturday   |     0 |          0.5
      16 | 2020-03-07 12:00     | Saturday   |     1 |          0.5
      17 | 2020-03-08 00:00     | Sunday     |     0 |          0.5
      18 | 2020-03-08 12:00     | Sunday     |     1 |          0.5
      19 | 2020-03-09 00:00     | Monday     |     0 |          0.3
      20 | 2020-03-09 08:00     | Monday     |     1 |          0.3
      21 | 2020-03-09 16:00     | Monday     |     2 |          0.3
      22 | 2020-03-10 00:00     | Tuesday    |     0 |          0.3
      23 | 2020-03-10 08:00     | Tuesday    |     1 |          0.3
      24 | 2020-03-10 16:00     | Tuesday    |     2 |          0.3
      25 | 2020-03-11 00:00     | Wednesday  |     0 |          0.3

## Building a Mini World

A `World` holds the entire simulation state. Here we build a small world
by hand for demonstration.

``` python
from june.demography import Person
from june.groups import Household
from june.groups.school import School
from june.groups.company import Company

# Population
people_list = []
ages = [5, 8, 32, 35, 42, 55, 68, 75]
for i, age in enumerate(ages):
    p = Person.from_attributes(sex='m' if i % 2 == 0 else 'f', age=age)
    people_list.append(p)

# Households
h1 = Household()
h1.add(people_list[0])  # child (5)
h1.add(people_list[2])  # parent (32)
h1.add(people_list[3])  # parent (35)

h2 = Household()
h2.add(people_list[4])  # adult (42)
h2.add(people_list[5])  # adult (55)

h3 = Household()
h3.add(people_list[6])  # elderly (68)
h3.add(people_list[7])  # elderly (75)

# School
school = School(coordinates=[51.5, -0.12], n_pupils_max=200,
                age_min=5, age_max=11, sector="primary")
school.add(people_list[0])
school.add(people_list[1])

# Company
company = Company(sector="Q", n_workers_max=20)
company.add(people_list[4])
company.add(people_list[5])

print("Mini-world summary:")
print(f"  People: {len(people_list)}")
print(f"  Households: 3 ({len(h1.people)}+{len(h2.people)}+{len(h3.people)} residents)")
print(f"  School: {school.n_pupils} pupils")
print(f"  Company: {company.n_workers} workers")
```

    Mini-world summary:
      People: 8
      Households: 3 (3+2+2 residents)
      School: 2 pupils
      Company: 2 workers

## The Interaction Model

The `Interaction` class controls how disease spreads within groups.

``` python
betas = {
    "household": 0.208,
    "school": 0.070,
    "company": 0.371,
}

print("Interaction model:")
print(f"  alpha_physical = 2.0")
for g, b in sorted(betas.items(), key=lambda x: -x[1]):
    bar = "█" * int(b * 40)
    print(f"  {g:<12} β = {b}  {bar}")
```

    Interaction model:
      alpha_physical = 2.0
      company      β = 0.371  ██████████████
      household    β = 0.208  ████████
      school       β = 0.07  ██

## Mini Simulation Loop

In a full simulation, the `Simulator` class wires together `World`,
`Interaction`, `Timer`, `ActivityManager`, and `Epidemiology`, typically
configured from YAML files. Here we sketch the core simulation loop to
illustrate the mechanics.

``` python
import random
import numpy as np

print("=== Mini SIR Simulation ===")
print()

# Parameters
n_people = 200
n_days = 30
beta = 0.3
gamma = 0.1
n_initial = 5

rng = random.Random(42)

# Population with households
all_people = []
for i in range(n_people):
    p = Person.from_attributes(sex=rng.choice(['m', 'f']), age=rng.randint(5, 80))
    all_people.append(p)

# Build an index mapping person -> position
pid_to_idx = {p.id: i for i, p in enumerate(all_people)}

# Create households (groups of 2-5)
households = []
idx = 0
while idx < n_people:
    hh = Household()
    hh_size = min(rng.randint(2, 5), n_people - idx)
    for j in range(hh_size):
        hh.add(all_people[idx + j])
    households.append(hh)
    idx += hh_size

# State tracking: 0=S, 1=I, 2=R
state = [0] * n_people
infected_day = [0] * n_people

# Seed infections
seeds = rng.sample(range(n_people), n_initial)
for s in seeds:
    state[s] = 1
    infected_day[s] = 0

# Run simulation
S_counts = [state.count(0)]
I_counts = [state.count(1)]
R_counts = [state.count(2)]

for day in range(1, n_days + 1):
    # Transmission within households
    for hh in households:
        members = list(hh.people)
        member_idxs = [pid_to_idx[p.id] for p in members]
        n_inf = sum(1 for i in member_idxs if state[i] == 1)
        if n_inf == 0:
            continue
        for i in member_idxs:
            if state[i] != 0:
                continue
            prob = 1.0 - (1.0 - beta / len(members)) ** n_inf
            if rng.random() < prob:
                state[i] = 1
                infected_day[i] = day

    # Recovery
    for i in range(n_people):
        if state[i] == 1 and (day - infected_day[i]) >= 3:
            if rng.random() < gamma:
                state[i] = 2

    S_counts.append(state.count(0))
    I_counts.append(state.count(1))
    R_counts.append(state.count(2))

# Display trajectory
print(f"{'Day':>3} | {'Susceptible':>11} | {'Infected':>8} | {'Recovered':>9}")
print("────|─────────────|──────────|──────────")
for d in [0, 5, 10, 15, 20, 25, 30]:
    bar_s = "░" * max(0, S_counts[d] // 5)
    bar_i = "█" * max(0, I_counts[d] // 5)
    bar_r = "▓" * max(0, R_counts[d] // 5)
    print(f"{d:3d} | {S_counts[d]:11d} | {I_counts[d]:8d} | {R_counts[d]:8d}  {bar_s}{bar_i}{bar_r}")

print()
print(f"Final: S={S_counts[-1]} I={I_counts[-1]} R={R_counts[-1]}")
print(f"Attack rate: {round(100 * R_counts[-1] / n_people, 1)}%")
```

    === Mini SIR Simulation ===

    Day | Susceptible | Infected | Recovered
    ────|─────────────|──────────|──────────
      0 |         195 |        5 |        0  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█
      5 |         194 |        4 |        2  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     10 |         190 |        7 |        3  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█
     15 |         189 |        7 |        4  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█
     20 |         189 |        3 |        8  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓
     25 |         189 |        2 |        9  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓
     30 |         189 |        0 |       11  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓

    Final: S=189 I=0 R=11
    Attack rate: 5.5%

## Full Simulation Architecture

In practice, a full JUNE simulation uses config-driven setup:

``` python
print("Full JUNE Simulation Architecture")
print("═" * 50)
print()
print("  ┌─────────────┐   YAML configs")
print("  │  Geography   │ ← area coordinates, population data")
print("  │  Demography  │ ← age/sex distributions, comorbidities")
print("  └──────┬──────┘")
print("         │ generate_world_from_geography()")
print("         ▼")
print("  ┌─────────────┐")
print("  │    World     │  people, households, schools,")
print("  │              │  companies, hospitals, leisure…")
print("  └──────┬──────┘")
print("         │ Simulator(world, interaction, ...)")
print("         ▼")
print("  ┌─────────────┐   ┌──────────────┐")
print("  │  Simulator   │──▶│  Each step:   │")
print("  │              │   │  1. Policies  │")
print("  │  timer       │   │  2. Activities│")
print("  │  interaction │   │  3. Transmit  │")
print("  │  epidemiology│   │  4. Progress  │")
print("  │  policies    │   │  5. Record    │")
print("  │  record      │   └──────────────┘")
print("  └─────────────┘")
print()
print("Key classes:")
print("  Simulator()  — wire up all subsystems")
print("  sim.run()    — execute full simulation")
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
             │ Simulator(world, interaction, ...)
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

    Key classes:
      Simulator()  — wire up all subsystems
      sim.run()    — execute full simulation

## Weekday vs Weekend Step Counts

``` python
timer3 = Timer(
    initial_day="2020-03-02",
    total_days=7,
    weekday_step_duration=[8, 8, 8],
    weekend_step_duration=[12, 12],
)

weekday_steps = 0
weekend_steps = 0
for step_num in range(100):
    try:
        next(timer3)
    except StopIteration:
        break
    if timer3.date.weekday() >= 5:
        weekend_steps += 1
    else:
        weekday_steps += 1

print(f"Over 7 days (Mon 2 Mar – Sun 8 Mar 2020):")
print(f"  Weekday steps: {weekday_steps}  (5 days × 3 steps)")
print(f"  Weekend steps: {weekend_steps}  (2 days × 2 steps)")
print(f"  Total steps:   {weekday_steps + weekend_steps}")
```

    Over 7 days (Mon 2 Mar – Sun 8 Mar 2020):
      Weekday steps: 80  (5 days × 3 steps)
      Weekend steps: 20  (2 days × 2 steps)
      Total steps:   100
