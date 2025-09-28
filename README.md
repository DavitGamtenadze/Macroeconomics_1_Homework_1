# Singapore GDP Macroeconomics Homework 1

Developed on MATLAB R2025b (macOS). No additional toolboxes are required; the Signal Processing Toolbox is optional and only used when available for Savitzky–Golay smoothing.

## Overview
This project reproduces the GDP, growth, productivity, and business-cycle analysis for Singapore used in Macroeconomics 1 Homework 1. The workflow is orchestrated through `1_code/main.m`, which processes raw data, generates cleaned datasets, produces figures, and exports summary tables.

## Data source
Data source: Singapore Department of Statistics (SingStat, https://www.singstat.gov.sg).

## How to run
1. Open MATLAB R2025b (or later).
2. Set the working directory to the repository root.
3. Run `run('1_code/main.m')`.

The script reads CSV files in `2_data/raw_data`, refreshes cleaned data in `2_data/processed_data`, writes figures to `4_results/figures`, and stores derived tables in `2_data/processed_data`.

## Repository layout
- `1_code/` – MATLAB source files and helper functions.
- `2_data/raw_data/` – Original GDP, population, and deflator CSV files.
- `2_data/processed_data/` – Cleaned datasets and generated summary tables.
- `4_results/` – Output figures (and tables where applicable).
- `3_docs/` – Supporting documentation.

## Notes
- If the Signal Processing Toolbox is installed, Savitzky–Golay smoothing will be applied to HP-cycle plots automatically. Without it, the code falls back to moving averages.
- Any updates to MATLAB or toolbox requirements should be noted here to keep collaborators in sync.