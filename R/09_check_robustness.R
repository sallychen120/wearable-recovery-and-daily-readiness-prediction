# Stage 09: Examine temporal dependence and p05 sensitivity
# Run from the RStudio project root

library(dplyr)
library(nlme)

# Read the exact model sample and transformations from Stage 07
input_path <- "data/intermediate/07_aim1_models.rds"

if (!file.exists(input_path)) {
  stop("Stage 07 output is missing. Run R/07_fit_aim1.R first.")
}

model_output <- readRDS(input_path)

# Preserve actual calendar-day distances, including gaps
full_data <- model_output$model_data %>%
  mutate(
    calendar_day = as.integer(
      date - model_output$reference_values$study_start
    )
  ) %>%
  arrange(participant_id, date) %>%
  as.data.frame()

without_p05 <- full_data %>%
  filter(participant_id != "p05") %>%
  droplevels()

# Keep the fixed effects identical to Stage 07
fixed_formula <- readiness ~
  hr_deviation +
  sleep_deviation +
  hr_person_mean_c +
  sleep_person_mean_c +
  study_day_30

# Fit each version using nlme's default optimizer
fit_version <- function(data, use_ar1) {
  correlation_structure <- if (use_ar1) {
    nlme::corAR1(
      value = 0.2,
      form = ~ calendar_day | participant_id,
      fixed = FALSE
    )
  } else {
    NULL
  }
  
  nlme::lme(
    fixed = fixed_formula,
    random = ~ 1 | participant_id,
    correlation = correlation_structure,
    data = data,
    method = "REML",
    na.action = na.fail,
    control = nlme::lmeControl(
      opt = "nlminb",
      maxIter = 100,
      msMaxIter = 200,
      msMaxEval = 1000,
      returnObject = FALSE
    )
  )
}

# Fit the planned comparisons
# Fit models sequentially and display progress
models <- list()

cat("\nFitting iid_all...\n")
models$iid_all <- fit_version(full_data, FALSE)

cat("\nFitting ar1_all...\n")
models$ar1_all <- fit_version(full_data, TRUE)

cat("\nFitting iid_without_p05...\n")
models$iid_without_p05 <- fit_version(without_p05, FALSE)

cat("\nFitting ar1_without_p05...\n")
models$ar1_without_p05 <- fit_version(without_p05, TRUE)

# Extract coefficients and approximate nlme t-based intervals
extract_coefficients <- function(fit, model_name) {
  coefficient_table <- summary(fit)$tTable
  critical_t <- qt(0.975, df = coefficient_table[, "DF"])
  
  data.frame(
    model = model_name,
    term = rownames(coefficient_table),
    estimate = coefficient_table[, "Value"],
    std_error = coefficient_table[, "Std.Error"],
    df = coefficient_table[, "DF"],
    conf_low =
      coefficient_table[, "Value"] -
      critical_t * coefficient_table[, "Std.Error"],
    conf_high =
      coefficient_table[, "Value"] +
      critical_t * coefficient_table[, "Std.Error"],
    p_value = coefficient_table[, "p-value"],
    row.names = NULL
  )
}

coefficient_comparison <- bind_rows(
  lapply(names(models), function(model_name) {
    extract_coefficients(models[[model_name]], model_name)
  })
)

# Summarize sample sizes and the estimated AR1 parameter
model_summary <- bind_rows(
  lapply(names(models), function(model_name) {
    fit <- models[[model_name]]
    correlation_structure <- fit$modelStruct$corStruct
    
    rho <- if (is.null(correlation_structure)) {
      NA_real_
    } else {
      as.numeric(coef(
        correlation_structure,
        unconstrained = FALSE
      ))
    }
    
    data.frame(
      model = model_name,
      observations = nobs(fit),
      participants = length(unique(nlme::getGroups(fit))),
      ar1_rho = rho
    )
  })
)

# Extract residuals adjusted for the fitted covariance structure
normalized_data <- bind_rows(
  lapply(names(models), function(model_name) {
    fit <- models[[model_name]]
    data <- nlme::getData(fit)
    
    data %>%
      select(participant_id, date, readiness) %>%
      mutate(
        model = model_name,
        fitted_readiness = as.numeric(fitted(fit)),
        normalized_residual = as.numeric(
          residuals(fit, type = "normalized")
        )
      )
  })
)

# Inspect only pairs separated by exactly one calendar day
residual_pairs <- normalized_data %>%
  group_by(model, participant_id) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    previous_date = lag(date),
    previous_residual = lag(normalized_residual),
    gap_days = as.integer(date - previous_date)
  ) %>%
  ungroup() %>%
  filter(!is.na(gap_days), gap_days == 1)

safe_cor <- function(x, y) {
  if (length(x) < 3L || sd(x) == 0 || sd(y) == 0) {
    return(NA_real_)
  }
  
  cor(x, y)
}

lag_summary <- residual_pairs %>%
  group_by(model, participant_id) %>%
  summarise(
    consecutive_day_pairs = n(),
    lag1_residual_correlation = safe_cor(
      previous_residual,
      normalized_residual
    ),
    .groups = "drop"
  )

# Save all versions and their diagnostics
robustness_output <- list(
  models = models,
  full_data = full_data,
  without_p05 = without_p05,
  coefficient_comparison = coefficient_comparison,
  model_summary = model_summary,
  normalized_data = normalized_data,
  lag_summary = lag_summary,
  alignment_status = model_output$alignment_status,
  ci_method = "Approximate nlme t-based confidence intervals",
  remaining_assumptions = paste(
    "Common predictor slopes and residual variance;",
    "one shared AR1 parameter within each AR1 model"
  )
)

saveRDS(
  robustness_output,
  "data/intermediate/09_aim1_robustness.rds"
)

readr::write_csv(
  coefficient_comparison,
  "results/aim1_robustness_coefficients.csv"
)

readr::write_csv(
  model_summary,
  "results/aim1_robustness_model_summary.csv"
)

readr::write_csv(
  lag_summary,
  "results/aim1_robustness_residual_correlations.csv"
)

# Display the primary comparisons
cat("\nModel sample sizes and AR1 estimates:\n")
print(as.data.frame(model_summary), row.names = FALSE)

cat("\nPrimary association estimates across all four versions:\n")
print(
  as.data.frame(
    coefficient_comparison %>%
      filter(term %in% c("hr_deviation", "sleep_deviation")) %>%
      select(model, term, estimate, conf_low, conf_high)
  ),
  row.names = FALSE
)

cat("\nStage 09 completed. All four model versions were saved.\n")