function calculate_gdp_growth_rates(gdpCsvFile, popCsvFile, outDir, baseQuarter, opts)
% Calculate average annualized growth rates for Nominal GDP and Real GDP per capita
% GDP/deflator from quarterly gdpCsvFile; population from annual popCsvFile (2-column: year | population)
% Computes implied inflation and Rule of 70 for Task 2/3

if nargin < 5, opts = struct(); end
if nargin < 4 || strlength(baseQuarter)==0
    baseQuarter = "1990 1Q";
end
if nargin < 3 || strlength(outDir)==0
    outDir = fullfile(pwd, '..', '4_results', 'figures');  % Default from 1_code
end
outDir = char(outDir);
if ~exist(outDir,'dir'), mkdir(outDir); end

dataDir = outDir;
if isfield(opts, 'dataDir') && strlength(string(opts.dataDir)) > 0
    dataDir = char(string(opts.dataDir));
end
if ~exist(dataDir,'dir'), mkdir(dataDir); end

verbose = isfield(opts, 'verbose') && opts.verbose;
logmsg(verbose, '    Calculating GDP per capita growth (base: %s)', baseQuarter);

logmsg(verbose, '      Reading GDP table: %s', gdpCsvFile);
T_gdp = readtable(gdpCsvFile, 'PreserveVariableNames', true);

logmsg(verbose, '      Reading population table: %s', popCsvFile);
T_pop = readtable(popCsvFile, 'PreserveVariableNames', true);

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

% Cut off data after 2024 Q4
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

% Extract annual population - handle both numeric and text columns
if isnumeric(T_pop{2, 1})
    popYears = double(T_pop{2:end, 1});
else
    popYears = str2double(string(T_pop{2:end, 1}));
end

if isnumeric(T_pop{2, 2})
    POP_annual = double(T_pop{2:end, 2});
else
    POP_annual = str2double(string(T_pop{2:end, 2}));
end

% Validate population data
if length(popYears) ~= length(POP_annual) || any(isnan(popYears)) || min(popYears) < 1900
    error('Invalid population data structure in %s. Expected years in col 1, population in col 2.', popCsvFile);
end

% Match to GDP years and interpolate to quarterly
uniqueGdpYears = unique(years_valid);
overlapIdx = ismember(popYears, uniqueGdpYears);
if sum(overlapIdx) < 2
    error('Population years (%d-%d) overlap too little with GDP (%d-%d). Check data range.', min(popYears), max(popYears), min(uniqueGdpYears), max(uniqueGdpYears));
end
popValidYears = popYears(overlapIdx);
popValidData = POP_annual(overlapIdx);

% Create quarterly population (constant within each year, linear interpolation across)
step_t = datetime.empty(0, 0);
step_pop = [];
for yr_idx = 1:length(popValidYears)
    yr = popValidYears(yr_idx);
    yr_pop = popValidData(yr_idx);
    for q = 1:4
        q_date = dateshift(datetime(yr, 1, 1), 'start', 'quarter', q) + calmonths(3) - caldays(1);
        step_t(end+1) = q_date;
        step_pop(end+1) = yr_pop;
    end
end
POP_quarterly = interp1(step_t, step_pop, t, 'linear', 'extrap');

% Extract GDP/deflator data
NGDP = extractNumericRow(T_gdp, iNom, colSel);
DEF = extractNumericRow(T_gdp, iDefl, colSel);

% Ensure all arrays have the same length
min_length = min([length(t), length(NGDP), length(DEF), length(POP_quarterly)]);
t = t(1:min_length);
NGDP = NGDP(1:min_length);
DEF = DEF(1:min_length);
POP_quarterly = POP_quarterly(1:min_length);
canon = canon(1:min_length);

% Update base_idx after truncation
base_idx = find(strcmp(canon, base_canon), 1, 'first');
if isempty(base_idx)
    error('Base quarter %s not found after truncation', base_canon);
end

