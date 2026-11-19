# Stage 21: Compare historical readiness prediction baselines
# Run from the RStudio project root

library(dplyr)

input_path <- "data/intermediate/20_prediction_features.rds"

if (!file.exists(input_path)) {
  stop("Stage 20 output is missing. Run Stage 20 first.")
}

feature_output <- readRDS(input_path)

# Select development data without evaluating the test period
development_data <- feature_output$prediction_features %>%
  filter(split %in% c("train", "validation"))

training_data <- development_data %>%
  filter(split == "train")

validation_data <- development_data %>%
  filter(split == "validation") %>%
  arrange(participant_id, target_date)

if (nrow(training_data) == 0L || nrow(validation_data) == 0L) {
  stop("Training and validation observations are required.")
}

if (max(training_data$target_date) >=
    min(validation_data$target_date)) {
  stop("Training dates must precede validation dates.")
}

if (anyDuplicated(
  validation_data[c("participant_id", "target_date")]
) > 0L) {
  stop("Duplicate validation participant-date keys require review.")
}

required_values <- c(
  "readiness_target",
  "last_readiness",
  "readiness_past_mean"
)

if (!all(vapply(
  validation_data[required_values],
  function(x) all(is.finite(x)),
  logical(1)
))) {
  stop("Validation targets and baseline predictions must be finite.")
}

if (any(
  validation_data$readiness_target < 0 |
  validation_data$readiness_target > 10
)) {
  stop("Readiness targets must be between 0 and 10.")
}

if (any(
  is.na(validation_data$last_readiness_date) |
  validation_data$last_readiness_date >=
  validation_data$target_date
)) {
  stop("Readiness history must precede each target date.")
}

# Apply two fixed prediction rules to the same validation dates
# Historical features were constructed in Stage 20
validation_predictions <- bind_rows(
  validation_data %>%
    transmute(
      participant_id,
      target_date,
      model = "baseline_last_readiness",
      observed = readiness_target,
      predicted = last_readiness
    ),
  validation_data %>%
    transmute(
      participant_id,
      target_date,
      model = "baseline_past_mean",
      observed = readiness_target,
      predicted = readiness_past_mean
    )
) %>%
  mutate(
    predicted = pmin(10, pmax(0, predicted)),
    error = predicted - observed,
    absolute_error = abs(error),
    squared_error = error^2
  )

# Calculate participant-specific errors
participant_metrics <- validation_predictions %>%
  group_by(model, participant_id) %>%
  summarise(
    prediction_targets = n(),
    mae = mean(absolute_error),
    rmse = sqrt(mean(squared_error)),
    .groups = "drop"
  ) %>%
  arrange(model, participant_id)

# Use pooled validation MAE as the primary selection metric
# Macro MAE gives equal weight to each participant
pooled_metrics <- validation_predictions %>%
  group_by(model) %>%
  summarise(
    prediction_targets = n(),
    participants = n_distinct(participant_id),
    mae = mean(absolute_error),
    rmse = sqrt(mean(squared_error)),
    .groups = "drop"
  )

macro_metrics <- participant_metrics %>%
  group_by(model) %>%
  summarise(
    macro_mae = mean(mae),
    .groups = "drop"
  )

validation_metrics <- pooled_metrics %>%
  left_join(macro_metrics, by = "model")

# Prefer the last-readiness baseline if MAE values are exactly tied
baseline_order <- c(
  "baseline_last_readiness",
  "baseline_past_mean"
)

validation_metrics <- validation_metrics %>%
  arrange(
    mae,
    match(model, baseline_order)
  )

selected_baseline <- validation_metrics$model[[1]]

selection <- validation_metrics %>%
  slice(1) %>%
  mutate(
    selection_dataset = "validation",
    selection_metric = "pooled MAE"
  )

# Preserve the evaluation rules for the later model comparison
evaluation_rules <- list(
  primary_metric = "Pooled MAE",
  secondary_metrics = c(
    "Pooled RMSE",
    "Equal-participant macro MAE",
    "Participant-specific MAE and RMSE"
  ),
  prediction_bounds = c(0, 10),
  baseline_tie_rule = "Prefer the last-readiness baseline",
  history_rule = paste(
    "Use only observations preceding each target date;",
    "earlier validation observations may update later histories"
  ),
  model_preprocessing_rule = paste(
    "Estimate imputation and scaling parameters",
    "from the model training data only"
  ),
  evaluation_scope = paste(
    "Retrospective chronological prediction",
    "for previously observed participants"
  )
)

dir.create("results", recursive = TRUE, showWarnings = FALSE)

readr::write_csv(
  validation_predictions,
  "results/aim3_baseline_validation_predictions.csv"
)

readr::write_csv(
  participant_metrics,
  "results/aim3_baseline_validation_participant_metrics.csv"
)

readr::write_csv(
  validation_metrics,
  "results/aim3_baseline_validation_metrics.csv"
)

readr::write_csv(
  selection,
  "results/aim3_selected_baseline.csv"
)

saveRDS(
  list(
    validation_predictions = validation_predictions,
    participant_metrics = participant_metrics,
    validation_metrics = validation_metrics,
    selected_baseline = selected_baseline,
    evaluation_rules = evaluation_rules,
    split_boundaries = feature_output$split_boundaries,
    evaluation_design = feature_output$evaluation_design,
    alignment_status = feature_output$alignment_status
  ),
  "data/intermediate/21_prediction_baselines.rds"
)

cat("\nDevelopment sample sizes:\n")
cat("Training targets:", nrow(training_data), "\n")
cat("Validation targets:", nrow(validation_data), "\n")

cat("\nValidation baseline performance:\n")
print(as.data.frame(validation_metrics), row.names = FALSE)

cat("\nSelected reference baseline:", selected_baseline, "\n")
cat("\nStage 21 completed. Validation baseline results were saved.\n")