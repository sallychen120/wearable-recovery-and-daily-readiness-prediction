# Stage 04b: Review source dates and reporting times
# Run from the RStudio project root

library(dplyr)

# Read the draft panel from Stage 03
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run R/03_merge.R first.")
}

merge_output <- readRDS(input_path)
daily_panel <- merge_output$daily_panel_draft

# Extract questionnaire hours in UTC
# Extract sleep hours as source clock labels without assigning a timezone
time_review <- daily_panel %>%
  mutate(
    wellness_hour_utc = as.integer(
      format(wellness_time_utc, "%H", tz = "UTC")
    ),
    sleep_end_date_label = as.Date(substr(end_time, 1, 10)),
    sleep_end_hour_label = as.integer(substr(end_time, 12, 13)),
    sleep_date_mismatch =
      !is.na(sleep_end_date_label) &
      sleep_end_date_label != date
  )

# These thresholds flag records for review only
# Questionnaire and sleep hours are not directly comparable yet
time_summary <- time_review %>%
  group_by(participant_id) %>%
  summarise(
    wellness_records = sum(!is.na(wellness_time_text)),
    wellness_before_06_utc = sum(
      wellness_hour_utc < 6,
      na.rm = TRUE
    ),
    sleep_records = sum(!is.na(end_time)),
    sleep_ending_at_or_after_12_source_clock = sum(
      sleep_end_hour_label >= 12,
      na.rm = TRUE
    ),
    sleep_date_mismatch_records = sum(sleep_date_mismatch),
    .groups = "drop"
  )

# Select records requiring closer inspection
timing_review_records <- time_review %>%
  filter(
    wellness_hour_utc < 6 |
      sleep_end_hour_label >= 12 |
      sleep_date_mismatch
  ) %>%
  select(
    participant_id, date, wellness_time_text,
    readiness, sleep_hours, start_time, end_time,
    wellness_hour_utc, sleep_end_hour_label,
    sleep_date_mismatch
  ) %>%
  arrange(participant_id, date)

# Save aggregate and record-level review outputs
readr::write_csv(
  time_summary,
  "results/timing_review_summary.csv"
)

readr::write_csv(
  timing_review_records,
  "data/intermediate/04b_timing_review_records.csv"
)

# Display the results
cat("\nSource timing summary:\n")
print(as.data.frame(time_summary), row.names = FALSE)

cat("\nFirst fifteen records flagged for timing review:\n")
print(
  as.data.frame(head(timing_review_records, 15)),
  row.names = FALSE
)

cat("\nStage 04b completed. Dates and measurements were not changed.\n")