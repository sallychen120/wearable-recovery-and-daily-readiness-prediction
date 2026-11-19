# Stage 02: Clean the imported participant data
# Run from the RStudio project root

library(dplyr)

# Read the output from Stage 01
input_path <- "data/intermediate/01_imported.rds"

if (!file.exists(input_path)) {
  stop("Stage 01 output is missing. Run R/01_import.R first.")
}

imported_data <- readRDS(input_path)

# Define a reusable cleaning function
clean_participant <- function(x) {
  
  participant_id <- x$participant_id
  
  # Extract wellness variables and preserve the original timestamp
  # The date is the UTC date label in the source file
  wellness <- x$wellness_raw %>%
    transmute(
      participant_id = participant_id,
      date = as.Date(substr(effective_time_frame, 1, 10)),
      wellness_time_text = effective_time_frame,
      readiness = readr::parse_double(readiness),
      fatigue = readr::parse_double(fatigue),
      self_report_sleep_hours = readr::parse_double(sleep_duration_h)
    ) %>%
    arrange(date, wellness_time_text)
  
  # Extract resting heart rate records
  resting_hr_before <- bind_rows(
    lapply(x$resting_hr_raw, function(record) {
      tibble(
        participant_id = participant_id,
        date = as.Date(substr(record$dateTime, 1, 10)),
        resting_hr = record$value$value
      )
    })
  )
  
  # Remove identical records and preserve the original measurement
  # Nonpositive heart rate values cannot be used as valid measurements
  resting_hr <- resting_hr_before %>%
    distinct() %>%
    mutate(
      resting_hr_raw = resting_hr,
      resting_hr_invalid =
        !is.na(resting_hr_raw) & resting_hr_raw <= 0,
      resting_hr = if_else(
        resting_hr_invalid,
        NA_real_,
        as.double(resting_hr_raw)
      )
    ) %>%
    arrange(date)
  
  # Extract sleep records and convert minutes asleep to hours
  # Preserve sleep times as text because the timezone is unverified
  sleep_before <- bind_rows(
    lapply(x$sleep_raw, function(record) {
      tibble(
        participant_id = participant_id,
        date = as.Date(record$dateOfSleep),
        log_id = as.character(record$logId),
        start_time = record$startTime,
        end_time = record$endTime,
        sleep_hours = record$minutesAsleep / 60,
        main_sleep = record$mainSleep
      )
    })
  )
  
  # Remove rows identical across all extracted sleep fields
  sleep <- sleep_before %>%
    distinct() %>%
    arrange(date, start_time)
  
  # Record the cleaning results for each source
  tables <- list(
    wellness = wellness,
    resting_hr = resting_hr,
    sleep = sleep
  )
  
  records_before <- c(
    nrow(x$wellness_raw),
    nrow(resting_hr_before),
    nrow(sleep_before)
  )
  
  records_after <- vapply(tables, nrow, integer(1))
  
  audit <- data.frame(
    participant_id = participant_id,
    source = names(tables),
    records_before = records_before,
    records_after = unname(records_after),
    duplicates_removed = records_before - unname(records_after),
    invalid_values_set_missing = c(
      0L,
      sum(resting_hr$resting_hr_invalid),
      0L
    ),
    repeated_date_rows = unname(vapply(
      tables,
      function(table) sum(duplicated(table$date)),
      integer(1)
    )),
    missing_date_rows = unname(vapply(
      tables,
      function(table) sum(is.na(table$date)),
      integer(1)
    ))
  )
  
  # Return separate cleaned tables and their audit
  list(
    participant_id = participant_id,
    wellness = wellness,
    resting_hr = resting_hr,
    sleep = sleep,
    audit = audit,
    sleep_timezone_status = "Unverified"
  )
}

# Apply the same cleaning function to each imported participant
cleaned_data <- lapply(imported_data, clean_participant)

# Combine the cleaning audit across participants
cleaning_audit <- bind_rows(
  lapply(cleaned_data, function(x) x$audit)
)

# Save the output for Stage 03
output_path <- "data/intermediate/02_cleaned.rds"
saveRDS(cleaned_data, output_path)

# Save the cleaning audit for documentation
dir.create("results", showWarnings = FALSE)

readr::write_csv(
  cleaning_audit,
  "results/cleaning_audit.csv"
)

# Display the cleaning audit
print(as.data.frame(cleaning_audit), row.names = FALSE)
cat("\nStage 02 completed. Output saved to:", output_path, "\n")