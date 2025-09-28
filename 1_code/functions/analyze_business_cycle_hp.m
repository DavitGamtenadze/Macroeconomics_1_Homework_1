function [t, cycles, stats, hfig] = analyze_business_cycle_hp(csvFile, baseQuarter, opts)
% HP cycles (λ=1600) with deflator rebased to baseQuarter.
% Legend shows ONLY: Real GDP, Real Consumption, Real Investment.
% White background, clear shocks; no files saved.

if nargin < 3, opts = struct(); end
if nargin < 2 || strlength(baseQuarter)==0
    baseQuarter = "1990 1Q";
end

verbose = isfield(opts, 'verbose') && opts.verbose;
logmsg(verbose, '    Running HP-cycle decomposition (base: %s)', baseQuarter);

% ----- Read and parse quarters -----
T = readtable(csvFile, "PreserveVariableNames", true);
logmsg(verbose, '      Read GDP table: %s', csvFile);
varNames = string(T.Properties.VariableNames);
qNames   = varNames(2:end);
[~, years, qnums, ok] = parseAllQuarters(qNames);
assert(any(ok), "No valid quarter headers in %s", csvFile);

years_valid = years(ok);
qnums_valid = qnums(ok);
t = createQuarterDates(years_valid, qnums_valid);
[t, order] = sort(t);
colSel = 1 + find(ok);
colSel = colSel(order);

% Canonical labels for base matching
canon = arrayfun(@(yr, qn) sprintf('%d %dQ', yr, qn), ...
                 years_valid(order), qnums_valid(order), ...
                 'UniformOutput', false);
[by, bq]  = parseBaseQuarter(baseQuarter);
base_tag  = sprintf('%d %dQ', by, bq);
base_idx  = find(strcmp(canon, base_tag), 1, 'first');
assert(~isempty(base_idx), 'Base quarter %s not found (range: %s to %s)', base_tag, canon{1}, canon{end});

% ----- Find rows (robust) -----
rows = lower(string(T{:,1}));
idxDefl = firstMatch(rows, [
    "gdp deflator"
    "gdp_deflator"
    "deflator"
    "implicit price deflator"
    "gdp implicit price"
]);
idxNGDP = firstMatch(rows, [
    "gdp at current market prices"
    "nominal gdp"
    "gdp current"
    "gdp at current"
    "gross domestic product, current"
]);
idxC_nom = firstMatch(rows, [
    "private consumption expenditure"
    "consumption expenditure of households"
    "personal consumption expenditure"
    "consumption, private"
]);
idxGFCF_nom = firstMatch(rows, [
    "gross fixed capital formation"
    "fixed investment"
    "gfcf"
]);
idxInv_nom = firstMatch(rows, [
    "changes in inventories"
    "inventory change"
    "change in stocks"
]);

assert(~isempty(idxDefl), 'GDP deflator row not found');
assert(~isempty(idxNGDP), 'Nominal GDP row not found');
assert(~isempty(idxC_nom), 'Nominal private consumption row not found');
assert(~isempty(idxGFCF_nom), 'Nominal GFCF row not found');

% ----- Numeric extraction -----
toNum = @(v) convert_to_numeric(v);
DEF  = toNum(T{idxDefl,  colSel});
NGDP = toNum(T{idxNGDP,  colSel});
Cnom = toNum(T{idxC_nom, colSel});
GFCF = toNum(T{idxGFCF_nom, colSel});
INV  = zeros(size(GFCF));
if ~isempty(idxInv_nom)
    INV = toNum(T{idxInv_nom, colSel});
end

% ----- Rebase deflator and construct real series -----
base_val = DEF(base_idx);
assert(~isnan(base_val) && base_val ~= 0, 'Invalid deflator at %s: %g', base_tag, base_val);
DEF_rebased = DEF / base_val * 100;

RGDP = NGDP ./ max(DEF_rebased, eps) * 100;
RC   = Cnom ./ max(DEF_rebased, eps) * 100;
RI   = (GFCF + INV) ./ max(DEF_rebased, eps) * 100;

% Align
RGDP = RGDP(:); RC = RC(:); RI = RI(:);
valid = ~isnan(RGDP) & ~isnan(RC) & ~isnan(RI) & ~isnan(DEF_rebased(:));
RGDP = RGDP(valid); RC = RC(valid); RI = RI(valid); t = t(valid);
logmsg(verbose, '      Filtered to %d valid observations', numel(t));

% ----- HP filter on logs -----
lambda = 1600;
[y_tr, y_cyc] = hp_filter(log(max(RGDP, eps)), lambda);
[c_tr, c_cyc] = hp_filter(log(max(RC,   eps)), lambda);
[i_tr, i_cyc] = hp_filter(log(max(RI,   eps)), lambda);

gdp_cycle_pct = 100 * y_cyc;
c_cycle_pct   = 100 * c_cyc;
i_cycle_pct   = 100 * i_cyc;