% Rebase deflator
base_val = DEF(base_idx);
if isnan(base_val) || base_val == 0
    error('Deflator at %s is invalid: %g', base_canon, base_val);
end
DEF_rebased = DEF / base_val * 100;
RGDP = NGDP ./ (DEF_rebased / 100);

% Per capita
NGDP_PC = NGDP ./ POP_quarterly * 1e6;
RGDP_PC = RGDP ./ POP_quarterly * 1e6;

% Quarterly growth rates
n = length(NGDP_PC);
ngdp_pc_growth = NaN(n-1, 1);
rgdp_pc_growth = NaN(n-1, 1);
for i = 2:n
    prev_n = NGDP_PC(i-1); curr_n = NGDP_PC(i);
    if ~isnan(prev_n) && ~isnan(curr_n) && prev_n ~= 0
        ngdp_pc_growth(i-1) = (curr_n - prev_n) / prev_n;
    end
    prev_r = RGDP_PC(i-1); curr_r = RGDP_PC(i);
    if ~isnan(prev_r) && ~isnan(curr_r) && prev_r ~= 0
        rgdp_pc_growth(i-1) = (curr_r - prev_r) / prev_r;
    end
end

% Annualize (×4 quarters) and convert to %
ngdp_pc_growth_ann = ngdp_pc_growth * 4 * 100;
rgdp_pc_growth_ann = rgdp_pc_growth * 4 * 100;

% Ensure consistent dimensions
min_growth_length = min([length(t(2:end)), length(ngdp_pc_growth_ann), length(rgdp_pc_growth_ann)]);
t_growth = t(2:min_growth_length+1);
ngdp_pc_growth_ann = ngdp_pc_growth_ann(1:min_growth_length);
rgdp_pc_growth_ann = rgdp_pc_growth_ann(1:min_growth_length);

% Force column vectors
t_growth = t_growth(:);
ngdp_pc_growth_ann = ngdp_pc_growth_ann(:);
rgdp_pc_growth_ann = rgdp_pc_growth_ann(:);

% Averages over sample
avg_nominal_growth = mean(ngdp_pc_growth_ann, 'omitnan');
avg_real_growth = mean(rgdp_pc_growth_ann, 'omitnan');

% Implied inflation (Task 2b)
implied_inflation = avg_nominal_growth - avg_real_growth;

% Rule of 70 (Task 2a)
years_to_double = 70 / avg_real_growth;
if avg_real_growth <= 0 || isnan(avg_real_growth)
    years_to_double = Inf;
end

% Output results
fprintf('\n=== Task 2: GDP per Capita Growth Analysis ===\n');
fprintf('Sample Period: %s to %s\n', canon{1}, canon{end});
fprintf('Base Quarter for Real GDP: %s (deflator rebased to 100)\n\n', base_canon);
fprintf('Average Annualized Nominal GDP per Capita Growth Rate: %.2f%%\n', avg_nominal_growth);
fprintf('Average Annualized Real GDP per Capita Growth Rate: %.2f%%\n', avg_real_growth);
fprintf('Implied Average Annual Inflation Rate: %.2f%%\n', implied_inflation);
fprintf('Years to Double Living Standards (Rule of 70): %.1f years\n', years_to_double);
fprintf('\nTask 3 Interpretation: The real growth of %.2f%% means living standards double every %.1f years.\n', avg_real_growth, years_to_double);
fprintf('Inflation accounts for %.2f%% of nominal growth, leaving %.2f%% as real per capita increase.\n', implied_inflation, avg_real_growth);

% Save results
results_table = table([avg_nominal_growth; avg_real_growth; implied_inflation; years_to_double], ...
                     'VariableNames', {'Value'}, ...
                     'RowNames', {'Avg Nominal Growth (%)'; 'Avg Real Growth (%)'; 'Implied Inflation (%)'; 'Years to Double'});
writetable(results_table, fullfile(dataDir, 'gdp_growth_summary.csv'));
logmsg(verbose, '      Saved gdp_growth_summary.csv to %s', dataDir);

