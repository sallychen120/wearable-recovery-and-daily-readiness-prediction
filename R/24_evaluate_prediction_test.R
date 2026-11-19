# Stage 24: Evaluate fixed prediction models on the chronological test set
# Run from the RStudio project root

library(dplyr)

feature_path <- "data/intermediate/20_prediction_features.rds"
model_path <- "data/intermediate/23_prediction_models.rds"

if (!file.exists(feature_path) || !file.exists(model_path)) {
  stop("Stage 20 and Stage 23 outputs are required.")
}

feature_output <- readRDS(feature_path)
model_output <- readRDS(model_path)

test_data <- feature_output$prediction_features %>%
  filter(split == "test") %>%
  arrange(participant_id, target_date)

if (nrow(test_data) == 0L) {
  stop("Test observations are required.")
}

if (anyDuplicated(
  test_data[c("participant_id", "target_date")]
) > 0L) {
  stop("Duplicate test participant-date keys require review.")
}

validation_end <- feature_output$split_boundaries %>%
  filter(split == "validation") %>%
  pull(end_date)

if (length(validation_end) != 1L ||
    any(test_data$target_date <= validation_end)) {
  stop("Test dates must follow the validation period.")
}

required_values <- c(
  "readiness_target",
  "last_readiness",
  "readiness_past_mean"
)

if (!all(vapply(
  test_data[required_values],
  function(x) all(is.finite(x)),
  logical(1)
))) {
  stop("Test outcomes and baseline predictions must be finite.")
}

if (any(
  is.na(test_data$last_readiness_date) |
  test_data$last_readiness_date >= test_data$target_date
)) {
  stop("Readiness history must precede each target date.")
}

# Apply the saved training-only preprocessing parameters
make_test_matrix <- function(data, preprocessing) {
  numeric_features <- preprocessing$numeric_features
  
  numeric_matrix <- as.matrix(
    as.data.frame(data[numeric_features])
  )
  
  storage.mode(numeric_matrix) <- "double"
  missing_matrix <- !is.finite(numeric_matrix)
  
  for (feature in numeric_features) {
    missing_rows <- missing_matrix[, feature]
    
    numeric_matrix[missing_rows, feature] <-
      preprocessing$medians[[feature]]
  }
  
  indicator_matrix <- missing_matrix * 1
  
  colnames(indicator_matrix) <- paste0(
    numeric_features,
    "_missing"
  )
  
  raw_matrix <- cbind(numeric_matrix, indicator_matrix)
  
  for (feature in names(preprocessing$category_levels)) {
    values <- as.character(data[[feature]])
    levels <- preprocessing$category_levels[[feature]]
    
    if (anyNA(values) || any(!values %in% levels)) {
      stop(paste("Unknown or missing categorical values:", feature))
    }
    
    dummy_matrix <- vapply(
      levels,
      function(level) as.numeric(values == level),
      numeric(nrow(data))
    )
    
    colnames(dummy_matrix) <- paste0(feature, "_", levels)
    
    raw_matrix <- cbind(raw_matrix, dummy_matrix)
  }
  
  if (!identical(
    colnames(raw_matrix),
    names(preprocessing$centers)
  )) {
    stop("Test columns must match the saved training columns.")
  }
  
  x_test <- sweep(
    raw_matrix,
    2,
    preprocessing$centers,
    "-"
  )
  
  x_test <- sweep(
    x_test,
    2,
    preprocessing$scales,
    "/"
  )
  
  if (!all(is.finite(x_test))) {
    stop("Processed test predictors must be finite.")
  }
  
  x_test
}

# Record the evaluation configuration before calculating test errors
evaluation_plan <- data.frame(
  model = names(model_output$models),
  lambda = vapply(
    model_output$models,
    function(model) model$lambda,
    numeric(1)
  ),
  fitting_data = "Original training period",
  parameter_selection_data = "Validation period",
  preprocessing_data = "Original training period",
  history_updates = "Earlier observations only",
  primary_metric = "Pooled MAE",
  reference_baseline = model_output$selected_baseline
)

readr::write_csv(
  evaluation_plan,
  "results/aim3_test_evaluation_plan.csv"
)

# Predict with fixed ridge coefficients and preprocessing parameters
ridge_predictions <- list()

