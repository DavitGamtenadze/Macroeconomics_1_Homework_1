function calculate_labor_productivity(gdpCsvFile, popCsvFile, outDir, baseQuarter, opts)
% Calculate Average Labor Productivity (ALP) and its growth rate
% ALP = Real GDP / Total Employment
% GDP from quarterly gdpCsvFile; employment from annual popCsvFile (column C: employment in thousands)

if nargin < 5, opts = struct(); end
if nargin < 4 || strlength(baseQuarter)==0
    baseQuarter = "1990 1Q";
end
if nargin < 3 || strlength(outDir)==0
    outDir = fullfile(pwd, '..', '4_results', 'figures');
end
outDir = char(outDir);
if ~exist(outDir,'dir'), mkdir(outDir); end

dataDir = outDir;
if isfield(opts, 'dataDir') && strlength(string(opts.dataDir)) > 0
    dataDir = char(string(opts.dataDir));
end
if ~exist(dataDir,'dir'), mkdir(dataDir); end

verbose = isfield(opts, 'verbose') && opts.verbose;
logmsg(verbose, '    Calculating labor productivity (base: %s)', baseQuarter);

logmsg(verbose, '      Reading GDP table: %s', gdpCsvFile);
T_gdp = readtable(gdpCsvFile, 'PreserveVariableNames', true);

logmsg(verbose, '      Reading employment table: %s', popCsvFile);
T_emp = readtable(popCsvFile, 'PreserveVariableNames', true);

% Extract quarter column headers from GDP file
varNames_gdp = string(T_gdp.Properties.VariableNames);
qNames = varNames_gdp(2:end);

% Parse quarters
[~, years, quarter_nums, valid_idx] = parseAllQuarters(qNames);
if sum(valid_idx) == 0
    error('No valid quarter headers in %s', gdpCsvFile);
end

% Sort chronologically
qNames_valid = qNames(valid_idx);
years_valid = years(valid_idx);
quarter_nums_valid = quarter_nums(valid_idx);
t = createQuarterDates(years_valid, quarter_nums_valid);
[t, sort_idx] = sort(t);
colSel = 1 + find(valid_idx);
colSel = colSel(sort_idx);

% CUT OFF DATA AFTER 2024 Q4
cutoff_date = datetime(2024, 12, 31);
cutoff_idx = t <= cutoff_date;
t = t(cutoff_idx);
colSel = colSel(cutoff_idx);
years_valid = years_valid(sort_idx);
quarter_nums_valid = quarter_nums_valid(sort_idx);
years_valid = years_valid(cutoff_idx);
quarter_nums_valid = quarter_nums_valid(cutoff_idx);

% Canonical labels
canon = arrayfun(@(yr, qn) sprintf('%d %dQ', yr, qn), ...
                years_valid, quarter_nums_valid, ...
                'UniformOutput', false);

% Find base quarter
[base_year, base_qnum] = parseBaseQuarter(baseQuarter);
base_canon = sprintf('%d %dQ', base_year, base_qnum);
base_idx = find(strcmp(canon, base_canon), 1, 'first');
if isempty(base_idx)
    error('Base quarter %s not found (range: %s to %s)', base_canon, canon{1}, canon{end});
end

% Locate rows in GDP table
iNom = findDataRow(T_gdp, {'gdp at current market prices', 'nominal gdp', 'gdp current'});
iDefl = findDataRow(T_gdp, {'gdp deflator', 'gdp_deflator', 'deflator'});
if isempty(iNom) || isempty(iDefl)
    fprintf('Available rows in %s:\n', gdpCsvFile);
    for k = 1:min(20, height(T_gdp))
        fprintf('  %d: %s\n', k, char(T_gdp{k,1}));
    end
    error('Missing Nominal GDP or deflator in %s', gdpCsvFile);
end

% Extract annual employment data (Column C: employment in thousands)
if isnumeric(T_emp{2, 1})
    empYears = double(T_emp{2:end, 1});