% Create growth time series table
growth_table = table(t_growth, ngdp_pc_growth_ann, rgdp_pc_growth_ann, ...
                     'VariableNames', {'Quarter', 'Nominal_Ann_Growth_Pct', 'Real_Ann_Growth_Pct'});
writetable(growth_table, fullfile(dataDir, 'gdp_growth_series.csv'));
logmsg(verbose, '      Saved gdp_growth_series.csv to %s', dataDir);

pop_table = table(t, POP_quarterly, 'VariableNames', {'Quarter', 'Population_Persons'});
writetable(pop_table, fullfile(dataDir, 'interpolated_population.csv'));
logmsg(verbose, '      Saved interpolated_population.csv to %s', dataDir);

% Create beautiful plot
createGrowthPlot(t_growth, ngdp_pc_growth_ann, rgdp_pc_growth_ann, outDir, canon{1}, canon{end}, avg_real_growth, years_to_double);
logmsg(verbose, '      Saved gdp_growth_rates.png and gdp_growth_rates.svg to %s', outDir);

fprintf('\nFigures saved to %s\n', outDir);
fprintf('Data tables saved to %s\n', dataDir);
logmsg(verbose, '    GDP growth analysis complete');
end

function createGrowthPlot(t, nominal_ann, real_ann, outDir, start_period, end_period, real_growth, years_double)
% Create beautiful dual-axis growth rate plot
    fig = figure('Color', 'w', 'Position', [100, 100, 1200, 700]);
    
    % Colors
    nominal_color = [0.2, 0.4, 0.8];  % Blue
    real_color = [0.8, 0.2, 0.2];     % Red
    
    % Left axis - Nominal growth
    yyaxis left
    p1 = plot(t, nominal_ann, 'LineWidth', 2.5, 'Color', nominal_color);
    ylabel('Nominal Growth Rate (%)', 'FontSize', 12, 'FontWeight', 'bold', 'Color', nominal_color)
    ax = gca;
    ax.YColor = nominal_color;
    
    % Right axis - Real growth
    yyaxis right
    p2 = plot(t, real_ann, 'LineWidth', 2.5, 'Color', real_color);
    ylabel('Real Growth Rate (%)', 'FontSize', 12, 'FontWeight', 'bold', 'Color', real_color)
    ax = gca;
    ax.YColor = real_color;
    
    % Add zero reference line
    hold on
    yline(0, '--', 'Color', [0.5, 0.5, 0.5], 'LineWidth', 1, 'Alpha', 0.7);
    hold off
    
    % Styling
    xlabel('Year', 'FontSize', 12, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2])
    title(sprintf('Annualized GDP per Capita Growth Rates (%s to %s)\nAverage Real Growth: %.2f%% | Doubling Time: %.1f years', ...
                  start_period, end_period, real_growth, years_double), ...
          'FontSize', 16, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.1])
    
    % Grid and formatting
    grid on
    ax = gca;
    ax.GridColor = [0.85, 0.85, 0.85];
    ax.GridLineStyle = '-';
    ax.GridAlpha = 0.4;
    ax.FontSize = 10;
    ax.FontName = 'Helvetica';
    ax.LineWidth = 1;
    
    % Clean axes
    set(ax, 'Box', 'off', 'TickDir', 'out')
    ax.XColor = [0.3, 0.3, 0.3];
    
    % Format x-axis to show years
    xtickformat('yyyy')
    
    % Legend
    yyaxis left  % Switch back to left to get both lines in legend
    legend([p1, p2], {'Nominal Growth', 'Real Growth'}, ...
           'Location', 'northeast', 'FontSize', 11, 'Box', 'off', ...
           'TextColor', [0.2, 0.2, 0.2])
    
    % White background
    ax.Color = 'w';
    
    % Save plot
    saveas(fig, fullfile(outDir, 'gdp_growth_rates.png'))
    saveas(fig, fullfile(outDir, 'gdp_growth_rates.svg'))
    close(fig)
end

% Helper functions (unchanged)
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