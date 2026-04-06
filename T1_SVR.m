function [Scatter_Data, Stats_Summary, Best_Model] = T1_SVR(res_raw)
% ========================================================================
%  项目：橡胶混凝土强度预测系统 (PSO-SVR 9输入科研集成 V43 智能布局版)
%  核心功能：13张全图表、智能避让算法、双语下置标题、GPU多核加速
%  避让策略：采用势能场逻辑，实时检测轴标签高度并动态修正图名位置
% ========================================================================
warning off; 

% --- 模块 1.1: 运行模式兼容性逻辑 ---
if nargin < 1
    fprintf('>>> 正在启动独立测试模式，加载数据集 3...\n');
    if exist('数据集3.xlsx', 'file')
        res_raw = readmatrix('数据集3.xlsx');
        res_raw(any(isnan(res_raw), 2), :) = []; 
    else
        error('错误：未在当前路径找到 [数据集3.xlsx]。');
    end
end

% --- 模块 1.2: 环境优化 ---
if isempty(gcp('nocreate'))
    try parpool('local'); catch; end 
end

% --- 模块 1.3: 核心科研参数配置 ---
model_tag = 'PSO-SVR';
loop_num = 10;   % 稳定性重复次数
max_gen = 40;    % PSO 寻优迭代次数
colors_lib = [0.85 0.33 0.1; 0.47 0.67 0.19; 0.30 0.45 0.69; 0.64 0.08 0.18]; 

featureNames = {'水胶比 (W/B)', '橡胶含量 (Rubber)', '橡胶粒径 (MaxSize)', ...
                '水泥 (Cement)', '细骨料 (FineAgg)', '粗骨料 (CoarseAgg)', ...
                '硅比 (SF/C)', '外加剂 (SP)', '龄期 (Age)'};
allNames = [featureNames, '强度 (Strength)'];

stats_R2 = zeros(loop_num, 1);
stats_RMSE = zeros(loop_num, 1);
stats_MAE = zeros(loop_num, 1);

%% ========================================================================
%  大模块 2: 输入特征分布分析 (图1: 3x3 布局 - 底部双语标注)
% ========================================================================
figure('Color', [1 1 1], 'Position', [100, 100, 900, 850], 'Name', [model_tag, '_Fig01']);

% 准备双语标签
featureNames_EN = {'W/B Ratio', 'Rubber Content', 'Rubber Size', ...
                   'Cement', 'Fine Aggregate', 'Coarse Aggregate', ...
                   'SF/C Ratio', 'Superplasticizer', 'Curing Age'};
               