else
    empYears = str2double(string(T_emp{2:end, 1}));
end

if isnumeric(T_emp{2, 3})  % Column C for employment
    EMP_annual = double(T_emp{2:end, 3});  % Employment in thousands
else
    EMP_annual = str2double(string(T_emp{2:end, 3}));
end

% Validate employment data
if length(empYears) ~= length(EMP_annual) || any(isnan(empYears)) || min(empYears) < 1900
    error('Invalid employment data structure in %s. Expected years in col 1, employment in col 3.', popCsvFile);
end

% Match to GDP years and interpolate to quarterly
uniqueGdpYears = unique(years_valid);
overlapIdx = ismember(empYears, uniqueGdpYears);
if sum(overlapIdx) < 2
    error('Employment years (%d-%d) overlap too little with GDP (%d-%d). Check data range.', min(empYears), max(empYears), min(uniqueGdpYears), max(uniqueGdpYears));
end
empValidYears = empYears(overlapIdx);
empValidData = EMP_annual(overlapIdx);

% Create quarterly employment (constant within each year)
step_t = datetime.empty(0, 0);
step_emp = [];
for yr_idx = 1:length(empValidYears)
    yr = empValidYears(yr_idx);
    yr_emp = empValidData(yr_idx);
    for q = 1:4
        q_date = dateshift(datetime(yr, 1, 1), 'start', 'quarter', q) + calmonths(3) - caldays(1);
        step_t(end+1) = q_date;
        step_emp(end+1) = yr_emp;
    end
end
EMP_quarterly = interp1(step_t, step_emp, t, 'linear', 'extrap');

% Extract GDP/deflator data
NGDP = extractNumericRow(T_gdp, iNom, colSel);
DEF = extractNumericRow(T_gdp, iDefl, colSel);

logmsg(verbose, '      Series lengths (t=%d, NGDP=%d, DEF=%d, EMP=%d)', length(t), length(NGDP), length(DEF), length(EMP_quarterly));

% Ensure all arrays have the same length
min_length = min([length(t), length(NGDP), length(DEF), length(EMP_quarterly)]);
t = t(1:min_length);
NGDP = NGDP(1:min_length);
DEF = DEF(1:min_length);
EMP_quarterly = EMP_quarterly(1:min_length);
canon = canon(1:min_length);

% Update base_idx after truncation
base_idx = find(strcmp(canon, base_canon), 1, 'first');
if isempty(base_idx)
    error('Base quarter %s not found after truncation', base_canon);
end

% Rebase deflator and calculate Real GDP
base_val = DEF(base_idx);
if isnan(base_val) || base_val == 0
    error('Deflator at %s is invalid: %g', base_canon, base_val);
end
DEF_rebased = DEF / base_val * 100;
RGDP = NGDP ./ (DEF_rebased / 100);

% Calculate Average Labor Productivity (ALP = Real GDP / Employment)
% RGDP is in millions, EMP is in thousands, so ALP will be in thousands per person
ALP = RGDP ./ EMP_quarterly;  % ALP in thousands of currency per worker

% Calculate natural log of ALP for growth analysis
log_ALP = log(ALP);

% Calculate quarterly growth rates of ALP
n = length(ALP);
alp_growth = NaN(n-1, 1);
for i = 2:n
    prev_alp = ALP(i-1); curr_alp = ALP(i);
    if ~isnan(prev_alp) && ~isnan(curr_alp) && prev_alp ~= 0
        alp_growth(i-1) = (curr_alp - prev_alp) / prev_alp;
    end
end

% Annualize growth rates (×4 quarters) and convert to %
alp_growth_ann = alp_growth * 4 * 100;

% FORCE ALL TO SAME LENGTH
min_growth_length = min([length(t(2:end)), length(alp_growth_ann)]);
t_growth = t(2:min_growth_length+1);
alp_growth_ann = alp_growth_ann(1:min_growth_length);
t_growth = t_growth(:);
alp_growth_ann = alp_growth_ann(:);

