# C题代码独立运行测试说明

本目录包含 MATLAB 和 Python 两套可独立运行的测试代码。两套代码使用相同的输入附件，分别用于复现问题 1 至问题 4 的计算结果。

## 一、目录结构

```text
代码独立运行测试文件夹/
├─ matlab/
│  ├─ Q1/Q1matlab代码测试/problem1.m
│  ├─ Q2/Q2matlab代码测试/problem2.m
│  ├─ Q3/Q3matlab代码测试/problem3.m
│  └─ Q4/Q4matlab代码测试/problem4.m
└─ python/
   ├─ Q1/solve_q1_two_cases.py
   ├─ Q2/solve_q2.py
   ├─ Q3/finalize_q3.py
   ├─ Q4/solve_q4.py
   └─ 附件/
```

各语言目录中的 `附件` 文件夹应与 `Q1`、`Q2`、`Q3`、`Q4` 文件夹保持同级，不能移动或重命名。代码使用脚本自身位置定位输入文件，一般不受启动工作目录影响；为便于测试，建议按照下面的方式运行。

## 二、MATLAB 代码测试

### 1. 环境要求

- MATLAB，建议使用 R2019b 或更高版本。
- 需要 **Optimization Toolbox**，因为代码使用 `linprog` 求解线性规划问题。
- 不需要 Python 环境。

### 2. 运行方法

在 MATLAB 的 Current Folder（当前文件夹）中打开本目录下相应的 `.m` 文件，点击 **Run**；

### 3. 输出结果

程序会在命令窗口打印计算过程、费用、购电量、储能范围等信息，并在相应题目的 MATLAB 测试目录中生成结果 Excel 文件：

- Q1：两种初始储电量情形的结果文件。
- Q2：问题 2 的全年滚动优化结果。
- Q3：问题 3 的最终策略结果。
- Q4：`result4-2.xlsx` 和 `result4-3.xlsx`。

## 三、Python 代码测试

### 1. 环境要求

- Python 3.9 或更高版本，建议使用 Python 3.10 及以上版本。
- 需要安装以下第三方包：
  - `numpy`
  - `openpyxl`
  - `scipy`

Python 代码使用 `scipy.optimize.linprog` 求解线性规划，不需要安装 MATLAB、Gurobi、CPLEX 或其他商业建模软件。

### 2. 安装依赖

在本目录的 `python` 文件夹中打开 PowerShell 或命令提示符，执行：

```powershell
cd "代码独立运行测试文件夹\python"
python -m pip install numpy openpyxl scipy
```


### 3. 运行各题代码

仍在 `代码独立运行测试文件夹/python` 目录下执行：

```powershell
python Q1\solve_q1_two_cases.py
python Q2\solve_q2.py
python Q3\finalize_q3.py
python Q4\solve_q4.py
```

其中：

- `Q1\solve_q1_two_cases.py`：计算问题 1 的两种初始储电量情形。
- `Q2\solve_q2.py`：计算问题 2 的全年滚动策略。
- `Q3\finalize_q3.py`：计算问题 3 的最终策略，并调用同目录下的 `solve_q3.py`。
- `Q4\solve_q4.py`：计算问题 4，并调用 `Q2\solve_q2.py` 和 `Q3\solve_q3.py` 的相关内容，因此必须保留完整目录结构。

程序会在对应的 Python 题目目录中生成 Excel、JSON 或 NPZ 结果文件，并在终端打印主要计算结果。

## 四、测试注意事项

1. 请勿只复制单个 `.m` 或 `.py` 文件运行，输入附件和相关题目脚本也必须一并保留。
2. 请勿修改 `附件1.xlsx` 至 `附件5` 的文件名、工作表名称和目录位置。
3. Python 和 MATLAB 应使用同一套输入附件，便于交叉验证结果。
4. 如果 MATLAB 报告 `linprog` 或 `optimoptions` 未定义，说明当前 MATLAB 未安装或未启用 Optimization Toolbox。
5. 如果 Python 报告 `ModuleNotFoundError`，请先按照上面的命令安装缺少的第三方包。
