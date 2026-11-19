# Stage 04c: Review zero-readiness patterns over time
# Run from the RStudio project root

library(dplyr)

# Read the draft panel from Stage 03
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run R/03_merge.R first.")
}

merge_output <- readRDS(input_path)
daily_panel <- merge_output$daily_panel_draft

# Summarize readiness separately by participant and month
monthly_summary <- daily_panel %>%
  mutate(month = format(date, "%Y-%m")) %>%
  group_by(participant_id, month) %>%
  summarise(
    observed_readiness_days = sum(!is.na(readiness)),
    zero_readiness_days = sum(readiness == 0, na.rm = TRUE),
    nonzero_readiness_days = sum(readiness > 0, na.rm = TRUE),
    .groups = "drop"
  )

# Identify consecutive calendar-day runs of each readiness state
# Missing observations interrupt a zero-readiness run
readiness_states <- daily_panel %>%
  group_by(participant_id) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    readiness_state = case_when(
      is.na(readiness) ~ "Missing",
      readiness == 0 ~ "Zero",
      TRUE ~ "Nonzero"
    ),
    run_id = cumsum(
      readiness_state != lag(readiness_state, default = "Start")
    )
  ) %>%
  ungroup()

zero_runs <- readiness_states %>%
  group_by(participant_id, run_id, readiness_state) %>%
  summarise(
    start_date = min(date),
    end_date = max(date),
    calendar_days = n(),
    .groups = "drop"
  ) %>%
  filter(readiness_state == "Zero") %>%
  arrange(participant_id, start_date)

# Preserve the selected p05 records for closer inspection
p05_records <- daily_panel %>%
  filter(participant_id == "p05", !is.na(readiness)) %>%
  select(
    participant_id, date, wellness_time_text,
    readiness, fatigue, self_report_sleep_hours
  ) %>%
  arrange(date)

# Save the review outputs
readr::write_csv(
  monthly_summary,
  "results/readiness_monthly_summary.csv"
)

readr::write_csv(
  zero_runs,
  "data/intermediate/04c_zero_readiness_runs.csv"
)

readr::write_csv(
  p05_records,
  "data/intermediate/04c_p05_readiness_review.csv"
)

# Display the p05 patterns
cat("\np05 monthly readiness summary:\n")
print(
  as.data.frame(filter(monthly_summary, participant_id == "p05")),
  row.names = FALSE
)

cat("\np05 consecutive zero-readiness runs:\n")
print(
  as.data.frame(filter(zero_runs, participant_id == "p05")),
  row.names = FALSE
)

cat("\nStage 04c completed. Readiness values were not changed.\n")