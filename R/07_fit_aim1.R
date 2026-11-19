# Stage 07: Fit the initial Aim 1 mixed-effects model
# Run from the RStudio project root

library(dplyr)
library(lmerTest)

# Read the features and complete-case sample from Stage 05
input_path <- "data/intermediate/05_features.rds"

if (!file.exists(input_path)) {
  stop("Stage 05 output is missing. Run R/05_build_features.R first.")
}

feature_output <- readRDS(input_path)

# Define common reference values for the participant means
# Centering changes the intercept interpretation, not the predictor slopes
hr_reference <- mean(
  feature_output$participant_baselines$hr_person_mean
)

sleep_reference <- mean(
  feature_output$participant_baselines$sleep_person_mean
)

study_start <- min(feature_output$feature_panel$date)

# Prepare the model data without changing the selected sample
model_data <- feature_output$analysis_data %>%
  mutate(
    participant_id = factor(participant_id),
    hr_person_mean_c = hr_person_mean - hr_reference,
    sleep_person_mean_c = sleep_person_mean - sleep_reference,
    study_day_30 = as.numeric(date - study_start) / 30
  ) %>%
  arrange(participant_id, date)

# Fit a random-intercept model using REML
# Within-person associations are assumed to be common across participants
# Residual temporal dependence will be checked in the next stage
main_model <- lmerTest::lmer(
  readiness ~
    hr_deviation +
    sleep_deviation +
    hr_person_mean_c +
    sleep_person_mean_c +
    study_day_30 +
    (1 | participant_id),
  data = model_data,
  REML = TRUE,
  na.action = na.fail,
  control = lme4::lmerControl(
    optimizer = "bobyqa",
    optCtrl = list(maxfun = 100000)
  )
)

# Extract fixed effects using Satterthwaite degrees of freedom
model_summary <- summary(
  main_model,
  ddf = "Satterthwaite"
)

coefficient_matrix <- coef(model_summary)

# Calculate approximate 95% t-based confidence intervals
critical_t <- qt(
  0.975,
  df = coefficient_matrix[, "df"]
)

fixed_effects <- data.frame(
  term = rownames(coefficient_matrix),
  estimate = coefficient_matrix[, "Estimate"],
  std_error = coefficient_matrix[, "Std. Error"],
  df = coefficient_matrix[, "df"],
  conf_low =
    coefficient_matrix[, "Estimate"] -
    critical_t * coefficient_matrix[, "Std. Error"],
  conf_high =
    coefficient_matrix[, "Estimate"] +
    critical_t * coefficient_matrix[, "Std. Error"],
  p_value = coefficient_matrix[, "Pr(>|t|)"],
  row.names = NULL
)

# Record numerical fitting checks
# These checks do not replace residual diagnostics
convergence_messages <- main_model@optinfo$conv$lme4$messages

fit_status <- data.frame(
  observations = nobs(main_model),
  participants = nlevels(model_data$participant_id),
  singular_fit = lme4::isSingular(main_model, tol = 1e-4),
  optimizer_converged = all(main_model@optinfo$conv$opt == 0),
  lme4_messages = if (is.null(convergence_messages)) {
    "None"
  } else {
    paste(unlist(convergence_messages), collapse = "; ")
  }
)

# Preserve the model, exact sample, and reference values
model_output <- list(
  main_model = main_model,
  model_data = model_data,
  fixed_effects = fixed_effects,
  fit_status = fit_status,
  reference_values = list(
    hr_reference = hr_reference,
    sleep_reference = sleep_reference,
    study_start = study_start
  ),
  alignment_status = feature_output$alignment_status,
  baseline_definition = feature_output$baseline_definition,
  readiness_rule = feature_output$readiness_rule,
  ci_method = "Approximate t intervals using Satterthwaite degrees of freedom",
  analysis_status = "Initial fit; model diagnostics pending"
)

dir.create("data/intermediate", recursive = TRUE, showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

saveRDS(
  model_output,
  "data/intermediate/07_aim1_models.rds"
)

readr::write_csv(
  fixed_effects,
  "results/aim1_fixed_effects.csv"
)

readr::write_csv(
  fit_status,
  "results/aim1_fit_status.csv"
)

# Record the software versions used for this fit
writeLines(
  capture.output(sessionInfo()),
  "results/07_session_info.txt"
)

# Display the model and the two primary associations
cat("\nInitial Aim 1 model summary:\n")
print(model_summary)

cat("\nPrimary within-person associations:\n")
print(
  fixed_effects %>%
    filter(term %in% c("hr_deviation", "sleep_deviation")),
  row.names = FALSE
)

cat("\nNumerical fitting checks:\n")
print(fit_status, row.names = FALSE)

cat("\nStage 07 completed. Model and coefficient tables were saved.\n")
cat("Model diagnostics are still required before final interpretation.\n")