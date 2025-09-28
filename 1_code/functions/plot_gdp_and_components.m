function plot_gdp_and_components(csvFile, outDir, opts)
% plot_gdp_and_components
% Reads quarterly GDP table and makes two plots:
% (1) Total GDP as a line
% (2) Components (C, I, G, NX) as stacked areas (NX filled red)
%
% CSV layout:
%   – Column A: series names
%   – Columns B..end: quarters (e.g., 2025 2Q, 2025Q2, x20252Q …)

if nargin < 3 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'verbose'), opts.verbose = false; end

csvFile = string(csvFile);
outDir  = string(outDir);

if ~exist(outDir,"dir"), mkdir(outDir); end
logmsg(opts.verbose, 'Plotting GDP components from %s', csvFile);

T = readtable(csvFile,"PreserveVariableNames",true);
varNames = string(T.Properties.VariableNames);
qNames   = varNames(2:end);

% ----- parse time -----
[t, ok] = arrayfun(@(s) parseQuarterName(s), qNames);
if ~all(ok)
    error("Could not parse some quarter names: %s", strjoin(qNames(~ok),", "));
end

% sort by time
[t, order] = sort(t);
colSel = 1 + order;    % columns to extract from T

% ----- locate series rows -----
rowIdx = @(p) find(contains(lower(string(T{:,1})), lower(p), "IgnoreCase",true), 1);

idxGDP   = rowIdx("gdp at current market prices");
idxC     = rowIdx("private consumption expenditure");
idxG     = rowIdx("government consumption expenditure");
idxGFCF  = rowIdx("gross fixed capital formation");
idxInv   = rowIdx("changes in inventories");
idxX     = rowIdx("exports of goods");
idxM     = rowIdx("imports of goods");
idxNXrow = rowIdx("net exports of goods");    % prefer direct NX row if present
if isempty(idxNXrow)
    idxNXrow = rowIdx("net exports");
end

assert(~isempty(idxGDP) && ~isempty(idxC) && ~isempty(idxG) && ...
       ~isempty(idxGFCF) && ~isempty(idxInv) && ...
       (~isempty(idxNXrow) || (~isempty(idxX) && ~isempty(idxM))), ...
       "Required series missing: ensure GDP, C, G, GFCF, inventories, and Net Exports (or Exports & Imports) exist.");

numRow = @(r) toNumericVector(T{r,colSel});

GDP = numRow(idxGDP);
C   = numRow(idxC);
G   = numRow(idxG);
I   = numRow(idxGFCF) + numRow(idxInv);

% Net Exports: use row directly if available; else compute X - M
if ~isempty(idxNXrow)
    NX = numRow(idxNXrow);
else
    NX = numRow(idxX) - numRow(idxM);
end

% ===== (1) total GDP line =====
createTotalGDPPlot(t, GDP, outDir);
logmsg(opts.verbose, 'Saved gdp_total.png and gdp_total.svg');

% ===== (2) components stacked (C, I, G, NX filled) =====
createComponentsPlot(t, C, I, G, NX, outDir);
logmsg(opts.verbose, 'Saved gdp_components.png and gdp_components.svg');

end

