%% CUMCM2026 C题 问题1 —— 微网日前计划购电策略 (线性规划, 双情形)
% 约定: 附件1 第 i 行(时刻戳) = 以该时刻为起点的 10 min 区间,
%       与 result1.xlsx 模板"计划购电量"表行序一一对应。
% 变量: x = [p; ch; dis; q; s]
%   p(t)  购电功率 kW, ch(t)/dis(t) 充/放电功率 kW, q(t) 弃光功率 kW
%   s(k)  第 k 段结束时的储电量 kWh, k = 0..144 (共145个)
% 双情形: A: S(0)自由(最优8550, 费用35118.60元); B: S(0)=6000(费用35126.95元)
% 参考解(Python/HiGHS): 两情形购电量均 59482.70 kWh —— 用于交叉验证。
clear; clc; close all;

%% ---------------- 1. 读取数据 ----------------
thisdir = fileparts(mfilename('fullpath'));
fdata = fullfile(thisdir, '..', '附件', '附件1.xlsx');
M  = readmatrix(fdata, 'Range', 'B2:D145');   % 电价/负载/光伏 (跳过时刻列)
c  = M(:,1);      % 电价 元/kWh
L  = M(:,2);      % 小区负载 kW
pv = M(:,3);      % 光伏发电预测功率 kW
T  = numel(c);  assert(T == 144, '数据行数应为144');
dt = 1/6;                            % 10 min = 1/6 h

%% ---------------- 2. 储能参数(附录1) ----------------
eta_c = 0.9;  eta_d = 0.9;           % 充/放电效率
Pmax  = 5000;                        % 最大充放电功率 kW
Smin  = 1200;  Smax = 10800;         % 运行储电量上下限 kWh

%% ---------------- 3. 变量索引 ----------------
ip  = 1:T;            ich = T+1:2*T;
idi = 2*T+1:3*T;      iq  = 3*T+1:4*T;
idxs = 4*T+1:5*T+1;                  % s(0)..s(144)
nx  = 5*T + 1;

%% ---------------- 4. 目标函数: min sum c(t)*p(t)*dt ----------------
fobj = zeros(nx,1);  fobj(ip) = c*dt;

%% ---------------- 5. 等式约束(公共部分) ----------------
% (a) 功率平衡: p(t) + pv(t) + dis(t) = L(t) + ch(t) + q(t)
% (b) 储能动态: s(t+1) = s(t) + eta_c*ch(t)*dt - dis(t)*dt/eta_d
% (c) 周期约束: s(144) = s(0)   (即 0:00 与 24:00 储电量相同)
Ii = [1:T, 1:T, 1:T, 1:T, ...                 % (a)
      T+(1:T), T+(1:T), T+(1:T), T+(1:T), ... % (b)
      2*T+1, 2*T+1];                          % (c)
Jj = [ip, idi, ich, iq, ...
      idxs(2:T+1), idxs(1:T), ich, idi, ...
      idxs(1), idxs(T+1)];
Vv = [ones(1,T), ones(1,T), -ones(1,T), -ones(1,T), ...
      ones(1,T), -ones(1,T), -eta_c*dt*ones(1,T), (dt/eta_d)*ones(1,T), ...
      1, -1];
Aeq0 = sparse(Ii, Jj, Vv, 2*T+1, nx);
beq0 = [L - pv; zeros(T,1); 0];

%% ---------------- 6. 上下界 ----------------
lb = zeros(nx,1);  ub = inf(nx,1);
ub(ich) = Pmax;  ub(idi) = Pmax;
lb(idxs) = Smin; ub(idxs) = Smax;

%% ---------------- 7. 双情形求解 ----------------
% 情形A: S(0) 自由优化 (稳态循环解读)      -> result1.xlsx
% 情形B: S(0)=6000 kWh 固定 (附录1初始值解读) -> result1_fix6000.xlsx
cases = {'A', [],    'result1.xlsx';
         'B', 6000,  'result1_fix6000.xlsx'};
opts = optimoptions('linprog', 'Algorithm', 'dual-simplex', 'Display', 'off');

