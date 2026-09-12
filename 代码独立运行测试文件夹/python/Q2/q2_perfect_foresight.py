#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Q2 完美预测费用下界 (图2"完美预测"柱的生成脚本)
口径: 与最终策略同框架(含储能, 计划LP日循环 S(144)=S(0)=S0 逐日继承),
      但预测=当天实际值(完美预测), 故无紧急购电。为费用理论下界。
"""
import importlib.util
from pathlib import Path
import numpy as np

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("q2", BASE / "Q2" / "solve_q2.py")
q2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q2)

C = 0.0
S0 = 6000.0
for d in range(q2.feb1, q2.NDAY):
    # 预测=当天实际(完美), 余量 γ=δ=1(无需余量), 日循环 S(144)=S(0)=S0
    g, dd = q2.GAMMA, q2.DELTA
    q2.GAMMA, q2.DELTA = 1.0, 1.0
    _, _, _, pc = q2.plan_lp(q2.LD[d], q2.PVD[d], S0)
    q2.GAMMA, q2.DELTA = g, dd
    C += pc

print(f"完美预测费用下界(2025.2.1-12.31, 含储能, 无紧急购电): {C:,.2f} 元")
# 参考: 最终策略 14,546,503.97 元 -> 预测误差残余代价 = C_final - C
