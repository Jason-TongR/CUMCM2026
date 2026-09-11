#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CUMCM 2026 C题 问题1 —— 微网日前计划购电策略 (LP 参考解)
约定: 附件1 第 i 行(时刻戳)对应该时刻起点的 10 min 区间,
     与 result1.xlsx 模板 "计划购电量" 表的行顺序一一对应。
变量: p[t]购电功率, ch[t]充电功率, dis[t]放电功率, q[t]弃光功率 (kW),
     s[k] 第 k 个区间结束时的储电量 (kWh), k=0..144
"""
import json
import numpy as np
import openpyxl
from scipy.optimize import linprog

BASE = "/home/jason/DataDisk/Jason's study/数学建模大赛/题目/CUMCM2026Problems/C题"
SRC = BASE + "/附件/附件1.xlsx"
OUT = BASE + "/Q1/result1.xlsx"

# ---------- 1. 读数据 ----------
wb = openpyxl.load_workbook(SRC, data_only=True)
ws = wb["Sheet1"]
rows = [r for r in ws.iter_rows(min_row=2, values_only=True)]
assert len(rows) == 144, f"数据行数={len(rows)}"
c = np.array([float(r[1]) for r in rows])   # 电价 元/kWh
L = np.array([float(r[2]) for r in rows])   # 负载 kW
pv = np.array([float(r[3]) for r in rows])  # 光伏预测 kW

T = 144
dt = 1.0 / 6.0          # 10 min = 1/6 h
ETA_C = ETA_D = 0.9     # 充/放电效率
PMAX = 5000.0           # 最大充放电功率 kW
SMIN, SMAX = 1200.0, 10800.0   # 运行储电量上下限 kWh

# ---------- 2. 组装 LP ----------
# x = [p(0:144), ch(144:288), dis(288:432), q(432:576), s(576:721)]
ip, ich, idi, iq, is_ = 0, T, 2 * T, 3 * T, 4 * T
nx = 4 * T + (T + 1)

f = np.zeros(nx)
f[ip:ip + T] = c * dt                       # 目标: 购电费用最小

Aeq, beq = [], []
for t in range(T):                          # 功率平衡: p+pv+dis = L+ch+q
    row = np.zeros(nx)
    row[ip + t] = 1; row[idi + t] = 1
    row[ich + t] = -1; row[iq + t] = -1
    Aeq.append(row); beq.append(L[t] - pv[t])
for t in range(T):                          # 储能动态
    row = np.zeros(nx)
    row[is_ + t + 1] = 1; row[is_ + t] = -1
    row[ich + t] = -ETA_C * dt; row[idi + t] = dt / ETA_D
    Aeq.append(row); beq.append(0.0)
row = np.zeros(nx)                          # 周期约束 s(144)=s(0)
row[is_] = 1; row[is_ + T] = -1
Aeq.append(row); beq.append(0.0)
Aeq = np.array(Aeq); beq = np.array(beq)

bounds = ([(0, None)] * T + [(0, PMAX)] * T + [(0, PMAX)] * T +
          [(0, None)] * T + [(SMIN, SMAX)] * (T + 1))

res = linprog(f, A_eq=Aeq, b_eq=beq, bounds=bounds, method="highs")
assert res.status == 0, res.message
x = res.x
print(f"求解成功, 最优购电费用 = {res.fun:.4f} 元")

# ---------- 3. 后处理 ----------
p, ch, dis = x[ip:ip+T], x[ich:ich+T], x[idi:idi+T]
q, s = x[iq:iq+T], x[is_:is_+T+1]
Ep, Ech, Edis, Eq = p*dt, ch*dt, dis*dt, q*dt   # kWh

tol = 1e-6
for arr in (Ep, Ech, Edis, Eq):
    arr[np.abs(arr) < tol] = 0.0

idx_t1 = [59, 71, 83, 95, 107, 119]  # 10:00,12:00,14:00,16:00,18:00,20:00
names_t1 = ["10:00-10:10","12:00-12:10","14:00-14:10",
            "16:00-16:10","18:00-18:10","20:00-20:10"]
blocks = [None] * 6
blocks[0] = [143] + list(range(0, 23))   # 0:00-4:00
blocks[1] = list(range(23, 47))          # 4:00-8:00
blocks[2] = list(range(47, 71))          # 8:00-12:00
blocks[3] = list(range(71, 95))          # 12:00-16:00
blocks[4] = list(range(95, 119))         # 16:00-20:00
blocks[5] = list(range(119, 143))        # 20:00-24:00
bnames = ["0:00-4:00","4:00-8:00","8:00-12:00",
          "12:00-16:00","16:00-20:00","20:00-24:00"]

s000 = s[143]      # 时钟 0:00(=24:00) 位于第143、144行之间
s2400 = s[143]

print("\n===== 表1 购电量 =====")
for n, i in zip(names_t1, idx_t1):
    print(f"{n}: {Ep[i]:.4f} kWh")
print(f"全天购电量: {Ep.sum():.4f} kWh   全天购电费: {res.fun:.4f} 元")

print("\n===== 表2 充放电量 =====")
for n, b in zip(bnames, blocks):
    print(f"{n}: 充电 {Ech[b].sum():9.4f} kWh   放电 {Edis[b].sum():9.4f} kWh")
print(f"0:00 储电量: {s000:.4f} kWh   24:00 储电量: {s2400:.4f} kWh")
print(f"\n弃光总量: {Eq.sum():.4f} kWh")
print(f"储电量范围: [{s.min():.2f}, {s.max():.2f}] kWh")

# 校验
bal = p + pv + dis - L - ch - q
print(f"功率平衡最大残差: {np.abs(bal).max():.2e} kW")
print(f"储能上下限校验: min={s.min():.2f}>=1200, max={s.max():.2f}<=10800")

# ---------- 4. 写 result1.xlsx (按模板版式重建) ----------
def tag(m):          # 分钟->时刻标签
    plus = "+1" if m >= 1440 else ""
    m = m % 1440
    return f"{m//60}:{m%60:02d}{plus}"

out = openpyxl.Workbook()
ws1 = out.active; ws1.title = "计划购电量"
ws1.append(["时间段", "购电量"])
for i in range(144):
    ws1.append([f"{tag(10*(i+1))}-{tag(10*(i+2))}", round(float(Ep[i]), 4)])
ws2 = out.create_sheet("充放电量")
ws2.append(["时间段", "充电量", "放电量", "时刻", "储电量"])
for j, (n, b) in enumerate(zip(bnames, blocks)):
    r = [n, round(float(Ech[b].sum()), 4), round(float(Edis[b].sum()), 4)]
    if j == 0: r += ["0:00", round(float(s000), 4)]
    elif j == 1: r += ["24:00", round(float(s2400), 4)]
    else: r += [None, None]
    ws2.append(r)
out.save(OUT)
print(f"\n已写出 {OUT}")

json.dump({"cost": res.fun, "total_purchase": float(Ep.sum()),
           "s000": float(s000), "curtail": float(Eq.sum())},
          open(BASE + "/Q1/summary1.json", "w"), ensure_ascii=False, indent=1)
