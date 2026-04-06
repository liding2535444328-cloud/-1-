%% ========================================================================
%  T7 主控平台：橡胶混凝土 6 模型综合集成系统 (SCI 一二区旗舰版)
%  修复：彻底解决 line 函数绘图与变量名大小写识别问题
%% ========================================================================
warning off; clear; clc; close all;
rng('shuffle');

% --- 模块 7.1: 数据精准加载 ---
res_raw = readmatrix('数据集3.xlsx');
res_raw(any(isnan(res_raw), 2), :) = []; 

modelNames = {'PSO-SVR', 'FA-RF', 'PSO-LSBoost', 'GA-BP', 'PSO-LSSVM', 'LSTM'};
colors = [0.85 0.33 0.10; 0.00 0.45 0.74; 0.47 0.67 0.19; 0.49 0.18 0.56; 0.93 0.69 0.13; 1.00 0.00 0.00];

% 预分配存储
All_R2_Loop = zeros(10, 6);
All_RMSE_Loop = zeros(10, 6);
All_MAE_Loop = zeros(10, 6);
Scatter_Collection = cell(6, 2); 
Summary_Time = zeros(6, 1);

%% --- 模块 7.2: 核心调度循环 (含自动分类导出逻辑) ---
fprintf('🚀 正在启动 6 模型深度对比评价系统 (SCI 旗舰版)...\n');
main_tic = tic; 

for m_idx = 1:6
    curr_model = modelNames{m_idx};
    fprintf('>>> [%d/6] 正在执行: %s 模型算法...\n', m_idx, curr_model);
    
    switch m_idx
        case 1, [S_Data, Stats, ~] = T1_SVR(res_raw);
        case 2, [S_Data, Stats, ~] = T2_RF(res_raw);
        case 3, [S_Data, Stats, ~] = T3_LSBoost(res_raw);
        case 4, [S_Data, Stats, ~] = T4_GABP(res_raw);
        case 5, [S_Data, Stats, ~] = T5_LSSVM(res_raw);
        case 6, [S_Data, Stats, ~] = T6_LSTM(res_raw);
    end
    
    % --- 核心增强：立即分类保存该模型的 13 张原始图 ---
    model_dir = [curr_model, '_Individual_Results'];
    if ~exist(model_dir, 'dir'); mkdir(model_dir); end
    
    all_figs = findall(0, 'Type', 'figure');
    for k = 1:length(all_figs)
        fig_name = get(all_figs(k), 'Name');
        if ~isempty(fig_name) && contains(fig_name, curr_model)
            exportgraphics(all_figs(k), fullfile(model_dir, [fig_name, '.png']), 'Resolution', 300);
        end
    end
    
    % 数据同步至总库
    All_R2_Loop(:, m_idx)   = double(Stats.R2_test_loop(:));
    All_RMSE_Loop(:, m_idx) = double(Stats.RMSE_test_loop(:));
    All_MAE_Loop(:, m_idx)  = double(Stats.MAE_test_loop(:));
    Summary_Time(m_idx)     = Stats.Time;
    Scatter_Collection{m_idx, 1} = double(S_Data.te_real(:));
    Scatter_Collection{m_idx, 2} = double(S_Data.te_sim(:));
    
    fprintf('✅ %s 数据已汇总，单体图表已导出至 [%s]\n', curr_model, model_dir);
    close all; % 及时关闭窗口，释放内存防止崩溃
end

