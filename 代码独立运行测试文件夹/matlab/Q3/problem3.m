%% CUMCM2026 C题 问题3 —— 计划+滚动调整购电策略 (最终策略 V4FR: V4F+末端备用>=4000)
% 标定光伏(逐时OLS[官方报,w1],30天滚动) + 双向调整(超额1.5倍总价/违约0.5倍) + 日内储能调节 + 紧急5倍
% 参考解(Python/HiGHS): 总费用 13,771,900 元级 (V4FR, 精确值见 summary3.json)
%   调整: 上调 638,431 kWh / 下调 457,921 kWh; 紧急购电量 91,359 kWh, 紧急天数 222/334
clear; clc;
thisdir = fileparts(mfilename('fullpath'));

%% ---------------- 1. 读取数据 ----------------
r1 = readmatrix(fullfile(thisdir,'..','附件','附件1.xlsx'), 'Range','B2:D145');
price = r1(:,1); L_typ = r1(:,2); PV_typ = r1(:,3);
LD  = readmatrix(fullfile(thisdir,'..','附件','附件2.xlsx'), 'Sheet','小区负载',        'Range','B2:EO366');
PVD = readmatrix(fullfile(thisdir,'..','附件','附件2.xlsx'), 'Sheet','光伏发电实际功率', 'Range','B2:EO366');
raw3 = readcell(fullfile(thisdir,'..','附件','附件3.xlsx'), 'Range','A2:Z1461');
NDAY = 365; T = 144; dt = 1/6;
PVh = reshape(PVD', 6, 24, 365); PVh = squeeze(mean(PVh,1))';   % 365×24 整点实际
Lh  = reshape(LD',  6, 24, 365); Lh  = squeeze(mean(Lh,1))';
FORE = zeros(365, 24, 4);                        % (天, 预报k小时, 发布: 0/6/12/18)
d = 0;
for i = 1:size(raw3,1)
    cc = raw3{i,1};
    nonempty = ~(isempty(cc) || (ischar(cc) && isempty(strtrim(cc))) || ...
                 (isstring(cc) && ismissing(cc)) || (isnumeric(cc) && isnan(cc)));
    if nonempty, d = d + 1; end
    issue = sscanf(char(raw3{i,2}), '%d:%*s');   % char() 兼容 string/char 两种读取类型
    ii = find(issue == [0 6 12 18]);
    FORE(d, :, ii) = cellfun(@double, raw3(i, 3:26));
end

%% ---------------- 2. 参数 ----------------
ETA_C = 0.9; ETA_D = 0.9; PMAX = 5000; SMIN = 1200; SMAX = 10800;
EMULT = 5; ADJ_PRE = 0.5;                        % 上/下调相对基础价的边际费率(超额总价1.5c/违约0.5c)
GAMMA = 1.02; DELTA = 0.98; LAM_PV = 0.1; LAM_L = 0.3;   % 费用网格寻优
ADJ_T = [36 72 108];                             % 调整起始区间(1基): 6:00/12:00/18:00
ISSUE = [6 12 18];
feb1 = 32;
opts = optimoptions('linprog','Algorithm','dual-simplex','Display','off');

%% ---------------- 3. 全年滚动 ----------------
plans_p = zeros(NDAY,T); adj_p = zeros(NDAY,T);
Emerg = zeros(NDAY,T); ch_r = zeros(NDAY,T); dis_r = zeros(NDAY,T);
Sall = zeros(NDAY,T+1); plan_cost = zeros(NDAY,1);
for d = 1:NDAY
    % --- 0:00 估计 ---
    h_est = pv_hour_est_issue(d, 0, FORE, PVh, NDAY);    % 0:00发布
    PVh10 = to_10min(d, h_est, PVD, PVh, T);
    Lh10 = load_est(d, LD, L_typ);
    Lh_h = load_hour_est(d, Lh, L_typ);
    if d == 1, S0 = 6000; else, S0 = Sall(d-1, T+1); end
    [ps, chs, diss] = lp_plan(Lh10*GAMMA, PVh10*DELTA, S0, price, ETA_C, ETA_D, PMAX, SMIN, SMAX, T, opts);
    plans_p(d,:) = ps'; plan_cost(d) = sum(ps.*price)*dt;
    p_adj = ps; S = zeros(T+1,1); S(1) = S0;
    bounds = [1 ADJ_T T+1];
    for si = 1:4
        a = bounds(si); b = bounds(si+1) - 1;
        if si > 1
            % --- 调整时刻 a: 最新预报标定 + 当日残差更新 ---
            h_est2 = pv_hour_est_issue(d, ISSUE(si-1), FORE, PVh, NDAY);
            h_end = floor((a-1)*10/60);                  % 已实现的时钟小时(1..h_end)
            res_pv = 0; npv = 0; res_l = 0;
            for h = 1:h_end
                col = h + 1;                             % PVh/Lh 列 = 时钟小时+1
                if h_est(h+1) > 50 || (d >= 8 && PVh(d-7,col) > 50)
                    res_pv = res_pv + PVh(d,col) - h_est(h+1); npv = npv + 1;
                end
                res_l = res_l + Lh(d,col) - Lh_h(col);
            end
            if npv > 0, h_est2 = h_est2 + LAM_PV * res_pv / npv; end
            h_est2 = max(h_est2, 0);
            PVh10 = to_10min(d, h_est2, PVD, PVh, T);
            Lh10(a:T) = Lh10(a:T) + LAM_L * res_l / max(h_end,1);
            [p_new, ch_new, dis_new] = lp_adjust(a, Lh10*GAMMA, PVh10*DELTA, S(a), ...
                plans_p(d,a:T)', price, ETA_C, ETA_D, PMAX, SMIN, SMAX, T, ADJ_PRE, EMULT, opts);
            p_adj(a:T) = p_new; chs(a:T) = ch_new; diss(a:T) = dis_new;
        end
        [e, cr, dr, S] = simulate_seg(p_adj, chs, diss, LD(d,:)', PVD(d,:)', S, a, b, ETA_C, ETA_D, PMAX, SMIN, SMAX, T);
        Emerg(d,a:b) = e'; ch_r(d,a:b) = cr'; dis_r(d,a:b) = dr';
    end
    adj_p(d,:) = p_adj';
    Sall(d,:) = S';
end

%% ---------------- 4. 年度统计 ----------------
up = max(adj_p - plans_p, 0); dn = max(plans_p - adj_p, 0);
sl = feb1:NDAY;
base = sum(adj_p(sl,:).*price','all')*dt;
fee_adj = sum((ADJ_PRE*up(sl,:) + ADJ_PRE*dn(sl,:)).*price','all')*dt;
C_e = sum(Emerg(sl,:).*price'.*EMULT,'all')*dt;
fprintf('===== 问题3 最终策略 V4FR =====\n');
fprintf('计划购电费(0:00口径) %.2f 元\n', sum(plan_cost(sl)));
fprintf('按调整量实付 %.2f 元, 违约/溢价费 %.2f 元\n', base, fee_adj);
fprintf('紧急购电费 %.2f 元, 紧急购电量 %.1f kWh\n', C_e, sum(Emerg(sl,:),'all')*dt);
fprintf('调整下调电量 %.1f kWh, 上调电量 %.1f kWh\n', sum(dn(sl,:),'all')*dt, sum(up(sl,:),'all')*dt);
fprintf('总费用 %.2f 元, 紧急天数 %d/334\n', base+fee_adj+C_e, nnz(sum(Emerg(sl,:),2)>1e-9));
fprintf('储电量范围 [%.1f, %.1f]\n', min(Sall,[],'all'), max(Sall,[],'all'));

%% ---------------- 5. 表3 指定日期 ----------------
blocks = {[144, 1:23], 24:47, 48:71, 72:95, 96:119, 120:143};
bname  = {'0:00-4:00','4:00-8:00','8:00-12:00','12:00-16:00','16:00-20:00','20:00-24:00'};
rowT1 = [60 72 84 96 108 120];
nameT1 = {'10:00-10:10','12:00-12:10','14:00-14:10','16:00-16:10','18:00-18:10','20:00-20:10'};
dvec = datetime(2025,1,1) + days(0:364)';
target = [datetime(2025,3,20), datetime(2025,6,21), datetime(2025,9,23), datetime(2025,12,21)];
for td = target
    d = find(dvec == td);
    Ea = adj_p(d,:)*dt; Ep = plans_p(d,:)*dt;
    fprintf('\n--- %s ---\n', datestr(td,'yyyy.mm.dd'));
    fprintf('计划购电量 %.2f -> 调整购电量 %.2f kWh, 计划购电费 %.2f 元\n', sum(Ep), sum(Ea), plan_cost(d));
    for k = 1:6, fprintf('  %s: %.4f\n', nameT1{k}, Ea(rowT1(k))); end
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

%% ---------------- 6. 写 result3.xlsx ----------------
fout = fullfile(thisdir, 'result3.xlsx');
if exist(fout,'file'), delete(fout); end
hdr = [{'日期\时间'}, arrayfun(@(i) [timetag(10*i),'-',timetag(10*(i+1))], 1:143, 'UniformOutput',false), ...
       {'0:00-0:10+1','全天购电量','全天购电费'}];
hdr{43} = '7:0-7:10';                            % 保留官方模板 typo
for sheet = 1:2
    if sheet == 1, PP = plans_p; else, PP = adj_p; end
    C1 = cell(335, 147); C1(1,:) = hdr;
    for i = 1:334
        d = feb1 - 1 + i;
        Ep = PP(d,:)*dt;
        C1{i+1,1} = dvec(d);
        for t = 1:T, C1{i+1,1+t} = round(Ep(t),4); end
        C1{i+1,146} = round(sum(Ep),4);
        if sheet == 1, C1{i+1,147} = round(plan_cost(d),4);
        else, C1{i+1,147} = round(sum(PP(d,:).*price')*dt,4); end
    end
    if sheet == 1, writecell(C1, fout, 'Sheet', '计划购电量');
    else, writecell(C1, fout, 'Sheet', '调整购电量'); end
end
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
C3 = cell(100000,3); nrow = 1;
C3(1,:) = {'日期','购电时间段','购电量'};
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

%% ================= 局部函数 =================
function s = timetag(m)
if m >= 1440, s = sprintf('%d:%02d+1', floor((m-1440)/60), mod(m-1440,60));
else, s = sprintf('%d:%02d', floor(m/60), mod(m,60)); end
end

function h_est = pv_hour_est_issue(d, issue, FORE, PVh, NDAY)
% 逐时OLS[官方issue时刻报, w1上周同星期] (30天滚动训练, 用0:00报训练)
% h_est(j): j=h+1 对应预报小时 h (h=1..24, 时钟 mod(h,24)); PVh 列 = 时钟小时+1
ii = find(issue == [0 6 12 18]);
h_est = zeros(25,1);
for h = 1:24
    k = h - issue;
    if k >= 1 && k <= 24, off = FORE(d, k, ii); else, off = 0; end
    col = mod(h,24) + 1;                               % 时钟 mod(h,24) 的 PVh 列
    if d >= 8, w1 = PVh(d-7, col); else, w1 = 0; end
    tr = max(8, d-30):d-1;
    if numel(tr) >= 5
        X = zeros(numel(tr),2); y = zeros(numel(tr),1);
        for j = 1:numel(tr)
            dd = tr(j);
            X(j,:) = [FORE(dd, h, 1), PVh(dd-7, col)];
            y(j) = PVh(dd, col);
        end
        beta = [ones(numel(tr),1), X] \ y;
        est = beta(1) + beta(2)*off + beta(3)*w1;
        if ~isfinite(est), est = 0.5*off + 0.5*w1; end
    else
        est = 0.5*off + 0.5*w1;
    end
    h_est(h+1) = max(est, 0);
end
end

function out = to_10min(d, h_est, PVD, PVh, T)
% 整点估计 → 144区间功率; 区间t的预报小时 FH=floor(t/6)(0..24), PVh列=mod(FH,24)+1
out = zeros(T,1);
for t = 1:T
    FH = floor(t/6);
    col = mod(FH,24) + 1;
    if d >= 8 && PVh(d-7,col) > 1e-6, shape = PVD(d-7,t)/PVh(d-7,col); else, shape = 1; end
    out(t) = h_est(FH+1) * shape;
end
end

function L = load_est(d, LD, L_typ)
if d == 1, L = L_typ; elseif d >= 8, L = LD(d-7,:)'; else, L = LD(d-1,:)'; end
end

function Lh_h = load_hour_est(d, Lh, L_typ)
if d == 1, Lh_h = mean(reshape(L_typ,6,24),1)'; elseif d >= 8, Lh_h = Lh(d-7,:)'; else, Lh_h = Lh(d-1,:)'; end
end

function [p, ch, dis] = lp_plan(Lh10, Ph10, S0, price, ETA_C, ETA_D, PMAX, SMIN, SMAX, T, opts)
n = T; o = 4*n; m = 5*n+1; dt = 1/6;
ip = 1:n; ich = n+1:2*n; idi = 2*n+1:3*n; iq = 3*n+1:4*n; is = o+1:m;
Ii = [1:n, 1:n, 1:n, 1:n, n+(1:n), n+(1:n), n+(1:n), n+(1:n), 2*n+1, 2*n+2];
Jj = [ip, idi, ich, iq, is(2:n+1), is(1:n), ich, idi, is(1), is(n+1)];
Vv = [ones(1,n), ones(1,n), -ones(1,n), -ones(1,n), ones(1,n), -ones(1,n), ...
      -ETA_C*dt*ones(1,n), (dt/ETA_D)*ones(1,n), 1, 1];
Aeq = sparse(Ii, Jj, Vv, 2*n+2, m);
beq = [Lh10 - Ph10; zeros(n,1); S0; S0];
f = zeros(m,1); f(ip) = price*dt;
lb = zeros(m,1); ub = inf(m,1);
ub(ich) = PMAX; ub(idi) = PMAX; lb(is) = SMIN; ub(is) = SMAX;
[x, ~, exitflag] = linprog(f, [], [], Aeq, beq, lb, ub, opts);
assert(exitflag==1, '计划LP不可行');
p = x(ip); ch = x(ich); dis = x(idi);
end

function [p, ch, dis] = lp_adjust(a, Lh10, Ph10, S_start, p_plan_seg, price, ...
                                  ETA_C, ETA_D, PMAX, SMIN, SMAX, T, ADJ_PRE, EMULT, opts)
% 双向调整, 末端自由, 带5c安全阀; u±边际费率均为 ADJ_PRE=0.5c
n = T - a + 1; o = 4*n; m = 5*n+1; M = m + 3*n; dt = 1/6;
iu1 = m+1:m+n; iu2 = m+n+1:m+2*n; ie = m+2*n+1:M;   % u+ / u- / e 三块索引
ip = 1:n; ich = n+1:2*n; idi = 2*n+1:3*n; iq = 3*n+1:4*n; is = o+1:m;
nrow = 3*n + 1;
Ii = [1:n, 1:n, 1:n, 1:n, 1:n, n+(1:n), n+(1:n), n+(1:n), n+(1:n), 2*n+1];
Jj = [ip, idi, ie, ich, iq, is(2:n+1), is(1:n), ich, idi, is(1)];
Vv = [ones(1,n), ones(1,n), ones(1,n), -ones(1,n), -ones(1,n), ones(1,n), -ones(1,n), ...
      -ETA_C*dt*ones(1,n), (dt/ETA_D)*ones(1,n), 1];
rows_u = 2*n+1 + (1:n);
Ii = [Ii, rows_u, rows_u, rows_u];
Jj = [Jj, ip, iu1, iu2];
Vv = [Vv, ones(1,n), -ones(1,n), ones(1,n)];
Aeq = sparse(Ii, Jj, Vv, nrow, M);
beq = [Lh10(a:T) - Ph10(a:T); zeros(n,1); S_start; p_plan_seg];
f = zeros(M,1);
f(ip) = price(a:T)*dt; f(iu1) = ADJ_PRE*price(a:T)*dt; f(iu2) = ADJ_PRE*price(a:T)*dt; f(ie) = EMULT*price(a:T)*dt;
lb = zeros(M,1); ub = inf(M,1);
ub(ich) = PMAX; ub(idi) = PMAX; lb(is) = SMIN; ub(is) = SMAX;
Aub = sparse(1, M); Aub(1, is(n+1)) = -1; bub = -4000;   % 末端最低备用 S(24:00)>=4000
[x, ~, exitflag] = linprog(f, Aub, bub, Aeq, beq, lb, ub, opts);
assert(exitflag==1, '调整LP不可行 a=%d', a);
p = x(ip); ch = x(ich); dis = x(idi);
end

function [e, cr, dr, S] = simulate_seg(ps, chs, diss, L, PV, S, a, b, ETA_C, ETA_D, PMAX, SMIN, SMAX, T)
dt = 1/6;
e = zeros(b-a+1,1); cr = zeros(b-a+1,1); dr = zeros(b-a+1,1);
for t = a:b
    dis_max = min(PMAX, max(S(t)-SMIN,0)*ETA_D/dt);
    ch_max  = min(PMAX, max(SMAX-S(t),0)/ETA_C/dt);
    dis = min(diss(t), dis_max); ch = min(chs(t), ch_max);
    resid = (L(t) - ps(t) - PV(t)) - (dis - ch);
    if resid > 0
        r = min(ch, resid); ch = ch - r; resid = resid - r;
        r = min(dis_max - dis, resid); dis = dis + r; resid = resid - r;
        e(t-a+1) = max(resid, 0);
    else
        sur = -resid;
        r = min(dis, sur); dis = dis - r; sur = sur - r;
        r = min(ch_max - ch, sur); ch = ch + r; sur = sur - r;
    end
    cr(t-a+1) = ch; dr(t-a+1) = dis;
    S(t+1) = S(t) + ETA_C*ch*dt - dis*dt/ETA_D;
end
end
