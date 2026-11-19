# Stage 15: Aggregate logged training load and inspect follow-up coverage
# Run from the RStudio project root

library(dplyr)
library(tidyr)

# Read training sessions and the full participant-day panel
input_paths <- c(
  training = "data/intermediate/14_training_sessions.rds",
  outcomes = "data/intermediate/05_features.rds"
)

if (!all(file.exists(input_paths))) {
  stop("Required outputs from Stages 14 and 05 are missing.")
}

training_output <- readRDS(input_paths[["training"]])
feature_output <- readRDS(input_paths[["outcomes"]])

sessions <- training_output$sessions

if (anyNA(sessions$training_date_utc)) {
  stop("Undated training records require review before daily aggregation.")
}

# Sum recorded sessions within each participant and UTC end date
# A day with an incomplete session receives an unknown total load
daily_training <- sessions %>%
  group_by(participant_id, training_date_utc) %>%
  summarise(
    logged_sessions = n(),
    usable_sessions = sum(load_usable),
    incomplete_sessions = sum(!load_usable),
    logged_daily_load = if (all(load_usable)) {
      sum(session_load)
    } else {
      NA_real_
    },
    logged_duration_minutes = if (all(load_usable)) {
      sum(duration_minutes)
    } else {
      NA_real_
    },
    .groups = "drop"
  ) %>%
  arrange(participant_id, training_date_utc)

# Calculate quantiles only from available daily load values
available_quantile <- function(x, probability) {
  observed <- x[!is.na(x)]
  
  if (length(observed) == 0) {
    return(NA_real_)
  }
  
  as.numeric(quantile(
    observed,
    probs = probability,
    type = 7
  ))
}

# Describe the amount and distribution of logged training
training_day_summary <- daily_training %>%
  group_by(participant_id) %>%
  summarise(
    dates_with_training_records = n(),
    sessions_recorded = sum(logged_sessions),
    usable_load_days = sum(!is.na(logged_daily_load)),
    days_with_multiple_sessions = sum(logged_sessions > 1),
    days_with_incomplete_load = sum(is.na(logged_daily_load)),
    load_p25 = available_quantile(logged_daily_load, 0.25),
    load_median = available_quantile(logged_daily_load, 0.50),
    load_p75 = available_quantile(logged_daily_load, 0.75),
    .groups = "drop"
  )

# Retain all dates with calculable logged load
# No high-load threshold is applied in this stage
usable_days <- daily_training %>%
  filter(!is.na(logged_daily_load)) %>%
  mutate(
    training_day_id = paste(
      participant_id,
      format(training_date_utc, "%Y%m%d"),
      sep = "_"
    )
  )

if (nrow(usable_days) == 0) {
  stop("No training dates have calculable logged load.")
}

# Use all available outcomes, including dates excluded from Aim 1's joint sample
outcome_panel <- feature_output$feature_panel %>%
  select(
    participant_id, date,
    readiness, resting_hr, sleep_hours,
    hr_deviation, sleep_deviation
  )

if (anyDuplicated(outcome_panel[c("participant_id", "date")]) > 0) {
  stop("The outcome panel contains duplicate participant-date keys.")
}

# Match the training date and the following three calendar dates
# Source-date matching does not establish exact elapsed hours
followup_grid <- expand_grid(
  training_day_id = usable_days$training_day_id,
  relative_day = 0:3
) %>%
  left_join(usable_days, by = "training_day_id") %>%
  mutate(date = training_date_utc + relative_day) %>%
  left_join(
    outcome_panel,
    by = c("participant_id", "date")
  ) %>%
  arrange(participant_id, training_date_utc, relative_day)

# Describe availability at each relative calendar day
followup_availability <- followup_grid %>%
  group_by(participant_id, relative_day) %>%
  summarise(
    training_dates = n(),
    readiness_available = sum(!is.na(readiness)),
    heart_rate_available = sum(!is.na(resting_hr)),
    sleep_available = sum(!is.na(sleep_hours)),
    all_three_available = sum(
      complete.cases(readiness, resting_hr, sleep_hours)
    ),
    .groups = "drop"
  )

# Check whether every date at +1, +2, and +3 has the required measurements
three_day_coverage <- followup_grid %>%
  filter(relative_day %in% 1:3) %>%
  group_by(training_day_id, participant_id) %>%
  summarise(
    readiness_all_three_days = all(!is.na(readiness)),
    heart_rate_all_three_days = all(!is.na(resting_hr)),
    sleep_all_three_days = all(!is.na(sleep_hours)),
    all_metrics_all_three_days = all(
      complete.cases(readiness, resting_hr, sleep_hours)
    ),
    .groups = "drop"
  )

followup_summary <- three_day_coverage %>%
  group_by(participant_id) %>%
  summarise(
    usable_training_dates = n(),
    readiness_complete_windows = sum(readiness_all_three_days),
    heart_rate_complete_windows = sum(heart_rate_all_three_days),
    sleep_complete_windows = sum(sleep_all_three_days),
    all_metrics_complete_windows = sum(all_metrics_all_three_days),
    .groups = "drop"
  )

# Save daily load and coverage outputs for event selection
saveRDS(
  list(
    daily_training = daily_training,
    training_day_summary = training_day_summary,
    followup_grid = followup_grid,
    three_day_coverage = three_day_coverage,
    followup_summary = followup_summary,
    alignment_status = feature_output$alignment_status,
    load_definition = "Sum of usable logged session loads per UTC end date",
    missing_training_rule = "Unreported training dates have unknown load"
  ),
  "data/intermediate/15_training_daily.rds"
)

readr::write_csv(
  training_day_summary,
  "results/training_day_summary.csv"
)

readr::write_csv(
  followup_availability,
  "results/training_followup_availability.csv"
)

readr::write_csv(
  followup_summary,
  "results/training_three_day_coverage.csv"
)

# Display the distributions and complete-window counts
cat("\nLogged daily training summary:\n")
print(as.data.frame(training_day_summary), row.names = FALSE)

cat("\nCoverage across calendar days +1, +2, and +3:\n")
print(as.data.frame(followup_summary), row.names = FALSE)

cat("\nTotal dates with calculable logged load:", nrow(usable_days), "\n")
cat("Windows may overlap and are not independent events.\n")
cat("Stage 15 completed. Daily load and coverage outputs were saved.\n")