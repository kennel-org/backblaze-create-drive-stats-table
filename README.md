# Import Backblaze HDD Data to MariaDB

This script imports Backblaze HDD data into MariaDB by creating a partitioned and indexed `drive_stats` table with comprehensive SMART attribute columns.

## Features

- **Table Creation:** Automatically creates the `drive_stats` table with detailed SMART attribute columns.
- **Indexing:** Sets up indexes on key columns (e.g., `date`, `serial_number`, `vendor`, etc.) to optimize query performance.
- **Partitioning:** Partitions the table by date to improve data management and scalability.
- **Flexible Configuration:** Easily adjust the working directory and database connection settings to suit your environment.

## Prerequisites

- **MariaDB:** A running MariaDB server.
- **R:** Ensure you have R installed.
- **Required R Packages:**
  - `RMariaDB`
  - `tictoc`
  - `stringr`
  - `purrr`
  - `dplyr`
  - `lubridate`

Install the required packages in R with:

```r
install.packages(c("RMariaDB", "tictoc", "stringr", "purrr", "dplyr", "lubridate"))

## License

This project is licensed under the MIT License.