for (model_name in names(model_output$models)) {
  model <- model_output$models[[model_name]]
  preprocessing <- model_output$preprocessing[[model_name]]
  
  x_test <- make_test_matrix(
    test_data,
    preprocessing
  )
  
  if (!identical(
    colnames(x_test),
    names(model$coefficients)
  )) {
    stop("Test columns must match the fitted coefficients.")
  }
  
  predicted <- as.numeric(
    model$intercept + x_test %*% model$coefficients
  )
  
  ridge_predictions[[model_name]] <- test_data %>%
    transmute(
      participant_id,
      target_date,
      model = model_name,
      observed = readiness_target,
      predicted = pmin(10, pmax(0, predicted))
    )
}

# Evaluate both historical questionnaire baselines on the same dates
baseline_predictions <- bind_rows(
  test_data %>%
    transmute(
      participant_id,
      target_date,
      model = "baseline_last_readiness",
      observed = readiness_target,
      predicted = last_readiness
    ),
  test_data %>%
    transmute(
      participant_id,
      target_date,
      model = "baseline_past_mean",
      observed = readiness_target,
      predicted = readiness_past_mean
    )
)

test_predictions <- bind_rows(
  baseline_predictions,
  bind_rows(ridge_predictions)
) %>%
  mutate(
    predicted = pmin(10, pmax(0, predicted)),
    error = predicted - observed,
    absolute_error = abs(error),
    squared_error = error^2
  )

participant_metrics <- test_predictions %>%
  group_by(model, participant_id) %>%
  summarise(
    prediction_targets = n(),
    mae = mean(absolute_error),
    rmse = sqrt(mean(squared_error)),
    .groups = "drop"
  )

pooled_metrics <- test_predictions %>%
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

comparison <- pooled_metrics %>%
  left_join(macro_metrics, by = "model")

reference_mae <- comparison %>%
  filter(model == model_output$selected_baseline) %>%
  pull(mae)

if (length(reference_mae) != 1L) {
  stop("The validation-selected reference baseline is required.")
}

comparison <- comparison %>%
  mutate(
    mae_change_vs_reference = mae - reference_mae,
    mae_reduction_percent = if (reference_mae > 0) {
      100 * (reference_mae - mae) / reference_mae
    } else {
      NA_real_
    }
  ) %>%
  arrange(mae)

participant_reference <- participant_metrics %>%
  filter(model == model_output$selected_baseline) %>%
  transmute(
    participant_id,
    reference_mae = mae
  )

participant_metrics <- participant_metrics %>%
  left_join(participant_reference, by = "participant_id") %>%
  mutate(
    mae_change_vs_reference = mae - reference_mae
  ) %>%
  arrange(model, participant_id)

sample_context <- test_data %>%
  summarise(
    prediction_targets = n(),
    participants = n_distinct(participant_id),
    first_target_date = min(target_date),
    last_target_date = max(target_date),
    both_absolute_wearables_available = sum(
      complete.cases(hr_lag2, sleep_lag2)
    ),
    both_personal_deviations_available = sum(
      complete.cases(hr_deviation_lag2, sleep_deviation_lag2)
    )
  )

saveRDS(
  list(
    evaluation_plan = evaluation_plan,
    test_predictions = test_predictions,
    test_comparison = comparison,
    participant_metrics = participant_metrics,
    sample_context = sample_context,
    selected_baseline = model_output$selected_baseline,
    evaluation_rules = model_output$evaluation_rules,
    alignment_status = model_output$alignment_status
  ),
  "data/intermediate/24_prediction_test_results.rds"
)

readr::write_csv(
  comparison,
  "results/aim3_test_model_comparison.csv"
)

readr::write_csv(
  participant_metrics,
  "results/aim3_test_participant_metrics.csv"
)

readr::write_csv(
  test_predictions,
  "results/aim3_test_predictions.csv"
)

readr::write_csv(
  sample_context,
  "results/aim3_test_sample_context.csv"
)

cat("\nTest sample context:\n")
print(as.data.frame(sample_context), row.names = FALSE)

cat("\nFixed-model test performance:\n")
print(as.data.frame(comparison), row.names = FALSE)

cat("\nStage 24 completed. Chronological test results were saved.\n")