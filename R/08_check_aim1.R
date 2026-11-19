# Stage 08: Inspect the initial Aim 1 model diagnostics
# Run from the RStudio project root

library(dplyr)
library(ggplot2)
library(lmerTest)

# Read the model and its exact analysis sample
input_path <- "data/intermediate/07_aim1_models.rds"

if (!file.exists(input_path)) {
  stop("Stage 07 output is missing. Run R/07_fit_aim1.R first.")
}

model_output <- readRDS(input_path)
main_model <- model_output$main_model

# Calculate conditional fitted values and scaled residuals
# Scaled residuals are not studentized residuals
diagnostic_data <- model_output$model_data %>%
  mutate(
    fitted_readiness = as.numeric(fitted(main_model)),
    scaled_residual =
      as.numeric(residuals(main_model)) / sigma(main_model)
  )

# Summarize residual patterns without excluding observations
diagnostic_summary <- diagnostic_data %>%
  group_by(participant_id) %>%
  summarise(
    complete_days = n(),
    scaled_residual_sd = sd(scaled_residual),
    residuals_above_3_in_absolute_value =
      sum(abs(scaled_residual) > 3),
    fitted_values_outside_readiness_scale =
      sum(fitted_readiness < 0 | fitted_readiness > 10),
    .groups = "drop"
  )

# Pair residuals only when observations are exactly one calendar day apart
# A later observed record is not necessarily the following day
lag_pairs <- diagnostic_data %>%
  group_by(participant_id) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    previous_date = lag(date),
    previous_residual = lag(scaled_residual),
    gap_days = as.integer(date - previous_date)
  ) %>%
  ungroup() %>%
  filter(!is.na(gap_days), gap_days == 1)

# Return NA when a correlation cannot be calculated
safe_cor <- function(x, y) {
  if (length(x) < 3L || sd(x) == 0 || sd(y) == 0) {
    return(NA_real_)
  }
  
  cor(x, y)
}

# Calculate descriptive lag-one correlations within participants
lag_summary <- lag_pairs %>%
  group_by(participant_id) %>%
  summarise(
    consecutive_day_pairs = n(),
    lag1_residual_correlation = safe_cor(
      previous_residual,
      scaled_residual
    ),
    .groups = "drop"
  )

# Use consistent figure formatting
diagnostic_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

# Inspect residual patterns across fitted readiness values
residual_plot <- ggplot(
  diagnostic_data,
  aes(x = fitted_readiness, y = scaled_residual)
) +
  geom_hline(yintercept = 0, color = "grey60") +
  geom_point(alpha = 0.3, size = 1) +
  geom_smooth(
    method = "loess",
    formula = y ~ x,
    se = FALSE,
    color = "#2166AC"
  ) +
  labs(
    title = "Residuals versus fitted readiness",
    x = "Conditional fitted readiness",
    y = "Residual divided by model residual SD"
  ) +
  diagnostic_theme

# Inspect the shape and tails of the residual distribution
qq_plot <- ggplot(
  diagnostic_data,
  aes(sample = scaled_residual)
) +
  stat_qq(alpha = 0.4, size = 1) +
  stat_qq_line(color = "#2166AC") +
  labs(
    title = "Residual normal Q-Q plot",
    x = "Theoretical normal quantile",
    y = "Observed scaled residual quantile"
  ) +
  diagnostic_theme

# Inspect residual dependence between actual consecutive days
lag_plot <- ggplot(
  lag_pairs,
  aes(x = previous_residual, y = scaled_residual)
) +
  geom_point(alpha = 0.4, size = 1) +
  geom_smooth(
    method = "lm",
    formula = y ~ x,
    se = FALSE,
    color = "#2166AC"
  ) +
  facet_wrap(~ participant_id, ncol = 4) +
  labs(
    title = "Residuals on consecutive calendar days",
    subtitle = "Descriptive patterns within each participant",
    x = "Previous day's scaled residual",
    y = "Current day's scaled residual"
  ) +
  diagnostic_theme

# Save tables and figures
dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

readr::write_csv(
  diagnostic_summary,
  "results/aim1_residual_summary.csv"
)

readr::write_csv(
  lag_summary,
  "results/aim1_lag1_residual_correlations.csv"
)

saveRDS(
  list(
    diagnostic_data = diagnostic_data,
    lag_pairs = lag_pairs,
    diagnostic_summary = diagnostic_summary,
    lag_summary = lag_summary
  ),
  "data/intermediate/08_aim1_diagnostics.rds"
)

ggsave(
  "figures/08_residuals_fitted.png",
  plot = residual_plot,
  width = 9, height = 6, dpi = 300, bg = "white"
)

ggsave(
  "figures/08_residual_qq.png",
  plot = qq_plot,
  width = 9, height = 6, dpi = 300, bg = "white"
)

ggsave(
  "figures/08_residual_lag1.png",
  plot = lag_plot,
  width = 12, height = 10, dpi = 300, bg = "white"
)

# Display the diagnostic results
cat("\nResidual summary:\n")
print(as.data.frame(diagnostic_summary), row.names = FALSE)

cat("\nConsecutive-day residual correlations:\n")
print(as.data.frame(lag_summary), row.names = FALSE)

print(residual_plot)
print(qq_plot)
print(lag_plot)

cat("\nStage 08 completed. Diagnostic tables and figures were saved.\n")