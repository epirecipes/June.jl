#!/usr/bin/env python3
"""
Household SIR scenario — Python side.

SIR with household-only transmission (no school/company).
Tests small-group dynamics with higher beta.

Usage:
    python eval/scenarios/household_sir.py --seed 42 --n_people 200 --n_steps 50

Output: CSV to stdout with columns step,susceptible,infected,recovered
Memory: optional --measure_memory prints MEMORY:current,peak to stderr
"""

import sys
import types
import argparse
import random
from math import exp, gamma, log

fake_turtle = types.ModuleType("turtle")
fake_turtle.home = lambda: None
sys.modules["turtle"] = fake_turtle


def gamma_pdf(x, shape, scale):
    if x <= 0.0:
        return 0.0
    try:
        log_pdf = (
            (shape - 1.0) * log(x)
            - x / scale
            - shape * log(scale)
            - log(gamma(shape))
        )
        return exp(log_pdf)
    except (ValueError, OverflowError):
        return 0.0


class TransmissionGamma:
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


def run_household_sir(seed, n_people=200, n_steps=50, n_initial_infected=5,
                      beta=0.5, gamma_shape=1.56, gamma_rate=0.53,
                      gamma_shift=-2.12, recovery_days=14):
    rng = random.Random(seed)

    people_sex = []
    people_age = []
    for _ in range(n_people):
        sex = rng.choice(["m", "f"])
        age = rng.randint(1, 80)
        people_sex.append(sex)
        people_age.append(age)

    # Households of 4 ONLY — no school or company
    households = []
    for i in range(0, n_people, 4):
        hh = list(range(i, min(i + 4, n_people)))
        households.append(hh)

    all_groups = households

    infected = [False] * n_people
    recovered = [False] * n_people
    days_infected = [0] * n_people

    indices = list(range(n_people))
    shuffled = indices[:]
    rng.shuffle(shuffled)
    initial_infected = shuffled[:n_initial_infected]
    for idx in initial_infected:
        infected[idx] = True
        days_infected[idx] = 1

    tg = TransmissionGamma(beta, gamma_shape, gamma_rate, gamma_shift)

    results = []
    s_count = sum(1 for i in range(n_people) if not infected[i] and not recovered[i])
    i_count = sum(1 for i in range(n_people) if infected[i] and not recovered[i])
    r_count = sum(recovered)
    results.append((0, s_count, i_count, r_count))

    for step in range(1, n_steps + 1):
        new_infections = [False] * n_people

        for group in all_groups:
            if not group:
                continue
            for pid in group:
                if infected[pid] and not recovered[pid]:
                    tg.update_infection_probability(float(days_infected[pid]))
                    prob = tg.probability
                    for qid in group:
                        if not infected[qid] and not recovered[qid] and not new_infections[qid]:
                            if rng.random() < prob:
                                new_infections[qid] = True

        for i in range(n_people):
            if new_infections[i]:
                infected[i] = True
                days_infected[i] = 1

        for i in range(n_people):
            if infected[i] and not recovered[i]:
                if days_infected[i] >= recovery_days:
                    infected[i] = False
                    recovered[i] = True
                else:
                    days_infected[i] += 1

        s_count = sum(1 for i in range(n_people) if not infected[i] and not recovered[i])
        i_count = sum(1 for i in range(n_people) if infected[i] and not recovered[i])
        r_count = sum(recovered)
        results.append((step, s_count, i_count, r_count))

    return results


def main():
    parser = argparse.ArgumentParser(description="Household SIR scenario (Python)")
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--n_people", type=int, default=200)
    parser.add_argument("--n_steps", type=int, default=50)
    parser.add_argument("--n_initial_infected", type=int, default=5)
    parser.add_argument("--beta", type=float, default=0.5)
    parser.add_argument("--gamma_shape", type=float, default=1.56)
    parser.add_argument("--gamma_rate", type=float, default=0.53)
    parser.add_argument("--gamma_shift", type=float, default=-2.12)
    parser.add_argument("--recovery_days", type=int, default=14)
    parser.add_argument("--measure_memory", action="store_true")
    args = parser.parse_args()

    if args.measure_memory:
        import tracemalloc
        tracemalloc.start()

    results = run_household_sir(
        seed=args.seed, n_people=args.n_people, n_steps=args.n_steps,
        n_initial_infected=args.n_initial_infected, beta=args.beta,
        gamma_shape=args.gamma_shape, gamma_rate=args.gamma_rate,
        gamma_shift=args.gamma_shift, recovery_days=args.recovery_days,
    )

    print("step,susceptible,infected,recovered")
    for step, s, i, r in results:
        print(f"{step},{s},{i},{r}")

    if args.measure_memory:
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        print(f"MEMORY:{current},{peak}", file=sys.stderr)


if __name__ == "__main__":
    main()
