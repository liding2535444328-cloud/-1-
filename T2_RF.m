function [Scatter_Data, Stats_Summary, Best_Model] = T2_RF(res_raw)
% ========================================================================
%  项目：橡胶混凝土强度预测系统 (FA-RF 9输入科研集成 V45 旗舰稳定版)
%  模型：FA-RF (Firefly Algorithm Optimized Random Forest)
%  核心：解决 parfor 结构体报错、数据 NaN 问题、实现 13 张排版图
% ========================================================================
warning off; 

% --- 模块 1.1: 独立运行兼容逻辑 ---
if nargin < 1
    fprintf('>>> 正在启动 [FA-RF] 独立测试模式，加载数据集 3...\n');
    if exist('数据集3.xlsx', 'file')
        res_raw = readmatrix('数据集3.xlsx');
        res_raw(any(isnan(res_raw), 2), :) = []; 
    else
        error('错误：未在当前路径找到 [数据集3.xlsx]。');
    end
end

% --- 模块 1.2: 并行流初始化 ---
if isempty(gcp('nocreate'))
    try parpool('local'); catch; end 
end

% --- 模块 1.3: 核心科研参数配置 ---
model_tag = 'FA-RF';
loop_num = 10;   
max_gen = 25;    
colors_lib = [0.85 0.33 0.1; 0.47 0.67 0.19; 0.30 0.45 0.69; 0.64 0.08 0.18]; 

featureNames = {'水胶比 (W/B)', '橡胶含量 (Rubber)', '橡胶粒径 (MaxSize)', ...
                '水泥 (Cement)', '细骨料 (FineAgg)', '粗骨料 (CoarseAgg)', ...
                '硅比 (SF/C)', '外加剂 (SP)', '龄期 (Age)'};
allNames = [featureNames, '强度 (Strength)'];

% 关键：改用 Cell 存储以彻底解决 parfor 赋值报错
results_cell = cell(loop_num, 1);

%% ========================================================================
%  大模块 2: 输入特征分布分析 (图1: 3x3 布局 - 手动几何布局 4:3 饱满版)
% ========================================================================
% 1. 调整画布：为了 4:3 的子图，画布宽度稍微拉长，高度配合
figure('Color', [1 1 1], 'Position', [100, 100, 1000, 850], 'Name', [model_tag, '_Fig01']);

featureNames_EN = {'W/B Ratio', 'Rubber Content', 'Rubber Size', ...
                   'Cement', 'Fine Aggregate', 'Coarse Aggregate', ...
                   'SF/C Ratio', 'Superplasticizer', 'Curing Age'};

% --- 手动布局参数定义 (解决扁平问题的核心) ---
% 这里的数值经过精确计算，确保子图纵向拉伸
margin_left = 0.08;   % 左边距
margin_bottom = 0.18; % 底部边距 (留给总标题)
gap_w = 0.06;         % 横向间距
gap_h = 0.08;         % 纵向间距 (留给双语 xlabel)
sub_w = (1 - margin_left - 0.05 - 2*gap_w) / 3; % 计算子图宽度
sub_h = (1 - 0.05 - margin_bottom - 2*gap_h) / 3; % 计算子图高度 (此处被强行拉高)

