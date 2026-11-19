# Stage 23: Fit ridge models and select penalties using validation MAE
# Run from the RStudio project root

library(dplyr)

design_path <- "data/intermediate/22_prediction_designs.rds"
baseline_path <- "data/intermediate/21_prediction_baselines.rds"

if (!file.exists(design_path) || !file.exists(baseline_path)) {
  stop("Stage 21 and Stage 22 outputs are required.")
}

design_output <- readRDS(design_path)
baseline_output <- readRDS(baseline_path)

y_train <- design_output$y_train
y_validation <- design_output$y_validation
validation_keys <- design_output$validation_keys

if (nrow(validation_keys) != length(y_validation)) {
  stop("Validation keys and outcomes must have matching lengths.")
}

# Define the penalty grid before fitting models
lambda_grid <- 10^seq(-4, 2, by = 0.5)

# Fit ridge regression using training-centered predictors
# Objective: mean squared training error + lambda * sum(beta^2)
# The intercept is not penalized
fit_ridge <- function(x, y, lambda) {
  if (nrow(x) != length(y)) {
    stop("Training predictors and outcomes must have matching lengths.")
  }
  
  if (!all(is.finite(x)) || !all(is.finite(y))) {
    stop("Training values must be finite.")
  }
  
  if (!is.finite(lambda) || lambda <= 0) {
    stop("The ridge penalty must be positive.")
  }
  
  if (any(abs(colMeans(x)) > 1e-8)) {
    stop("Predictors must be centered using training means.")
  }
  
  intercept <- mean(y)
  centered_y <- y - intercept
  
  coefficients <- solve(
    crossprod(x) / nrow(x) +
      diag(lambda, ncol(x)),
    crossprod(x, centered_y) / nrow(x)
  )
  
  coefficients <- setNames(
    as.numeric(coefficients),
    colnames(x)
  )
  
  list(
    intercept = intercept,
    coefficients = coefficients,
    lambda = lambda,
    training_rows = nrow(x)
  )
}

predict_ridge <- function(model, x) {
  if (!identical(
    colnames(x),
    names(model$coefficients)
  )) {
    stop("Prediction columns must match the fitted model.")
  }
  
  prediction <- as.numeric(
    model$intercept + x %*% model$coefficients
  )
  
  pmin(10, pmax(0, prediction))
}

score_predictions <- function(
    observed,
    predicted,
    participant_id
) {
  if (!all(is.finite(observed)) ||
      !all(is.finite(predicted))) {
    stop("Observed and predicted values must be finite.")
  }
  
  absolute_error <- abs(predicted - observed)
  
  participant_mae <- tapply(
    absolute_error,
    participant_id,
    mean
  )
  
  data.frame(
    prediction_targets = length(observed),
    participants = length(unique(participant_id)),
    mae = mean(absolute_error),
    rmse = sqrt(mean((predicted - observed)^2)),
    macro_mae = mean(participant_mae)
  )
}

tuning_rows <- list()
selected_rows <- list()
selected_models <- list()
selected_predictions <- list()

for (model_name in names(design_output$designs)) {
  cat("\nFitting model:", model_name, "\n")
  
  design <- design_output$designs[[model_name]]
  
  candidate_scores <- lapply(lambda_grid, function(lambda) {
    fitted_model <- fit_ridge(
      design$x_train,
      y_train,
      lambda
    )
    
    predicted <- predict_ridge(
      fitted_model,
      design$x_validation
    )
    
    scores <- score_predictions(
      y_validation,
      predicted,
      validation_keys$participant_id
    )
    
    data.frame(
      model = model_name,
      lambda = lambda,
      scores
    )
  })
  
  model_tuning <- bind_rows(candidate_scores)
  
  # Select the lowest validation MAE
  # Prefer the larger penalty if MAE values are exactly tied
  best <- model_tuning %>%
    arrange(mae, desc(lambda)) %>%
    slice(1) %>%
    mutate(
      grid_boundary = lambda %in% range(lambda_grid)
    )
  
  fitted_model <- fit_ridge(
    design$x_train,
    y_train,
    best$lambda[[1]]
  )
  
  predicted <- predict_ridge(
    fitted_model,
    design$x_validation
  )
  
  tuning_rows[[model_name]] <- model_tuning
  selected_rows[[model_name]] <- best
  selected_models[[model_name]] <- fitted_model
  
  selected_predictions[[model_name]] <- validation_keys %>%
    mutate(
      model = model_name,
      observed = y_validation,
      predicted = predicted,
      error = predicted - observed,
      absolute_error = abs(error),
      squared_error = error^2
    )
}