logmsg(verbose, '      Growth series length: %d observations', length(alp_growth_ann));

% Calculate average productivity growth
avg_alp_growth = mean(alp_growth_ann, 'omitnan');

% Output results
fprintf('\n=== Task 2.4 & 2.5: Labor Productivity Analysis ===\n');
fprintf('Sample Period: %s to %s\n', canon{1}, canon{end});
fprintf('Base Quarter for Real GDP: %s (deflator rebased to 100)\n\n', base_canon);
fprintf('Average Annualized Labor Productivity Growth Rate: %.2f%% (Task 2.5)\n', avg_alp_growth);

% Task 2.6: Compare with GDP per capita growth (you'll need to run the other function first)
fprintf('\nTask 2.6 Analysis:\n');
fprintf('a) Average annual labor productivity growth: %.2f%%\n', avg_alp_growth);
fprintf('b) [Compare with Task 2.3 Real GDP per capita growth for full analysis]\n');

% Save results
results_table = table([avg_alp_growth], ...
                     'VariableNames', {'Value'}, ...
                     'RowNames', {'Avg ALP Growth (%)'});
writetable(results_table, fullfile(dataDir, 'productivity_summary.csv'));
logmsg(verbose, '      Saved productivity_summary.csv to %s', dataDir);

try
    alp_table = table(t(:), ALP(:), log_ALP(:), 'VariableNames', {'Quarter', 'ALP_Thousands_Per_Worker', 'Log_ALP'});
    writetable(alp_table, fullfile(dataDir, 'labor_productivity_levels.csv'));
    logmsg(verbose, '      Saved labor_productivity_levels.csv to %s', dataDir);
    
    growth_table = table(t_growth(:), alp_growth_ann(:), 'VariableNames', {'Quarter', 'ALP_Ann_Growth_Pct'});
    writetable(growth_table, fullfile(dataDir, 'labor_productivity_growth.csv'));
    logmsg(verbose, '      Saved labor_productivity_growth.csv to %s', dataDir);
    fprintf('SUCCESS: Productivity tables created in %s!\n', dataDir);
catch ME
    fprintf('Error creating tables: %s\n', ME.message);
end

% Create plots
createProductivityPlots(t, ALP, log_ALP, t_growth, alp_growth_ann, outDir, canon{1}, canon{end}, avg_alp_growth);
logmsg(verbose, '      Saved labor_productivity_[analysis|clean].png');

fprintf('\nFigures saved to %s\n', outDir);
fprintf('Data tables saved to %s\n', dataDir);
logmsg(verbose, '    Labor productivity analysis complete');
end

% FIXED Helper function for plotting
function createProductivityPlots(t, ALP, log_ALP, t_growth, alp_growth_ann, outDir, start_period, end_period, avg_growth)
% FIXED: Plot with proper colors and visibility
fig_analysis = figure('Color', 'w', 'Position', [100 100 1400 800]);

% SUBPLOT 1: ALP levels
subplot(2, 2, 1);
plot(t, ALP, 'b-', 'LineWidth', 2);
grid on;
xlabel('Quarter', 'Color', 'k');
ylabel('ALP (Thousands per Worker)', 'Color', 'k');
title('Average Labor Productivity Levels', 'Color', 'k');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', 'k', 'GridAlpha', 0.3);
datetick('x', 'yyyy', 'keepticks');
set(gca, 'Box', 'off');

% SUBPLOT 2: log(ALP)  
subplot(2, 2, 2);
plot(t, log_ALP, 'r-', 'LineWidth', 2);
grid on;
xlabel('Quarter', 'Color', 'k');
ylabel('ln(ALP)', 'Color', 'k');
title('Natural Log of Labor Productivity (Task 2.5)', 'Color', 'k');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', 'k', 'GridAlpha', 0.3);
datetick('x', 'yyyy', 'keepticks');
set(gca, 'Box', 'off');

% SUBPLOT 3: Growth rates
subplot(2, 2, 3);
plot(t_growth, alp_growth_ann, 'g-', 'LineWidth', 1.5);
hold on;
% Add reference lines
ylims = get(gca, 'YLim');
plot([t_growth(1) t_growth(end)], [avg_growth avg_growth], 'g--', 'LineWidth', 2);
plot([t_growth(1) t_growth(end)], [0 0], 'k--', 'LineWidth', 1);
% Add text annotation
text(t_growth(end-20), avg_growth + 1, sprintf('Avg: %.2f%%', avg_growth), ...
     'Color', 'g', 'FontWeight', 'bold', 'BackgroundColor', 'w');
grid on;
xlabel('Quarter', 'Color', 'k');
ylabel('Growth Rate (%)', 'Color', 'k');
title('Annualized Labor Productivity Growth', 'Color', 'k');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', 'k', 'GridAlpha', 0.3);
datetick('x', 'yyyy', 'keepticks');
set(gca, 'Box', 'off');

% SUBPLOT 4: Histogram
subplot(2, 2, 4);
h = histogram(alp_growth_ann, 20);
set(h, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'k', 'FaceAlpha', 0.7);
hold on;
% Add mean line
ylims = get(gca, 'YLim');
line([avg_growth avg_growth], ylims, 'Color', 'r', 'LineWidth', 3, 'LineStyle', '-');
text(avg_growth, ylims(2)*0.85, sprintf('Mean: %.2f%%', avg_growth), ...
     'HorizontalAlignment', 'center', 'Color', 'r', 'FontWeight', 'bold', ...
     'BackgroundColor', 'w', 'EdgeColor', 'k');
grid on;
xlabel('Growth Rate (%)', 'Color', 'k');
ylabel('Frequency', 'Color', 'k');
title('Distribution of Productivity Growth', 'Color', 'k');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', 'k', 'GridAlpha', 0.3);
set(gca, 'Box', 'off');

% MAIN TITLE
sgtitle(sprintf('Labor Productivity Analysis (%s to %s)', start_period, end_period), ...
        'Color', 'k', 'FontSize', 16, 'FontWeight', 'bold');

% Save with high resolution
saveas(fig_analysis, fullfile(outDir, 'labor_productivity_analysis.png'));
print(fig_analysis, fullfile(outDir, 'labor_productivity_analysis_hires.png'), '-dpng', '-r300');
close(fig_analysis);

% CREATE A SECOND, SIMPLER PLOT FOR BETTER VISIBILITY
fig_clean = figure('Color', 'w', 'Position', [200 200 1200 400]);

% Just the two most important plots side by side
subplot(1, 2, 1);
plot(t, ALP, 'b-', 'LineWidth', 3);
grid on;
xlabel('Quarter', 'FontSize', 12, 'Color', 'k');
ylabel('ALP (Thousands per Worker)', 'FontSize', 12, 'Color', 'k');
title('Labor Productivity Levels', 'FontSize', 14, 'Color', 'k', 'FontWeight', 'bold');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'FontSize', 11);
set(gca, 'GridColor', [0.5 0.5 0.5], 'GridAlpha', 0.3);
datetick('x', 'yyyy', 'keepticks');

