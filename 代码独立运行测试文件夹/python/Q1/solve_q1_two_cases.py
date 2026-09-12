#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CUMCM 2026 C题 问题1 —— 双情形求解
  情形A: S(0) 自由优化 (稳态循环, 仅要求 S(0:00)=S(24:00))  -> result1.xlsx
  情形B: S(0)=S(24:00)=6000 kWh 固定 (附录1初始值解读)       -> result1_fix6000.xlsx
约定: 附件1 第 i 行(时刻戳)对应该时刻起点的 10 min 区间。
"""
import json
from pathlib import Path
import numpy as np
import openpyxl
from scipy.optimize import linprog

BASE = Path(__file__).resolve().parents[1]
SRC = BASE / "附件" / "附件1.xlsx"

wb = openpyxl.load_workbook(SRC, data_only=True)
rows = [r for r in wb["Sheet1"].iter_rows(min_row=2, values_only=True)]
assert len(rows) == 144
c  = np.array([float(r[1]) for r in rows])
L  = np.array([float(r[2]) for r in rows])
pv = np.array([float(r[3]) for r in rows])

T, dt = 144, 1.0 / 6.0
ETA_C = ETA_D = 0.9
PMAX = 5000.0
SMIN, SMAX = 1200.0, 10800.0
ip, ich, idi, iq, is_ = 0, T, 2 * T, 3 * T, 4 * T
nx = 5 * T + 1

def solve(s0_fixed=None):
    f = np.zeros(nx); f[ip:ip + T] = c * dt
    Aeq, beq = [], []
    for t in range(T):
        r = np.zeros(nx)
        r[ip + t] = 1; r[idi + t] = 1; r[ich + t] = -1; r[iq + t] = -1
        Aeq.append(r); beq.append(L[t] - pv[t])
    for t in range(T):
        r = np.zeros(nx)
        r[is_ + t + 1] = 1; r[is_ + t] = -1
        r[ich + t] = -ETA_C * dt; r[idi + t] = dt / ETA_D
        Aeq.append(r); beq.append(0.0)
    r = np.zeros(nx); r[is_] = 1; r[is_ + T] = -1      # S(144)=S(0)
    Aeq.append(r); beq.append(0.0)
    if s0_fixed is not None:                            # S(0)=s0_fixed
        r = np.zeros(nx); r[is_] = 1
        Aeq.append(r); beq.append(s0_fixed)
    bnd = ([(0, None)] * T + [(0, PMAX)] * 2 * T +
           [(0, None)] * T + [(SMIN, SMAX)] * (T + 1))
    res = linprog(f, A_eq=np.array(Aeq), b_eq=np.array(beq),
                  bounds=bnd, method="highs")
    assert res.status == 0, res.message
    return res

def postprocess(res):
    x = res.x
    p, ch, dis = x[ip:ip+T], x[ich:ich+T], x[idi:idi+T]
    q, s = x[iq:iq+T], x[is_:is_+T+1]
    Ep, Ech, Edis, Eq = p*dt, ch*dt, dis*dt, q*dt
    for a in (Ep, Ech, Edis, Eq):
        a[np.abs(a) < 1e-6] = 0.0
    bal = np.abs(p + pv + dis - L - ch - q).max()
    assert bal < 1e-6 and s.min() >= SMIN-1e-6 and s.max() <= SMAX+1e-6
    return Ep, Ech, Edis, Eq, s

idx_t1 = [59, 71, 83, 95, 107, 119]
names_t1 = ["10:00-10:10","12:00-12:10","14:00-14:10",
            "16:00-16:10","18:00-18:10","20:00-20:10"]
blocks = [[143] + list(range(0, 23))] + [list(range(a, b))
         for a, b in [(23, 47), (47, 71), (71, 95), (95, 119), (119, 143)]]
bnames = ["0:00-4:00","4:00-8:00","8:00-12:00",
          "12:00-16:00","16:00-20:00","20:00-24:00"]

def tag(m):
    plus = "+1" if m >= 1440 else ""
    m %= 1440
    return f"{m//60}:{m%60:02d}{plus}"

def write_xlsx(path, Ep, Ech, Edis, s):
    out = openpyxl.Workbook()
    ws1 = out.active; ws1.title = "计划购电量"
    ws1.append(["时间段", "购电量"])
    for i in range(144):
        ws1.append([f"{tag(10*(i+1))}-{tag(10*(i+2))}", round(float(Ep[i]), 4)])
    ws2 = out.create_sheet("充放电量")
    ws2.append(["时间段", "充电量", "放电量", "时刻", "储电量"])
    for j, (n, b) in enumerate(zip(bnames, blocks)):
        r = [n, round(float(Ech[b].sum()), 4), round(float(Edis[b].sum()), 4)]
        if j == 0:   r += ["0:00",  round(float(s[143]), 4)]
        elif j == 1: r += ["24:00", round(float(s[143]), 4)]
        else:        r += [None, None]
        ws2.append(r)
    out.save(path)

def report(name, res, Ep, Ech, Edis, Eq, s):
    print(f"\n{'='*56}\n {name}\n{'='*56}")
    print(f"全天购电费: {res.fun:.4f} 元   全天购电量: {Ep.sum():.4f} kWh")
    print(f"0:00/24:00 储电量: {s[143]:.4f} kWh   弃光: {Eq.sum():.4f} kWh")
    for n, i in zip(names_t1, idx_t1):
        print(f"  {n}: {Ep[i]:.4f}")
    for n, b in zip(bnames, blocks):
        print(f"  {n}: 充电 {Ech[b].sum():9.4f}  放电 {Edis[b].sum():9.4f}")
    # 关键时刻轨迹 (s[k]=第k段结束储电量, 对应时钟 10(k+1) 分钟)
    anchors = {"0:00": 143, "6:00": 35, "8:00": 47, "10:00": 59,
               "14:30": 86, "18:00": 107, "20:50": 124, "22:00": 131}
    tr = "  轨迹: " + "  ".join(f"{k}={s[v]:.0f}" for k, v in anchors.items())
    print(tr)
    return {"cost": res.fun, "purchase": float(Ep.sum()), "s000": float(s[143]),
            "curtail": float(Eq.sum()),
            "t1": {n: float(Ep[i]) for n, i in zip(names_t1, idx_t1)},
            "t2": {n: [float(Ech[b].sum()), float(Edis[b].sum())]
                   for n, b in zip(bnames, blocks)}}

# ---- 情形 A: S(0) 自由 ----
resA = solve()
EpA, EchA, EdisA, EqA, sA = postprocess(resA)
sumA = report("情形 A: S(0) 自由优化", resA, EpA, EchA, EdisA, EqA, sA)
write_xlsx(BASE / "Q1" / "result1.xlsx", EpA, EchA, EdisA, sA)

# ---- 情形 B: S(0)=6000 固定 ----
resB = solve(s0_fixed=6000.0)
EpB, EchB, EdisB, EqB, sB = postprocess(resB)
sumB = report("情形 B: S(0)=S(24:00)=6000 kWh 固定", resB, EpB, EchB, EdisB, EqB, sB)
write_xlsx(BASE / "Q1" / "result1_fix6000.xlsx", EpB, EchB, EdisB, sB)

print(f"\n费用差: {resB.fun - resA.fun:+.4f} 元 "
      f"({(resB.fun - resA.fun)/resA.fun*100:+.4f}%)")
json.dump({"A_free": sumA, "B_fix6000": sumB},
          open(BASE / "Q1" / "summary1_two_cases.json", "w"),
          ensure_ascii=False, indent=1)
print("已写出 result1.xlsx (情形A) 与 result1_fix6000.xlsx (情形B)")
