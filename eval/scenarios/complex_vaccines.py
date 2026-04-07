#!/usr/bin/env python3
"""
Complex vaccination scenario with NPIs — standalone Python implementation.

Simulates a JUNE-like agent-based model with:
- Structured population (UK age distribution)
- Multiple group types (households, schools, companies, leisure venues)
- Contact matrices with subgroup structure and physical contacts
- SEIR + hospitalisation + death health progression
- Vaccination with efficacy against infection, symptoms, and death
- School social distancing NPI
- Day/night activity schedule with weekday/weekend patterns

Usage:
    python eval/scenarios/complex_vaccines.py --seed 42 --n_people 5000 --n_steps 100

Output: CSV to stdout with columns:
    step,day,susceptible,exposed,infected,recovered,dead,hospitalised,vaccinated_infected
Memory: optional --measure_memory prints MEMORY:current,peak to stderr
"""

import sys
import types
import argparse
import random
from math import exp, gamma as math_gamma, log

# Turtle workaround (required by some JUNE transitive deps)
fake_turtle = types.ModuleType("turtle")
fake_turtle.home = lambda: None
sys.modules["turtle"] = fake_turtle

# ── Constants ────────────────────────────────────────────────────────────────

BETAS = {
    'household': 0.208,
    'school': 0.070,
    'company': 0.371,
    'pub': 0.429,
    'grocery': 0.041,
}

CONTACT_MATRICES = {
    'household': {
        'contacts': [[1.37, 1.30, 1.49, 1.49],
                     [1.30, 2.48, 1.31, 1.31],
                     [1.30, 0.93, 1.19, 1.19],
                     [1.30, 0.93, 1.19, 1.31]],
        'physical': [[0.79, 0.70, 0.70, 0.70],
                     [0.70, 0.34, 0.40, 0.40],
                     [0.70, 0.40, 0.62, 0.62],
                     [0.70, 0.62, 0.62, 0.45]],
        'char_time': 12,
    },
    'school': {
        'contacts': [[5, 15], [0.75, 2.5]],
        'physical': [[0.05, 0.08], [0.08, 0.15]],
        'char_time': 8,
    },
    'company': {
        'contacts': [[4.8]],
        'physical': [[0.07]],
        'char_time': 8,
    },
    'pub': {
        'contacts': [[3]],
        'physical': [[0.12]],
        'char_time': 3,
    },
    'grocery': {
        'contacts': [[1.5]],
        'physical': [[0.12]],
        'char_time': 3,
    },
}

ALPHA_PHYSICAL = 2.0

# UK-like age distribution: (min_age, max_age, fraction)
AGE_DISTRIBUTION = [
    (0, 4, 0.06),
    (5, 11, 0.08),
    (12, 15, 0.05),
    (16, 17, 0.03),
    (18, 24, 0.09),
    (25, 44, 0.27),
    (45, 64, 0.25),
    (65, 79, 0.13),
    (80, 99, 0.04),
]

# Vaccination efficacy parameters
VAX_EFFICACY_INFECTION = 0.80
VAX_EFFICACY_SYMPTOMS = 0.90
VAX_EFFICACY_DEATH = 0.95

# Disease timing (days)
EXPOSED_DAYS = 3
INFECTIOUS_DAYS = 7
HOSPITAL_DAYS = 10
DEATH_DAY = 5
ASYMPTOMATIC_FRACTION = 0.40

# Activity schedules: list of (duration_hours, active_group_types)
WEEKDAY_SCHEDULE = [
    (1.0, ['household']),
    (8.0, ['household', 'school', 'company']),
    (1.0, ['household']),
    (3.0, ['household', 'pub', 'grocery']),
    (11.0, ['household']),
]

WEEKEND_SCHEDULE = [
    (12.0, ['household', 'pub', 'grocery']),
    (12.0, ['household']),
]


# ── Age-dependent rates ─────────────────────────────────────────────────────

