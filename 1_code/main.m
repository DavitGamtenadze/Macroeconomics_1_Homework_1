%% MAIN.M - Singapore GDP Macroeconomic Analysis
% Complete analysis of Singapore's GDP data covering:
% - Data processing and validation
% - GDP components visualization
% - Real vs Nominal GDP analysis  
% - Growth rate calculations and trends
% - Labor productivity analysis
% - Business cycle analysis using HP filter
%
% Author: Davit Gamtenadze
% Course: Macroeconomics 1 - Homework 1
% Date: September 2025

clear; close all; clc;
fprintf('=============================================================\n');
fprintf('    Singapore GDP Macroecnomic Analysis\n');
fprintf('=============================================================\n\n');

%% Setup and Configuration
thisDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisDir, 'functions'));

% Define paths
rawDataDir = fullfile(thisDir, '..', '2_data', 'raw_data');
procDataDir = fullfile(thisDir, '..', '2_data', 'processed_data');
resultsDir = fullfile(thisDir, '..', '4_results', 'figures');
tablesDir = fullfile(thisDir, '..', '4_results', 'tables');

% Create directories if they don't exist
if ~exist(procDataDir, 'dir'), mkdir(procDataDir); end
if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end
if ~exist(tablesDir, 'dir'), mkdir(tablesDir); end

% Configuration
BASE_QUARTER = "1990 1Q";  % Base quarter for deflator rebasing
ANALYSIS_TITLE = 'Singapore GDP Analysis (1990-2024)';

fprintf('Preparing processed data directory...\n');
process_raw_data('verbose', true);

% File paths - favour processed artefacts, gracefully fall back to raw
gdpFile = fullfile(procDataDir, 'gdp_cleaned.csv');
if ~exist(gdpFile, 'file')
    gdpFile = fullfile(rawDataDir, 'gdp.csv');
end

popFile = fullfile(procDataDir, 'population_employment_cleaned.csv');
if ~exist(popFile, 'file')
    popFile = fullfile(rawDataDir, 'sg_annual_population_employment_1990_2025.csv');
end

fprintf('Configuration:\n');
fprintf('  Base Quarter: %s\n', BASE_QUARTER);
fprintf('  GDP Data: %s\n', gdpFile);
fprintf('  Population Data: %s\n', popFile);
fprintf('  Results Directory: %s\n\n', resultsDir);

%% TASK 1: Data Processing and GDP Components Analysis
fprintf('TASK 1: Processing data and analyzing GDP components...\n');
fprintf('--------------------------------------------------------\n');

% Create GDP total and components plots
fprintf('  Creating GDP visualization plots...\n');
plot_gdp_and_components(gdpFile, resultsDir, struct('verbose', true));

% Create nominal vs real GDP comparison plots  
fprintf('  Creating nominal vs real GDP plots...\n');
plot_nominal_real_gdp(gdpFile, resultsDir, BASE_QUARTER, struct('verbose', true));

fprintf('  GDP components analysis completed.\n\n');

%% TASK 2: GDP Growth Rate Analysis
fprintf('TASK 2: Calculating GDP growth rates and per capita analysis...\n');
fprintf('----------------------------------------------------------------\n');

fprintf('  Calculating GDP per capita growth rates...\n');
calculate_gdp_growth_rates(gdpFile, popFile, resultsDir, BASE_QUARTER, struct('verbose', true, 'dataDir', procDataDir));

fprintf('  GDP growth analysis completed.\n\n');

%% TASK 2.4-2.6: Labor Productivity Analysis  
fprintf('TASK 2.4-2.6: Labor productivity analysis...\n');
fprintf('----------------------------------------------\n');

fprintf('  Calculating labor productivity trends...\n');
calculate_labor_productivity(gdpFile, popFile, resultsDir, BASE_QUARTER, struct('verbose', true, 'dataDir', procDataDir));

fprintf('  Labor productivity analysis completed.\n\n');

%% TASK 3: Business Cycle Analysis
fprintf('TASK 3: Business cycle analysis using HP filter...\n');
fprintf('---------------------------------------------------\n');

fprintf('  Running HP filter analysis (λ=1600)...\n');
try
    [t, cycles, stats, hfig] = analyze_business_cycle_hp(gdpFile, BASE_QUARTER, struct('verbose', true));
    
    % Save business cycle statistics
    writetable(stats, fullfile(tablesDir, 'business_cycle_stats.csv'));
    
    % Save the HP cycles data
    cycles_table = table(t(:), cycles.gdp_pct(:), cycles.c_pct(:), cycles.i_pct(:), ...
        'VariableNames', {'Quarter', 'GDP_Cycle_Pct', 'Consumption_Cycle_Pct', 'Investment_Cycle_Pct'});
    writetable(cycles_table, fullfile(resultsDir, 'hp_cycles_series.csv'));
    
    % Save the figure
    saveas(hfig, fullfile(resultsDir, 'business_cycle.svg'));
    saveas(hfig, fullfile(resultsDir, 'hp_cycles_rebased.png'));
    print(hfig, fullfile(resultsDir, 'hp_cycles_rebased_hires.png'), '-dpng', '-r300');
    close(hfig);
    
    % Display results
    fprintf('\n  Business Cycle Statistics:\n');
    disp(stats);
    
    fprintf('  Business cycle analysis completed.\n\n');
    
catch ME
    fprintf('  ⚠ Error in business cycle analysis: %s\n', ME.message);
    fprintf('  Continuing with other analyses...\n\n');
end

%% SUMMARY AND FINAL RESULTS
fprintf('ANALYSIS SUMMARY\n');
fprintf('================\n');
fprintf('All analyses completed successfully.\n\n');

fprintf('Generated Files:\n');
fprintf('  Figures saved to: %s\n', resultsDir);
fprintf('  Tables saved to: %s\n', tablesDir);
fprintf('  Processed data: %s\n', procDataDir);

fprintf('\nKey Output Files:\n');
files_to_check = {
    fullfile(resultsDir, 'gdp_total.png'), 'GDP Total Plot';
    fullfile(resultsDir, 'gdp_components.png'), 'GDP Components Plot';
    fullfile(resultsDir, 'gdp_nominal_and_log.svg'), 'Nominal GDP Analysis';
    fullfile(resultsDir, 'gdp_real_and_log.svg'), 'Real GDP Analysis';
    fullfile(resultsDir, 'gdp_growth_rates.png'), 'GDP Growth Rates';
    fullfile(resultsDir, 'labor_productivity_clean.png'), 'Labor Productivity';
    fullfile(resultsDir, 'business_cycle.svg'), 'Business Cycle Analysis';
    fullfile(resultsDir, 'gdp_growth_summary.csv'), 'Growth Summary Data';
    fullfile(tablesDir, 'business_cycle_stats.csv'), 'Business Cycle Stats'
};

for i = 1:size(files_to_check, 1)
    filepath = files_to_check{i, 1};
    description = files_to_check{i, 2};
    if exist(filepath, 'file')
        fprintf('  %s -- generated\n', description);
    else
        fprintf('  %s -- not found\n', description);
    end
end

fprintf('\n=============================================================\n');
fprintf('Analysis complete. Review outputs in 4_results.\n');
fprintf('=============================================================\n');
