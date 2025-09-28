function summary = process_raw_data(opts)
%PROCESS_RAW_DATA Clean raw CSVs and hydrate the processed_data directory.
%   process_raw_data() uses sensible defaults and verbosity off.
%   process_raw_data(struct('verbose',true)) enables status messages.
%   summary = process_raw_data(...) returns paths of generated artefacts.

arguments
    opts.verbose (1,1) logical = false
    opts.force   (1,1) logical = false
end

thisDir  = fileparts(mfilename('fullpath'));
rawDir   = fullfile(thisDir, '..', '..', '2_data', 'raw_data');
procDir  = fullfile(thisDir, '..', '..', '2_data', 'processed_data');

if ~exist(procDir, 'dir')
    mkdir(procDir);
end

logmsg(opts.verbose, 'Processing raw data files.');

summary = struct();

%% GDP data -------------------------------------------------------------
gdpFileRaw  = fullfile(rawDir,  'gdp.csv');
gdpFileProc = fullfile(procDir, 'gdp_cleaned.csv');

if opts.force || ~exist(gdpFileProc, 'file')
    logmsg(opts.verbose, 'Cleaning GDP dataset: %s', gdpFileRaw);
    T_gdp = readtable(gdpFileRaw, 'PreserveVariableNames', true);

    % Drop rows that are entirely empty (except for the first column label)
    emptyRows = all(ismissing(T_gdp{:, 2:end}) | T_gdp{:, 2:end} == "", 2);
    T_gdp(emptyRows, :) = [];

    % Trim whitespace from series labels
    if iscellstr(T_gdp{:,1}) || isstring(T_gdp{:,1})
        T_gdp{:,1} = strtrim(string(T_gdp{:,1}));
    end

    writetable(T_gdp, gdpFileProc);
    summary.gdp = gdpFileProc;
    logmsg(opts.verbose, 'Saved cleaned GDP table to %s', gdpFileProc);
else
    logmsg(opts.verbose, 'GDP dataset already processed (use force=true to refresh).');
    summary.gdp = gdpFileProc;
end

%% Population & employment data ----------------------------------------
popFileRaw  = fullfile(rawDir,  'sg_annual_population_employment_1990_2025.csv');
popFileProc = fullfile(procDir, 'population_employment_cleaned.csv');

if opts.force || ~exist(popFileProc, 'file')
    logmsg(opts.verbose, 'Cleaning population/employment dataset: %s', popFileRaw);
    T_pop = readtable(popFileRaw, 'PreserveVariableNames', true);

    % Remove rows without a valid year entry
    yearCol = T_pop{:,1};
    if iscell(yearCol) || isstring(yearCol)
        yearVals = str2double(string(yearCol));
    else
        yearVals = double(yearCol);
    end
    validRows = ~isnan(yearVals);
    T_pop = T_pop(validRows, :);

    writetable(T_pop, popFileProc);
    summary.population = popFileProc;
    logmsg(opts.verbose, 'Saved cleaned population table to %s', popFileProc);
else
    logmsg(opts.verbose, 'Population dataset already processed (use force=true to refresh).');
    summary.population = popFileProc;
end

%% Deflator (optional auxiliary file) ----------------------------------
deflFileRaw  = fullfile(rawDir,  'gdp_deflator_base_2015.csv');
deflFileProc = fullfile(procDir, 'gdp_deflator_cleaned.csv');

if exist(deflFileRaw, 'file') && (opts.force || ~exist(deflFileProc, 'file'))
    logmsg(opts.verbose, 'Cleaning GDP deflator dataset: %s', deflFileRaw);
    T_defl = readtable(deflFileRaw, 'PreserveVariableNames', true);

    % Find the header row labelled "Data Series" and keep from there on
    dataStartRow = find(contains(string(T_defl{:,1}), 'Data Series', 'IgnoreCase', true), 1);
    if ~isempty(dataStartRow)
        T_defl_clean = T_defl(dataStartRow:end, :);
    else
        T_defl_clean = T_defl;
    end

    writetable(T_defl_clean, deflFileProc);
    summary.deflator = deflFileProc;
    logmsg(opts.verbose, 'Saved cleaned deflator table to %s', deflFileProc);
elseif exist(deflFileRaw, 'file')
    logmsg(opts.verbose, 'Deflator dataset already processed (use force=true to refresh).');
    summary.deflator = deflFileProc;
end

logmsg(opts.verbose, 'Raw data processing complete (output dir: %s).', procDir);

end