def hosp_rate(age):
    """Probability of hospitalisation given symptomatic infection."""
    if age < 40:
        return 0.01
    elif age < 60:
        return 0.05
    elif age < 80:
        return 0.15
    else:
        return 0.30


def death_rate(age):
    """Probability of death given hospitalisation."""
    if age < 60:
        return 0.05
    elif age < 80:
        return 0.20
    else:
        return 0.40


def base_susceptibility(age):
    """Age-dependent susceptibility multiplier."""
    return 0.5 if age <= 12 else 1.0


def household_subgroup(age):
    """Household subgroup: 0=kids(0-5), 1=young(6-17), 2=adults(18-64), 3=old(65+)."""
    if age <= 5:
        return 0
    elif age <= 17:
        return 1
    elif age <= 64:
        return 2
    else:
        return 3


# ── Gamma PDF and Transmission (matches June.jl) ────────────────────────────

def gamma_pdf(x, shape, scale):
    """Standard Gamma PDF: f(x; k, theta) for x > 0."""
    if x <= 0.0:
        return 0.0
    try:
        log_pdf = (
            (shape - 1.0) * log(x)
            - x / scale
            - shape * log(scale)
            - log(math_gamma(shape))
        )
        return exp(log_pdf)
    except (ValueError, OverflowError):
        return 0.0


class TransmissionGamma:
    """Matches June.jl's TransmissionGamma normalization."""

    def __init__(self, max_infectiousness, shape, rate, shift):
        self.max_infectiousness = max_infectiousness
        self.shape = shape
        self.rate = rate
        self.shift = shift
        self.scale = 1.0 / rate
        self.probability = 0.0
        mode = (shape - 1.0) * self.scale
        pdf_at_mode = gamma_pdf(mode, shape, self.scale) if mode > 0 else 1.0
        self.norm = max_infectiousness / pdf_at_mode if pdf_at_mode > 1e-30 else 0.0

    def update_infection_probability(self, time_from_infection):
        if time_from_infection > self.shift:
            self.probability = self.norm * gamma_pdf(
                time_from_infection - self.shift, self.shape, self.scale
            )
        else:
            self.probability = 0.0


# ── Population creation ──────────────────────────────────────────────────────

def create_population(n_people, rng):
    """Create population with UK-like age distribution."""
    ages = []
    sexes = []
    total_assigned = 0
    for i, (lo, hi, frac) in enumerate(AGE_DISTRIBUTION):
        if i < len(AGE_DISTRIBUTION) - 1:
            n = int(round(n_people * frac))
        else:
            n = n_people - total_assigned
        total_assigned += n
        for _ in range(n):
            ages.append(rng.randint(lo, hi))
            sexes.append(rng.choice(['m', 'f']))

    # Shuffle to randomise ordering
    indices = list(range(n_people))
    rng.shuffle(indices)
    ages = [ages[indices[i]] for i in range(n_people)]
    sexes = [sexes[indices[i]] for i in range(n_people)]
    return ages, sexes


# ── Group creation ───────────────────────────────────────────────────────────

