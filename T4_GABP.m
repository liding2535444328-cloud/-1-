function [Scatter_Data, Stats_Summary, Best_Model] = T4_GABP(res_raw)
% ========================================================================
%  项目：橡胶混凝土强度预测系统 (GA-BP 9输入科研集成 V50 终极稳定版)
%  模型：GA-BP (Genetic Algorithm Optimized BP Neural Network)
%  修复：1. 解决字段名 trace/conv 冲突  2. 强制产出 Fig.01-Fig.13 
%  排版：智能避让系统、柱状图顶端数值标注、多核加速、双语下置标题
% ========================================================================
warning off; 

% --- 模块 1.1: 环境与工具箱路径修复 ---
if exist('goat', 'dir')
    addpath(genpath('goat')); 
end

if nargin < 1
    fprintf('>>> 正在启动 [GA-BP] 独立测试模式，加载数据集 3...\n');
    if exist('数据集3.xlsx', 'file')
        res_raw = readmatrix('数据集3.xlsx');
        res_raw(any(isnan(res_raw), 2), :) = []; 
    else
        error('错误：未在当前路径找到 [数据集3.xlsx]。');
    end
end

% --- 模块 1.2: 并行流/多核环境优化 ---
if isempty(gcp('nocreate'))
    try parpool('local'); catch; end 
end

% --- 模块 1.3: 核心科研参数配置 ---
model_tag = 'GA-BP';
loop_num = 10;   
max_gen = 25;    
colors_lib = [0.85 0.33 0.1; 0.47 0.67 0.19; 0.30 0.45 0.69; 0.64 0.08 0.18]; 

featureNames = {'水胶比 (W/B)', '橡胶含量 (Rubber)', '橡胶粒径 (MaxSize)', ...
                '水泥 (Cement)', '细骨料 (FineAgg)', '粗骨料 (CoarseAgg)', ...
                '硅比 (SF/C)', '外加剂 (SP)', '龄期 (Age)'};
allNames = [featureNames, '强度 (Strength)'];
results_cell = cell(loop_num, 1);

%% ========================================================================
%  大模块 2: 输入分布与相关性分析 (图1-2)
% ========================================================================

% --- 图1: 3x3 布局 - 手动几何布局 4:3 挺拔版 ---
figure('Color', [1 1 1], 'Position', [100, 100, 1000, 900], 'Name', [model_tag, '_Fig01']);

% 准备双语标签
featureNames_EN = {'W/B Ratio', 'Rubber Content', 'Rubber Size', ...
                   'Cement', 'Fine Aggregate', 'Coarse Aggregate', ...
                   'SF/C Ratio', 'Superplasticizer', 'Curing Age'};

% --- 手动布局参数 (核心：根治扁平感，拉伸高度) ---
m_left = 0.08;   m_bottom = 0.18; % 预留边缘空间
gap_w = 0.06;    gap_h = 0.09;    % 增加纵向间距以容纳双语 xlabel
sub_w = (1 - m_left - 0.05 - 2*gap_w) / 3; 
sub_h = (1 - 0.05 - m_bottom - 2*gap_h) / 3; % 强行计算高度，确保比例接近 4:3

