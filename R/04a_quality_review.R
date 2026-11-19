# Stage 04a: Review measurement validity
# Run from the RStudio project root

library(dplyr)

# Read the draft panel from Stage 03
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run R/03_merge.R first.")
}

merge_output <- readRDS(input_path)
daily_panel <- merge_output$daily_panel_draft

# Flag values outside the measurement or questionnaire domain
# Readiness equal to zero is a valid scale value
quality_flags <- daily_panel %>%
  mutate(
    hr_nonpositive =
      !is.na(resting_hr) & resting_hr <= 0,
    readiness_out_of_range =
      !is.na(readiness) & (readiness < 0 | readiness > 10),
    fatigue_out_of_range =
      !is.na(fatigue) & (fatigue < 1 | fatigue > 5)
  )

# Summarize quality checks separately for each participant
quality_summary <- quality_flags %>%
  group_by(participant_id) %>%
  summarise(
    calendar_days = n(),
    hr_missing_days = sum(is.na(resting_hr)),
    hr_nonpositive_days = sum(hr_nonpositive),
    hr_positive_days = sum(resting_hr > 0, na.rm = TRUE),
    readiness_zero_days = sum(readiness == 0, na.rm = TRUE),
    readiness_out_of_range_days = sum(readiness_out_of_range),
    fatigue_out_of_range_days = sum(fatigue_out_of_range),
    .groups = "drop"
  )

# Preserve flagged records for review
flagged_records <- quality_flags %>%
  filter(
    hr_nonpositive |
      readiness_out_of_range |
      fatigue_out_of_range
  ) %>%
  select(
    participant_id, date, wellness_time_text,
    resting_hr, readiness, fatigue, sleep_hours,
    hr_nonpositive, readiness_out_of_range,
    fatigue_out_of_range
  )

# Save aggregate results and local record-level review data
dir.create("results", showWarnings = FALSE)
dir.create("data/intermediate", recursive = TRUE, showWarnings = FALSE)

readr::write_csv(
  quality_summary,
  "results/quality_review_summary.csv"
)

readr::write_csv(
  flagged_records,
  "data/intermediate/04a_flagged_records.csv"
)

# Display the review results
cat("\nMeasurement quality summary:\n")
print(as.data.frame(quality_summary), row.names = FALSE)

cat("\nFirst ten flagged records:\n")
print(as.data.frame(head(flagged_records, 10)), row.names = FALSE)

cat("\nStage 04a completed. No measurements were changed.\n")