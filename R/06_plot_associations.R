# Stage 06: Plot participant-specific associations
# Run from the RStudio project root

library(dplyr)
library(ggplot2)

# Read the features created in Stage 05
input_path <- "data/intermediate/05_features.rds"

if (!file.exists(input_path)) {
  stop("Stage 05 output is missing. Run R/05_build_features.R first.")
}

feature_output <- readRDS(input_path)
analysis_data <- feature_output$analysis_data
analysis_counts <- feature_output$analysis_counts

# Include the number of complete days in each participant label
participant_labels <- setNames(
  paste0(
    analysis_counts$participant_id,
    " (n = ", analysis_counts$complete_days, ")"
  ),
  analysis_counts$participant_id
)

# Use the same plotting settings for both predictors
make_association_plot <- function(data, predictor, axis_label, plot_title) {
  ggplot(
    data,
    aes(x = .data[[predictor]], y = readiness)
  ) +
    geom_vline(
      xintercept = 0,
      linetype = "dashed",
      color = "grey65"
    ) +
    geom_point(
      position = position_jitter(
        width = 0,
        height = 0.08,
        seed = 42
      ),
      alpha = 0.4,
      size = 1
    ) +
    geom_smooth(
      method = "lm",
      formula = y ~ x,
      se = FALSE,
      color = "#2166AC",
      linewidth = 0.7
    ) +
    facet_wrap(
      ~ participant_id,
      ncol = 4,
      labeller = as_labeller(participant_labels)
    ) +
    scale_y_continuous(breaks = c(0, 5, 10)) +
    coord_cartesian(ylim = c(-0.2, 10.2)) +
    labs(
      title = plot_title,
      subtitle = paste(
        "Unadjusted participant-specific trends;",
        "time alignment unverified"
      ),
      x = axis_label,
      y = "Readiness (0-10)",
      caption = paste(
        "Points are slightly displaced vertically for visibility.",
        "Lines are descriptive."
      )
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold")
    )
}

# Plot resting heart rate deviations
hr_plot <- make_association_plot(
  data = analysis_data,
  predictor = "hr_deviation",
  axis_label = "Resting heart rate minus participant mean (bpm)",
  plot_title = "Resting heart rate deviations and readiness"
)

# Plot sleep duration deviations
sleep_plot <- make_association_plot(
  data = analysis_data,
  predictor = "sleep_deviation",
  axis_label = "Sleep duration minus participant mean (hours)",
  plot_title = "Sleep duration deviations and readiness"
)

# Save both figures with a white background
dir.create("figures", showWarnings = FALSE)

ggsave(
  filename = "figures/06_hr_deviation_readiness.png",
  plot = hr_plot,
  width = 12,
  height = 10,
  units = "in",
  dpi = 300,
  bg = "white"
)

ggsave(
  filename = "figures/06_sleep_deviation_readiness.png",
  plot = sleep_plot,
  width = 12,
  height = 10,
  units = "in",
  dpi = 300,
  bg = "white"
)

# Display both figures
print(hr_plot)
print(sleep_plot)

cat("\nStage 06 completed. Both association figures were saved.\n")