function createTotalGDPPlot(t, GDP, outDir)
% Create clean, professional GDP line plot
    fig = figure('Color', 'w', 'Position', [100, 100, 1000, 600]);
    
    % Clean blue color
    gdp_color = [0.1, 0.3, 0.7];
    
    % Simple, clean line without markers
    plot(t, GDP, 'LineWidth', 2.5, 'Color', gdp_color);
    
    % Clean styling
    xlabel('Year', 'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2])
    ylabel('GDP (Billion USD)', 'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2])
    title('Gross Domestic Product', 'FontSize', 18, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.1])
    
    % Clean grid
    grid on
    ax = gca;
    ax.GridColor = [0.85, 0.85, 0.85];
    ax.GridLineStyle = '-';
    ax.GridAlpha = 0.4;
    ax.FontSize = 11;
    ax.FontName = 'Helvetica';
    
    % Clean axes
    set(ax, 'Box', 'off', 'TickDir', 'out')
    ax.XColor = [0.3, 0.3, 0.3];
    ax.YColor = [0.3, 0.3, 0.3];
    ax.LineWidth = 1;
    
    % Format axes
    ax.YAxis.Exponent = 0;
    ytickformat('%,.0f');
    xtickformat('yyyy');
    
    % White background
    ax.Color = 'w';
    
    if ishghandle(fig)
        saveas(fig, fullfile(outDir, 'gdp_total.png'))
    end
    if ishghandle(fig)
        saveas(fig, fullfile(outDir, 'gdp_total.svg'))
    end
    if ishghandle(fig)
        close(fig)
    end
end

function createComponentsPlot(t, C, I, G, NX, outDir)
% Create clean stacked components plot with proper ordering
    fig = figure('Color', 'w', 'Position', [100, 100, 1000, 600]);
    
    % Clean, distinct colors - ordered from bottom to top
    colors = [
        0.4, 0.6, 0.9;   % Light blue for Consumption (bottom/largest)
        0.9, 0.5, 0.2;   % Orange for Investment  
        0.3, 0.7, 0.4;   % Green for Government
        0.8, 0.3, 0.3    % Red for Net Exports (top)
    ];
    
    % Handle negative net exports properly
    nxPos = max(NX, 0);
    
    % Stack in logical order: C (base), then I, then G, then positive NX
    A = [C(:), I(:), G(:), nxPos(:)];
    
    % Create clean stacked areas
    h = area(t, A, 'LineStyle', 'none', 'EdgeColor', 'w', 'LineWidth', 0.5);
    hold on
    
    % Apply colors
    for i = 1:numel(h)
        set(h(i), 'FaceColor', colors(i, :), 'FaceAlpha', 0.85);
    end
    
    % Handle negative NX if present
    if any(NX < 0)
        negNX = min(NX, 0);
        aNeg = area(t, negNX, 'LineStyle', 'none', 'BaseValue', 0);
        set(aNeg, 'FaceColor', colors(4, :), 'FaceAlpha', 0.6);
    end
    
    % Clean styling
    xlabel('Year', 'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2])
    ylabel('GDP Components (Billion USD)', 'FontSize', 13, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2])
    title('GDP Components (Expenditure Approach)', 'FontSize', 18, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.1])
    
    % Clean legend - order matches visual stack from bottom to top
    legend({'Consumption (C)', 'Investment (I)', 'Government (G)', 'Net Exports (NX)'}, ...
           'Location', 'northwest', 'FontSize', 11, 'Box', 'off', ...
           'TextColor', [0.2, 0.2, 0.2])
    
    % Clean grid and axes
    grid on
    ax = gca;
    ax.GridColor = [0.85, 0.85, 0.85];
    ax.GridLineStyle = '-';
    ax.GridAlpha = 0.4;
    ax.FontSize = 11;
    ax.FontName = 'Helvetica';
    
    set(ax, 'Box', 'off', 'TickDir', 'out')
    ax.XColor = [0.3, 0.3, 0.3];
    ax.YColor = [0.3, 0.3, 0.3];
    ax.LineWidth = 1;
    
    % Format axes
    ax.YAxis.Exponent = 0;
    ytickformat('%,.0f');
    xtickformat('yyyy');
    
    % White background
    ax.Color = 'w';
    
    hold off
    
    if ishghandle(fig)
        saveas(fig, fullfile(outDir, 'gdp_components.png'))
    end
    if ishghandle(fig)
        saveas(fig, fullfile(outDir, 'gdp_components.svg'))
    end
    if ishghandle(fig)
        close(fig)
    end
end

% ---------------- helper functions ----------------
function v = toNumericVector(vals)
    if iscell(vals)
        v = cellfun(@(x) str2double(string(x)), vals);
    else
        v = double(vals);
        if any(isnan(v))
            v = str2double(string(vals));
        end
    end
end

function [dt, ok] = parseQuarterName(name)
    s = char(strtrim(name));
    ok = false; dt = NaT;
    pats = { ...
        'x?(\d{4})([1-4])Q$', ...
        '^(\d{4})Q([1-4])$', ...
        '^(\d{4})\s*([1-4])Q$', ...
        '^(\d{4})\s*Q([1-4])$', ...
        '^(\d{4})[-_/ ]([1-4])Q$' };
    for k = 1:numel(pats)
        tok = regexp(s, pats{k},'tokens','once');
        if ~isempty(tok)
            yr = str2double(tok{1});
            q  = str2double(tok{2});
            dt = dateshift(datetime(yr,1,1),"start","quarter",q) + calmonths(3) - days(1);
            ok = true;
            return
        end
    end
end