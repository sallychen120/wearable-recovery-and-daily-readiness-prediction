# Stage 04: Describe the draft participant-day panel
# Run from the RStudio project root

library(dplyr)
library(tidyr)
library(ggplot2)

# Read the output from Stage 03
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run R/03_merge.R first.")
}

merge_output <- readRDS(input_path)
daily_panel <- merge_output$daily_panel_draft

# Create output folders
dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

# Reshape the core measurements for summaries and plots
trajectory_data <- daily_panel %>%
  select(participant_id, date, readiness, resting_hr, sleep_hours) %>%
  pivot_longer(
    cols = c(readiness, resting_hr, sleep_hours),
    names_to = "metric",
    values_to = "value"
  )

# Return NA when a metric has no observed values
summarise_observed <- function(values, statistic) {
  observed <- values[!is.na(values)]
  
  if (length(observed) == 0) {
    return(NA_real_)
  }
  
  statistic(observed)
}

# Calculate descriptive statistics separately for each participant
metric_summary <- trajectory_data %>%
  group_by(participant_id, metric) %>%
  summarise(
    observed_days = sum(!is.na(value)),
    missing_days = sum(is.na(value)),
    mean = round(summarise_observed(value, mean), 2),
    sd = round(summarise_observed(value, sd), 2),
    minimum = round(summarise_observed(value, min), 2),
    maximum = round(summarise_observed(value, max), 2),
    .groups = "drop"
  )

# Flag short sleep records for review without excluding them
sleep_review <- daily_panel %>%
  filter(!is.na(sleep_hours), sleep_hours < 4) %>%
  select(
    participant_id, date, log_id,
    sleep_hours, start_time, end_time
  )

# Save summary tables
readr::write_csv(
  metric_summary,
  "results/metric_summary.csv"
)

readr::write_csv(
  merge_output$coverage_summary,
  "results/data_coverage.csv"
)

# Keep record-level review data in the local intermediate folder
readr::write_csv(
  sleep_review,
  "data/intermediate/04_sleep_review.csv"
)

# Add readable labels for the plots
plot_data <- trajectory_data %>%
  mutate(
    metric = factor(
      metric,
      levels = c("readiness", "resting_hr", "sleep_hours"),
      labels = c(
        "Readiness (0-10)",
        "Resting heart rate (bpm)",
        "Sleep duration (hours)"
      )
    )
  )

# Generate a separate draft figure for each participant
for (current_id in unique(daily_panel$participant_id)) {
  
  participant_plot_data <- plot_data %>%
    filter(participant_id == current_id)
  
  trajectory_plot <- ggplot(
    participant_plot_data,
    aes(x = date, y = value)
  ) +
    geom_point(size = 1.2, alpha = 0.7, na.rm = TRUE) +
    facet_wrap(~ metric, ncol = 1, scales = "free_y") +
    labs(
      title = paste0(
        current_id,
        ": Daily wearable and readiness measurements"
      ),
      subtitle = merge_output$alignment_status,
      x = "Date",
      y = NULL
    ) +
    theme_minimal(base_size = 12)
  
  ggsave(
    filename = file.path(
      "figures",
      paste0(current_id, "_trajectories_draft.png")
    ),
    plot = trajectory_plot,
    width = 10,
    height = 8,
    units = "in",
    dpi = 300
  )
  
  print(trajectory_plot)
}

# Display the summaries for inspection
cat("\nDescriptive statistics:\n")
print(as.data.frame(metric_summary), row.names = FALSE)

cat("\nSleep records flagged for review:\n")
print(
  as.data.frame(
    sleep_review %>%
      select(participant_id, date, sleep_hours)
  ),
  row.names = FALSE
)

cat("\nStage 04 completed. Summary tables and draft figures saved.\n")