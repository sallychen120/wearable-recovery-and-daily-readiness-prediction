# Stage 17: Describe measurement changes around high-load training dates
# Run from the RStudio project root

library(dplyr)
library(tidyr)
library(ggplot2)

# Read candidate events and their measurement windows
input_path <- "data/intermediate/16_aim2_event_candidates.rds"

if (!file.exists(input_path)) {
  stop("Stage 16 output is missing. Run R/16_select_training_events.R first.")
}

event_output <- readRDS(input_path)

# Define both samples using measurement availability and window overlap
complete_events <- event_output$event_coverage %>%
  filter(all_metrics_complete_window)

main_events <- complete_events %>%
  filter(nonoverlapping_window)

if (nrow(main_events) == 0) {
  stop("No complete nonoverlapping windows are available.")
}

# Summarize sample composition and subsequent logged training
sample_context <- bind_rows(
  main_events %>% mutate(sample = "Nonoverlapping"),
  complete_events %>% mutate(sample = "All complete")
) %>%
  group_by(sample) %>%
  summarise(
    participants = n_distinct(participant_id),
    events = n(),
    events_with_later_training_records = sum(later_training_reported),
    .groups = "drop"
  )

# Reshape complete event windows into one row per metric and relative day
event_long <- event_output$event_windows %>%
  semi_join(
    complete_events,
    by = c("event_id", "participant_id")
  ) %>%
  select(
    event_id, participant_id, relative_day,
    nonoverlapping_window,
    readiness, resting_hr, sleep_hours
  ) %>%
  pivot_longer(
    cols = c(resting_hr, sleep_hours, readiness),
    names_to = "metric",
    values_to = "value"
  ) %>%
  group_by(event_id, participant_id, metric) %>%
  mutate(
    reference_value = value[relative_day == -1],
    change = value - reference_value
  ) %>%
  ungroup()

# Retain the primary sample and the broader descriptive comparison
sample_long <- bind_rows(
  event_long %>%
    filter(nonoverlapping_window) %>%
    mutate(sample = "Nonoverlapping"),
  event_long %>%
    mutate(sample = "All complete")
)

# Average events within each participant first
participant_summary <- sample_long %>%
  group_by(sample, participant_id, metric, relative_day) %>%
  summarise(
    participant_mean_change = mean(change),
    events = n_distinct(event_id),
    .groups = "drop"
  ) %>%
  mutate(
    metric_label = factor(
      metric,
      levels = c("resting_hr", "sleep_hours", "readiness"),
      labels = c(
        "Resting heart rate (bpm)",
        "Sleep duration (hours)",
        "Readiness (points)"
      )
    )
  )

# Give each participant equal weight in the descriptive mean
grand_summary <- participant_summary %>%
  group_by(sample, metric, metric_label, relative_day) %>%
  summarise(
    mean_change = mean(participant_mean_change),
    participants = n(),
    events = sum(events),
    .groups = "drop"
  )

main_participants <- participant_summary %>%
  filter(sample == "Nonoverlapping")

main_mean <- grand_summary %>%
  filter(sample == "Nonoverlapping")

main_context <- sample_context %>%
  filter(sample == "Nonoverlapping")

trajectory_theme <- theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0)
  )

# Show participant means and the equally weighted primary mean
primary_plot <- ggplot(
  main_participants,
  aes(
    x = relative_day,
    y = participant_mean_change,
    group = participant_id
  )
) +
  geom_hline(yintercept = 0, color = "grey65") +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "grey70"
  ) +
  geom_line(color = "grey60", alpha = 0.7, linewidth = 0.6) +
  geom_point(color = "grey60", alpha = 0.7, size = 1.2) +
  geom_line(
    data = main_mean,
    aes(y = mean_change, group = 1),
    color = "#2166AC",
    linewidth = 1.2
  ) +
  geom_point(
    data = main_mean,
    aes(y = mean_change, group = 1),
    color = "#2166AC",
    size = 2.5
  ) +
  facet_wrap(~ metric_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = -1:3) +
  labs(
    title = "Changes around high-load training dates",
    subtitle = paste0(
      main_context$participants, " participants; ",
      main_context$events, " complete nonoverlapping windows"
    ),
    x = "Calendar day relative to the training date",
    y = "Change from source date -1",
    caption = paste(
      "Thin grey lines: participant means. Blue line: equal-participant mean.\n",
      "Other training may occur within windows. Source-date alignment remains unverified."
    )
  ) +
  trajectory_theme

# Label both samples with their actual sizes
sample_labels <- setNames(
  paste0(
    sample_context$sample, ": ",
    sample_context$participants, " participants, ",
    sample_context$events, " events"
  ),
  sample_context$sample
)

comparison_plot <- ggplot(
  grand_summary,
  aes(
    x = relative_day,
    y = mean_change,
    color = sample,
    group = sample
  )
) +
  geom_hline(yintercept = 0, color = "grey65") +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "grey70"
  ) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  facet_wrap(~ metric_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = -1:3) +
  scale_color_manual(
    values = c(
      "Nonoverlapping" = "#2166AC",
      "All complete" = "#B35806"
    ),
    breaks = c("Nonoverlapping", "All complete"),
    labels = sample_labels[c("Nonoverlapping", "All complete")]
  ) +
  labs(
    title = "Trajectory comparison across event samples",
    subtitle = "Equal-participant descriptive means",
    x = "Calendar day relative to the training date",
    y = "Change from source date -1",
    color = NULL,
    caption = paste(
      "Samples differ in participants and events; this is a descriptive comparison.\n",
      "Source-date alignment remains unverified."
    )
  ) +
  trajectory_theme +
  theme(legend.position = "bottom")

# Save numerical summaries, event membership, and figures
readr::write_csv(
  sample_context,
  "results/aim2_trajectory_sample_context.csv"
)

readr::write_csv(
  grand_summary,
  "results/aim2_trajectory_summary.csv"
)

readr::write_csv(
  participant_summary,
  "data/intermediate/17_participant_trajectories.csv"
)

saveRDS(
  list(
    primary_event_ids = main_events$event_id,
    complete_event_ids = complete_events$event_id,
    participant_summary = participant_summary,
    grand_summary = grand_summary,
    sample_context = sample_context,
    reference_definition = "Measurement on the preceding source date",
    alignment_status = event_output$alignment_status
  ),
  "data/intermediate/17_aim2_trajectories.rds"
)

ggsave(
  "figures/17_aim2_primary_trajectories.png",
  plot = primary_plot,
  width = 10, height = 9, dpi = 300, bg = "white"
)

ggsave(
  "figures/17_aim2_window_comparison.png",
  plot = comparison_plot,
  width = 10, height = 9, dpi = 300, bg = "white"
)

cat("\nTrajectory sample context:\n")
print(as.data.frame(sample_context), row.names = FALSE)

cat("\nEqual-participant mean changes:\n")
print(as.data.frame(grand_summary), row.names = FALSE)

print(primary_plot)
print(comparison_plot)

cat("\nStage 17 completed. Descriptive trajectories and summaries were saved.\n")