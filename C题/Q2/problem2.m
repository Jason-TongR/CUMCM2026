%% CUMCM2026 C题 问题2 —— 全年滚动计划购电策略 (最终策略)
% 策略: w1预测(上周同星期实际) + 余量(负载×1.05, 光伏×0.98)
% 日前: 日LP计划(日循环 S(144)=S(0)=S0, S0=前日实际末储电量; 1月1日S0=6000)
% 日内: 计划购电照付不议; 实际偏差储能限额内调节(缺口: 减充电→加放电→紧急购电5倍;
%       富余: 减放电→加充电→弃光)
% 参考解(Python/HiGHS): 总费用 14,546,504 元 = 计划 13,676,311 + 紧急 870,192 元,
%   紧急购电量 145,134 kWh, 紧急天数 102/334。
clear; clc;
thisdir = fileparts(mfilename('fullpath'));

%% ---------------- 1. 读取数据 ----------------
r1 = readmatrix(fullfile(thisdir,'..','附件','附件1.xlsx'), 'Range','B2:D145');
price = r1(:,1);  L_typ = r1(:,2);  PV_typ = r1(:,3);
LD  = readmatrix(fullfile(thisdir,'..','附件','附件2.xlsx'), 'Sheet','小区负载',        'Range','B2:EO366');
PVD = readmatrix(fullfile(thisdir,'..','附件','附件2.xlsx'), 'Sheet','光伏发电实际功率', 'Range','B2:EO366');
NDAY = size(LD,1);  assert(NDAY==365 && size(LD,2)==144, '附件2尺寸异常');
T = 144; dt = 1/6;

%% ---------------- 2. 参数 ----------------
ETA_C = 0.9; ETA_D = 0.9; PMAX = 5000; SMIN = 1200; SMAX = 10800; EMULT = 5;
GAMMA = 1.05; DELTA = 0.98;              % 余量系数(扫描选定)
ip = 1:T; ich = T+1:2*T; idi = 2*T+1:3*T; iq = 3*T+1:4*T; idxs = 4*T+1:5*T+1;
nx = 5*T + 1;
feb1 = 32;                               % 2月1日是第32天

% LP 公共部分
fobj = zeros(nx,1); fobj(ip) = price*dt;
Ii = [1:T, 1:T, 1:T, 1:T, T+(1:T), T+(1:T), T+(1:T), T+(1:T)];
Jj = [ip, idi, ich, iq, idxs(2:T+1), idxs(1:T), ich, idi];
Vv = [ones(1,T), ones(1,T), -ones(1,T), -ones(1,T), ...
      ones(1,T), -ones(1,T), -ETA_C*dt*ones(1,T), (dt/ETA_D)*ones(1,T)];
AeqBase = sparse(Ii, Jj, Vv, 2*T, nx);
lb = zeros(nx,1); ub = inf(nx,1);
ub(ich) = PMAX; ub(idi) = PMAX; lb(idxs) = SMIN; ub(idxs) = SMAX;
opts = optimoptions('linprog','Algorithm','dual-simplex','Display','off');

