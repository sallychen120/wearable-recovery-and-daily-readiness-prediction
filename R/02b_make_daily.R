# Stage 02b: Select one wellness and main-sleep record per date
# Run from the RStudio project root

library(dplyr)

# Read the full cleaned records from Stage 02
input_path <- "data/intermediate/02_cleaned.rds"

if (!file.exists(input_path)) {
  stop("Stage 02 output is missing. Run R/02_clean.R first.")
}

cleaned_data <- readRDS(input_path)

# Apply the daily selection rules to one participant
prepare_daily <- function(x) {
  
  participant_id <- x$participant_id
  
  # Parse the original wellness timestamps as UTC
  wellness_with_time <- x$wellness %>%
    mutate(
      wellness_time_utc = readr::parse_datetime(
        wellness_time_text,
        locale = readr::locale(tz = "UTC")
      )
    )
  
  if (anyNA(wellness_with_time$wellness_time_utc)) {
    stop("Unparsed wellness timestamps for ", participant_id)
  }
  
  # Record the number of reports and select the earliest per UTC date
  # Keep ties so that ambiguous selections trigger the check below
  wellness_daily <- wellness_with_time %>%
    group_by(participant_id, date) %>%
    mutate(wellness_reports_that_day = n()) %>%
    slice_min(
      order_by = wellness_time_utc,
      n = 1,
      with_ties = TRUE
    ) %>%
    ungroup() %>%
    arrange(date)
  
  # Select main sleep without summing other sleep episodes
  sleep_daily <- x$sleep %>%
    filter(main_sleep %in% TRUE) %>%
    arrange(date)
  
  # Require one selected record per participant-date
  if (anyDuplicated(wellness_daily[c("participant_id", "date")]) > 0) {
    stop("Tied earliest wellness reports for ", participant_id)
  }
  
  if (anyDuplicated(sleep_daily[c("participant_id", "date")]) > 0) {
    stop("Multiple main-sleep records per date for ", participant_id)
  }
  
  # Document how many records were selected
  daily_audit <- data.frame(
    participant_id = participant_id,
    wellness_before = nrow(x$wellness),
    wellness_selected = nrow(wellness_daily),
    sleep_before = nrow(x$sleep),
    sleep_selected = nrow(sleep_daily),
    sleep_unknown_main_flags = sum(is.na(x$sleep$main_sleep))
  )
  
  # Return tables compatible with Stage 03
  list(
    participant_id = participant_id,
    wellness = wellness_daily,
    resting_hr = x$resting_hr,
    sleep = sleep_daily,
    daily_audit = daily_audit,
    sleep_timezone_status = x$sleep_timezone_status
  )
}

# Apply the rules to every participant
daily_data <- lapply(cleaned_data, prepare_daily)

daily_selection_audit <- bind_rows(
  lapply(daily_data, function(x) x$daily_audit)
)

# Save new outputs without replacing the full cleaned records
output_path <- "data/intermediate/02_daily.rds"
saveRDS(daily_data, output_path)

readr::write_csv(
  daily_selection_audit,
  "results/daily_selection_audit.csv"
)

print(as.data.frame(daily_selection_audit), row.names = FALSE)
cat("\nStage 02b completed. Output saved to:", output_path, "\n")