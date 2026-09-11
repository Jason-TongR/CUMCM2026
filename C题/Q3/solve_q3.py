#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CUMCM 2026 C题 问题3 —— 计划+滚动调整购电策略
流程(每天d):
  0:00  光伏估计=逐时OLS[官方0:00报, w1](30天滚动); 负载=w1; 计划LP(S(144)=S(0)=S0) → p_plan
  6/12/18:00 光伏估计=逐时OLS[官方最新报, w1] + λ_pv·当日已实现残差;
             负载估计 += λ_L·当日已实现残差 → 调整LP(分段成本 上调1.5c/下调0.5c) → p_adj
  日内   储能贪心调节(同Q2), 缺口→紧急购电(5c)
结算: C = Σ[c·p_adj + 0.5c·(p_plan-p_adj)+ + 1.5c·(p_adj-p_plan)+]·dt + Σ5c·e·dt
变体: V0=Q2式(w1光伏) V1=原始0:00报 V2=原始报+调整 V3=标定无调整 V4=完整(交付)
约定: 时刻戳=区间起点; 调整区间起点(0基): 6:00→35, 12:00→71, 18:00→107
"""
import json
import numpy as np
import openpyxl
from scipy.optimize import linprog

BASE = "/home/jason/DataDisk/Jason's study/数学建模大赛/题目/CUMCM2026Problems/C题"

c1 = openpyxl.load_workbook(BASE + "/附件/附件1.xlsx", data_only=True)["Sheet1"]
rows1 = list(c1.iter_rows(min_row=2, values_only=True))
price = np.array([float(r[1]) for r in rows1])
L_typ = np.array([float(r[2]) for r in rows1])
PV_typ = np.array([float(r[3]) for r in rows1])

def load_cols(path, sheet):
    ws = openpyxl.load_workbook(path, data_only=True)[sheet]
    rows = list(ws.iter_rows(min_row=2, values_only=True))
    return [r[0] for r in rows], np.array([[float(v) for v in r[1:145]] for r in rows])

dates, LD = load_cols(BASE + "/附件/附件2.xlsx", "小区负载")
_, PVD = load_cols(BASE + "/附件/附件2.xlsx", "光伏发电实际功率")
PVh = PVD.reshape(365, 24, 6).mean(2)
Lh  = LD.reshape(365, 24, 6).mean(2)
ws3 = openpyxl.load_workbook(BASE + "/附件/附件3.xlsx", data_only=True)["Sheet1"]
rows3 = list(ws3.iter_rows(min_row=2, values_only=True))
FORE = {}
d_ = -1
for r in rows3:
    if r[0] != '' and r[0] is not None: d_ += 1
    FORE[(d_, int(str(r[1]).split(':')[0]))] = np.array([float(v) for v in r[2:26]])

NDAY = 365
T, dt = 144, 1.0 / 6.0
ETA_C = ETA_D = 0.9
PMAX, SMIN, SMAX = 5000.0, 1200.0, 10800.0
EMULT = 5.0
# 结算: 超额部分按 1.5c 计价(=基础 c + 0.5c 溢价), 违约部分按 0.5c 计价
# LP 目标中 u⁺/u⁻ 的系数均为 0.5c(相对基础价的边际)
ADJ_UP_PRE, ADJ_DN = 0.5, 0.5
LAM_PV, LAM_L = 0.3, 0.4
ADJ_T = [35, 71, 107]
ISSUE_OF = {35: 6, 71: 12, 107: 18}
feb1 = 31
hour_of = np.array([(t + 1) // 6 for t in range(T)])     # 1..24

# ---------- 估计模型 ----------
def pv_hour_est(d, issue, calib):
    """25个整点(1..24)的光伏功率估计"""
    h_est = np.zeros(25)
    f = FORE[(d, issue)]
    for h in range(1, 25):
        k = h - issue
        off = f[k - 1] if 1 <= k <= 24 else 0.0
        if not calib:
            h_est[h] = off; continue
        w1 = PVh[d - 7, h % 24] if d >= 7 else 0.0
        tr = [dd for dd in range(max(7, d - 30), d)]
        if len(tr) >= 5:
            X = np.array([[FORE[(dd, 0)][h - 1], PVh[dd - 7, h % 24]] for dd in tr])
            y = np.array([PVh[dd, h % 24] for dd in tr])
            beta, *_ = np.linalg.lstsq(np.column_stack([np.ones(len(tr)), X]), y, rcond=None)
            est = beta[0] + beta[1] * off + beta[2] * w1
            if not np.isfinite(est): est = 0.5 * off + 0.5 * w1
        else:
            est = 0.5 * off + 0.5 * w1
        h_est[h] = max(est, 0.0)
    return h_est

def to_10min(d, h_est):
    out = np.zeros(T)
    for t in range(T):
        h = hour_of[t] % 24
        denom = PVh[d - 7, h] if d >= 7 else 0.0
        shape = PVD[d - 7, t] / denom if (d >= 7 and denom > 1e-6) else 1.0
        out[t] = h_est[hour_of[t]] * shape
    return out

def load_est(d):
    if d == 0: return L_typ.copy()
    if d >= 7: return LD[d - 7].copy()
    return LD[d - 1].copy()

def load_hour_est(d):
    if d == 0: return L_typ.reshape(24, 6).mean(1)
    if d >= 7: return Lh[d - 7]
    return Lh[d - 1]

# ---------- LP ----------
def lp_plan(Lh10, Ph10, S0):
    """计划LP: min Σc·p·dt, S(144)=S(0)=S0. 返回 p,ch,dis (kW, 144)"""
    n = T; o = 4 * n; m = 5 * n + 1
    A = np.zeros((2 * n + 2, m)); b = np.zeros(2 * n + 2)
    for t in range(n):
        A[t, t] = 1; A[t, 2 * n + t] = 1; A[t, n + t] = -1; A[t, 3 * n + t] = -1
        b[t] = Lh10[t] - Ph10[t]
        A[n + t, o + t + 1] = 1; A[n + t, o + t] = -1
        A[n + t, n + t] = -ETA_C * dt; A[n + t, 2 * n + t] = dt / ETA_D
    A[2 * n, o] = 1; b[2 * n] = S0
    A[2 * n + 1, o + n] = 1; b[2 * n + 1] = S0
    f = np.zeros(m); f[:n] = price * dt
    bnd = [(0, None)] * n + [(0, PMAX)] * 2 * n + [(0, None)] * n + [(SMIN, SMAX)] * (n + 1)
    res = linprog(f, A_eq=A, b_eq=b, bounds=bnd, method="highs")
    assert res.status == 0, "计划LP不可行"
    x = res.x
    return x[:n], x[n:2 * n], x[2 * n:3 * n]

def lp_adjust(a, Lh10, Ph10, S_start, S_end, p_plan_seg, down_only=False, free_terminal=False):
    """调整LP: 区间a..143, min Σ[c·p_adj + 0.5c·(u⁺+u⁻) + 5c·e]·dt
    (u⁺ 边际 0.5c ⇒ 超额总价 1.5c; u⁻ 边际 0.5c ⇒ 违约 0.5c), s(a)=S_start
    e 为安全阀(紧急购电预期, 5c), 保证任何情形下可行;
    down_only=True 时 p_adj ≤ p_plan; free_terminal=True 时末端仅受[SMIN,SMAX]约束"""
    n = T - a; o = 4 * n; m = 5 * n + 1; M = m + 2 * n + n
    iu, ie = m, m + 2 * n                                # u± 与 e 的偏移
    n_eq = 3 * n + (1 if free_terminal else 2)
    A = np.zeros((n_eq, M)); b = np.zeros(n_eq)
    for t in range(n):
        gt = a + t
        A[t, t] = 1; A[t, 2 * n + t] = 1; A[t, ie + t] = 1
        A[t, n + t] = -1; A[t, 3 * n + t] = -1
        b[t] = Lh10[gt] - Ph10[gt]
        A[n + t, o + t + 1] = 1; A[n + t, o + t] = -1
        A[n + t, n + t] = -ETA_C * dt; A[n + t, 2 * n + t] = dt / ETA_D
    A[2 * n, o] = 1; b[2 * n] = S_start
    if not free_terminal:
        A[2 * n + 1, o + n] = 1; b[2 * n + 1] = S_end
    for i in range(n):
        row = 2 * n + (1 if free_terminal else 2) + i
        A[row, i] = 1
        A[row, iu + i] = -1
        A[row, iu + n + i] = 1
        b[row] = p_plan_seg[i]
    f = np.zeros(M)
    f[:n] = price[a:] * dt
    f[iu:iu + n] = ADJ_UP_PRE * price[a:] * dt
    f[iu + n:iu + 2 * n] = ADJ_DN * price[a:] * dt
    f[ie:] = EMULT * price[a:] * dt
    ub_p = p_plan_seg if down_only else [None] * n
    bnd = ([(0, ub_p[i]) for i in range(n)] + [(0, PMAX)] * 2 * n + [(0, None)] * n +
           [(SMIN, SMAX)] * (n + 1) + [(0, None)] * 2 * n + [(0, None)] * n)
    res = linprog(f, A_eq=A, b_eq=b, bounds=bnd, method="highs")
    assert res.status == 0, f"调整LP不可行 a={a}"
    x = res.x
    return x[:n], x[n:2 * n], x[2 * n:3 * n]

def lp_storage_only(a, Lh10, Ph10, S_start, S_end, p_fix):
    """购电计划固定时, 重排余日储能计划: min Σ q(弃光) 使平衡可行"""
    n = T - a; o = 3 * n; m = 4 * n + 1
    A = np.zeros((2 * n + 2, m)); b = np.zeros(2 * n + 2)
    for t in range(n):
        gt = a + t
        A[t, 2 * n + t] = 1; A[t, n + t] = -1; A[t, 3 * n + t] = -1
        b[t] = Lh10[gt] - Ph10[gt] - p_fix[t]
        A[n + t, o + t + 1] = 1; A[n + t, o + t] = -1
        A[n + t, n + t] = -ETA_C * dt; A[n + t, 2 * n + t] = dt / ETA_D
    A[2 * n, o] = 1; b[2 * n] = S_start
    A[2 * n + 1, o + n] = 1; b[2 * n + 1] = S_end
    f = np.zeros(m); f[3 * n:o] = 1.0          # min 弃光
    bnd = [(0, PMAX)] * 2 * n + [(0, None)] * n + [(SMIN, SMAX)] * (n + 1)
    res = linprog(f, A_eq=A, b_eq=b, bounds=bnd, method="highs")
    assert res.status == 0, f"储能重排LP不可行 a={a}"
    x = res.x
    return x[:n], x[n:2 * n]

# ---------- 日内模拟 ----------
def simulate_seg(ps, chs, diss, L, PV, S, a, b):
    """区间[a,b) 模拟, S就地更新, 返回 (紧急功率, 实际充电, 实际放电) 段数组"""
    e = np.zeros(b - a); cr = np.zeros(b - a); dr = np.zeros(b - a)
    for t in range(a, b):
        dis_max = min(PMAX, max(S[t] - SMIN, 0.0) * ETA_D / dt)
        ch_max = min(PMAX, max(SMAX - S[t], 0.0) / ETA_C / dt)
        dis = min(diss[t], dis_max); ch = min(chs[t], ch_max)
        resid = (L[t] - ps[t] - PV[t]) - (dis - ch)
        if resid > 0:
            r = min(ch, resid); ch -= r; resid -= r
            r = min(dis_max - dis, resid); dis += r; resid -= r
            e[t - a] = max(resid, 0.0)
        else:
            sur = -resid
            r = min(dis, sur); dis -= r; sur -= r
            r = min(ch_max - ch, sur); ch += r; sur -= r
        cr[t - a], dr[t - a] = ch, dis
        S[t + 1] = S[t] + ETA_C * ch * dt - dis * dt / ETA_D
    return e, cr, dr

# ---------- 全年滚动 ----------
def run_year(mode, GAMMA=1.02, DELTA=0.98, THETA=0.0):
    """mode: V0 w1光伏无调整 | V1 原始预报 | V2 原始+调整 | V3 标定无调整
             V4 完整调整 | V4T 阈值调整(偏离≤THETA kW不调整) | V4D 仅下调"""
    plans_p = np.zeros((NDAY, T)); adj_p = np.zeros((NDAY, T))
    Emerg = np.zeros((NDAY, T)); ch_r = np.zeros((NDAY, T)); dis_r = np.zeros((NDAY, T))
    Sall = np.zeros((NDAY, T + 1)); plan_cost = np.zeros(NDAY)
    for d in range(NDAY):
        if mode == "V0":
            PVh10 = PVD[d - 7].copy() if d >= 7 else PV_typ.copy()
        elif mode in ("V1", "V2"):
            PVh10 = to_10min(d, pv_hour_est(d, 0, calib=False))
        else:
            PVh10 = to_10min(d, pv_hour_est(d, 0, calib=True))
        Lh10 = load_est(d); Lh_h = load_hour_est(d)
        S0 = 6000.0 if d == 0 else Sall[d - 1, T]
        ps, chs, diss = lp_plan(Lh10 * GAMMA, PVh10 * DELTA, S0)
        plans_p[d] = ps; plan_cost[d] = float((ps * price).sum() * dt)
        p_adj = ps.copy()
        S = Sall[d]; S[0] = S0
        do_adj = mode in ("V2", "V4", "V4F", "V4T", "V4D")
        bounds = [0, ADJ_T[0], ADJ_T[1], ADJ_T[2], T]
        for si in range(4):
            a, b = bounds[si], bounds[si + 1]
            if si > 0 and do_adj:
                issue = ISSUE_OF[a]
                calib = (mode != "V2")
                h_est = pv_hour_est(d, issue, calib).copy()
                # 当日已实现残差(整点级, 相对0:00估计)
                h_end = (a * 10) // 60                     # 已实现的最后整点
                res_pv, npv, res_l = 0.0, 0, 0.0
                est0 = pv_hour_est(d, 0, calib)
                for h in range(1, h_end + 1):
                    hh = h % 24
                    if est0[h] > 50 or (d >= 7 and PVh[d - 7, hh] > 50):
                        res_pv += PVh[d, hh] - est0[h]; npv += 1
                    res_l += Lh[d, hh] - Lh_h[hh]
                if npv > 0: h_est += LAM_PV * res_pv / npv
                h_est = np.maximum(h_est, 0.0)
                PVh10 = to_10min(d, h_est)
                Lh10 = Lh10.copy(); Lh10[a:] += LAM_L * res_l / max(h_end, 1)
                if mode == "V4D":
                    p_new, ch_new, dis_new = lp_adjust(a, Lh10 * GAMMA, PVh10 * DELTA,
                                                       S[a], S0, plans_p[d][a:],
                                                       down_only=True, free_terminal=True)
                elif mode == "V4T":
                    p_lp, _, _ = lp_adjust(a, Lh10 * GAMMA, PVh10 * DELTA,
                                           S[a], S0, plans_p[d][a:])
                    mask = np.abs(p_lp - plans_p[d][a:]) > THETA
                    p_new = np.where(mask, p_lp, plans_p[d][a:])
                    ch_new, dis_new = lp_storage_only(a, Lh10 * GAMMA, PVh10 * DELTA,
                                                      S[a], S0, p_new)
                else:
                    p_new, ch_new, dis_new = lp_adjust(a, Lh10 * GAMMA, PVh10 * DELTA,
                                                       S[a], S0, plans_p[d][a:],
                                                       free_terminal=(mode == "V4F"))
                p_adj[a:], chs[a:], diss[a:] = p_new, ch_new, dis_new
            e, cr, dr = simulate_seg(p_adj, chs, diss, LD[d], PVD[d], S, a, b)
            Emerg[d, a:b] = e; ch_r[d, a:b] = cr; dis_r[d, a:b] = dr
        adj_p[d] = p_adj
    return dict(plans_p=plans_p, adj_p=adj_p, Emerg=Emerg, ch_r=ch_r,
                dis_r=dis_r, Sall=Sall, plan_cost=plan_cost)

def settle(R, sl):
    """费用结算: C = Σ[c·p_adj]dt + Σ[0.5c·u⁻ + 0.5c·u⁺]dt + Σ5c·e·dt
    (等价于 Σ[c·min+0.5c·(plan-adj)⁺+1.5c·(adj-plan)⁺]dt + 紧急)"""
    pp = R["plans_p"][sl]; pa = R["adj_p"][sl]; e = R["Emerg"][sl]
    base = float((pa * price).sum() * dt)
    up = np.maximum(pa - pp, 0.0); dn = np.maximum(pp - pa, 0.0)
    fee_adj = float(((ADJ_UP_PRE * up + ADJ_DN * dn) * price).sum() * dt)
    emerg = float((e * price * EMULT).sum() * dt)
    plan_nominal = float((pp * price).sum() * dt)
    return dict(total=base + fee_adj + emerg, base=base, fee_adj=fee_adj,
                emerg=emerg, plan_nominal=plan_nominal,
                E_emerg=float(e.sum() * dt),
                E_adj_up=float(up.sum() * dt), E_adj_dn=float(dn.sum() * dt))

if __name__ == "__main__":
    rep = slice(feb1, NDAY)
    print(f"{'变体':<26}{'总费用(万)':>12}{'实付(万)':>11}{'调整费(万)':>11}{'紧急费(万)':>11}{'紧急MWh':>9}")
    results = {}
    for mode, name in [("V0", "V0 Q2式(w1光伏无调整)"), ("V1", "V1 原始0:00报无调整"),
                       ("V2", "V2 原始报+原始调整"), ("V3", "V3 标定无调整"),
                       ("V4", "V4 完整策略")]:
        R = run_year(mode)
        s = settle(R, rep)
        results[mode] = (R, s)
        print(f"{name:<26}{s['total']/1e4:>12.1f}{s['base']/1e4:>11.1f}"
              f"{s['fee_adj']/1e4:>11.1f}{s['emerg']/1e4:>11.1f}{s['E_emerg']/1e3:>9.1f}", flush=True)
    np.save(BASE + "/Q3/results_variants.npy", results, allow_pickle=True)