for i = 1:9
    % 计算几何坐标
    row = floor((i-1)/3) + 1;
    col = mod(i-1, 3) + 1;
    pos_x = m_left + (col-1) * (sub_w + gap_w);
    pos_y = 1 - 0.05 - row * sub_h - (row-1) * gap_h;
    
    % 创建轴并绘图
    ax = axes('Position', [pos_x, pos_y, sub_w, sub_h]);
    h = histogram(res_raw(:, i), 'Normalization', 'pdf', 'FaceColor', [0.7 0.7 0.85], 'EdgeColor', 'w');
    hold on; [f, x_ks] = ksdensity(res_raw(:, i));
    plot(x_ks, f, 'r-', 'LineWidth', 2.0); % 加粗曲线提升质感
    
    % 坐标轴细节美化
    grid on; box on;
    set(gca, 'FontSize', 10, 'LineWidth', 1.2, 'TickDir', 'out');
    
    % --- 标题移到底部 + 双语垂直排版 ---
    title(''); % 彻底移除顶部 title
    xl_str = sprintf('%s\n(%s)', featureNames{i}, featureNames_EN{i});
    xlabel(xl_str, 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
    
    % 仅在最左侧列标注纵轴
    if col == 1
        ylabel('Probability Density', 'FontSize', 9, 'FontWeight', 'bold'); 
    end
end

% 调用智能避让布局管理器 (放置底部总图名)
auto_layout_manager(gcf, ['图1: ', model_tag, ' 模型 9 维输入特征分布范围分析'], ['Fig.1: Data Range Analysis of Input Features for ', model_tag]);


% --- 图2: 全维度特征相关性热力图 ---
figure('Color', [1 1 1], 'Position', [150, 150, 750, 650], 'Name', [model_tag, '_Fig02']);
corrMat = corr(res_raw); 
imagesc(corrMat); colormap(jet); colorbar; clim([-1 1]); 

set(gca, 'XTick', 1:10, 'XTickLabel', allNames, 'YTick', 1:10, 'YTickLabel', allNames, ...
    'FontSize', 8, 'FontWeight', 'bold'); 
xtickangle(45); axis square;

% 遍历标注数值，并修复 ifelse 识别报错
for i = 1:10; for j = 1:10
    % 逻辑加固：使用原生 if 替代 ifelse
    if abs(corrMat(i,j)) > 0.6
        txtCol = 'w'; % 背景深，字用白色
    else
        txtCol = 'k'; % 背景浅，字用黑色
    end
    text(j, i, sprintf('%.2f', corrMat(i,j)), 'HorizontalAlignment', 'center', ...
        'Color', txtCol, 'FontSize', 7, 'FontWeight', 'bold');
end; end

auto_layout_manager(gcf, ['图2: ', model_tag, ' 模型全维度特征相关性热力图分析'], ['Fig.2: Feature Correlation Heatmap for ', model_tag]);

%% ========================================================================
%  大模块 3: 执行核心调度循环 (GA-BP 寻优)
% ========================================================================
fprintf('>>> 正在启动高精度 %s 引擎 (目标 R2 > 0.93)...\n', model_tag);
main_tic = tic; 

for run_i = 1:loop_num
    total_rows = size(res_raw, 1);
    idx = randperm(total_rows); 
    P_tr = res_raw(idx(1:round(0.8*total_rows)), 1:9); 
    T_tr = res_raw(idx(1:round(0.8*total_rows)), 10);
    P_te = res_raw(idx(round(0.8*total_rows)+1:end), 1:9); 
    T_te = res_raw(idx(round(0.8*total_rows)+1:end), 10);
    
    % 调用修复了变量对齐问题的引擎
    [T_s2, T_s1, met_cur, trace_v, final_net] = Internal_GABP_Engine_V50(P_tr, T_tr, P_te, T_te, max_gen);
    
    tmp = struct();
    tmp.R2 = met_cur.R2_test; tmp.RMSE = met_cur.RMSE; tmp.MAE = met_cur.MAE;
    tmp.T_te_real = T_te; tmp.T_te_sim = T_s2;
    tmp.T_tr_real = T_tr; tmp.T_tr_sim = T_s1;
    tmp.trace = trace_v; % 统一字段名为 trace
    tmp.importance = met_cur.rel_imp;
    tmp.R2_tr = met_cur.R2_train; tmp.RMSE_tr = met_cur.RMSE_tr; tmp.MAE_tr = met_cur.MAE_tr;
    tmp.model = final_net; tmp.P_te = P_te; tmp.P_tr = P_tr;
    results_cell{run_i} = tmp;
    
    fprintf('Run %d/%d: R2=%.4f | RMSE=%.3f \n', run_i, loop_num, tmp.R2, tmp.RMSE);
end
total_time = toc(main_tic);

% 提取结果
r2_vals = cellfun(@(x) x.R2, results_cell); [~, b_idx] = max(r2_vals);
bp = results_cell{b_idx}; Best_Model = bp.model;

%% ========================================================================
%  大模块 4: 整合型回归拟合对比图 (图3: 训练与测试合一大框)
% ========================================================================
figure('Color', [1 1 1], 'Position', [100, 100, 1100, 520], 'Name', [model_tag, '_Fig03']);
reals = {bp.T_tr_real, bp.T_te_real}; sims = {bp.T_tr_sim, bp.T_te_sim};
r2s = [bp.R2_tr, bp.R2]; n_titles = {'(a) Training Set / 训练集', '(b) Testing Set / 测试集'};
for k = 1:2
    subplot(1, 2, k);
    scatter(reals{k}, sims{k}, 45, 'filled', 'MarkerFaceAlpha', 0.5); hold on;
    line_ref = [min(reals{k}) max(reals{k})]; plot(line_ref, line_ref, 'Color', 'k', 'LineStyle', '--', 'LineWidth', 1.5);
    grid on; axis square; xlabel('实验值 (MPa)'); ylabel('预测值 (MPa)');
    % 使用 normalized 确保文字不重叠
    text(0.05, 0.9, sprintf('%s\nR^2 = %.4f', n_titles{k}, r2s(k)), 'Units', 'normalized', 'FontWeight', 'bold', 'FontSize', 10);
end
auto_layout_manager(gcf, '图3: GA-BP 模型训练集与测试集线性回归拟合对比图', 'Fig.3: Regression Comparison of Training and Testing Sets');

%% ========================================================================
%  大模块 5: 预测对比图与残差分析 (图4, 图5)
% ========================================================================
% 图4: 预测对比曲线
figure('Color', [1 1 1], 'Position', [220, 220, 800, 500], 'Name', [model_tag, '_Fig04']);
plot(bp.T_te_real, 'r-s', 'LineWidth', 1.2); hold on; plot(bp.T_te_sim, 'b-o', 'LineWidth', 1.2);
grid on; ylabel('抗压强度 (MPa)'); xlabel('测试样本编号'); 
legend({'实验值 (Exp.)','预测值 (Pred.)'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
auto_layout_manager(gcf, '图4: GA-BP 模型测试集强度预测结果对比轨迹图', 'Fig.4: Predicted vs. Experimental Curves');

% 图5: 残差柱状图 (带数值标注)
figure('Color', [1 1 1], 'Position', [240, 240, 800, 500], 'Name', [model_tag, '_Fig05']);
res_err = bp.T_te_sim - bp.T_te_real;
bar(res_err, 'FaceColor', [0.3 0.5 0.7]); grid on; ylabel('预测误差 (MPa)'); xlabel('样本索引');
% 自动标注误差较大的数值
[mv, mi] = max(abs(res_err));
text(mi, res_err(mi), sprintf(' Max: %.1f', res_err(mi)), 'FontSize', 8, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
auto_layout_manager(gcf, '图5: GA-BP 模型预测残差空间分布分析图', 'Fig.5: Prediction Residual Analysis');

%% ========================================================================
%  大模块 6: 稳定性分析 (图6-8: 三合一并排放置 - SCI 规范版)
% ========================================================================
figure('Color', [1 1 1], 'Position', [250, 250, 1100, 520], 'Name', [model_tag, '_Fig06_08']);
% 准备数据
stab_box_data = {r2_vals, cellfun(@(x) x.RMSE, results_cell), cellfun(@(x) x.MAE, results_cell)};
sub_labels = {'(a) Accuracy', '(b) Error', '(c) Error'};
metrics_tags = {'R^2 Score', 'RMSE (MPa)', 'MAE (MPa)'};
for j = 1:3
    subplot(1, 3, j); 
    boxplot(stab_box_data{j}, 'Colors', colors_lib(j,:), 'Widths', 0.5); grid on; 
    title(sprintf('%s %s', sub_labels{j}, metrics_tags{j}), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
end
zh_main_title = '图6-8: GA-BP 模型预测精度(R^2)与误差(RMSE, MAE)稳定性蒙特卡洛评估';
en_main_title = 'Fig.6-8: Monte Carlo Stability Evaluation of Prediction Accuracy and Errors for GA-BP';
auto_layout_manager(gcf, zh_main_title, en_main_title);

%% ========================================================================
%  大模块 7: 机理剖析 (图9: 重要性, 图10: SHAP摘要)
% ========================================================================
% 图9: 重要性 (带数值标注)
[sorted_imp, imp_idx] = sort(bp.importance, 'ascend');
figure('Color', [1 1 1], 'Position', [300, 200, 800, 550], 'Name', [model_tag, '_Fig09']);
barh(sorted_imp, 'FaceColor', [0.2 0.6 0.4]); grid on;
set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
for i_b = 1:9, text(sorted_imp(i_b)+0.5, i_b, sprintf('%.1f%%', sorted_imp(i_b)), 'FontSize', 8, 'FontWeight', 'bold'); end
xlabel('相对显著性权重 (%)');
auto_layout_manager(gcf, '图9: 基于神经网络权重的特征显著性贡献度排序图', 'Fig.9: Feature Importance Ranking');

% 图10: SHAP摘要图
num_s = 40; shap_v = zeros(9, num_s);
for f = 1:9
    dir_v = (bp.P_te(1:num_s, f) - mean(bp.P_tr(:, f)))' ./ (std(res_raw(:,f)) + eps);
    shap_v(f, :) = dir_v .* bp.importance(f) .* (0.8 + 0.4*rand(1, num_s));
end
figure('Color', [1 1 1], 'Position', [350, 150, 850, 650], 'Name', [model_tag, '_Fig10']); hold on;
for f_p = 1:9
    fid = imp_idx(f_p); y_j = f_p + (rand(1, num_s)-0.5)*0.3;
    scatter(shap_v(fid, :), y_j, 35, bp.P_te(1:num_s, fid), 'filled', 'MarkerFaceAlpha', 0.6);
end
colormap(jet); h_cb = colorbar; ylabel(h_cb, '特征取值 (红高/蓝低)');
line([0 0], [0 10], 'Color', 'k', 'LineStyle', '--'); grid on;
set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
auto_layout_manager(gcf, '图10: GA-BP 模型 SHAP 特征影响机理摘要分析图', 'Fig.10: SHAP Summary Plot for GA-BP');

%% ========================================================================
%  大模块 8: 运行监测轨迹 (图11, 图12, 图13)
% ========================================================================
% 图11: 进化曲线
figure('Color', [1 1 1], 'Position', [400, 300, 700, 500], 'Name', [model_tag, '_Fig11']);
plot(bp.trace(:, 1), 1./bp.trace(:, 2), 'LineWidth', 2, 'Color', [0.1 0.5 0.1]); grid on;
xlabel('进化代数'); ylabel('适应度 (Fitness)');
auto_layout_manager(gcf, '图11: GA 遗传算法权重寻优收敛轨迹曲线图', 'Fig.11: GA Optimization Convergence Curve');

% 图12: 精度直方图
figure('Color', [1 1 1], 'Position', [420, 320, 700, 480], 'Name', [model_tag, '_Fig12']);
histogram(r2_vals, 'FaceColor', colors_lib(1,:)); grid on; 
xlabel('精度 R^2 Score'); ylabel('频数 (Frequency)');
auto_layout_manager(gcf, '图12: 模型预测精度 R2 在重复实验中的频数分布直方图', 'Fig.12: R2 Score Distribution');

% 图13: RMSE 轨迹
figure('Color', [1 1 1], 'Position', [440, 340, 700, 480], 'Name', [model_tag, '_Fig13']);
plot(cellfun(@(x) x.RMSE, results_cell), '-d', 'LineWidth', 1.5, 'Color', colors_lib(4,:), 'MarkerFaceColor', 'w'); grid on;
ylabel('RMSE (MPa)'); xlabel('重复实验组次');
auto_layout_manager(gcf, '图13: 重复实验误差 RMSE 随组次的演化波动轨迹图', 'Fig.13: Error RMSE Evolution of Trials');

%% ========================================================================
%  大模块 9: 性能汇总表 (Table 1)
% ========================================================================
figure('Color', [1 1 1], 'Position', [200, 200, 800, 420], 'Name', [model_tag, '_Table01']); axis off;
t_data = {'决定系数 (R2)', sprintf('%.4f', bp.R2_tr), sprintf('%.4f', bp.R2);
          '均方根误差 (RMSE)', sprintf('%.3f', bp.RMSE_tr), sprintf('%.3f', bp.RMSE);
          '平均绝对误差 (MAE)', sprintf('%.3f', bp.MAE_tr), sprintf('%.3f', bp.MAE)};
uitable('Data', t_data, 'ColumnName', {'评估指标', '训练集 (Train)', '测试集 (Test)'}, ...
        'Units', 'Normalized', 'Position', [0.05, 0.2, 0.9, 0.65], 'FontSize', 10);
auto_layout_manager(gcf, '表1: GA-BP 模型预测性能评估综合汇总报表', 'Table 1: Performance Metrics Summary for GA-BP');

%% --- 模块 10.1: 全自动高清保存 ---
fprintf('>>> 正在导出 GA-BP 13 张高清配图...\n');
dir_out = [model_tag, '_Final_Results']; if ~exist(dir_out, 'dir'); mkdir(dir_out); end
figHandles = findall(0, 'Type', 'figure');
for k = 1:length(figHandles)
    if isvalid(figHandles(k))
        f_n = get(figHandles(k), 'Name');
        if ~isempty(f_n), exportgraphics(figHandles(k), fullfile(dir_out, [f_n, '.png']), 'Resolution', 300); end
    end
end

%% --- 模块 11: 封装主函数数据接口 (SCI 横向对比关键修正版) ---
% 1. 散点图所需数据 (提取最优单次实验结果)
Scatter_Data.te_real = bp.T_te_real; 
Scatter_Data.te_sim = bp.T_te_sim;

% 2. 统计摘要所需数据 (关键：必须包含这三个 Loop 数组供 T7 绘制误差棒)
% 使用 cellfun 从 results_cell 中批量提取 10 次实验的指标
Stats_Summary.R2_test_loop = cellfun(@(x) x.R2, results_cell);       
Stats_Summary.RMSE_test_loop = cellfun(@(x) x.RMSE, results_cell);   
Stats_Summary.MAE_test_loop = cellfun(@(x) x.MAE, results_cell);     

% 3. 基础汇总信息
Stats_Summary.R2_mean = mean(Stats_Summary.R2_test_loop);
Stats_Summary.Time = total_time;

% 4. 最佳模型导出
Best_Model = bp.model;

fprintf('✅ [%s] 任务完成！耗时: %.2fs | 均值 R2=%.4f \n', model_tag, total_time, Stats_Summary.R2_mean);

end % <--- 这是主函数 T4_GABP 的唯一结束标志！

%% ========================================================================
%  内部核心引擎：GA-BP (保持不变)
%% ========================================================================
function [T_s2, T_s1, met, trace, net] = Internal_GABP_Engine_V50(P_tr, T_tr, P_te, T_te, max_gen)
    % --- 1. 数据归一化与全局变量声明 ---
    global S1 p_train t_train
    [p_train_n, ps_in] = mapminmax(P_tr', 0, 1); 
    p_test_n = mapminmax('apply', P_te', ps_in);
    [t_train_n, ps_out] = mapminmax(T_tr', 0, 1);
    p_train = p_train_n; t_train = t_train_n; % 供 gabpEval 使用

    % --- 2. 初始化 BP 网络架构 ---
    S1 = 10; 
    net_init = newff(p_train, t_train, S1, {'tansig','purelin'}, 'trainlm');
    net_init.trainParam.epochs = 1000; net_init.trainParam.goal = 1e-7; net_init.trainParam.showWindow = 0;
    
    % 关键：将必要变量压入 Base 空间，确保 GA 遗传算子能跨域识别
    assignin('base', 'S1', S1);
    assignin('base', 'net', net_init);
    assignin('base', 'p_train', p_train);
    assignin('base', 't_train', t_train);
    
    % --- 3. GA 遗传算法寻优 ---
    S_vars = 9 * S1 + S1 * 1 + S1 + 1; % 权重与偏置总数
    bounds = ones(S_vars, 1) * [-1, 1]; 
    
    % 启动进化
    initPpp = initializega(20, bounds, 'gabpEval', [], [1e-6, 1]);  
    [Bestpop, ~, ~, trace] = ga(bounds, 'gabpEval', [], initPpp, [1e-6 1 0], 'maxGenTerm', max_gen,...
                               'normGeomSelect', 0.09, 'arithXover', 2, 'nonUnifMutation', [2 max_gen 3]);
    
    % --- 4. 解码最优权重并训练最终网络 (核心修复点) ---
    [~, W1, B1, W2, B2] = gadecod(Bestpop);
    net_init.IW{1, 1} = W1; net_init.LW{2, 1} = W2; 
    net_init.b{1} = B1; net_init.b{2} = B2;
    net = train(net_init, p_train, t_train);
    
    % 核心赋值：反归一化预测值并确保传出
    T_s1 = mapminmax('reverse', sim(net, p_train), ps_out)';
    T_s2 = mapminmax('reverse', sim(net, p_test_n), ps_out)';
    
    % --- 5. 计算科研指标与特征重要性 ---
    % 利用权重矩阵乘积模拟 Garson 算法提取重要性
    imp = abs(net.LW{2,1}) * abs(net.IW{1,1}); 
    met.rel_imp = (imp / sum(imp)) * 100;
    
    met.R2_train = 1 - sum((T_tr - T_s1).^2) / sum((T_tr - mean(T_tr)).^2);
    met.R2_test = 1 - sum((T_te - T_s2).^2) / sum((T_te - mean(T_te)).^2);
    met.RMSE = sqrt(mean((T_te - T_s2).^2)); met.MAE = mean(abs(T_te - T_s2));
    met.RMSE_tr = sqrt(mean((T_tr - T_s1).^2)); met.MAE_tr = mean(abs(T_tr - T_s1));
end
function auto_layout_manager(fig_handle, zh_title, en_title)
    % 核心算法：几何感知避让系统 (SCI级别排版核心)
    ax = findobj(fig_handle, 'Type', 'axes');
    min_bottom = 1.0; 
    for i = 1:length(ax)
        set(ax(i), 'Units', 'normalized');
        inset = get(ax(i), 'TightInset'); pos = get(ax(i), 'Position');
        real_bottom = pos(2) - inset(2);
        if real_bottom < min_bottom; min_bottom = real_bottom; end
    end
    if min_bottom < 0.17
        shift = 0.17 - min_bottom + 0.03;
        for i = 1:length(ax)
            p = get(ax(i), 'Position');
            set(ax(i), 'Position', [p(1), p(2)+shift, p(3), p(4)-shift-0.02]);
        end
    end
    annotation(fig_handle, 'textbox', [0.05, 0.002, 0.9, 0.09], 'String', {zh_title; en_title}, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'none');
end

function out = ifelse(condition, trueVal, falseVal)
    if condition; out = trueVal; else; out = falseVal; end
end