Final_Mean = [mean(All_R2_Loop)', mean(All_RMSE_Loop)', mean(All_MAE_Loop)'];
Final_Std  = [std(All_R2_Loop)', std(All_RMSE_Loop)', std(All_MAE_Loop)'];

%% --- 模块 7.3: 渲染 图15 (R2 趋势对比) ---
figure('Color', [1 1 1], 'Position', [100, 100, 950, 600], 'Name', 'Compare_R2');
hold on; grid on;
for i = 1:6
    b = bar(i, Final_Mean(i,1), 0.6);
    set(b, 'FaceColor', colors(i,:), 'EdgeColor', 'k', 'LineWidth', 1.1);
end
% 绘制折线趋势
plot(1:6, Final_Mean(:,1), '-o', 'Color', [0.3 0.3 0.3], 'LineWidth', 2, 'MarkerFaceColor', 'w');
% 绘制误差范围
errorbar(1:6, Final_Mean(:,1), Final_Std(:,1), 'k.', 'LineWidth', 1.2, 'CapSize', 10);
% 标注数值
for i = 1:6
    text(i, Final_Mean(i,1)+Final_Std(i,1)+0.005, sprintf('%.4f', Final_Mean(i,1)), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 10);
end
set(gca, 'XTick', 1:6, 'XTickLabel', modelNames, 'FontSize', 10);
ylabel('Determination Coefficient R^2 Score', 'FontWeight', 'bold');
auto_layout_manager_T7(gcf, '图15: 6种异构模型预测精度 (R^2) 横向对比趋势图', 'Fig.15: R^2 Comparison and Trend Analysis');

%% --- 模块 7.4: 渲染 图16 (误差对比趋势) ---
figure('Color', [1 1 1], 'Position', [150, 150, 1000, 600], 'Name', 'Compare_Error');
b_grp = bar(Final_Mean(:, 2:3), 'grouped', 'EdgeColor', 'k', 'LineWidth', 1.1);
set(b_grp(1), 'FaceColor', [0.2 0.4 0.6]); % RMSE
set(b_grp(2), 'FaceColor', [0.6 0.2 0.2]); % MAE
hold on; grid on;
% 绘制 RMSE 和 MAE 的连接折线
x_coord = zeros(6, 2);
for j = 1:2
    x_coord(:,j) = b_grp(j).XData + b_grp(j).XOffset;
    plot(x_coord(:,j), Final_Mean(:, j+1), '-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'w');
    % 标注数值
    for i = 1:6
        text(x_coord(i,j), Final_Mean(i, j+1)+0.1, sprintf('%.2f', Final_Mean(i, j+1)), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    end
end
set(gca, 'XTick', 1:6, 'XTickLabel', modelNames);
ylabel('Error Value (MPa)', 'FontWeight', 'bold');
legend({'RMSE', 'MAE'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
auto_layout_manager_T7(gcf, '图16: 6种异构模型预测误差 (RMSE, MAE) 横向对比趋势图', 'Fig.16: RMSE and MAE Comparison');

%% --- 模块 8: 全系统集成对比图导出 ---
t7_out_dir = 'T7_Global_Comparison_Results'; 
if ~exist(t7_out_dir, 'dir'); mkdir(t7_out_dir); end

fprintf('>>> 正在导出 T7 综合对比分析高清图...\n');
% 强制刷新当前图形缓存，确保对比图被捕捉
drawnow; 

allFig = findall(0, 'Type', 'figure');
for k = 1:length(allFig)
    try
        if isvalid(allFig(k))
            f_n = get(allFig(k), 'Name');
            % 只有名为 Compare_R2 或 Compare_Error 的图才进 T7 总库
            if contains(f_n, 'Compare')
                save_path = fullfile(t7_out_dir, [f_n, '.png']);
                exportgraphics(allFig(k), save_path, 'Resolution', 300);
            end
        end
    catch
        continue;
    end
end

fprintf('\n🏆 所有任务圆满完成！\n');
fprintf('1. 单体模型图：已按模型名存入各自的 _Individual_Results 文件夹\n');
fprintf('2. 综合对比图：已存入 [%s] 文件夹\n', t7_out_dir);
fprintf('📊 总运行耗时: %.2f 秒。\n', toc(main_tic));

%% ========================================================================
%  T7 专用辅助函数模块 (保持挺拔比例)
% ========================================================================
function auto_layout_manager_T7(fig_handle, zh_title, en_title)
    % 获取所有坐标轴
    ax_objs = findobj(fig_handle, 'Type', 'axes');
    for i = 1:length(ax_objs)
        set(ax_objs(i), 'Units', 'normalized');
        p = get(ax_objs(i), 'Position');
        % 向上偏移 0.08 并拉伸，确保满足 4:3 的饱满感并给底部标题留空
        set(ax_objs(i), 'Position', [p(1), p(2)+0.08, p(3), p(4)*0.85]);
    end
    % 添加双语总标题
    annotation(fig_handle, 'textbox', [0.05, 0.002, 0.9, 0.09], 'String', {zh_title; en_title}, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', 'FontSize', 11, 'Interpreter', 'none');
end