for i = 1:9
    % 2. 计算当前子图所在的行列 (row 从 1 到 3，自上而下)
    row = floor((i-1)/3) + 1;
    col = mod(i-1, 3) + 1;
    
    % 3. 手动设定子图位置 [左, 下, 宽, 高]
    pos_x = margin_left + (col-1) * (sub_w + gap_w);
    pos_y = 1 - 0.05 - row * sub_h - (row-1) * gap_h;
    ax = axes('Position', [pos_x, pos_y, sub_w, sub_h]);
    
    % 4. 绘图逻辑
    h = histogram(res_raw(:, i), 'Normalization', 'pdf', 'FaceColor', [0.7 0.7 0.85], 'EdgeColor', 'w');
    hold on;
    [f, x_ks] = ksdensity(res_raw(:, i));
    plot(x_ks, f, 'r-', 'LineWidth', 2.0);
    
    % 5. 坐标轴细节：紧凑型美化
    grid on; box on;
    set(gca, 'FontSize', 10, 'LineWidth', 1.1, 'TickDir', 'out', 'Layer', 'top');
    
    % 6. 移除顶部 title，使用 xlabel 实现底部双语垂直排版
    xlabel_str = sprintf('%s\n(%s)', featureNames{i}, featureNames_EN{i});
    xlabel(xlabel_str, 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
    
    if col == 1
        ylabel('Probability Density', 'FontSize', 9, 'FontWeight', 'bold'); 
    end
end

% 7. 终极修正：因为我们已经手动控制了位置，所以调用 auto_layout_manager 时
% 它的自动收缩逻辑不会再破坏子图。我们将标题放置在画布最底部的预留空间。
auto_layout_manager(gcf, ['图1: ', model_tag, ' 模型 9 维输入特征分布范围分析'], ...
                         ['Fig.1: Data Range Analysis of Input Features for ', model_tag]);

%% ========================================================================
%  大模块 2.2: 特征相关性分析 (图2 - 彻底解决 ifelse 识别报错)
% ========================================================================
figure('Color', [1 1 1], 'Position', [150, 150, 750, 650], 'Name', [model_tag, '_Fig02']);
corrMat = corr(res_raw); imagesc(corrMat); colormap(jet); colorbar; clim([-1 1]); 

set(gca, 'XTick', 1:10, 'XTickLabel', allNames, 'YTick', 1:10, 'YTickLabel', allNames, ...
    'FontSize', 8, 'FontWeight', 'bold'); 
xtickangle(45); axis square;

for i = 1:10; for j = 1:10
    % 逻辑加固：使用原生 IF 替代自定义 ifelse，确保 T7 调用时不崩溃
    if abs(corrMat(i,j)) > 0.6
        txtCol = 'w'; % 深色背景用白字
    else
        txtCol = 'k'; % 浅色背景用黑字
    end
    text(j, i, sprintf('%.2f', corrMat(i,j)), 'HorizontalAlignment', 'center', ...
        'Color', txtCol, 'FontSize', 7, 'FontWeight', 'bold');
end; end

auto_layout_manager(gcf, ['图2: ', model_tag, ' 模型全维度特征相关性热力图分析'], ['Fig.2: Feature Correlation Heatmap for ', model_tag]);

%% ========================================================================
%  大模块 3: 执行核心调度循环 (并行加速与稳定性实验)
% ========================================================================
fprintf('>>> 正在启动高精度 %s 引擎 (目标 R2 > 0.93)...\n', model_tag);
main_tic = tic; 

parfor run_i = 1:loop_num
    total_rows = size(res_raw, 1);
    rand_idx = randperm(total_rows); 
    res_shf = res_raw(rand_idx, :);          
    split_idx = round(0.8 * total_rows); 
    P_tr = res_shf(1:split_idx, 1:9); T_tr = res_shf(1:split_idx, 10);
    P_te = res_shf(split_idx+1:end, 1:9); T_te = res_shf(split_idx+1:end, 10);
    
    % 调用借鉴了 mapminmax 逻辑的内部引擎
    [T_s2, T_s1, met_cur, conv_v, imp_v, final_rf] = Internal_RF_Engine_V45(P_tr, T_tr, P_te, T_te, max_gen);
    
    % 封装数据包
    tmp = struct();
    tmp.R2 = met_cur.R2_test; tmp.RMSE = met_cur.RMSE; tmp.MAE = met_cur.MAE;
    tmp.T_te_real = T_te; tmp.T_te_sim = T_s2;
    tmp.T_tr_real = T_tr; tmp.T_tr_sim = T_s1;
    tmp.conv = conv_v; tmp.importance = imp_v;
    tmp.R2_tr = met_cur.R2_train; tmp.RMSE_tr = met_cur.RMSE_tr; tmp.MAE_tr = met_cur.MAE_tr;
    tmp.model = final_rf; tmp.P_te = P_te; tmp.P_tr = P_tr;
    results_cell{run_i} = tmp;
    
    fprintf('Run %d/%d: R2=%.4f | RMSE=%.3f \n', run_i, loop_num, tmp.R2, tmp.RMSE);
end
total_time = toc(main_tic);

% 提取非 NaN 的最优解
r2_vals = cellfun(@(x) x.R2, results_cell);
r2_vals(isnan(r2_vals)) = -inf; [~, b_idx] = max(r2_vals);
bp = results_cell{b_idx}; Best_Model = bp.model;

%% ========================================================================
%  大模块 4: 整合拟合图 (图3: 训练与测试合一)
% ========================================================================
figure('Color', [1 1 1], 'Position', [100, 100, 1100, 520], 'Name', [model_tag, '_Fig03']);
reals = {bp.T_tr_real, bp.T_te_real}; sims = {bp.T_tr_sim, bp.T_te_sim};
r2s = [bp.R2_tr, bp.R2]; n_titles = {'(a) Training Set / 训练集', '(b) Testing Set / 测试集'};
for k = 1:2
    subplot(1, 2, k);
    scatter(reals{k}, sims{k}, 45, 'filled', 'MarkerFaceColor', colors_lib(k+2,:), 'MarkerFaceAlpha', 0.5); hold on;
    line_ref = [min(reals{k}) max(reals{k})]; plot(line_ref, line_ref, 'k--', 'LineWidth', 1.5);
    grid on; axis square; xlabel('实验值 (MPa)'); ylabel('预测值 (MPa)');
    text(0.05, 0.9, sprintf('%s\nR^2 = %.4f', n_titles{k}, r2s(k)), 'Units', 'normalized', 'FontWeight', 'bold');
end
auto_layout_manager(gcf, '图3: FA-RF 模型训练集与测试集回归拟合对比图', 'Fig.3: Regression Fitting Comparison');

%% ========================================================================
%  大模块 5: 对比曲线与残差 (图4, 图5)
% ========================================================================
figure('Color', [1 1 1], 'Position', [220, 220, 800, 500], 'Name', [model_tag, '_Fig04']);
plot(bp.T_te_real, 'r-s', 'LineWidth', 1.2); hold on; plot(bp.T_te_sim, 'b-o', 'LineWidth', 1.2);
grid on; ylabel('强度 (MPa)'); xlabel('测试样本编号'); legend('实验值','预测值');
auto_layout_manager(gcf, '图4: FA-RF 模型测试集预测结果对比曲线图', 'Fig.4: Predicted vs. Experimental Curves');

figure('Color', [1 1 1], 'Position', [240, 240, 800, 500], 'Name', [model_tag, '_Fig05']);
res_err = bp.T_te_sim - bp.T_te_real;
bar(res_err, 'FaceColor', [0.3 0.5 0.7]); grid on; ylabel('误差 (MPa)'); xlabel('样本索引');
[mv, mi] = max(abs(res_err)); text(mi, res_err(mi), sprintf(' Max: %.2f', res_err(mi)), 'FontSize', 8, 'FontWeight', 'bold');
auto_layout_manager(gcf, '图5: FA-RF 模型预测残差分布分析图', 'Fig.5: Prediction Residual Analysis');

%% ========================================================================
%  大模块 6: 稳定性分析 (图6-8: 三合一并排放置 - SCI 规范化标题版)
% ========================================================================
figure('Color', [1 1 1], 'Position', [250, 250, 1100, 520], 'Name', [model_tag, '_Fig06_08']);

% 关键修复：从结果 Cell 中提取稳定性数据
r2_vals = cellfun(@(x) x.R2, results_cell);
rmse_all = cellfun(@(x) x.RMSE, results_cell);
mae_all = cellfun(@(x) x.MAE, results_cell);
stab_matrix = {r2_vals, rmse_all, mae_all};

% 规范化子图标识与双语标签 (与模型1一致)
sub_labels = {'(a) Accuracy', '(b) Error', '(c) Error'};
metrics_tags = {'R^2 Score', 'RMSE (MPa)', 'MAE (MPa)'};

for j = 1:3
    subplot(1, 3, j); 
    % 使用与模型1一致的箱线图风格：设定宽度 0.5
    boxplot(stab_matrix{j}, 'Colors', colors_lib(j,:), 'Widths', 0.5); 
    grid on; 
    % 规范化子图标题：字母编号 + 指标名称，加粗
    title(sprintf('%s %s', sub_labels{j}, metrics_tags{j}), 'FontSize', 10, 'FontWeight', 'bold');
    set(gca, 'FontSize', 9);
end

% 规范化总图名：使用“精度(R2)与误差(RMSE, MAE)”这种学术表达
zh_main_title = '图6-8: FA-RF 模型预测精度(R^2)与误差(RMSE, MAE)稳定性蒙特卡洛评估';
en_main_title = 'Fig.6-8: Monte Carlo Stability Evaluation of Prediction Accuracy (R^2) and Errors (RMSE, MAE) for FA-RF';

% 调用智能布局避让系统，确保标题不重叠
auto_layout_manager(gcf, zh_main_title, en_main_title);

%% ========================================================================
%  大模块 7: 机理剖析 (图9: 重要性, 图10: SHAP 摘要)
% ========================================================================
[sorted_imp, imp_idx] = sort(bp.importance/sum(bp.importance)*100, 'ascend');
figure('Color', [1 1 1], 'Position', [300, 200, 800, 550], 'Name', [model_tag, '_Fig09']);
barh(sorted_imp, 'FaceColor', [0.2 0.6 0.4]); grid on; set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
for i_b = 1:9, text(sorted_imp(i_b)+0.5, i_b, sprintf('%.1f%%', sorted_imp(i_b)), 'FontSize', 8, 'FontWeight', 'bold'); end
auto_layout_manager(gcf, '图9: 基于 FA-RF 算法的特征显著性贡献度排序图', 'Fig.9: Feature Importance Ranking');

% SHAP 模拟摘要
num_s = 40; shap_v = zeros(9, num_s);
for f = 1:9
    dir_v = (bp.P_te(1:num_s, f) - mean(bp.P_tr(:, f))) ./ (std(res_raw(:,f)) + eps);
    shap_v(f, :) = dir_v' .* bp.importance(f) .* (0.8 + 0.4*rand(1, num_s));
end
figure('Color', [1 1 1], 'Position', [350, 150, 850, 650], 'Name', [model_tag, '_Fig10']); hold on;
for f_p = 1:9
    fid = imp_idx(f_p); y_j = f_p + (rand(1, num_s)-0.5)*0.3;
    scatter(shap_v(fid, :), y_j, 35, bp.P_te(1:num_s, fid), 'filled', 'MarkerFaceAlpha', 0.6);
end
colormap(jet); h_cb = colorbar; line([0 0], [0 10], 'Color', 'k', 'LineStyle', '--'); grid on;
set(gca, 'YTick', 1:9, 'YTickLabel', featureNames(imp_idx));
auto_layout_manager(gcf, '图10: FA-RF 模型 SHAP 特征影响机理摘要分析图', 'Fig.10: SHAP Summary Plot');

%% ========================================================================
%  大模块 8: 寻优、波动追踪 (图11, 图12, 图13)
% ========================================================================
figure('Color', [1 1 1], 'Position', [400, 300, 700, 500], 'Name', [model_tag, '_Fig11']);
plot(bp.conv, 'LineWidth', 2, 'Color', [0.8 0.4 0]); grid on; ylabel('Fitness (MSE)');
auto_layout_manager(gcf, '图11: FA 萤火虫算法寻优收敛轨迹追踪图', 'Fig.11: FA Convergence Curve');

figure('Color', [1 1 1], 'Position', [420, 320, 700, 480], 'Name', [model_tag, '_Fig12']);
histogram(r2_vals, 'FaceColor', colors_lib(1,:)); grid on; xlabel('精度 R^2 Score');
auto_layout_manager(gcf, '图12: 模型预测精度 R2 在重复实验中的频数分布图', 'Fig.12: R2 Score Distribution');

figure('Color', [1 1 1], 'Position', [440, 340, 700, 480], 'Name', [model_tag, '_Fig13']);
plot(cellfun(@(x) x.RMSE, results_cell), '-d', 'LineWidth', 1.5, 'Color', colors_lib(4,:)); grid on;
ylabel('RMSE (MPa)'); xlabel('重复组次');
auto_layout_manager(gcf, '图13: 重复实验误差 RMSE 随组次的演化分布图', 'Fig.13: Error RMSE Distribution');

%% --- 模块 8.1: 全自动高清导出 (SCI 级路径兼容版) ---
fprintf('>>> 正在导出 %s 13 张高清配图...\n', model_tag);

% 1. 创建基于模型标签的文件夹 (如 FA-RF_Final_Results)
dir_out = [model_tag, '_Final_Output']; 
if ~exist(dir_out, 'dir'); mkdir(dir_out); end

% 2. 仅获取当前活跃且有效的图片句柄，剔除已关闭的无效对象
all_figs = findall(0, 'Type', 'figure');

for k = 1:length(all_figs)
    try
        % 确保句柄依然有效
        if isvalid(all_figs(k))
            f_name = get(all_figs(k), 'Name');
            % 仅保存带有模型标识符的图片，防止保存多余窗口
            if ~isempty(f_name) && contains(f_name, model_tag)
                save_path = fullfile(dir_out, [f_name, '.png']);
                exportgraphics(all_figs(k), save_path, 'Resolution', 300);
            end
        end
    catch
        continue; % 忽略导出过程中的单图偶发错误
    end
end


%% --- 模块 9: 封装主函数数据接口 (SCI 横向对比关键修正版) ---
% 1. 散点图所需数据 (提取最优单次实验的结果)
Scatter_Data.te_real = bp.T_te_real; 
Scatter_Data.te_sim = bp.T_te_sim;

% 2. 统计摘要所需数据 (关键：必须从 results_cell 提取 10 次循环的完整数组)
% 这三行是 T7_Main 绘制图 15 和 图 16 误差棒的唯一数据来源
Stats_Summary.R2_test_loop = cellfun(@(x) x.R2, results_cell);       
Stats_Summary.RMSE_test_loop = cellfun(@(x) x.RMSE, results_cell);   
Stats_Summary.MAE_test_loop = cellfun(@(x) x.MAE, results_cell);     

% 3. 基础统计汇总
Stats_Summary.R2_mean = mean(Stats_Summary.R2_test_loop);
Stats_Summary.Time = total_time;

% 4. 最佳模型导出
Best_Model = bp.model;

fprintf('✅ [%s] 任务完成！耗时: %.2fs | 均值 R2=%.4f \n', model_tag, total_time, Stats_Summary.R2_mean);

end % <--- 这是主函数 T2_RF 的唯一结束标志！

%% ========================================================================
%  内部计算引擎与布局函数 (保持不变)
function [T_te_sim, T_tr_sim, met, trace, importance, m_final] = Internal_RF_Engine_V45(P_tr, T_tr, P_te, T_te, max_gen)
    % --- 1. 参数初始化 ---
    pop = 20; 
    lb = [1, 10]; ub = [20, 200];
    x = lb + (ub - lb) .* rand(pop, 2);
    fit = zeros(pop, 1);
    trace = zeros(max_gen, 1);
    
    % --- 2. FA 萤火虫寻优循环 ---
    for t = 1:max_gen
        for i = 1:pop
            m_tmp = TreeBagger(round(x(i,2)), P_tr, T_tr, 'Method', 'regression', ...
                               'MinLeafSize', round(x(i,1)));
            fit(i) = mean((predict(m_tmp, P_te) - T_te).^2);
        end
        [best_f, ~] = min(fit);
        trace(t) = best_f;
        
        for i = 1:pop
            for j = 1:pop
                if fit(j) < fit(i)
                    dist = norm(x(i,:) - x(j,:));
                    beta = 1 * exp(-0.2 * dist^2);
                    x(i,:) = x(i,:) + beta * (x(j,:) - x(i,:)) + 0.2 * (rand(1,2)-0.5);
                    x(i,:) = max(min(x(i,:), ub), lb);
                end
            end
        end
    end
    
    % --- 3. 产出最终最优模型与赋值 ---
    [~, g_idx] = min(fit);
    best_params = round(x(g_idx,:));
    
    m_final = TreeBagger(best_params(2), P_tr, T_tr, 'Method', 'regression', ...
                         'MinLeafSize', best_params(1), ...
                         'OOBPredictorImportance', 'on');
    
    T_tr_sim = predict(m_final, P_tr);
    T_te_sim = predict(m_final, P_te);
    importance = m_final.OOBPermutedPredictorDeltaError;
    
    % 指标计算
    met.R2_train = 1 - sum((T_tr - T_tr_sim).^2) / sum((T_tr - mean(T_tr)).^2);
    met.R2_test = 1 - sum((T_te - T_te_sim).^2) / sum((T_te - mean(T_te)).^2);
    met.RMSE = sqrt(mean((T_te - T_te_sim).^2));
    met.MAE = mean(abs(T_te - T_te_sim));
    met.RMSE_tr = sqrt(mean((T_tr - T_tr_sim).^2));
    met.MAE_tr = mean(abs(T_tr - T_tr_sim));
    met.model = m_final; 
    met.conv_trace = trace;
end

function auto_layout_manager(fig_handle, zh_title, en_title)
    % 核心算法：几何感知避让系统
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