%% ---------------- 3. 全年滚动 ----------------
plans_p = zeros(NDAY,T); Emerg = zeros(NDAY,T);
ch_r = zeros(NDAY,T); dis_r = zeros(NDAY,T);
Sall = zeros(NDAY,T+1); plan_cost = zeros(NDAY,1);
S0 = 6000;                               % 附录1: 2025-1-1 0:00
for d = 1:NDAY
    % --- w1 预测 ---
    if d == 1,     Lhat = L_typ;      PVhat = PV_typ;
    elseif d >= 8, Lhat = LD(d-7,:)'; PVhat = PVD(d-7,:)';
    else,          Lhat = LD(d-1,:)'; PVhat = PVD(d-1,:)';
    end
    % --- 日前 LP ---
    beq = [Lhat*GAMMA - PVhat*DELTA; zeros(T,1)];
    rS = sparse(1,nx); rS(idxs(1)) = 1;
    rE = sparse(1,nx); rE(idxs(T+1)) = 1;
    Aeq = [AeqBase; rS; rE];  beq = [beq; S0; S0];
    [x, fval, exitflag] = linprog(fobj, [], [], Aeq, beq, lb, ub, opts);
    assert(exitflag==1, '第%d天计划LP未收敛', d);
    ps = x(ip); chs = x(ich); diss = x(idi);
    % --- 日内模拟 ---
    e = zeros(T,1); cr = zeros(T,1); dr = zeros(T,1); S = zeros(T+1,1); S(1) = S0;
    for t = 1:T
        dis_max = min(PMAX, max(S(t)-SMIN,0)*ETA_D/dt);
        ch_max  = min(PMAX, max(SMAX-S(t),0)/ETA_C/dt);
        dis = min(diss(t), dis_max);  ch = min(chs(t), ch_max);
        resid = (LD(d,t) - ps(t) - PVD(d,t)) - (dis - ch);
        if resid > 0
            r = min(ch, resid); ch = ch - r; resid = resid - r;
            r = min(dis_max - dis, resid); dis = dis + r; resid = resid - r;
            e(t) = max(resid, 0);
        else
            sur = -resid;
            r = min(dis, sur); dis = dis - r; sur = sur - r;
            r = min(ch_max - ch, sur); ch = ch + r; sur = sur - r;
        end
        cr(t) = ch; dr(t) = dis;
        S(t+1) = S(t) + ETA_C*ch*dt - dis*dt/ETA_D;
    end
    plans_p(d,:) = ps'; Emerg(d,:) = e'; ch_r(d,:) = cr'; dis_r(d,:) = dr';
    Sall(d,:) = S'; plan_cost(d) = fval;
    S0 = S(T+1);
end