tuning_results <- bind_rows(tuning_rows)
selected_parameters <- bind_rows(selected_rows)

# Compare both ridge models with both questionnaire baselines
comparison <- bind_rows(
  baseline_output$validation_metrics %>%
    mutate(lambda = NA_real_),
  selected_parameters %>%
    select(-grid_boundary)
) %>%
  select(
    model,
    lambda,
    prediction_targets,
    participants,
    mae,
    rmse,
    macro_mae
  )

reference_mae <- baseline_output$validation_metrics %>%
  filter(model == baseline_output$selected_baseline) %>%
  pull(mae)

if (length(reference_mae) != 1L || reference_mae <= 0) {
  stop("A single positive reference baseline MAE is required.")
}

comparison <- comparison %>%
  mutate(
    mae_change_vs_reference = mae - reference_mae,
    mae_reduction_percent =
      100 * (reference_mae - mae) / reference_mae
  ) %>%
  arrange(mae)

validation_predictions <- bind_rows(
  baseline_output$validation_predictions,
  bind_rows(selected_predictions)
)

participant_metrics <- validation_predictions %>%
  group_by(model, participant_id) %>%
  summarise(
    prediction_targets = n(),
    mae = mean(absolute_error),
    rmse = sqrt(mean(squared_error)),
    .groups = "drop"
  ) %>%
  arrange(model, participant_id)

# Save preprocessing parameters with the fitted models
preprocessing <- lapply(
  design_output$designs,
  function(design) {
    design[c(
      "numeric_features",
      "category_levels",
      "medians",
      "centers",
      "scales"
    )]
  }
)

saveRDS(
  list(
    models = selected_models,
    preprocessing = preprocessing,
    lambda_grid = lambda_grid,
    selected_parameters = selected_parameters,
    tuning_results = tuning_results,
    validation_comparison = comparison,
    validation_predictions = validation_predictions,
    participant_metrics = participant_metrics,
    selected_baseline = baseline_output$selected_baseline,
    evaluation_rules = design_output$evaluation_rules,
    split_boundaries = design_output$split_boundaries,
    alignment_status = design_output$alignment_status,
    selection_rule = paste(
      "Minimize pooled validation MAE;",
      "prefer the larger lambda for exact ties"
    ),
    ridge_objective = paste(
      "Mean squared training error plus",
      "lambda times the sum of squared coefficients;",
      "unpenalized intercept"
    )
  ),
  "data/intermediate/23_prediction_models.rds"
)

readr::write_csv(
  tuning_results,
  "results/aim3_ridge_validation_tuning.csv"
)

readr::write_csv(
  selected_parameters,
  "results/aim3_ridge_selected_parameters.csv"
)

readr::write_csv(
  comparison,
  "results/aim3_validation_model_comparison.csv"
)

readr::write_csv(
  validation_predictions,
  "results/aim3_validation_predictions.csv"
)

readr::write_csv(
  participant_metrics,
  "results/aim3_validation_participant_metrics.csv"
)

cat("\nSelected ridge penalties:\n")
print(as.data.frame(selected_parameters), row.names = FALSE)

cat("\nValidation model comparison:\n")
print(as.data.frame(comparison), row.names = FALSE)

cat("\nStage 23 completed. Validation model results were saved.\n")