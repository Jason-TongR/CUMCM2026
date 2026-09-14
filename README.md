# CUMCM2026 · Microgrid Energy Scheduling

> A reproducible modeling and optimization repository for **China Undergraduate Mathematical Contest in Modeling 2026 · Problem C**.
>
> **Forecast demand. Schedule energy. Adapt in real time. Quantify uncertainty.**

[![Python](https://img.shields.io/badge/Python-3.9%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2019b%2B-0076A8?logo=mathworks&logoColor=white)](https://www.mathworks.com/products/matlab.html)
[![Optimization](https://img.shields.io/badge/Optimization-LP%20%2B%20Rolling%20Control-2F855A)](#modeling-architecture)
[![License](https://img.shields.io/badge/License-Academic%20Use-lightgrey)](#notes-on-use)

English | [中文](READMECN.md)

---

## Project At A Glance

This repository develops a complete decision framework for a photovoltaic-and-storage microgrid under changing forecasts, operating constraints, and electricity prices.

The central question is simple but operationally rich:

> **How should a microgrid commit to grid purchases before reality is known, then react when demand, solar generation, and prices deviate from the plan?**

The solution is organized as a four-stage progression:

| Stage | Decision setting | Core contribution |
| --- | --- | --- |
| **Q1** | Deterministic daily operation | Linear-programming benchmark for tariff arbitrage and storage dispatch |
| **Q2** | Annual uncertainty and real-time deviations | Weekday-aware forecasting, day-ahead commitment, and emergency-power control |
| **Q3** | Intra-day photovoltaic forecast updates | Calibrated forecast fusion, bidirectional adjustment, and terminal reserve protection |
| **Q4** | Day-by-day volatile electricity prices | Reuse and stress-test the Q2/Q3 strategy chain under realistic price variation |

The repository includes mathematical write-ups, Python implementations, MATLAB implementations, generated summaries, test layouts, and supporting submission materials.

## Results Snapshot

The headline figures below are produced by the final models documented in `C题/`.

| Finding | Result |
| --- | ---: |
| Q1 daily bill with storage | **¥35,118.60** |
| Q1 saving versus no storage | **¥12,933.45/day · 26.9%** |
| Q2 annual cost, rolling strategy | **¥14,546,503.97** |
| Q3 annual cost, calibrated adjustment strategy | **¥13,687,490.69** |
| Q3 improvement over Q2 | **¥859,013.28 · 5.91%** |
| Q4 cost under volatile prices, Q2 strategy | **¥15,263,635.75** |
| Q4 cost under volatile prices, Q3 strategy | **¥14,315,636.38** |
| Q4 advantage of Q3 over Q2 | **¥947,999.37 · 6.21%** |

These numbers are intentionally accompanied by the underlying assumptions and validation artifacts. They are research results for this dataset and model setup, not universal tariff or investment recommendations.

## Modeling Architecture

```text
Historical data + official forecasts
                |
                v
      Forecast construction
  (weekday structure / OLS calibration
       / residual-based updates)
                |
                v
        Day-ahead LP planning
  (grid purchase + charge/discharge
      + curtailment + storage state)
                |
                v
       Intra-day adjustment
  (plan deviation settlement + reserve
        protection + safety valve)
                |
                v
       Real-time physical dispatch
  (reduce charging -> discharge ->
       emergency purchase / curtailment)
                |
                v
      Accounting, diagnostics, and
        cross-language verification
```

### Common physical assumptions

- 144 ten-minute intervals per day.
- Storage operating range: **1,200–10,800 kWh**.
- Maximum charge/discharge power: **5,000 kW**.
- Charge and discharge efficiency: **90%** each.
- Emergency purchases are settled at **5×** the ordinary electricity price.
- Linear programs are solved with `scipy.optimize.linprog` in Python and `linprog` in MATLAB.

### What changes across the four questions?

- **Q1:** deterministic daily cycle with a free or fixed initial state comparison.
- **Q2:** actual annual demand and PV deviations are handled through a `w1` forecast, proportional safety margins, and rolling real-time dispatch.
- **Q3:** photovoltaic forecasts are calibrated against historical observations; updates at 06:00, 12:00, and 18:00 support bidirectional plan adjustment. A terminal reserve of 4,000 kWh avoids shortsighted depletion.
- **Q4:** the fixed daily tariff is replaced by a daily 144-point price curve while preserving the forecasting, planning, adjustment, and settlement logic.

## Repository Map

```text
CUMCM2026/
├── C题/                              # Main models, scripts, data, summaries, and explanations
│   ├── Q1/                           # Deterministic daily LP
│   ├── Q2/                           # Annual forecast + rolling dispatch
│   ├── Q3/                           # Forecast calibration + plan adjustment
│   ├── Q4/                           # Volatile-price extension
│   ├── 补充完善内容/                  # Supplementary improvement notes
│   ├── 论文素材/                      # Materials selected for the paper
│   └── 附件/                          # Problem data and supporting attachments
├── 代码独立运行测试文件夹/             # Self-contained MATLAB/Python test layout
│   ├── matlab/                        # Independent MATLAB entry points
│   ├── python/                        # Independent Python entry points
│   └── README.md                      # Detailed execution guide
└── 成品提交/                           # Submission-ready supporting materials
    ├── 支撑材料/                       # Figures, source programs, results, AI-use notes
    └── 论文/                           # Final paper materials
```

## Reproduce The Computations

### Python

Recommended: Python 3.9 or newer. From the independent test directory:

```powershell
cd "代码独立运行测试文件夹\python"
python -m pip install numpy openpyxl scipy

python Q1\solve_q1_two_cases.py
python Q2\solve_q2.py
python Q3\finalize_q3.py
python Q4\solve_q4.py
```

The scripts locate their inputs relative to the project layout. Keep each `附件` directory beside its corresponding question folders; do not rename the supplied workbooks, sheets, or data files.

### MATLAB

Recommended: MATLAB R2019b or newer with **Optimization Toolbox**. Open the relevant script in its test directory and click **Run**, or run it from MATLAB's Current Folder:

```matlab
problem1
problem2
problem3
problem4
```

The MATLAB scripts print costs, energy totals, storage bounds, and other diagnostics, and generate question-specific Excel outputs. The exact Current Folder and attachment layout are documented in [代码独立运行测试文件夹/README.md](代码独立运行测试文件夹/README.md).

### Important execution note

Run from a complete question directory rather than copying a single script. Q3 and Q4 reuse shared logic and data; preserving the supplied relative layout is part of reproducibility.

## Documentation & Outputs

| Topic | Entry point |
| --- | --- |
| Q1 assumptions, LP formulation, sensitivity analysis | [C题/Q1/模型说明.md](C题/Q1/模型说明.md) |
| Q2 forecasting, rolling control, and annual evaluation | [C题/Q2/模型说明Q2.md](C题/Q2/模型说明Q2.md) |
| Q3 forecast calibration and bidirectional adjustment | [C题/Q3/模型说明Q3.md](C题/Q3/模型说明Q3.md) |
| Q4 volatile-price modeling and sensitivity analysis | [C题/Q4/模型说明Q4.md](C题/Q4/模型说明Q4.md) |
| Q1 implementation | [C题/Q1/solve_q1_two_cases.py](C题/Q1/solve_q1_two_cases.py) |
| Q2 implementation | [C题/Q2/solve_q2.py](C题/Q2/solve_q2.py) |
| Q3 implementation | [C题/Q3/finalize_q3.py](C题/Q3/finalize_q3.py) |
| Q4 implementation | [C题/Q4/solve_q4.py](C题/Q4/solve_q4.py) |
| Structured result summaries | `C题/Q1/summary1_two_cases.json`, `C题/Q2/summary2.json`, `C题/Q3/summary3.json`, `C题/Q4/summary4.json` |
| Independent execution guide | [代码独立运行测试文件夹/README.md](代码独立运行测试文件夹/README.md) |

## Design Choices Worth Reading

### 1. Forecasting follows the data structure

The annual load series has a strong weekday pattern. Q2 therefore uses the actual value from the same weekday in the previous week (`w1`) instead of relying only on persistence or a moving average. This turns a large state-switching error into a manageable safety-margin problem.

### 2. The penalty structure changes the optimization behavior

Under the 5× emergency tariff, under-purchasing is much more expensive than over-purchasing. The planning margins are therefore treated as a quantile-style risk decision rather than an arbitrary buffer.

### 3. Adjustment is valuable only when it is priced correctly

Q3 models both upward and downward deviations from the original plan. The 0.5× deviation charge makes adjustment an intermediate option between perfect plan adherence and 5× emergency purchases. Forecast calibration and a 4,000 kWh terminal reserve prevent the adjustment mechanism from becoming either too timid or too shortsighted.

### 4. Volatility is about correlation, not just the mean price

In Q4, the volatile tariff preserves the annual mean price but changes its relationship with demand and PV output. The resulting cost increase is therefore explained through price-load and price-PV correlation, not a simple tariff-level shift.

## Reproducibility Checklist

- Use the supplied attachments without changing filenames, sheet names, or relative locations.
- Keep Python and MATLAB pointed at the same input data when comparing implementations.
- Record the Python, NumPy, SciPy, OpenPyXL, MATLAB, and Optimization Toolbox versions for formal reruns.
- Treat generated Excel, JSON, and NPZ files as outputs of an experiment; the model explanations state which scenario each file represents.
- Inspect the storage bounds, energy balance, emergency purchases, and cross-day continuity when modifying a strategy.

## Notes On Use

This is an academic modeling repository created for analysis, competition submission, and reproducible experimentation. The data, assumptions, prices, forecasts, and storage parameters are specific to the contest problem. The code is provided for scholarly and educational use; validate all assumptions before applying the framework to an actual microgrid.

For the Chinese project guide, see [READMECN.md](READMECN.md).