subplot(1, 2, 2);
plot(t_growth, alp_growth_ann, 'g-', 'LineWidth', 2);
hold on;
ylims = get(gca, 'YLim');
plot([t_growth(1) t_growth(end)], [avg_growth avg_growth], 'r--', 'LineWidth', 3);
plot([t_growth(1) t_growth(end)], [0 0], 'k:', 'LineWidth', 1);
text(t_growth(end-15), avg_growth + 2, sprintf('Average: %.2f%%', avg_growth), ...
     'Color', 'r', 'FontWeight', 'bold', 'FontSize', 12, ...
     'BackgroundColor', 'w', 'EdgeColor', 'r');
grid on;
xlabel('Quarter', 'FontSize', 12, 'Color', 'k');
ylabel('Annualized Growth Rate (%)', 'FontSize', 12, 'Color', 'k');
title('Labor Productivity Growth', 'FontSize', 14, 'Color', 'k', 'FontWeight', 'bold');
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'FontSize', 11);
set(gca, 'GridColor', [0.5 0.5 0.5], 'GridAlpha', 0.3);
datetick('x', 'yyyy', 'keepticks');

sgtitle(sprintf('Singapore Labor Productivity: %.2f%% Average Growth (%s to %s)', ...
        avg_growth, start_period, end_period), ...
        'Color', 'k', 'FontSize', 16, 'FontWeight', 'bold');

