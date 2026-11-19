# Stage 19: Audit chronological prediction samples
# Run from the RStudio project root

library(dplyr)
library(tidyr)

# Read cleaned daily measurements before full-period mean centering
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run the Aim 1 pipeline first.")
}

panel_output <- readRDS(input_path)

prediction_calendar <- panel_output$daily_panel_draft %>%
  select(
    participant_id, date, wellness_time_text,
    readiness, resting_hr, sleep_hours
  ) %>%
  arrange(participant_id, date)

# Require unique keys and a complete calendar for calendar-day lagging
if (anyNA(prediction_calendar$date)) {
  stop("Missing dates require review.")
}

if (anyDuplicated(
  prediction_calendar[c("participant_id", "date")]
) > 0) {
  stop("Duplicate participant-date keys require review.")
}

prediction_calendar <- prediction_calendar %>%
  group_by(participant_id) %>%
  mutate(calendar_gap = as.integer(date - lag(date))) %>%
  ungroup()

if (any(prediction_calendar$calendar_gap != 1, na.rm = TRUE)) {
  stop("Calendar gaps must be filled before constructing daily lags.")
}

# Establish common date boundaries before selecting target observations
calendar_dates <- seq(
  min(prediction_calendar$date),
  max(prediction_calendar$date),
  by = "day"
)

train_end <- calendar_dates[floor(length(calendar_dates) * 0.60)]
validation_end <- calendar_dates[floor(length(calendar_dates) * 0.80)]

split_boundaries <- data.frame(
  split = c("train", "validation", "test"),
  start_date = c(
    min(calendar_dates),
    train_end + 1,
    validation_end + 1
  ),
  end_date = c(
    train_end,
    validation_end,
    max(calendar_dates)
  )
)

# Carry questionnaire observations forward within each participant
# Then lag them so that the current target never enters its own history
prediction_calendar <- prediction_calendar %>%
  select(-calendar_gap) %>%
  mutate(
    history_readiness = readiness,
    history_readiness_date = if_else(
      !is.na(readiness),
      date,
      as.Date(NA)
    )
  ) %>%
  group_by(participant_id) %>%
  arrange(date, .by_group = TRUE) %>%
  fill(
    history_readiness,
    history_readiness_date,
    .direction = "down"
  ) %>%
  mutate(
    last_readiness = lag(history_readiness),
    last_readiness_date = lag(history_readiness_date),
    days_since_last_readiness =
      as.integer(date - last_readiness_date),
    hr_lag2 = lag(resting_hr, 2),
    sleep_lag2 = lag(sleep_hours, 2),
    wearable_source_date = lag(date, 2)
  ) %>%
  ungroup() %>%
  select(-history_readiness, -history_readiness_date) %>%
  mutate(
    split = factor(
      case_when(
        date <= train_end ~ "train",
        date <= validation_end ~ "validation",
        TRUE ~ "test"
      ),
      levels = c("train", "validation", "test")
    )
  )

# Audit dates with an observed target
prediction_targets <- prediction_calendar %>%
  filter(!is.na(readiness))

participant_audit <- prediction_targets %>%
  group_by(participant_id, split) %>%
  summarise(
    observed_targets = n(),
    baseline_available = sum(!is.na(last_readiness)),
    hr_lag2_available = sum(!is.na(hr_lag2)),
    sleep_lag2_available = sum(!is.na(sleep_lag2)),
    baseline_and_wearables_available = sum(
      complete.cases(last_readiness, hr_lag2, sleep_lag2)
    ),
    .groups = "drop"
  ) %>%
  complete(
    participant_id,
    split,
    fill = list(
      observed_targets = 0L,
      baseline_available = 0L,
      hr_lag2_available = 0L,
      sleep_lag2_available = 0L,
      baseline_and_wearables_available = 0L
    )
  ) %>%
  arrange(participant_id, split)

split_audit <- participant_audit %>%
  group_by(split) %>%
  summarise(
    participants_with_targets = sum(observed_targets > 0),
    observed_targets = sum(observed_targets),
    baseline_available = sum(baseline_available),
    baseline_and_wearables_available =
      sum(baseline_and_wearables_available),
    .groups = "drop"
  )

# Preserve a common candidate sample with an available persistence baseline
# Wearable missingness is retained for later training-only preprocessing
eligible_targets <- prediction_targets %>%
  filter(!is.na(last_readiness))

# Save the audit and raw historical measurements for feature construction
saveRDS(
  list(
    prediction_calendar = prediction_calendar,
    eligible_targets = eligible_targets,
    split_boundaries = split_boundaries,
    participant_audit = participant_audit,
    split_audit = split_audit,
    forecast_definition = paste(
      "Target day d; questionnaire history through d-1;",
      "wearable source-date features through d-2"
    ),
    evaluation_design =
      "Rolling next-day forecasting for previously observed participants",
    alignment_status = panel_output$alignment_status,
    feature_rule =
      "Do not use full-period participant means from Aim 1 as predictors"
  ),
  "data/intermediate/19_prediction_audit.rds"
)

readr::write_csv(
  split_boundaries,
  "results/prediction_split_boundaries.csv"
)

readr::write_csv(
  participant_audit,
  "results/prediction_participant_audit.csv"
)

readr::write_csv(
  split_audit,
  "results/prediction_split_audit.csv"
)

cat("\nChronological split boundaries:\n")
print(split_boundaries, row.names = FALSE)

cat("\nPrediction sample availability:\n")
print(as.data.frame(split_audit), row.names = FALSE)

cat("\nTest-period availability by participant:\n")
print(
  as.data.frame(filter(participant_audit, split == "test")),
  row.names = FALSE
)

cat("\nStage 19 completed. Prediction sample audit was saved.\n")