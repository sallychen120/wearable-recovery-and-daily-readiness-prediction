# Stage 11: Plot Aim 1 estimates with robust confidence intervals
# Run from the RStudio project root

library(dplyr)
library(ggplot2)

# Read the interval comparisons from Stage 10
input_path <- "data/intermediate/10_aim1_robust_intervals.rds"

if (!file.exists(input_path)) {
  stop("Stage 10 output is missing. Run R/10_robust_intervals.R first.")
}

interval_output <- readRDS(input_path)

# Retain robust intervals for both primary predictors
# Express heart rate associations per 5 bpm and sleep per 1 hour
plot_results <- interval_output$primary_comparison %>%
  filter(inference == "Participant-clustered CR2") %>%
  mutate(
    multiplier = if_else(term == "hr_deviation", 5, 1),
    estimate = estimate * multiplier,
    std_error = std_error * multiplier,
    conf_low = conf_low * multiplier,
    conf_high = conf_high * multiplier,
    contrast = if_else(
      term == "hr_deviation",
      "Resting HR: 5 bpm above personal mean",
      "Sleep: 1 hour above personal mean"
    )
  )

# Arrange all four model versions consistently
model_order <- c(
  "iid_all",
  "ar1_all",
  "iid_without_p05",
  "ar1_without_p05"
)

model_labels <- c(
  "All participants\nIndependent residuals",
  "All participants\nAR(1) residuals",
  "Excluding p05\nIndependent residuals",
  "Excluding p05\nAR(1) residuals"
)

plot_results <- plot_results %>%
  mutate(
    model_label = factor(
      model,
      levels = rev(model_order),
      labels = rev(model_labels)
    ),
    contrast = factor(
      contrast,
      levels = c(
        "Resting HR: 5 bpm above personal mean",
        "Sleep: 1 hour above personal mean"
      )
    )
  )

# Display estimates and intervals without significance-based styling
results_plot <- ggplot(
  plot_results,
  aes(x = estimate, y = model_label)
) +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "grey55"
  ) +
  geom_segment(
    aes(
      x = conf_low,
      xend = conf_high,
      yend = model_label
    ),
    linewidth = 0.8,
    color = "#2166AC"
  ) +
  geom_point(size = 2.7, color = "#2166AC") +
  facet_wrap(~ contrast, scales = "free_x", nrow = 1) +
  labs(
    title = "Within-person deviations and daily readiness",
    subtitle = "Participant-clustered CR2 95% confidence intervals",
    x = "Estimated readiness difference (points)",
    y = NULL,
    caption = paste(
      "All participants: 14 people, 1,219 days.",
      "Excluding p05: 13 people, 1,158 days.\n",
      "Exploratory same-date associations;",
      "temporal ordering remains unverified."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_blank(),
    strip.text = element_text(face = "bold", size = 10),
    plot.caption = element_text(hjust = 0)
  )

# Save the figure and its numerical source table
dir.create("figures", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

ggsave(
  filename = "figures/11_aim1_robust_estimates.png",
  plot = results_plot,
  width = 12,
  height = 6,
  units = "in",
  dpi = 300,
  bg = "white"
)

results_table <- plot_results %>%
  select(
    model, contrast, estimate, std_error,
    df, conf_low, conf_high, p_value
  )

readr::write_csv(
  results_table,
  "results/aim1_robust_estimates_display_units.csv"
)

print(results_plot)

cat("\nAim 1 estimates in display units:\n")
print(as.data.frame(results_table), row.names = FALSE)

cat("\nStage 11 completed. The result figure and table were saved.\n")