% Save the cleaner version
saveas(fig_clean, fullfile(outDir, 'labor_productivity_clean.png'));
print(fig_clean, fullfile(outDir, 'labor_productivity_clean_hires.png'), '-dpng', '-r300');
close(fig_clean);

fprintf('Plots saved: labor_productivity_analysis.png and labor_productivity_clean.png\n');
end

% [ALL THE SAME HELPER FUNCTIONS AS BEFORE]
function [quarters, years, quarter_nums, valid_idx] = parseAllQuarters(qNames)
n = length(qNames);
quarters = strings(n, 1);
years = zeros(n, 1);
quarter_nums = zeros(n, 1);
valid_idx = false(n, 1);

for i = 1:n
    [yr, qn, success] = parseQuarterName(qNames(i));
    if success
        quarters(i) = qNames(i);
        years(i) = yr;
        quarter_nums(i) = qn;
        valid_idx(i) = true;
    end
end
end

function [year_val, quarter_val, success] = parseQuarterName(name)
s = char(strtrim(name));
success = false;
year_val = NaN;
quarter_val = NaN;

patterns = {
    '^x?(\d{4})([1-4])Q$', '^(\d{4})Q([1-4])$', '^(\d{4})\s+([1-4])Q$', ...
    '^(\d{4})\s*Q([1-4])$', '^(\d{4})[-_/]Q([1-4])$', '^(\d{4})[-_/]([1-4])Q$'
};

for p = 1:length(patterns)
    tokens = regexp(s, patterns{p}, 'tokens', 'once', 'ignorecase');
    if ~isempty(tokens)
        year_val = str2double(tokens{1});
        quarter_val = str2double(tokens{2});
        if ~isnan(year_val) && ~isnan(quarter_val) && quarter_val >= 1 && quarter_val <= 4
            success = true;
            return;
        end
    end
end
end

function [base_year, base_qnum] = parseBaseQuarter(baseQuarter)
[year_val, quarter_val, success] = parseQuarterName(baseQuarter);
if ~success
    error('Invalid base quarter: %s', baseQuarter);
end
base_year = year_val;
base_qnum = quarter_val;
end

function t = createQuarterDates(years, quarter_nums)
t = datetime.empty(length(years), 0);
for i = 1:length(years)
    month = quarter_nums(i) * 3;
    last_day = eomday(years(i), month);
    t(i) = datetime(years(i), month, last_day);
end
end

function row_idx = findDataRow(T, search_terms)
row_idx = [];
row_labels = lower(string(T{:,1}));
for k = 1:length(search_terms)
    term = lower(char(search_terms{k}));
    idx = find(contains(row_labels, term), 1, 'first');
    if ~isempty(idx)
        row_idx = idx;
        return;
    end
end
end

function data = extractNumericRow(T, row_idx, col_indices)
raw_data = T{row_idx, col_indices};
if iscell(raw_data)
    data = cellfun(@(x) str2double(string(x)), raw_data);
else
    data = double(raw_data);
end
data(isnan(data) & ~ismissing(raw_data)) = NaN;
end