def create_households(ages, n_people, rng):
    """Create households with family-like age structure (~n/4 households)."""
    kids = [i for i in range(n_people) if ages[i] <= 17]
    adults = [i for i in range(n_people) if 18 <= ages[i] <= 64]
    elderly = [i for i in range(n_people) if ages[i] >= 65]

    rng.shuffle(kids)
    rng.shuffle(adults)
    rng.shuffle(elderly)

    households = []
    ki, ai, ei = 0, 0, 0

    # Family households: 1-2 adults + 1-3 kids
    while ki < len(kids) and ai < len(adults):
        hh = [adults[ai]]
        ai += 1
        if ai < len(adults) and rng.random() < 0.7:
            hh.append(adults[ai])
            ai += 1
        n_kids = min(rng.choice([1, 2, 2, 3]), len(kids) - ki)
        for _ in range(n_kids):
            hh.append(kids[ki])
            ki += 1
        if ei < len(elderly) and rng.random() < 0.08:
            hh.append(elderly[ei])
            ei += 1
        households.append(hh)

    # Remaining kids go into existing family households
    while ki < len(kids):
        if households:
            idx = rng.randint(0, len(households) - 1)
            households[idx].append(kids[ki])
        else:
            households.append([kids[ki]])
        ki += 1

    # Elderly households: singles or pairs
    while ei < len(elderly):
        if ei + 1 < len(elderly) and rng.random() < 0.5:
            households.append([elderly[ei], elderly[ei + 1]])
            ei += 2
        else:
            households.append([elderly[ei]])
            ei += 1

    # Remaining adults: shared households of 1-4
    while ai < len(adults):
        remain = len(adults) - ai
        sz = min(rng.choice([1, 2, 2, 3, 4]), remain)
        households.append(adults[ai:ai + sz])
        ai += sz

    return households


def create_schools(ages, n_people, rng):
    """Create 3 schools: primary(5-11), secondary(12-15), sixth-form(16-18).

    Returns (schools, teacher_set) where schools is a list of
    (members, subgroup_map) and subgroup 0=teacher, 1=student.
    """
    primary_students = [i for i in range(n_people) if 5 <= ages[i] <= 11]
    secondary_students = [i for i in range(n_people) if 12 <= ages[i] <= 15]
    sixth_students = [i for i in range(n_people) if 16 <= ages[i] <= 18]

    # Teachers: adults 25-60, 2% of workforce
    potential_teachers = [i for i in range(n_people) if 25 <= ages[i] <= 60]
    rng.shuffle(potential_teachers)
    n_teachers = max(3, int(len(potential_teachers) * 0.02))
    teacher_pool = potential_teachers[:n_teachers]

    student_lists = [primary_students, secondary_students, sixth_students]
    total_students = sum(len(s) for s in student_lists)

    if total_students == 0:
        return [], set()

    # Distribute teachers proportionally, at least 1 per school with students
    teacher_counts = []
    for sl in student_lists:
        tc = max(1, int(n_teachers * len(sl) / total_students)) if sl else 0
        teacher_counts.append(tc)
    while sum(teacher_counts) > len(teacher_pool):
        for j in range(len(teacher_counts) - 1, -1, -1):
            if teacher_counts[j] > 1:
                teacher_counts[j] -= 1
                break

    schools = []
    teacher_set = set()
    ti = 0
    for students, n_t in zip(student_lists, teacher_counts):
        if not students:
            continue
        teachers = teacher_pool[ti:ti + n_t]
        ti += n_t
        teacher_set.update(teachers)
        members = list(teachers) + list(students)
        subgroup_map = {}
        for pid in teachers:
            subgroup_map[pid] = 0
        for pid in students:
            subgroup_map[pid] = 1
        schools.append((members, subgroup_map))

    return schools, teacher_set


