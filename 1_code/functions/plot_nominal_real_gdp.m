function plot_nominal_real_gdp(csvFile, outDir, baseQuarter, opts)
% Rebase GDP deflator to specified quarter and create plots
% Args: csvFile path, output directory, base quarter (e.g., "1990 1Q")

if nargin < 4 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'verbose'), opts.verbose = false; end

if nargin < 3 || strlength(string(baseQuarter))==0
    baseQuarter = "1990 1Q";
end

csvFile = string(csvFile);
outDir  = string(outDir);
baseQuarter = string(baseQuarter);

if ~exist(outDir,"dir"), mkdir(outDir); end
    logmsg(opts.verbose, 'Plotting nominal and real GDP (base quarter %s)', baseQuarter);

T = readtable(csvFile, "PreserveVariableNames", true);

% Extract quarter column headers (skip first column which contains row labels)
varNames = string(T.Properties.VariableNames);
qNames = varNames(2:end);

% Parse all quarter headers into year/quarter components
[~, years, quarter_nums, valid_idx] = parseAllQuarters(qNames);
if sum(valid_idx) == 0
    error('No valid quarter headers found');
end

% Keep only successfully parsed quarters
years_valid = years(valid_idx);
quarter_nums_valid = quarter_nums(valid_idx);

% Convert to datetime objects for proper chronological sorting
t = createQuarterDates(years_valid, quarter_nums_valid);
[t, sort_idx] = sort(t);
colSel = find(valid_idx);
colSel = 1 + colSel(sort_idx); % Adjust indices for data extraction

% Create standardized quarter labels for exact matching
canon = arrayfun(@(yr, qn) sprintf('%d %dQ', yr, qn), ...
                years_valid(sort_idx), quarter_nums_valid(sort_idx), ...
                'UniformOutput', false);

% Find the base quarter for deflator rebasing
[base_year, base_qnum] = parseBaseQuarter(baseQuarter);
base_canon = sprintf('%d %dQ', base_year, base_qnum);
base_idx = find(strcmp(canon, base_canon), 1, 'first');
if isempty(base_idx)
    error('Base quarter %s not found in data range: %s to %s', ...
          base_canon, canon{1}, canon{end});
end

% Locate data rows in the table
iNom = findDataRow(T, ["gdp at current market prices", "nominal gdp", "gdp current"]);
iDefl = findDataRow(T, ["gdp_deflator", "gdp deflator", "deflator"]);
if isempty(iNom) || isempty(iDefl)
    error('Missing Nominal GDP or GDP deflator rows');
end

% Extract time series data
NGDP = extractNumericRow(T, iNom, colSel);
DEF = extractNumericRow(T, iDefl, colSel);

% Rebase deflator so that base quarter = 100
base_val = DEF(base_idx);
if isnan(base_val) || base_val == 0
    error('Deflator at base quarter (%s) is invalid: %g', base_canon, base_val);
end
DEF_rebased = DEF / base_val * 100;
RGDP = NGDP ./ (DEF_rebased / 100);

% Generate plots
createNominalPlot(t, NGDP, outDir);
createRealPlot(t, RGDP, base_canon, outDir);
    logmsg(opts.verbose, 'Saved gdp_nominal_and_log files and gdp_real_and_log files');
end

function [quarters, years, quarter_nums, valid_idx] = parseAllQuarters(qNames)
% Parse quarter names into components, return which ones succeeded
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
% Extract year and quarter number from various naming conventions
    s = char(strtrim(name));
    success = false;
    year_val = NaN;
    quarter_val = NaN;
    
    patterns = { ...
        '^x?(\d{4})([1-4])Q$', ... % x20231Q, 20231Q
        '^(\d{4})Q([1-4])$', ...   % 2023Q1
        '^(\d{4})\s+([1-4])Q$', ... % 2023 1Q
        '^(\d{4})\s*Q([1-4])$', ... % 2023Q1, 2023 Q1
        '^(\d{4})[-_/]Q([1-4])$', ... % 2023-Q1
        '^(\d{4})[-_/]([1-4])Q$' ...  % 2023-1Q
    };
    
    for p = 1:length(patterns)
        tokens = regexp(s, patterns{p}, 'tokens', 'once', 'ignorecase');
        if ~isempty(tokens)
            year_val = str2double(tokens{1});
            quarter_val = str2double(tokens{2});
            if ~isnan(year_val) && ~isnan(quarter_val) && ...
               quarter_val >= 1 && quarter_val <= 4
                success = true;
                return;
            end
        end
    end
end

function [base_year, base_qnum] = parseBaseQuarter(baseQuarter)
% Convert base quarter string to year/quarter numbers
    [year_val, quarter_val, success] = parseQuarterName(baseQuarter);
    if ~success
        error('Could not parse base quarter: %s', baseQuarter);
    end
    base_year = year_val;
    base_qnum = quarter_val;
end

function t = createQuarterDates(years, quarter_nums)
% Convert year/quarter pairs to datetime objects (end of quarter)
    t = datetime.empty(length(years), 0);
    for i = 1:length(years)
        month = quarter_nums(i) * 3;  % Q1->Mar, Q2->Jun, Q3->Sep, Q4->Dec
        t(i) = datetime(years(i), month, eomday(years(i), month));
    end
end

function row_idx = findDataRow(T, search_terms)
% Search for row containing any of the given terms
    row_idx = [];
    row_labels = lower(string(T{:,1}));
    
    for term = search_terms
        idx = find(contains(row_labels, lower(term)), 1, 'first');
        if ~isempty(idx)
            row_idx = idx;
            break;
        end
    end
end