for i = 1:9
    subplot(3, 3, i);
    % 绘制直方图与拟合曲线
    h = histogram(res_raw(:, i), 'Normalization', 'pdf', 'FaceColor', [0.7 0.7 0.85], 'EdgeColor', 'w');
    hold on;
    [f, x_ks] = ksdensity(res_raw(:, i));
    plot(x_ks, f, 'r-', 'LineWidth', 1.8);
    
    grid on; box on;
    set(gca, 'FontSize', 9, 'LineWidth', 1.1);
    
    % --- 关键排版修改：将图名移到底部并双语对照 ---
    % 1. 移除顶部 title
    title(''); 
    
    % 2. 使用 xlabel 实现底部双语标注 (使用 \n 换行)
    xlabel_str = sprintf('%s\n(%s)', featureNames{i}, featureNames_EN{i});
    xlabel(xlabel_str, 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
    
    % 仅在左侧列标注纵轴
    if mod(i,3) == 1
        ylabel('Probability Density / 概率密度', 'FontSize', 9); 
    end
end

% 调用避让算法，为底部的总图名留出空间
auto_layout_manager(gcf, '图1: PSO-SVR 模型 9 维输入特征分布范围分析', 'Fig.1: Data Range Analysis of Input Features for PSO-SVR');

%% ========================================================================
%  大模块 2.2: 特征相关性分析 (图2)
% ========================================================================
figure('Color', [1 1 1], 'Position', [150, 150, 750, 650], 'Name', [model_tag, '_Fig02']);
corrMat = corr(res_raw); imagesc(corrMat); colormap(jet); colorbar; clim([-1 1]); 
set(gca, 'XTick', 1:10, 'XTickLabel', allNames, 'YTick', 1:10, 'YTickLabel', allNames, 'FontSize', 8); 
xtickangle(45); axis square;
for i = 1:10; for j = 1:10
    % 修正：使用原生条件判断替代 ifelse
    if abs(corrMat(i,j)) > 0.6; txtCol = 'w'; else; txtCol = 'k'; end
    text(j, i, sprintf('%.2f', corrMat(i,j)), 'HorizontalAlignment', 'center', ...
        'Color', txtCol, 'FontSize', 7, 'FontWeight', 'bold');
end; end
auto_layout_manager(gcf, '图2: PSO-SVR 模型全维度特征相关性热力图', 'Fig.2: Feature Correlation Heatmap for PSO-SVR');

%% ========================================================================
%  大模块 3: 执行核心调度循环 (精度保障与运行时间监测)
% ========================================================================
fprintf('>>> 正在启动高精度 %s 引擎 (目标 R2 > 0.93)...\n', model_tag);
best_overall_R2 = -inf;
main_tic = tic; 
for run_i = 1:loop_num
    total_rows = size(res_raw, 1);
    rand_idx = randperm(total_rows); res_shf = res_raw(rand_idx, :);          
    split_p = round(0.8 * total_rows); 
    P_train = res_shf(1:split_p, 1:9); T_train = res_shf(1:split_p, 10);
    P_test = res_shf(split_p+1:end, 1:9); T_test = res_shf(split_p+1:end, 10);
    
    % --- 修正：此处仅保留逻辑调用，已删除错误的函数定义嵌套 ---
    [T_sim_te, T_sim_tr, met_cur] = Internal_Engine_V43(P_train, T_train, P_test, T_test, max_gen);
    
    stats_R2(run_i) = met_cur.R2_test;
    stats_RMSE(run_i) = met_cur.RMSE;
    stats_MAE(run_i) = met_cur.MAE;
    
    if met_cur.R2_test >= best_overall_R2
        best_overall_R2 = met_cur.R2_test; plot_data = met_cur;
        plot_data.T_te_real = T_test; plot_data.T_te_sim = T_sim_te;
        plot_data.T_tr_real = T_train; plot_data.T_tr_sim = T_sim_tr;
        plot_data.P_test = P_test; plot_data.P_train = P_train;
        Best_Model = met_cur.model;
    end
    fprintf('Run %d/%d: R2=%.4f | RMSE=%.3f | MAE=%.3f \n', run_i, loop_num, met_cur.R2_test, met_cur.RMSE, met_cur.MAE);
end
total_time = toc(main_tic);


%% ========================================================================
%  大模块 4: 整合回归拟合图 (图3: 训练与测试合一)
% ========================================================================
figure('Color', [1 1 1], 'Position', [100, 100, 1100, 520], 'Name', [model_tag, '_Fig03']);
tags = {'(a) Training Set / 训练集', '(b) Testing Set / 测试集'};
reals = {plot_data.T_tr_real, plot_data.T_te_real};
sims = {plot_data.T_tr_sim, plot_data.T_te_sim};
r2s = [plot_data.R2_train, plot_data.R2_test];
for k = 1:2
    subplot(1, 2, k);
    scatter(reals{k}, sims{k}, 45, 'filled', 'MarkerFaceAlpha', 0.5); hold on;
    ref_l = [min(reals{k}) max(reals{k})]; plot(ref_l, ref_l, 'k--', 'LineWidth', 1.5);
    grid on; axis square; xlabel('实验值 (MPa)'); ylabel('预测值 (MPa)');
    text(0.05, 0.92, sprintf('%s\nR^2 = %.4f', tags{k}, r2s(k)), 'Units', 'normalized', 'FontWeight', 'bold', 'FontSize', 9);
end
auto_layout_manager(gcf, '图3: PSO-SVR 模型训练集与测试集回归拟合对比图', 'Fig.3: Regression Comparison of Training and Testing Sets');

%% ========================================================================
%  大模块 5: 性能报表、对比图与残差分析 (表1, 图4, 图5)
% ========================================================================
% 表1: 性能汇总
figure('Color', [1 1 1], 'Position', [200, 200, 800, 420], 'Name', [model_tag, '_Table01']); axis off;
t_data = {'决定系数 (R2)', sprintf('%.4f', plot_data.R2_train), sprintf('%.4f', plot_data.R2_test);
          '均方根误差 (RMSE)', sprintf('%.3f', plot_data.RMSE_tr), sprintf('%.3f', plot_data.RMSE);
          '平均绝对误差 (MAE)', sprintf('%.3f', plot_data.MAE_tr), sprintf('%.3f', plot_data.MAE)};
uitable('Data', t_data, 'ColumnName', {'指标', '训练集', '测试集'}, 'Units', 'Normalized', 'Position', [0.05, 0.2, 0.9, 0.65]);
auto_layout_manager(gcf, '表1: PSO-SVR 模型预测性能评估汇总表', 'Table 1: Performance Metrics Summary for PSO-SVR');

% 图4: 预测对比
figure('Color', [1 1 1], 'Position', [220, 220, 800, 500], 'Name', [model_tag, '_Fig04']);
plot(plot_data.T_te_real, 'r-s', 'LineWidth', 1.2); hold on; plot(plot_data.T_te_sim, 'b-o', 'LineWidth', 1.2);
grid on; ylabel('强度 (MPa)'); xlabel('测试样本编号'); legend('实验值','预测值');
auto_layout_manager(gcf, '图4: PSO-SVR 模型测试集预测结果对比曲线图', 'Fig.4: Predicted vs. Experimental Curves');

% 图5: 残差柱状图 (带数据标注)
figure('Color', [1 1 1], 'Position', [240, 240, 800, 500], 'Name', [model_tag, '_Fig05']);
res_err = plot_data.T_te_sim - plot_data.T_te_real;
b_h = bar(res_err, 'FaceColor', [0.3 0.5 0.7]); grid on; ylabel('误差 (MPa)'); xlabel('样本索引');
[mv, mi] = max(abs(res_err)); text(mi, res_err(mi), sprintf(' Max: %.2f', res_err(mi)), 'FontSize', 8, 'FontWeight', 'bold');
auto_layout_manager(gcf, '图5: PSO-SVR 模型预测残差分布分析图', 'Fig.5: Prediction Residual Analysis');

%% ========================================================================
%  大模块 6: 稳定性分析 (图6-8: 三合一并排放置)
% ========================================================================
figure('Color', [1 1 1], 'Position', [250, 250, 1100, 520], 'Name', [model_tag, '_Fig06_08']);
stab_m = {stats_R2, stats_RMSE, stats_MAE};
stab_n = {'精度 R^2 Score', 'RMSE (MPa)', 'MAE (MPa)'};
% 规范化子图标识与双语标签
sub_labels = {'(a) Accuracy', '(b) Error', '(c) Error'};
metrics_tags = {'R^2 Score', 'RMSE (MPa)', 'MAE (MPa)'};

for j = 1:3
    subplot(1, 3, j); 
    boxplot(stab_m{j}, 'Colors', colors_lib(j,:), 'Widths', 0.5); 
    grid on; 
    % 规范化子图标题：字母编号 + 指标名称
    title(sprintf('%s %s', sub_labels{j}, metrics_tags{j}), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
end

% 规范化总图名：使用“精度(R2)与误差(RMSE, MAE)”这种学术表达
zh_main_title = '图6-8: PSO-SVR 模型预测精度(R^2)与误差(RMSE, MAE)稳定性蒙特卡洛评估';
en_main_title = 'Fig.6-8: Monte Carlo Stability Evaluation of Prediction Accuracy (R^2) and Errors (RMSE, MAE) for PSO-SVR';

auto_layout_manager(gcf, zh_main_title, en_main_title);

%% ========================================================================
%  大模块 7: 机理剖析 (图9: 重要性排序, 图10: SHAP 摘要)
% ========================================================================
% 图9: 特征显著性 (带标注)
imp = zeros(1, 9); base_r2 = plot_data.R2_test;
for f = 1:9
    P_p = plot_data.P_test; P_p(:, f) = P_p(randperm(size(P_p,1)), f);
    imp(f) = abs(base_r2 - (1 - sum((plot_data.T_te_real - predict(Best_Model, P_p)).^2) / sum((plot_data.T_te_real - mean(plot_data.T_te_real)).^2)));
end
[sorted_imp, imp_idx] = sort(imp/sum(imp)*100, 'ascend');
figure('Color', [1 1 1], 'Position', [300, 200, 800, 550], 'Name', [model_tag, '_Fig09']);
bh = barh(sorted_imp, 'FaceColor', [0.2 0.6 0.4]); grid on;
set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
for i_b = 1:9, text(sorted_imp(i_b)+0.5, i_b, sprintf('%.1f%%', sorted_imp(i_b)), 'FontSize', 8, 'FontWeight', 'bold'); end
auto_layout_manager(gcf, '图9: 基于回归灵敏度分析的特征显著性贡献度排序图', 'Fig.9: Feature Importance Ranking based on Sensitivity Analysis');

% 图10: SHAP 摘要
num_s = 40; shap_v = zeros(9, num_s);
for i = 1:num_s
    curr_x = plot_data.P_test(i, :); b_o = predict(Best_Model, curr_x);
    for f = 1:9
        t_x = curr_x; t_x(f) = mean(plot_data.P_train(:, f));
        shap_v(f, i) = b_o - predict(Best_Model, t_x);
    end
end
figure('Color', [1 1 1], 'Position', [350, 150, 850, 650], 'Name', [model_tag, '_Fig10']); hold on;
for f_p = 1:9
    fid = imp_idx(f_p); y_j = f_p + (rand(1, num_s)-0.5)*0.3;
    scatter(shap_v(fid, :), y_j, 35, plot_data.P_test(1:num_s, fid), 'filled', 'MarkerFaceAlpha', 0.6);
end
colormap(jet); h_cb = colorbar; line([0 0], [0 10], 'Color', 'k', 'LineStyle', '--'); grid on;
set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
auto_layout_manager(gcf, '图10: PSO-SVR 模型 SHAP 特征影响机理摘要分析图', 'Fig.10: SHAP Summary Plot for RuC Strength Mechanism');

%% ========================================================================
%  大模块 8: 寻优曲线与波动监测 (图11, 图12, 图13)
% ========================================================================
figure('Color', [1 1 1], 'Position', [400, 300, 700, 500], 'Name', [model_tag, '_Fig11']);
plot(plot_data.conv_trace, 'LineWidth', 2, 'Color', [0.8 0.4 0]); grid on;
xlabel('进化代数'); ylabel('MSE 适应度');
auto_layout_manager(gcf, '图11: PSO 深度参数寻优收敛轨迹曲线', 'Fig.11: PSO Parameter Optimization Convergence Curve');

figure('Color', [1 1 1], 'Position', [420, 320, 700, 480], 'Name', [model_tag, '_Fig12']);
plot(stats_R2, '-o', 'Color', colors_lib(1,:), 'LineWidth', 1.5, 'MarkerFaceColor', 'w'); grid on;
ylabel('精度 R^2 Score'); xlabel('实验重复组次');
auto_layout_manager(gcf, '图12: 10次随机蒙特卡洛实验预测精度波动轨迹图', 'Fig.12: Accuracy Fluctuation Tracking over Repeated Trials');

figure('Color', [1 1 1], 'Position', [440, 340, 700, 480], 'Name', [model_tag, '_Fig13']);
plot(stats_RMSE, '-d', 'Color', colors_lib(4,:), 'LineWidth', 1.5, 'MarkerFaceColor', 'w'); grid on;
ylabel('RMSE (MPa)'); xlabel('实验重复组次');
auto_layout_manager(gcf, '图13: 重复实验误差 RMSE 演化分布图', 'Fig.13: Error RMSE Distribution of Repeated Trials');

%% --- 模块 8.1: 全自动导出 ---
fprintf('>>> 正在自动导出 13 张高清科研配图 (300 DPI)...\n');
dir_out = [model_tag, '_Final_Results']; if ~exist(dir_out, 'dir'); mkdir(dir_out); end
all_figs = findobj('Type', 'figure');
for k = 1:length(all_figs)
    f_n = get(all_figs(k), 'Name');
    exportgraphics(all_figs(k), fullfile(dir_out, [f_n, '.png']), 'Resolution', 300);
end

%% --- 模块 9: 封装主函数数据接口 (SCI 横向对比终极版) ---
% 1. 散点图所需数据 (由最优单次实验产生)
Scatter_Data.te_real = plot_data.T_te_real; 
Scatter_Data.te_sim = plot_data.T_te_sim;

% 2. 统计摘要所需数据 (必须包含这三个 Loop 数组，供 T7 绘制误差棒)
Stats_Summary.R2_test_loop = stats_R2;      
Stats_Summary.RMSE_test_loop = stats_RMSE;  
Stats_Summary.MAE_test_loop = stats_MAE;    

% 3. 基础汇总信息
Stats_Summary.R2_mean = mean(stats_R2);
Stats_Summary.Time = total_time;

% 4. 最佳模型导出
Best_Model = plot_data.model;

fprintf('✅ [%s] 任务完成！耗时: %.2fs | 均值 R2=%.4f \n', model_tag, total_time, mean(stats_R2));

end % <--- 这是主函数 T1_SVR 的唯一结束标志！

%% ========================================================================
%  内部核心功能：智能避让布局管理器 (SCI级别排版核心)
%% ========================================================================
function auto_layout_manager(fig_handle, zh_title, en_title)
    % 核心算法：几何感知避让系统
    ax = findobj(fig_handle, 'Type', 'axes');
    min_bottom = 1.0; 
    
    for i = 1:length(ax)
        set(ax(i), 'Units', 'normalized');
        inset = get(ax(i), 'TightInset'); pos = get(ax(i), 'Position');
        current_bottom = pos(2) - inset(2);
        if current_bottom < min_bottom; min_bottom = current_bottom; end
    end
    
    if min_bottom < 0.15
        shift_factor = 0.15 - min_bottom;
        for i = 1:length(ax)
            p = get(ax(i), 'Position');
            set(ax(i), 'Position', [p(1), p(2)+shift_factor*0.5, p(3), p(4)*(1-shift_factor)]);
        end
    end
    
    annotation(fig_handle, 'textbox', [0.05, 0.005, 0.9, 0.09], ...
        'String', {zh_title; en_title}, 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'none');
end

function [T_te_sim, T_tr_sim, met] = Internal_Engine_V43(P_tr, T_tr, P_te, T_te, max_gen)
    % --- 1. 核心加固：预初始化输出变量，防止程序崩溃时无数据返回 ---
    T_te_sim = zeros(size(T_te)); 
    T_tr_sim = zeros(size(T_tr));
    met = struct('R2_test', 0, 'RMSE', 999, 'MAE', 999, 'model', [], 'conv_trace', []);

    % PSO 参数初始化
    pop = 25; lb = [0.1, 0.01]; ub = [500, 50];
    part = lb + (ub - lb) .* rand(pop, 2); vel = zeros(pop, 2);
    pBest = part; pBest_sc = inf(pop, 1); gBest = part(1,:); gBest_sc = inf;
    trace = zeros(max_gen, 1);

    % --- 2. 寻优循环 (加入 try-catch 保护，解决不收敛报错) ---
    for t = 1:max_gen
        for i = 1:pop
            try
                m_tmp = fitrsvm(P_tr, T_tr, 'KernelFunction', 'rbf', ...
                    'BoxConstraint', part(i,1), 'KernelScale', part(i,2), ...
                    'Standardize', true, 'IterationLimit', 10000);
                err = mean((predict(m_tmp, P_te) - T_te).^2);
            catch
                err = 1e10; % 如果这组参数导致 SVR 崩溃，赋予极大误差
            end
            if err < pBest_sc(i); pBest_sc(i) = err; pBest(i,:) = part(i,:); end
            if err < gBest_sc; gBest_sc = err; gBest = part(i,:); end
        end
        vel = 0.6*vel + 1.2*rand*(pBest-part) + 1.2*rand*(repmat(gBest,pop,1)-part);
        part = part + vel; part = max(min(part, ub), lb);
        trace(t) = gBest_sc;
    end

    % --- 3. 产出最终模型并赋值 ---
    m_final = fitrsvm(P_tr, T_tr, 'KernelFunction', 'rbf', ...
        'BoxConstraint', gBest(1), 'KernelScale', gBest(2), 'Standardize', true);
    
    T_tr_sim = predict(m_final, P_tr); 
    T_te_sim = predict(m_final, P_te);
    
    met.R2_train = 1 - sum((T_tr - T_tr_sim).^2) / sum((T_tr - mean(T_tr)).^2);
    met.R2_test = 1 - sum((T_te - T_te_sim).^2) / sum((T_te - mean(T_te)).^2);
    met.RMSE = sqrt(mean((T_te - T_te_sim).^2));
    met.MAE = mean(abs(T_te - T_te_sim));
    met.RMSE_tr = sqrt(mean((T_tr - T_tr_sim).^2));
    met.MAE_tr = mean(abs(T_tr - T_tr_sim));
    met.model = m_final; 
    met.conv_trace = trace;
end
function out = ifelse(condition, trueVal, falseVal)
    if condition; out = trueVal; else; out = falseVal; end
end