def create_companies(ages, n_people, teacher_set, rng):
    """Create 10 companies for working-age adults not teaching or in school."""
    workers = [i for i in range(n_people)
               if 19 <= ages[i] <= 64 and i not in teacher_set]
    rng.shuffle(workers)
    n_companies = min(10, max(1, len(workers) // 5))
    companies = []
    per_company = len(workers) // n_companies if n_companies > 0 else 0
    for c in range(n_companies):
        start = c * per_company
        end = start + per_company if c < n_companies - 1 else len(workers)
        companies.append(workers[start:end])
    return companies


# ── Pre-compute effective contacts ───────────────────────────────────────────

def precompute_effective_contacts():
    """Pre-compute effective contact matrices for all group types."""
    eff = {}
    for gtype, cm in CONTACT_MATRICES.items():
        contacts = cm['contacts']
        physical = cm['physical']
        n_sg = len(contacts)
        ec = [[0.0] * n_sg for _ in range(n_sg)]
        for a in range(n_sg):
            for b in range(n_sg):
                raw = contacts[a][b]
                if raw > 0:
                    phys_frac = physical[a][b] / raw
                    ec[a][b] = raw * (1.0 + (ALPHA_PHYSICAL - 1.0) * phys_frac)
        eff[gtype] = ec
    return eff


# ── Transmission helpers ─────────────────────────────────────────────────────

def _transmit_household(members, ages, state, days_infected, susceptibility,
                        new_exposed, tg, ec_matrix, beta, char_time, dt, rng):
    """Transmission within a household using 4-subgroup contact matrix."""
    active = [p for p in members if state[p] not in ('D', 'H')]
    if len(active) <= 1:
        return
    infected_list = [p for p in active if state[p] == 'I']
    if not infected_list:
        return
    group_size = len(active)
    dt_ratio = dt / char_time
    for pid in infected_list:
        tg.update_infection_probability(days_infected[pid])
        inf = tg.probability
        if inf <= 0:
            continue
        sg_i = household_subgroup(ages[pid])
        for qid in active:
            if state[qid] != 'S' or qid in new_exposed:
                continue
            sg_j = household_subgroup(ages[qid])
            ec = ec_matrix[sg_i][sg_j]
            if ec <= 0:
                continue
            prob = 1.0 - exp(-beta * ec * inf * susceptibility[qid]
                             * dt_ratio / group_size)
            if rng.random() < prob:
                new_exposed.add(qid)


def _transmit_subgroup(members, subgroup_map, state, days_infected,
                       susceptibility, new_exposed, tg, ec_matrix,
                       beta, char_time, dt, rng):
    """Transmission within a group with explicit subgroup map (e.g. school)."""
    active = [p for p in members if state[p] not in ('D', 'H')]
    if len(active) <= 1:
        return
    infected_list = [p for p in active if state[p] == 'I']
    if not infected_list:
        return
    group_size = len(active)
    dt_ratio = dt / char_time
    for pid in infected_list:
        tg.update_infection_probability(days_infected[pid])
        inf = tg.probability
        if inf <= 0:
            continue
        sg_i = subgroup_map.get(pid, 0)
        for qid in active:
            if state[qid] != 'S' or qid in new_exposed:
                continue
            sg_j = subgroup_map.get(qid, 0)
            ec = ec_matrix[sg_i][sg_j]
            if ec <= 0:
                continue
            prob = 1.0 - exp(-beta * ec * inf * susceptibility[qid]
                             * dt_ratio / group_size)
            if rng.random() < prob:
                new_exposed.add(qid)


def _transmit_single(members, state, days_infected, susceptibility,
                     new_exposed, tg, ec_matrix, beta, char_time, dt, rng):
    """Transmission within a single-subgroup group (company, pub, grocery)."""
    active = [p for p in members if state[p] not in ('D', 'H')]
    if len(active) <= 1:
        return
    infected_list = [p for p in active if state[p] == 'I']
    if not infected_list:
        return
    group_size = len(active)
    ec = ec_matrix[0][0]
    if ec <= 0:
        return
    dt_ratio = dt / char_time
    for pid in infected_list:
        tg.update_infection_probability(days_infected[pid])
        inf = tg.probability
        if inf <= 0:
            continue
        for qid in active:
            if state[qid] != 'S' or qid in new_exposed:
                continue
            prob = 1.0 - exp(-beta * ec * inf * susceptibility[qid]
                             * dt_ratio / group_size)
            if rng.random() < prob:
                new_exposed.add(qid)


# ── Simulation ───────────────────────────────────────────────────────────────

def run_simulation(seed, n_people, n_steps, n_initial_infected,
                   vax_min_age, vax_coverage, school_beta_factor):
    rng = random.Random(seed)

    # ── Population ──
    ages, sexes = create_population(n_people, rng)

    # ── Groups ──
    households = create_households(ages, n_people, rng)
    schools, teacher_set = create_schools(ages, n_people, rng)
    companies = create_companies(ages, n_people, teacher_set, rng)

    # ── Person state arrays ──
    state = ['S'] * n_people
    days_in_state = [0] * n_people
    days_infected = [0.0] * n_people
    is_symptomatic = [False] * n_people
    will_hospitalise = [False] * n_people
    will_die = [False] * n_people
    vaccinated = [False] * n_people
    ever_infected_vax = [False] * n_people

    # ── Vaccination ──
    eligible = [i for i in range(n_people) if ages[i] >= vax_min_age]
    n_vax = int(len(eligible) * vax_coverage)
    rng.shuffle(eligible)
    for pid in eligible[:n_vax]:
        vaccinated[pid] = True

    # ── Pre-compute susceptibility ──
    susceptibility = [0.0] * n_people
    for i in range(n_people):
        s = base_susceptibility(ages[i])
        if vaccinated[i]:
            s *= (1.0 - VAX_EFFICACY_INFECTION)
        susceptibility[i] = s

    # ── Seed initial infections (start as infectious) ──
    all_ids = list(range(n_people))
    rng.shuffle(all_ids)
    for idx in all_ids[:n_initial_infected]:
        state[idx] = 'I'
        days_in_state[idx] = 0
        days_infected[idx] = 1.0
        sym_prob = 1.0 - ASYMPTOMATIC_FRACTION
        if vaccinated[idx]:
            sym_prob *= (1.0 - VAX_EFFICACY_SYMPTOMS)
        is_symptomatic[idx] = rng.random() < sym_prob
        if is_symptomatic[idx]:
            will_hospitalise[idx] = rng.random() < hosp_rate(ages[idx])
        if vaccinated[idx]:
            ever_infected_vax[idx] = True

    # ── Transmission model ──
    tg = TransmissionGamma(1.0, 1.56, 0.53, -2.12)
    eff_contacts = precompute_effective_contacts()

    # ── Simulation loop ──
    results = []

    for day in range(n_steps + 1):
        # Record daily state
        s_count = e_count = i_count = r_count = d_count = h_count = 0
        for i in range(n_people):
            st = state[i]
            if st == 'S':
                s_count += 1
            elif st == 'E':
                e_count += 1
            elif st == 'I':
                i_count += 1
            elif st == 'R':
                r_count += 1
            elif st == 'D':
                d_count += 1
            elif st == 'H':
                h_count += 1
        vi_count = sum(ever_infected_vax)
        results.append((day, day, s_count, e_count, i_count, r_count,
                         d_count, h_count, vi_count))

        if day >= n_steps:
            break

        # ── Determine schedule ──
        day_of_week = day % 7
        is_weekday = day_of_week < 5
        schedule = WEEKDAY_SCHEDULE if is_weekday else WEEKEND_SCHEDULE
        leisure_rate = 0.2 if is_weekday else 0.3

        # ── Leisure attendance for today ──
        pub_today = [i for i in range(n_people)
                     if state[i] not in ('D', 'H') and rng.random() < leisure_rate]
        grocery_today = [i for i in range(n_people)
                         if state[i] not in ('D', 'H') and rng.random() < leisure_rate]

        new_exposed = set()

        # ── Sub-timesteps ──
        for dt, active_types in schedule:
            for gtype in active_types:
                if gtype == 'household':
                    for hh in households:
                        _transmit_household(
                            hh, ages, state, days_infected, susceptibility,
                            new_exposed, tg, eff_contacts['household'],
                            BETAS['household'],
                            CONTACT_MATRICES['household']['char_time'],
                            dt, rng)

                elif gtype == 'school':
                    beta_s = BETAS['school'] * school_beta_factor
                    for members, subgroup_map in schools:
                        _transmit_subgroup(
                            members, subgroup_map, state, days_infected,
                            susceptibility, new_exposed, tg,
                            eff_contacts['school'], beta_s,
                            CONTACT_MATRICES['school']['char_time'],
                            dt, rng)

                elif gtype == 'company':
                    for members in companies:
                        _transmit_single(
                            members, state, days_infected, susceptibility,
                            new_exposed, tg, eff_contacts['company'],
                            BETAS['company'],
                            CONTACT_MATRICES['company']['char_time'],
                            dt, rng)

                elif gtype == 'pub':
                    _transmit_single(
                        pub_today, state, days_infected, susceptibility,
                        new_exposed, tg, eff_contacts['pub'],
                        BETAS['pub'],
                        CONTACT_MATRICES['pub']['char_time'],
                        dt, rng)

                elif gtype == 'grocery':
                    _transmit_single(
                        grocery_today, state, days_infected, susceptibility,
                        new_exposed, tg, eff_contacts['grocery'],
                        BETAS['grocery'],
                        CONTACT_MATRICES['grocery']['char_time'],
                        dt, rng)

        # ── Apply new exposures ──
        for pid in new_exposed:
            state[pid] = 'E'
            days_in_state[pid] = 0
            if vaccinated[pid]:
                ever_infected_vax[pid] = True

        # ── Disease progression (daily) ──
        for i in range(n_people):
            si = state[i]

            if si == 'E':
                days_in_state[i] += 1
                if days_in_state[i] >= EXPOSED_DAYS:
                    state[i] = 'I'
                    days_in_state[i] = 0
                    days_infected[i] = 1.0
                    sym_prob = 1.0 - ASYMPTOMATIC_FRACTION
                    if vaccinated[i]:
                        sym_prob *= (1.0 - VAX_EFFICACY_SYMPTOMS)
                    is_symptomatic[i] = rng.random() < sym_prob
                    if is_symptomatic[i]:
                        will_hospitalise[i] = rng.random() < hosp_rate(ages[i])

            elif si == 'I':
                days_in_state[i] += 1
                days_infected[i] += 1.0
                if days_in_state[i] >= INFECTIOUS_DAYS:
                    if will_hospitalise[i]:
                        state[i] = 'H'
                        days_in_state[i] = 0
                        dp = death_rate(ages[i])
                        if vaccinated[i]:
                            dp *= (1.0 - VAX_EFFICACY_DEATH)
                        will_die[i] = rng.random() < dp
                    else:
                        state[i] = 'R'
                        days_in_state[i] = 0

            elif si == 'H':
                days_in_state[i] += 1
                if will_die[i] and days_in_state[i] >= DEATH_DAY:
                    state[i] = 'D'
                    days_in_state[i] = 0
                elif not will_die[i] and days_in_state[i] >= HOSPITAL_DAYS:
                    state[i] = 'R'
                    days_in_state[i] = 0

    return results


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Complex vaccination scenario with NPIs (Python)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--n_people", type=int, default=5000)
    parser.add_argument("--n_steps", type=int, default=100)
    parser.add_argument("--n_initial_infected", type=int, default=25)
    parser.add_argument("--vax_min_age", type=int, default=18)
    parser.add_argument("--vax_coverage", type=float, default=0.8)
    parser.add_argument("--school_beta_factor", type=float, default=1.0)
    parser.add_argument("--measure_memory", action="store_true")
    args = parser.parse_args()

    if args.measure_memory:
        import tracemalloc
        tracemalloc.start()

    results = run_simulation(
        seed=args.seed,
        n_people=args.n_people,
        n_steps=args.n_steps,
        n_initial_infected=args.n_initial_infected,
        vax_min_age=args.vax_min_age,
        vax_coverage=args.vax_coverage,
        school_beta_factor=args.school_beta_factor,
    )

    print("step,day,susceptible,exposed,infected,recovered,"
          "dead,hospitalised,vaccinated_infected")
    for row in results:
        print(",".join(str(x) for x in row))

    if args.measure_memory:
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        print(f"MEMORY:{current},{peak}", file=sys.stderr)


if __name__ == "__main__":
    main()
