# Stage 20: Construct historical features for readiness prediction
# Run from the RStudio project root

library(dplyr)
library(tidyr)

# Read the chronological calendar and fixed split definitions
input_path <- "data/intermediate/19_prediction_audit.rds"

if (!file.exists(input_path)) {
  stop("Stage 19 output is missing. Run R/19_audit_prediction_data.R first.")
}

prediction_output <- readRDS(input_path)
prediction_calendar <- prediction_output$prediction_calendar

window_days <- 14L
minimum_observations <- 5L

# Calculate statistics from earlier calendar rows only
# Stage 19 verified that each participant has a complete daily calendar
past_window_stats <- function(
    values,
    window_days,
    minimum_observations
) {
  historical_mean <- rep(NA_real_, length(values))
  historical_count <- integer(length(values))
  
  for (i in seq_along(values)) {
    if (i == 1L) {
      next
    }
    
    earlier_indices <- seq.int(
      max(1L, i - window_days),
      i - 1L
    )
    
    observed <- values[earlier_indices]
    observed <- observed[is.finite(observed)]
    
    historical_count[i] <- length(observed)
    
    if (length(observed) >= minimum_observations) {
      historical_mean[i] <- mean(observed)
    }
  }
  
  list(
    mean = historical_mean,
    count = historical_count
  )
}

# Build each participant's features using only their earlier observations
build_person_features <- function(person_data) {
  person_data <- arrange(person_data, date)
  
  hr_history <- past_window_stats(
    person_data$resting_hr,
    window_days,
    minimum_observations
  )
  
  sleep_history <- past_window_stats(
    person_data$sleep_hours,
    window_days,
    minimum_observations
  )
  
  person_data %>%
    mutate(
      readiness_past_count = lag(
        cumsum(!is.na(readiness)),
        default = 0L
      ),
      readiness_past_sum = lag(
        cumsum(replace_na(readiness, 0)),
        default = 0
      ),
      readiness_past_mean = if_else(
        readiness_past_count > 0,
        readiness_past_sum / readiness_past_count,
        NA_real_
      ),
      hr_baseline_lag2 = lag(hr_history$mean, 2),
      sleep_baseline_lag2 = lag(sleep_history$mean, 2),
      hr_baseline_count_lag2 = lag(hr_history$count, 2),
      sleep_baseline_count_lag2 = lag(sleep_history$count, 2),
      hr_deviation_lag2 = hr_lag2 - hr_baseline_lag2,
      sleep_deviation_lag2 = sleep_lag2 - sleep_baseline_lag2
    )
}

feature_calendar <- bind_rows(
  lapply(
    base::split(
      prediction_calendar,
      prediction_calendar$participant_id
    ),
    build_person_features
  )
) %>%
  arrange(participant_id, date) %>%
  mutate(
    weekday = c(
      "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
    )[as.integer(format(date, "%u"))],
    baseline_window_start = date - 16,
    baseline_window_end = date - 3
  )

# Keep the same candidate target dates as Stage 19
# Missing wearable features remain missing; target values are not imputed
prediction_features <- feature_calendar %>%
  filter(
    !is.na(readiness),
    !is.na(last_readiness)
  ) %>%
  transmute(
    participant_id,
    target_date = date,
    split,
    readiness_target = readiness,
    weekday,
    last_readiness,
    last_readiness_date,
    days_since_last_readiness,
    readiness_past_mean,
    readiness_past_count,
    hr_lag2,
    sleep_lag2,
    wearable_source_date,
    hr_baseline_lag2,
    sleep_baseline_lag2,
    hr_baseline_count_lag2,
    sleep_baseline_count_lag2,
    baseline_window_start,
    baseline_window_end,
    hr_deviation_lag2,
    sleep_deviation_lag2
  )

# Declare predictors explicitly to keep targets and audit dates out of models
feature_specification <- tibble::tribble(
  ~feature, ~type, ~model_B, ~model_C,
  "participant_id", "categorical", TRUE, TRUE,
  "weekday", "categorical", TRUE, TRUE,
  "last_readiness", "numeric", TRUE, TRUE,
  "readiness_past_mean", "numeric", TRUE, TRUE,
  "days_since_last_readiness", "numeric", TRUE, TRUE,
  "hr_lag2", "numeric", TRUE, TRUE,
  "sleep_lag2", "numeric", TRUE, TRUE,
  "hr_deviation_lag2", "numeric", FALSE, TRUE,
  "sleep_deviation_lag2", "numeric", FALSE, TRUE
)

# Document feature availability without dropping additional target dates
feature_coverage <- prediction_features %>%
  group_by(split) %>%
  summarise(
    participants = n_distinct(participant_id),
    prediction_targets = n(),
    both_absolute_wearables_available = sum(
      complete.cases(hr_lag2, sleep_lag2)
    ),
    both_personal_deviations_available = sum(
      complete.cases(hr_deviation_lag2, sleep_deviation_lag2)
    ),
    .groups = "drop"
  )

# Save the model-ready CSV for the Python stage
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

readr::write_csv(
  prediction_features,
  "data/processed/aim3_prediction_features.csv"
)

readr::write_csv(
  feature_specification,
  "results/prediction_feature_specification.csv"
)

readr::write_csv(
  feature_coverage,
  "results/prediction_feature_coverage.csv"
)

saveRDS(
  list(
    prediction_features = prediction_features,
    feature_specification = feature_specification,
    feature_coverage = feature_coverage,
    split_boundaries = prediction_output$split_boundaries,
    baseline_rule = paste(
      "Previous 14 calendar days before the wearable source date;",
      "at least 5 valid observations; features then lagged by 2 days"
    ),
    evaluation_design = prediction_output$evaluation_design,
    alignment_status = prediction_output$alignment_status
  ),
  "data/intermediate/20_prediction_features.rds"
)

cat("\nPrediction feature coverage:\n")
print(as.data.frame(feature_coverage), row.names = FALSE)

cat("\nDeclared model predictors:\n")
print(as.data.frame(feature_specification), row.names = FALSE)

cat("\nStage 20 completed. Historical prediction features were saved.\n")