% ----- Stats (Task 3.2) -----
sd_gdp = std(gdp_cycle_pct, 'omitnan');
sd_c   = std(c_cycle_pct,   'omitnan');
sd_i   = std(i_cycle_pct,   'omitnan');
corr_c_y = corr(c_cycle_pct, gdp_cycle_pct, 'rows','pairwise');
corr_i_y = corr(i_cycle_pct, gdp_cycle_pct, 'rows','pairwise');

stats = table( ...
    ["GDP"; "Consumption"; "Investment"], ...
    round([sd_gdp; sd_c; sd_i], 2), ...
    round([1; corr_c_y; corr_i_y], 2), ...
    'VariableNames', {'Series','StdDev_Cycle_Pct','Corr_with_GDP_Cycle'});

% ----- Outputs -----
cycles = struct();
cycles.gdp_pct = gdp_cycle_pct(:);
cycles.c_pct   = c_cycle_pct(:);
cycles.i_pct   = i_cycle_pct(:);
cycles.gdp_trend = y_tr(:);
cycles.c_trend   = c_tr(:);
cycles.i_trend   = i_tr(:);
logmsg(verbose, '      Computed HP cycles (sigma_GDP=%.2f)', sd_gdp);

% ===================== Plot (white, clear shocks) =====================
use_smoothing = true;
y_plot = use_smoothing * sg_smooth(gdp_cycle_pct, 5, 2) + ~use_smoothing * gdp_cycle_pct;
c_plot = use_smoothing * sg_smooth(c_cycle_pct,   5, 2) + ~use_smoothing * c_cycle_pct;
i_plot = use_smoothing * sg_smooth(i_cycle_pct,   7, 2) + ~use_smoothing * i_cycle_pct;

sd_y = sd_gdp;
thr1 = 1.0 * sd_y;
thr2 = 2.0 * sd_y;

hfig = figure('Color','w','Position',[80 120 1400 650]); hold on;

% Context bands: ±2σ (darker), ±1σ (lighter)
fill([t(1) t(end) t(end) t(1)], [thr2 thr2 -thr2 -thr2], [0.93 0.93 0.93], 'EdgeColor','none');
fill([t(1) t(end) t(end) t(1)], [thr1 thr1 -thr1 -thr1], [0.96 0.96 0.96], 'EdgeColor','none');

% Shock fills (no legend entries are added)
above2 = gdp_cycle_pct >=  thr2;
below2 = gdp_cycle_pct <= -thr2;
fill_mask_series(t, gdp_cycle_pct, above2, [0.95 0.35 0.35], 0.30); % positive shocks
fill_mask_series(t, gdp_cycle_pct, below2, [0.35 0.45 0.95], 0.30); % negative shocks

% Series lines (ONLY these 3 will be in legend)
hGDP = plot(t, y_plot, 'Color',[0.05 0.05 0.05],  'LineWidth', 2.8, 'DisplayName','Real GDP');
hC   = plot(t, c_plot, 'Color',[0.00 0.45 0.85],  'LineWidth', 2.2, 'DisplayName','Real Consumption');
hI   = plot(t, i_plot, 'Color',[0.85 0.10 0.10],  'LineWidth', 2.0, 'DisplayName','Real Investment');

% Zero line (no legend)
yline(0, ':', 'Color',[0.35 0.35 0.35], 'LineWidth', 1.1, 'HandleVisibility','off');

% Add faint raw GDP as context (no legend)
plot(t, gdp_cycle_pct, 'Color',[0.2 0.2 0.2 0.35], 'LineWidth', 1.0, 'HandleVisibility','off');

% Peak/trough markers (no legend)
[pkv, pkx] = findpeaks(gdp_cycle_pct, 'MinPeakProminence', 0.8*sd_y);
[tv, tx]   = findpeaks(-gdp_cycle_pct, 'MinPeakProminence', 0.8*sd_y); tv = -tv;
scatter(t(pkx), pkv, 32, [0 0 0], 'filled', 'MarkerEdgeColor','w', 'HandleVisibility','off');
scatter(t(tx),  tv,  32, [0 0 0], 'filled', 'MarkerEdgeColor','w', 'HandleVisibility','off');

% Axes
grid on; box off;
ax = gca;
ax.Color     = 'w';
ax.GridColor = [0.75 0.75 0.75];
ax.GridAlpha = 0.35;
ax.XColor    = [0.1 0.1 0.1];
ax.YColor    = [0.1 0.1 0.1];
ax.LineWidth = 0.9;

xlabel('Quarter', 'Color','k', 'FontSize', 11);
ylabel('% deviation from trend', 'Color','k', 'FontSize', 11);

