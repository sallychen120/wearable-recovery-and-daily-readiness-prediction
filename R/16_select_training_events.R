# Stage 16: Define high-load candidates and inspect event-window feasibility
# Run from the RStudio project root

library(dplyr)
library(tidyr)

# Read daily training data and the full outcome panel
input_paths <- c(
  training = "data/intermediate/15_training_daily.rds",
  outcomes = "data/intermediate/05_features.rds"
)

if (!all(file.exists(input_paths))) {
  stop("Required outputs from Stages 15 and 05 are missing.")
}

training_output <- readRDS(input_paths[["training"]])
feature_output <- readRDS(input_paths[["outcomes"]])

daily_training <- training_output$daily_training
minimum_training_days <- 20L

# Determine eligibility before examining outcome trajectories
eligibility <- training_output$training_day_summary %>%
  transmute(
    participant_id,
    usable_load_days,
    high_load_threshold = load_p75,
    eligible_for_events =
      usable_load_days >= minimum_training_days &
      !is.na(load_p75),
    eligibility_reason = case_when(
      usable_load_days == 0 ~ "No calculable logged load",
      usable_load_days < minimum_training_days ~
        "Fewer than 20 calculable training dates",
      TRUE ~ "Eligible"
    )
  )

readr::write_csv(
  eligibility,
  "results/aim2_participant_eligibility.csv"
)

# Select dates at or above each eligible participant's 75th percentile
candidates <- daily_training %>%
  left_join(eligibility, by = "participant_id") %>%
  filter(
    eligible_for_events,
    !is.na(logged_daily_load),
    logged_daily_load >= high_load_threshold
  ) %>%
  transmute(
    participant_id,
    event_date = training_date_utc,
    event_logged_load = logged_daily_load,
    high_load_threshold,
    event_id = paste(
      participant_id,
      format(training_date_utc, "%Y%m%d"),
      sep = "_"
    )
  ) %>%
  group_by(participant_id) %>%
  arrange(event_date, .by_group = TRUE) %>%
  mutate(
    days_since_previous_candidate =
      as.integer(event_date - lag(event_date)),
    days_until_next_candidate =
      as.integer(lead(event_date) - event_date),
    nonoverlapping_window =
      (
        is.na(days_since_previous_candidate) |
          days_since_previous_candidate > 4
      ) &
      (
        is.na(days_until_next_candidate) |
          days_until_next_candidate > 4
      )
  ) %>%
  ungroup()

if (nrow(candidates) == 0) {
  stop("No high-load candidates were found. Review the eligibility table.")
}

# A nonoverlapping window has no other candidate within four calendar days
# This does not establish the absence of other or unreported exercise
outcome_panel <- feature_output$feature_panel %>%
  select(
    participant_id, date,
    readiness, resting_hr, sleep_hours,
    hr_deviation, sleep_deviation
  )

if (anyDuplicated(outcome_panel[c("participant_id", "date")]) > 0) {
  stop("The outcome panel contains duplicate participant-date keys.")
}

# Preserve evidence of other logged training within the window
training_calendar <- daily_training %>%
  transmute(
    participant_id,
    date = training_date_utc,
    logged_sessions_on_date = logged_sessions,
    logged_load_on_date = logged_daily_load
  )

# Construct five calendar-date observations for every candidate
event_windows <- expand_grid(
  event_id = candidates$event_id,
  relative_day = seq.int(-1L, 3L)
) %>%
  left_join(candidates, by = "event_id") %>%
  mutate(date = event_date + relative_day) %>%
  left_join(
    outcome_panel,
    by = c("participant_id", "date")
  ) %>%
  left_join(
    training_calendar,
    by = c("participant_id", "date")
  ) %>%
  arrange(participant_id, event_date, relative_day)

# Count complete measurement windows without examining outcome magnitudes
event_coverage <- event_windows %>%
  group_by(event_id, participant_id) %>%
  summarise(
    readiness_complete_window = all(!is.na(readiness)),
    heart_rate_complete_window = all(!is.na(resting_hr)),
    sleep_complete_window = all(!is.na(sleep_hours)),
    all_metrics_complete_window = all(
      complete.cases(readiness, resting_hr, sleep_hours)
    ),
    all_metrics_complete_post_days = all(
      complete.cases(
        readiness[relative_day >= 1],
        resting_hr[relative_day >= 1],
        sleep_hours[relative_day >= 1]
      )
    ),
    later_training_reported = any(
      relative_day >= 1 &
        !is.na(logged_sessions_on_date)
    ),
    .groups = "drop"
  ) %>%
  left_join(
    candidates,
    by = c("event_id", "participant_id")
  )

# Summarize candidate counts and alternative coverage requirements
event_summary <- event_coverage %>%
  group_by(participant_id) %>%
  summarise(
    candidate_events = n(),
    nonoverlapping_events = sum(nonoverlapping_window),
    readiness_complete_windows = sum(readiness_complete_window),
    heart_rate_complete_windows = sum(heart_rate_complete_window),
    sleep_complete_windows = sum(sleep_complete_window),
    all_metrics_complete_post_windows =
      sum(all_metrics_complete_post_days),
    all_metrics_complete_five_day_windows =
      sum(all_metrics_complete_window),
    nonoverlapping_complete_five_day_windows = sum(
      nonoverlapping_window & all_metrics_complete_window
    ),
    events_with_later_training_records =
      sum(later_training_reported),
    .groups = "drop"
  )

# Save candidates, measurement coverage, and the declared rules
saveRDS(
  list(
    eligibility = eligibility,
    candidates = candidates,
    event_windows = event_windows,
    event_coverage = event_coverage,
    event_summary = event_summary,
    rules = list(
      minimum_training_days = minimum_training_days,
      threshold = "At or above personal logged-day 75th percentile",
      relative_days = seq.int(-1L, 3L),
      nonoverlap_rule =
        "No other high-load candidate within four calendar days"
    ),
    alignment_status = feature_output$alignment_status,
    missing_training_rule =
      "Absence of a training report does not establish a rest day"
  ),
  "data/intermediate/16_aim2_event_candidates.rds"
)

readr::write_csv(
  event_summary,
  "results/aim2_event_counts.csv"
)

# Display the feasibility results
cat("\nParticipant eligibility and personal thresholds:\n")
print(as.data.frame(eligibility), row.names = FALSE)

cat("\nHigh-load event counts and coverage:\n")
print(as.data.frame(event_summary), row.names = FALSE)

cat("\nTotal high-load candidates:", nrow(candidates), "\n")
cat(
  "Candidates with nonoverlapping windows:",
  sum(candidates$nonoverlapping_window),
  "\n"
)

cat("\nStage 16 completed. Candidate events and coverage were saved.\n")