function data = extractNumericRow(T, row_idx, col_indices)
% Extract numeric data from specified table row and columns
    raw_data = T{row_idx, col_indices};
    
    if iscell(raw_data)
        data = cellfun(@convertToNumber, raw_data);
    else
        data = double(raw_data);
    end
end

function num = convertToNumber(val)
% Handle mixed data types when converting to numeric
    if isnumeric(val)
        num = double(val);
    else
        str_val = string(val);
        if ismissing(str_val) || str_val == ""
            num = NaN;
        else
            num = str2double(str_val);
        end
    end
end

function createNominalPlot(t, NGDP, outDir)
% Plot nominal GDP levels and log values on dual y-axes with beautiful styling
    fig = figure('Color', 'w', 'Position', [100, 100, 1000, 600]);
    
    % Set up colors
    blue_color = [0.2, 0.4, 0.8];
    red_color = [0.8, 0.2, 0.2];
    
    yyaxis left
    p1 = plot(t, NGDP, 'LineWidth', 2.5, 'Color', blue_color);
    ylabel('Nominal GDP', 'FontSize', 12, 'FontWeight', 'bold', 'Color', blue_color)
    ytickformat('%,.0f')
    ax = gca;
    ax.YColor = blue_color;
    
    yyaxis right
    p2 = plot(t, log(NGDP), 'LineWidth', 2.5, 'LineStyle', '--', 'Color', red_color);
    ylabel('log(Nominal GDP)', 'FontSize', 12, 'FontWeight', 'bold', 'Color', red_color)
    ytickformat('%.2f')
    ax = gca;
    ax.YColor = red_color;
    
    % Styling
    xlabel('Quarter', 'FontSize', 12, 'FontWeight', 'bold')
    title('Nominal GDP and its Natural Logarithm', 'FontSize', 16, 'FontWeight', 'bold')
    
    % Grid and axis formatting
    grid on
    ax = gca;
    ax.GridColor = [0.9, 0.9, 0.9];
    ax.GridLineStyle = '-';
    ax.GridAlpha = 0.6;
    ax.MinorGridAlpha = 0.3;
    ax.FontSize = 10;
    ax.FontName = 'Arial';
    ax.LineWidth = 1.2;
    
    % Remove box and improve appearance
    set(ax, 'Box', 'off', 'TickDir', 'out')
    ax.XAxis.FontSize = 10;
    ax.YAxis(1).Exponent = 0;
    ax.YAxis(2).Exponent = 0;
    
    % Add legend
    legend([p1, p2], {'Nominal GDP', 'log(Nominal GDP)'}, ...
           'Location', 'northwest', 'FontSize', 11, ...
           'Box', 'off', 'Color', 'none')
    
    % Improve margins
    ax.Position(3) = ax.Position(3) * 0.85; % Reduce width slightly for better proportions
    
    % Format x-axis
    xtickformat('yyyy-QQ')
    
    saveas(fig, fullfile(outDir, 'gdp_nominal_and_log.svg'))
    saveas(fig, fullfile(outDir, 'gdp_nominal_and_log.png'), 'png')
    close(fig)
end

function createRealPlot(t, RGDP, base_canon, outDir)
% Plot real GDP levels and log values on dual y-axes with beautiful styling
    fig = figure('Color', 'w', 'Position', [100, 100, 1000, 600]);
    
    % Set up colors
    green_color = [0.2, 0.7, 0.3];
    orange_color = [0.9, 0.4, 0.1];
    
    yyaxis left
    p1 = plot(t, RGDP, 'LineWidth', 2.5, 'Color', green_color);
    ylabel(sprintf('Real GDP (deflator base = 100 at %s)', base_canon), ...
           'FontSize', 12, 'FontWeight', 'bold', 'Color', green_color)
    ytickformat('%,.0f')
    ax = gca;
    ax.YColor = green_color;
    
    yyaxis right
    p2 = plot(t, log(RGDP), 'LineWidth', 2.5, 'LineStyle', '--', 'Color', orange_color);
    ylabel('log(Real GDP)', 'FontSize', 12, 'FontWeight', 'bold', 'Color', orange_color)
    ytickformat('%.2f')
    ax = gca;
    ax.YColor = orange_color;
    
    % Styling
    xlabel('Quarter', 'FontSize', 12, 'FontWeight', 'bold')
    title('Real GDP and its Natural Logarithm', 'FontSize', 16, 'FontWeight', 'bold')
    
    % Grid and axis formatting
    grid on
    ax = gca;
    ax.GridColor = [0.9, 0.9, 0.9];
    ax.GridLineStyle = '-';
    ax.GridAlpha = 0.6;
    ax.MinorGridAlpha = 0.3;
    ax.FontSize = 10;
    ax.FontName = 'Arial';
    ax.LineWidth = 1.2;
    
    % Remove box and improve appearance
    set(ax, 'Box', 'off', 'TickDir', 'out')
    ax.XAxis.FontSize = 10;
    ax.YAxis(1).Exponent = 0;
    ax.YAxis(2).Exponent = 0;
    
    % Add legend
    legend([p1, p2], {'Real GDP', 'log(Real GDP)'}, ...
           'Location', 'northwest', 'FontSize', 11, ...
           'Box', 'off', 'Color', 'none')
    
    % Improve margins
    ax.Position(3) = ax.Position(3) * 0.85; % Reduce width slightly for better proportions
    
    % Format x-axis
    xtickformat('yyyy-QQ')
    
    saveas(fig, fullfile(outDir, 'gdp_real_and_log.svg'))
    saveas(fig, fullfile(outDir, 'gdp_real_and_log.png'), 'png')
    close(fig)
end