for ic = 1:size(cases,1)
    tag   = cases{ic,1};
    s0fix = cases{ic,2};
    fout  = fullfile(thisdir, cases{ic,3});

    Aeq = Aeq0;  beq = beq0;
    if ~isempty(s0fix)                      % (d) 固定 S(0)=s0fix
        r = sparse(1, nx);  r(idxs(1)) = 1;
        Aeq = [Aeq; r];  beq = [beq; s0fix];
    end

    [x, fval, exitflag] = linprog(fobj, [], [], Aeq, beq, lb, ub, opts);
    assert(exitflag == 1, 'linprog 未收敛, exitflag = %d', exitflag);
    fprintf('\n===== 情形 %s =====\n最优购电费用 = %.4f 元\n', tag, fval);

    %% 后处理
    p = x(ip); ch = x(ich); dis = x(idi); q = x(iq); s = x(idxs);
    Ep = p*dt; Ech = ch*dt; Edis = dis*dt; Eq = q*dt;      % kWh
    tol = 1e-6;
    Ep(abs(Ep)<tol)=0; Ech(abs(Ech)<tol)=0; Edis(abs(Edis)<tol)=0; Eq(abs(Eq)<tol)=0;

    % --- 表1: 指定时段购电量 (时刻起点=数据行号: 10:00->60, 12:00->72, ...) ---
    rowT1 = [60 72 84 96 108 120];
    nameT1 = {'10:00-10:10','12:00-12:10','14:00-14:10', ...
              '16:00-16:10','18:00-18:10','20:00-20:10'};
    fprintf('--- 表1 购电量 ---\n');
    for k = 1:6
        fprintf('%s: %.4f kWh\n', nameT1{k}, Ep(rowT1(k)));
    end
    fprintf('全天购电量: %.4f kWh\n', sum(Ep));

    % --- 表2: 4h 分段充放电量 (行144=0:00+1-0:10+1即时钟0:00-0:10, 归入 0:00-4:00) ---
    blocks = {[144, 1:23], 24:47, 48:71, 72:95, 96:119, 120:143};
    bname  = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
    Ebch = zeros(6,1); Ebdis = zeros(6,1);
    fprintf('--- 表2 充放电量 ---\n');
    for k = 1:6
        Ebch(k) = sum(Ech(blocks{k})); Ebdis(k) = sum(Edis(blocks{k}));
        fprintf('%s: 充电 %9.4f kWh   放电 %9.4f kWh\n', bname{k}, Ebch(k), Ebdis(k));
    end
    s000 = s(144);  s2400 = s(144);      % 时钟0:00/24:00 在第143、144行之间
    fprintf('0:00 储电量: %.4f kWh    24:00 储电量: %.4f kWh\n', s000, s2400);
    fprintf('弃光总量: %.4f kWh, 储电量范围 [%.2f, %.2f] kWh\n', sum(Eq), min(s), max(s));
    fprintf('功率平衡最大残差: %.2e kW (应~0)\n', max(abs(p + pv + dis - L - ch - q)));

    %% 写结果文件 (按模板版式重建)
    C1 = cell(145,2);
    C1(1,:) = {'时间段','购电量'};
    for i = 1:T
        C1{i+1,1} = [timetag(10*i), '-', timetag(10*(i+1))];
        C1{i+1,2} = round(Ep(i), 4);
    end
    C2 = cell(7,5);
    C2(1,:) = {'时间段','充电量','放电量','时刻','储电量'};
    for k = 1:6
        C2{k+1,1} = bname{k};
        C2{k+1,2} = round(Ebch(k), 4);
        C2{k+1,3} = round(Ebdis(k), 4);
    end
    C2{2,4} = '0:00';  C2{2,5} = round(s000, 4);
    C2{3,4} = '24:00'; C2{3,5} = round(s2400, 4);
    if exist(fout,'file'), delete(fout); end
    writecell(C1, fout, 'Sheet', '计划购电量');
    writecell(C2, fout, 'Sheet', '充放电量');
    fprintf('已写出 %s\n', fout);

    if ic == 1   % 保存情形A轨迹用于绘图
        pA = p; chA = ch; disA = dis; sA = s;
    end
end

%% ---------------- 10. 绘图(情形A, 论文用图) ----------------
tt = (1:T)/6;                                   % 小时(近似)
figure('Position',[100 100 900 720]);
subplot(4,1,1); stairs(tt,c); ylabel('电价(元/kWh)'); grid on; title('电价曲线');
subplot(4,1,2); stairs(tt,pA); hold on; stairs(tt,L); ylabel('功率(kW)');
legend('购电功率','小区负载'); grid on; title('购电功率与负载');
subplot(4,1,3); bar(tt,[chA,-disA],1,'stacked'); ylabel('功率(kW)');
legend('充电','放电(取负)'); grid on; title('储能充放电功率');
subplot(4,1,4); stairs(0:T, sA); ylabel('储电量(kWh)'); xlabel('时间(10min格)');
hold on; yline(Smin,'--'); yline(Smax,'--'); grid on; title('储电量变化(情形A)');
saveas(gcf, fullfile(thisdir, 'q1_fig.png'));

%% ---------------- 局部函数 ----------------
function s = timetag(m)          % 分钟数 -> 'H:MM' 或 'H:MM+1'
if m >= 1440
    s = sprintf('%d:%02d+1', floor((m-1440)/60), mod(m-1440,60));
else
    s = sprintf('%d:%02d', floor(m/60), mod(m,60));
end
end
