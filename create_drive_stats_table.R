# Create drive_stats table for MariaDB
#
# 2018-06-11 Initial version creation
# 2024-01-01 add index and partitioning
# 2025-02-16 Refined the script for 2024Q4 data

library("RMariaDB")
library("tictoc")
library("stringr")
library("purrr")
library("dplyr")
library("lubridate")
library("yaml")

get_script_directory <- function() {
  # Check for command line argument for --file= (Rscript execution)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    # Extract the script path from the --file= argument
    script_path <- normalizePath(sub("^--file=", "", file_arg))
    # Return the directory containing the script
    return(dirname(script_path))
  }
  
  # Check if running in RStudio and get the active document's path
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    script_path <- rstudioapi::getActiveDocumentContext()$path
    if (nzchar(script_path)) {
      # Return the directory containing the active script
      return(dirname(normalizePath(script_path)))
    }
  }
  
  # Return NA if the script directory could not be determined
  return(NA)
}

# Set working directory to the script's directory
script_directory <- get_script_directory()
print(script_directory)
setwd(script_directory)

outfile_path <- "outfile/"
infile_path <- "infile/"
tmp_path <- "tmp/"

# List of directories to check and create if missing
dirs <- c(outfile_path, infile_path, tmp_path)

# Loop through each directory and create it if it doesn't exist
for (dir in dirs) {
  if (!dir.exists(dir)) {
    dir.create(dir)
    cat(sprintf("Directory '%s' created.\n", dir))
  } else {
    cat(sprintf("Directory '%s' already exists.\n", dir))
  }
}

# Load the configuration file (config.yml)
config <- read_yaml("config.yml")
db_config <- config$db_connection

# Connect to the database with a hard-coded timeout value (Inf)
con <- dbConnect(
  RMariaDB::MariaDB(),
  username = db_config$username,
  password = db_config$password,
  host     = db_config$host,
  port     = db_config$port,
  dbname   = db_config$dbname,
  timeout  = Inf  # Timeout is hardcoded as Inf, not read from the YAML file
)

# dbSendQuery(con, "DROP TABLE drive_stats ;")

# Create Table
smart_attribute_no = c((1:5),
                       (7:13),
                       (15:18),
                       (22:24),
                       27,
                       71,
                       82,
                       90,
                       (160:161),
                       (163:184),
                       (187:202),
                       206,
                       210,
                       218,
                       220,
                       (222:226),
                       (230:235),
                       (240:242),
                       (244:248),
                       (250:252),
                       (254:255)
)

smart_attribute <-
  paste0(rep(
    paste0(
      ', smart_',
      smart_attribute_no,
      '_normalized INTEGER, smart_',
      smart_attribute_no,
      '_raw BIGINT'
    )
  ), collapse = "")

sql <- paste0(
  "CREATE TABLE IF NOT EXISTS drive_stats (
    id BIGINT AUTO_INCREMENT,
    date DATE NOT NULL,
    serial_number VARCHAR(32) NOT NULL,
    vendor VARCHAR(16) NOT NULL,
    model VARCHAR(64) NOT NULL,
    model_backblaze VARCHAR(64) NOT NULL,
    source_file VARCHAR(32) NOT NULL,
    modified TINYINT NOT NULL,
    capacity_bytes BIGINT NOT NULL,
    failure TINYINT NOT NULL,
    datacenter VARCHAR(8),
    cluster_id VARCHAR(8),
    vault_id VARCHAR(8),
    pod_id VARCHAR(8),
    pod_slot_num VARCHAR(8),
    is_legacy_format VARCHAR(16)",
  smart_attribute,
  ", PRIMARY KEY(id, date),
  UNIQUE (date, serial_number));"
)

dbSendQuery(con, sql)

# Check if index already exists
index_exists <-
  dbGetQuery(
    con,
    "SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.STATISTICS
    WHERE table_name = 'drive_stats' AND index_name = 'date_index'"
  )

# If index doesn't exist, create it
if (index_exists$count[1] == 0) {
  dbSendQuery(con, "CREATE INDEX date_index ON drive_stats(date)")
  dbSendQuery(con,
              "CREATE INDEX serial_number_index ON drive_stats(serial_number)")
  dbSendQuery(con, "CREATE INDEX vendor_index ON drive_stats(vendor)")
  dbSendQuery(con, "CREATE INDEX model_index ON drive_stats(model)")
  dbSendQuery(con,
              "CREATE INDEX source_file_index ON drive_stats(source_file)")
  dbSendQuery(con, "CREATE INDEX modified_index ON drive_stats(modified)")
  dbSendQuery(con,
              "CREATE INDEX capacity_bytes_index ON drive_stats(capacity_bytes)")
  dbSendQuery(con, "CREATE INDEX failure_index ON drive_stats(failure)")
  dbSendQuery(con,
              "CREATE INDEX datacenter_index ON drive_stats(datacenter)")
  dbSendQuery(con,
              "CREATE INDEX cluster_id_index ON drive_stats(cluster_id)")
  dbSendQuery(con, "CREATE INDEX vault_id_index ON drive_stats(vault_id)")
  dbSendQuery(con, "CREATE INDEX pod_id_index ON drive_stats(pod_id)")
  dbSendQuery(con,
              "CREATE INDEX pod_slot_num_index ON drive_stats(pod_slot_num)")
  dbSendQuery(con,
              "CREATE INDEX is_legacy_format_index ON drive_stats(is_legacy_format)")
  dbSendQuery(con,
              "CREATE INDEX smart_9_raw_index ON drive_stats (smart_9_raw)")
  
  # Create data partition
  create_range_partition_statement <-
    function(start_year,
             start_month,
             end_year,
             end_month,
             table_name) {
      start_date <- make_date(start_year, start_month, 1)
      end_date <-
        make_date(end_year, end_month, 1) %>% ceiling_date("month")
      dates <- seq(start_date, end_date, by = "month")
      
      partition_statements <- sapply(dates, function(date) {
        partition_name <- format(date, "%Y%m")
        next_month <- ceiling_date(date, "month")
        sprintf(
          "PARTITION p%s VALUES LESS THAN ('%s')",
          partition_name,
          format(next_month, "%Y-%m-%d")
        )
      })
      
      full_statement <-
        sprintf(
          "ALTER TABLE %s\nPARTITION BY RANGE COLUMNS(date) (\n    %s\n);",
          table_name,
          paste(partition_statements, collapse = ",\n    ")
        )
      
      return(full_statement)
    }
  
  sql <-
    create_range_partition_statement(2013, 4, 2039, 12, 'drive_stats')
  dbSendQuery(con, sql)
}
