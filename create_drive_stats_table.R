# Create drive_stats table for MariaDB
#
# 2018-06-11 Initial version creation
# 2024-01-01 add index and partitioning
# 2025-02-16 Refined for 2024Q4 data
# 2025-10-17 Enhanced with composite indexes for analytic queries

library("RMariaDB")
library("tictoc")
library("stringr")
library("purrr")
library("dplyr")
library("lubridate")
library("yaml")

get_script_directory <- function() {
  # Detect script directory (works in both Rscript and RStudio)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg))
    return(dirname(script_path))
  }
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    script_path <- rstudioapi::getActiveDocumentContext()$path
    if (nzchar(script_path))
      return(dirname(normalizePath(script_path)))
  }
  return(NA)
}

# --- Setup working directories ---
script_directory <- get_script_directory()
print(script_directory)
setwd(script_directory)

outfile_path <- "outfile/"
infile_path  <- "infile/"
tmp_path     <- "tmp/"

dirs <- c(outfile_path, infile_path, tmp_path)
for (dir in dirs) {
  if (!dir.exists(dir)) {
    dir.create(dir)
    cat(sprintf("Directory '%s' created.\n", dir))
  } else {
    cat(sprintf("Directory '%s' already exists.\n", dir))
  }
}

# --- Load DB configuration ---
config <- read_yaml("config.yml")
db_config <- config$db_connection

# --- Connect to MariaDB ---
con <- tryCatch({
  dbConnect(
    RMariaDB::MariaDB(),
    username = db_config$username,
    password = db_config$password,
    host     = db_config$host,
    port     = db_config$port,
    dbname   = db_config$dbname,
    timeout  = Inf
  )
}, error = function(e) {
  stop(paste("Database connection failed:", e$message))
})

cat("Database connection established successfully.\n")

# --- SMART attribute column generation ---
smart_attribute_no <- c((1:5),
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

smart_attribute <- paste0(sapply(smart_attribute_no, function(x) {
  sprintf(", smart_%d_normalized INTEGER, smart_%d_raw BIGINT", x, x)
}), collapse = "")

# --- Create Table ---
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
cat("Table 'drive_stats' created or already exists.\n")

# --- Index creation with existence check ---
existing_indexes <- dbGetQuery(
  con,
  "
  SELECT index_name FROM INFORMATION_SCHEMA.STATISTICS
  WHERE table_name = 'drive_stats';
"
)$index_name

create_index_if_missing <- function(name, sql) {
  if (!(name %in% existing_indexes)) {
    dbSendQuery(con, sql)
    cat(sprintf("Index '%s' created.\n", name))
  } else {
    cat(sprintf("Index '%s' already exists.\n", name))
  }
}

# --- Core single-column indexes ---
create_index_if_missing("date_index", "CREATE INDEX date_index ON drive_stats(date)")
create_index_if_missing(
  "serial_number_index",
  "CREATE INDEX serial_number_index ON drive_stats(serial_number)"
)
create_index_if_missing("vendor_index",
                        "CREATE INDEX vendor_index ON drive_stats(vendor)")
create_index_if_missing("model_index", "CREATE INDEX model_index ON drive_stats(model)")
create_index_if_missing("source_file_index",
                        "CREATE INDEX source_file_index ON drive_stats(source_file)")
create_index_if_missing("modified_index",
                        "CREATE INDEX modified_index ON drive_stats(modified)")
create_index_if_missing(
  "capacity_bytes_index",
  "CREATE INDEX capacity_bytes_index ON drive_stats(capacity_bytes)"
)
create_index_if_missing("failure_index",
                        "CREATE INDEX failure_index ON drive_stats(failure)")
create_index_if_missing("datacenter_index",
                        "CREATE INDEX datacenter_index ON drive_stats(datacenter)")
create_index_if_missing("cluster_id_index",
                        "CREATE INDEX cluster_id_index ON drive_stats(cluster_id)")
create_index_if_missing("vault_id_index",
                        "CREATE INDEX vault_id_index ON drive_stats(vault_id)")
create_index_if_missing("pod_id_index",
                        "CREATE INDEX pod_id_index ON drive_stats(pod_id)")
create_index_if_missing(
  "pod_slot_num_index",
  "CREATE INDEX pod_slot_num_index ON drive_stats(pod_slot_num)"
)
create_index_if_missing(
  "is_legacy_format_index",
  "CREATE INDEX is_legacy_format_index ON drive_stats(is_legacy_format)"
)
create_index_if_missing("smart_9_raw_index",
                        "CREATE INDEX smart_9_raw_index ON drive_stats(smart_9_raw)")

# --- Composite indexes for analytics ---
create_index_if_missing("model_date_index",
                        "CREATE INDEX model_date_index ON drive_stats(model, date)")
create_index_if_missing(
  "vendor_model_failure_index",
  "CREATE INDEX vendor_model_failure_index ON drive_stats(vendor, model, failure)"
)
create_index_if_missing(
  "date_failure_index",
  "CREATE INDEX date_failure_index ON drive_stats(date, failure)"
)

cat("All essential indexes verified and created.\n")

# --- Partition creation (only if not exists) ---
partition_exists <- dbGetQuery(
  con,
  "
  SELECT COUNT(*) AS count
  FROM INFORMATION_SCHEMA.PARTITIONS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'drive_stats';
"
)

if (partition_exists$count[1] == 0) {
  create_range_partition_statement <- function(start_year,
                                               start_month,
                                               end_year,
                                               end_month,
                                               table_name) {
    start_date <- make_date(start_year, start_month, 1)
    end_date   <- make_date(end_year, end_month, 1) %>% ceiling_date("month")
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
    full_statement <- sprintf(
      "ALTER TABLE %s\nPARTITION BY RANGE COLUMNS(date) (\n    %s\n);",
      table_name,
      paste(partition_statements, collapse = ",\n    ")
    )
    return(full_statement)
  }
  
  sql <- create_range_partition_statement(2013, 4, 2039, 12, 'drive_stats')
  dbSendQuery(con, sql)
  cat("Date range partitions created successfully.\n")
} else {
  cat("Partitions already exist. Skipping partition creation.\n")
}

# --- Close connection ---
dbDisconnect(con)
cat("Database connection closed successfully.\n")
