# Import Backblaze HDD Data to MariaDB

This R script initializes and configures the `drive_stats` table in MariaDB for Backblaze HDD data analysis.  
It automatically handles directory setup, configuration loading, database connection, table creation, indexing, and partitioning.

## Features

- **Automatic Directory Setup:**  
  Creates `infile/`, `outfile/`, and `tmp/` directories if they do not exist.

- **Configurable Database Connection:**  
  Loads connection parameters from `config.yml` for flexible deployment.

- **Table Creation:**  
  Generates a `drive_stats` table with all major SMART attribute columns (normalized and raw) for Backblaze HDD reliability analysis.

- **Indexing:**  
  - Creates single-column indexes on critical fields such as:
    - `date`, `serial_number`, `vendor`, `model`, `source_file`, `failure`, etc.  
  - Adds composite indexes to accelerate analytic queries:
    - `(model, date)`
    - `(vendor, model, failure)`
    - `(date, failure)`

- **Partitioning:**  
  Automatically partitions the table by `date` from April 2013 through December 2039, improving scalability and query performance on time-series workloads.

- **Validation and Safety Checks:**  
  Checks for existing indexes and partitions before creating new ones to ensure idempotent behavior.

## Prerequisites

- **MariaDB:**  
  Running and accessible with user credentials provided in `config.yml`.

- **R Environment:**  
  Ensure R (≥4.0.0) is installed and accessible via command line or RStudio.

- **Required R Packages:**

  ```r
  install.packages(c(
    "RMariaDB",
    "tictoc",
    "stringr",
    "purrr",
    "dplyr",
    "lubridate",
    "yaml"
  ))