miny = floor(min([gdp_cycle_pct; c_cycle_pct; i_plot; -2.2*sd_y]));
maxy = ceil( max([gdp_cycle_pct; c_cycle_pct; i_plot;  2.2*sd_y]));
miny = min(miny, -15); maxy = max(maxy, 15);
ylim([miny maxy]);
yticks(unique(round(linspace(miny, maxy, 11))));
datetick('x', 'yyyy', 'keeplimits');

% Title + legend (ONLY three entries)
span_txt = sprintf('%s to %s', datestr(t(1),'yyyy-Qq'), datestr(t(end),'yyyy-Qq'));
title(sprintf('HP Cycles (λ=1600), Deflator rebased: %s = 100   |   %s', base_tag, span_txt), ...
      'FontWeight','bold', 'Color','k', 'FontSize', 14);
legend([hGDP hC hI], 'Location','northwest');

% Stats footer
txt = sprintf('Std dev (%%):  GDP %.2f | C %.2f | I %.2f     Corr(C,Y)=%.2f, Corr(I,Y)=%.2f     (σ_Y=%.2f)', ...
    sd_gdp, sd_c, sd_i, corr_c_y, corr_i_y, sd_gdp);
annotation('textbox', [0.50 0.015 0.48 0.06], 'String', txt, ...
    'HorizontalAlignment','right', 'EdgeColor','none', 'Color',[0.15 0.15 0.15]);

end

% ===================== Helpers =====================

function v = convert_to_numeric(vals)
    if isnumeric(vals), v = double(vals); return; end
    if iscell(vals),    v = str2double(string(vals)); return; end
    v = str2double(string(vals));
end

function idx = firstMatch(rows, patterns)
idx = [];
for k = 1:numel(patterns)
    hit = find(contains(rows, lower(patterns(k))), 1, 'first');
    if ~isempty(hit), idx = hit; return; end
end
end

function [trend, cycle] = hp_filter(y, lambda)
y = y(:);
T = length(y);
if T < 6, trend = y; cycle = y - trend; return; end
I = speye(T);
D = spdiags([ones(T,1) -2*ones(T,1) ones(T,1)], 0:2, T-2, T);
A = I + lambda * (D' * D);
trend = A \ y;
cycle = y - trend;
end

function [quarters, years, quarter_nums, valid_idx] = parseAllQuarters(qNames)
n = length(qNames);
quarters = strings(n, 1);
years = zeros(n, 1);
quarter_nums = zeros(n, 1);
valid_idx = false(n, 1);
for i = 1:n
    [yr, qn, ok] = parseQuarterName(qNames(i));
    if ok
        quarters(i) = qNames(i);
        years(i) = yr;
        quarter_nums(i) = qn;
        valid_idx(i) = true;
    end
end
end

function [year_val, quarter_val, success] = parseQuarterName(name)
s = char(strtrim(name));
success = false; year_val = NaN; quarter_val = NaN;
pats = {'x?(\d{4})([1-4])Q$','^(\d{4})Q([1-4])$','^(\d{4})\s*([1-4])Q$','^(\d{4})\s*Q([1-4])$','^(\d{4})[-_/ ]([1-4])Q$'};
for k = 1:numel(pats)
    tok = regexp(s, pats{k}, 'tokens', 'once');
    if ~isempty(tok)
        year_val    = str2double(tok{1});
        quarter_val = str2double(tok{2});
        if quarter_val>=1 && quarter_val<=4 && ~isnan(year_val)
            success = true; return;
        end
    end
end
end

function [base_year, base_qnum] = parseBaseQuarter(baseQuarter)
[year_val, quarter_val, ok] = parseQuarterName(baseQuarter);
if ~ok, error('Invalid base quarter: %s', baseQuarter); end
base_year = year_val; base_qnum = quarter_val;
end

function t = createQuarterDates(years, quarter_nums)
t = datetime.empty(length(years), 0);
for i = 1:length(years)
    m = quarter_nums(i) * 3;
    t(i) = datetime(years(i), m, eomday(years(i), m));
end
end

function y_s = sg_smooth(y, window, poly)
y = y(:);
n = numel(y);
window = max(3, 2*floor(window/2)+1); % odd
if exist('sgolayfilt','file') == 2
    y_s = sgolayfilt(y, poly, window);
else
    k = (window-1)/2; y_s = y;
    for i = 1:n
        lo = max(1, i-k); hi = min(n, i+k);
        y_s(i) = mean(y(lo:hi), 'omitnan');
    end
end
end

function fill_mask_series(t, y, mask, color, alpha)
if ~any(mask), return; end
d = diff([false; mask(:); false]);
s = find(d==1); e = find(d==-1)-1;
for k = 1:numel(s)
    idx = s(k):e(k);
    patch([t(idx) fliplr(t(idx))], [zeros(size(idx)) fliplr(y(idx)')], ...
          color, 'EdgeColor','none', 'FaceAlpha', alpha, 'HandleVisibility','off');
end
end