%% ---------------- 4. 全年统计 ----------------
E_p = sum(plans_p(feb1:end,:),'all')*dt;
C_p = sum(plan_cost(feb1:end));
E_e = sum(Emerg(feb1:end,:),'all')*dt;
C_e = sum(Emerg(feb1:end,:).*price'.*EMULT,'all')*dt;
fprintf('===== 问题2 最终策略 =====\n');
fprintf('计划购电量 %.1f kWh, 计划购电费 %.2f 元\n', E_p, C_p);
fprintf('紧急购电量 %.1f kWh, 紧急购电费 %.2f 元\n', E_e, C_e);
fprintf('总费用 %.2f 元, 紧急天数 %d/334\n', C_p+C_e, nnz(sum(Emerg(feb1:end,:),2)>1e-9));
fprintf('储电量范围 [%.1f, %.1f] kWh\n', min(Sall,[],'all'), max(Sall,[],'all'));

%% ---------------- 5. 表3 指定日期 ----------------
blocks = {[144, 1:23], 24:47, 48:71, 72:95, 96:119, 120:143};
bname  = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
rowT1 = [60 72 84 96 108 120];
nameT1 = {'10:00-10:10','12:00-12:10','14:00-14:10','16:00-16:10','18:00-18:10','20:00-20:10'};
dvec = datetime(2025,1,1) + days(0:364)';
target = [datetime(2025,3,20), datetime(2025,6,21), datetime(2025,9,23), datetime(2025,12,21)];
for td = target
    d = find(dvec == td);
    Ep = plans_p(d,:)*dt;
    fprintf('\n--- %s ---\n', datestr(td,'yyyy.mm.dd'));
    fprintf('全天计划购电量 %.2f kWh, 计划购电费 %.2f 元\n', sum(Ep), plan_cost(d));
    for k = 1:6, fprintf('  %s: %.4f\n', nameT1{k}, Ep(rowT1(k))); end
    for k = 1:6
        if k == 1
            ebch = ch_r(d-1,144)*dt + sum(ch_r(d,1:23))*dt;
            ebdis = dis_r(d-1,144)*dt + sum(dis_r(d,1:23))*dt;
        else
            ebch = sum(ch_r(d,blocks{k}))*dt; ebdis = sum(dis_r(d,blocks{k}))*dt;
        end
        fprintf('  %s: 充电 %.4f  放电 %.4f\n', bname{k}, ebch, ebdis);
    end
    s000 = 6000; if d > 1, s000 = Sall(d-1,144); end
    fprintf('  s(0:00)=%.2f, s(24:00)=%.2f\n', s000, Sall(d,144));
    % 紧急窗口
    e = Emerg(d,:); t = 1;
    if all(e<=1e-9), fprintf('  紧急购电: 无\n'); end
    while t <= T
        if e(t) > 1e-9
            j = t; while j<T && e(j+1)>1e-9, j = j+1; end
            fprintf('  紧急购电 %s-%s: %.4f kWh\n', timetag(10*t), timetag(10*(j+1)), sum(e(t:j))*dt);
            t = j+1;
        else, t = t + 1; end
    end
end

%% ---------------- 6. 写 result2.xlsx ----------------
fout = fullfile(thisdir, 'result2.xlsx');
if exist(fout,'file'), delete(fout); end
C1 = cell(335, 147);
C1(1,:) = [{'日期\时间'}, arrayfun(@(i) [timetag(10*i),'-',timetag(10*(i+1))], 1:143, 'UniformOutput',false), ...
           {'0:00-0:10+1','全天购电量','全天购电费'}];
C1{1,43} = '7:0-7:10';         % 保留官方模板第43列的 typo 以逐字一致
for i = 1:334
    d = feb1 - 1 + i;
    Ep = plans_p(d,:)*dt;
    C1{i+1,1} = dvec(d);
    for t = 1:144, C1{i+1,1+t} = round(Ep(t),4); end
    C1{i+1,146} = round(sum(Ep),4);
    C1{i+1,147} = round(plan_cost(d),4);
end
writecell(C1, fout, 'Sheet', '计划购电量');

C2 = cell(1+334*6, 6);
C2(1,:) = {'日期','时间段','充电量','放电量','时刻','储电量'};
for i = 1:334
    d = feb1 - 1 + i;
    s000 = 6000; if d > 1, s000 = Sall(d-1,144); end
    for k = 1:6
        r = (i-1)*6 + k + 1;
        if k == 1, C2{r,1} = dvec(d); end
        C2{r,2} = bname{k};
        if k == 1
            C2{r,3} = round(ch_r(d-1,144)*dt + sum(ch_r(d,1:23))*dt, 4);
            C2{r,4} = round(dis_r(d-1,144)*dt + sum(dis_r(d,1:23))*dt, 4);
        else
            C2{r,3} = round(sum(ch_r(d,blocks{k}))*dt, 4);
            C2{r,4} = round(sum(dis_r(d,blocks{k}))*dt, 4);
        end
        if k == 1, C2{r,5} = '0:00';  C2{r,6} = round(s000,4); end
        if k == 2, C2{r,5} = '24:00'; C2{r,6} = round(Sall(d,144),4); end
    end
end
writecell(C2, fout, 'Sheet', '充放电量');

C3 = cell(100000,3); nrow = 0;
C3(1,:) = {'日期','购电时间段','购电量'}; nrow = 1;
for i = 1:334
    d = feb1 - 1 + i; e = Emerg(d,:); t = 1; first = true;
    while t <= T
        if e(t) > 1e-9
            j = t; while j<T && e(j+1)>1e-9, j = j+1; end
            nrow = nrow + 1;
            if first, C3{nrow,1} = dvec(d); first = false; end
            C3{nrow,2} = [timetag(10*t),'-',timetag(10*(j+1))];
            C3{nrow,3} = round(sum(e(t:j))*dt, 4);
            t = j+1;
        else, t = t + 1; end
    end
end
writecell(C3(1:nrow,:), fout, 'Sheet', '紧急购电量');
fprintf('\n已写出 %s\n', fout);

%% ---------------- 局部函数 ----------------
function s = timetag(m)
if m >= 1440
    s = sprintf('%d:%02d+1', floor((m-1440)/60), mod(m-1440,60));
else
    s = sprintf('%d:%02d', floor(m/60), mod(m,60));
end
end
