# Stage 10: Calculate participant-clustered robust confidence intervals
# Run from the RStudio project root

library(dplyr)
library(nlme)

if (!requireNamespace("clubSandwich", quietly = TRUE)) {
  stop("Install clubSandwich before running this script.")
}

# Read the four fitted models from Stage 09
input_path <- "data/intermediate/09_aim1_robustness.rds"

if (!file.exists(input_path)) {
  stop("Stage 09 output is missing. Run R/09_check_robustness.R first.")
}

robustness_output <- readRDS(input_path)
models <- robustness_output$models

# Recalculate uncertainty without refitting the model coefficients
# Each participant is treated as one independent cluster
calculate_cr2 <- function(fit, model_name) {
  robust_covariance <- clubSandwich::vcovCR(
    fit,
    cluster = nlme::getGroups(fit),
    type = "CR2"
  )
  
  coefficient_test <- clubSandwich::coef_test(
    fit,
    vcov = robust_covariance,
    test = "Satterthwaite"
  )
  
  critical_t <- qt(
    0.975,
    df = coefficient_test$df_Satt
  )
  
  result <- data.frame(
    model = model_name,
    inference = "Participant-clustered CR2",
    term = names(nlme::fixef(fit)),
    estimate = coefficient_test$beta,
    std_error = coefficient_test$SE,
    df = coefficient_test$df_Satt,
    conf_low =
      coefficient_test$beta -
      critical_t * coefficient_test$SE,
    conf_high =
      coefficient_test$beta +
      critical_t * coefficient_test$SE,
    p_value = coefficient_test$p_Satt,
    row.names = NULL
  )
  
  list(
    coefficients = result,
    covariance = robust_covariance
  )
}

# Apply the same inference method to every model version
robust_components <- setNames(
  lapply(names(models), function(model_name) {
    calculate_cr2(models[[model_name]], model_name)
  }),
  names(models)
)

robust_coefficients <- bind_rows(
  lapply(robust_components, function(x) x$coefficients)
)

# Preserve the original model-based intervals for comparison
model_based_coefficients <-
  robustness_output$coefficient_comparison %>%
  mutate(inference = "Model-based") %>%
  select(
    model, inference, term, estimate,
    std_error, df, conf_low, conf_high, p_value
  )

coefficient_comparison <- bind_rows(
  model_based_coefficients,
  robust_coefficients
)

primary_comparison <- coefficient_comparison %>%
  filter(term %in% c("hr_deviation", "sleep_deviation")) %>%
  arrange(term, model, inference)

# Save the inference results and covariance estimates
saveRDS(
  list(
    robust_components = robust_components,
    coefficient_comparison = coefficient_comparison,
    primary_comparison = primary_comparison,
    method = "Participant-clustered CR2 with Satterthwaite correction",
    package_version = as.character(
      packageVersion("clubSandwich")
    )
  ),
  "data/intermediate/10_aim1_robust_intervals.rds"
)

readr::write_csv(
  coefficient_comparison,
  "results/aim1_interval_comparison_all_terms.csv"
)

readr::write_csv(
  primary_comparison,
  "results/aim1_interval_comparison_primary.csv"
)

writeLines(
  capture.output(sessionInfo()),
  "results/10_session_info.txt"
)

# Display the primary estimates and both interval methods
cat("\nPrimary associations and interval comparison:\n")
print(
  as.data.frame(
    primary_comparison %>%
      select(
        model, inference, term,
        estimate, df, conf_low, conf_high
      )
  ),
  row.names = FALSE
)

cat("\nStage 10 completed. Robust interval comparisons were saved.\n")