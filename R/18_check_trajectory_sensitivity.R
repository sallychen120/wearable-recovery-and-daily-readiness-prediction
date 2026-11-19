# Stage 18: Check sensitivity to omitting individual participants
# Run from the RStudio project root

library(dplyr)
library(ggplot2)

# Read the participant-level trajectories from Stage 17
input_path <- "data/intermediate/17_aim2_trajectories.rds"

if (!file.exists(input_path)) {
  stop("Stage 17 output is missing. Run R/17_plot_training_trajectories.R first.")
}

trajectory_output <- readRDS(input_path)

primary_participants <- trajectory_output$participant_summary %>%
  filter(sample == "Nonoverlapping")

participant_ids <- unique(primary_participants$participant_id)
participant_count <- length(participant_ids)

if (participant_count < 3) {
  stop("At least three participants are required for this sensitivity check.")
}

full_mean <- trajectory_output$grand_summary %>%
  filter(sample == "Nonoverlapping") %>%
  select(
    metric,
    relative_day,
    full_sample_mean = mean_change
  )

# Remove each participant together with all their contributing events
# Recalculate the equally weighted mean among the remaining participants
omission_curves <- bind_rows(
  lapply(participant_ids, function(omitted_id) {
    primary_participants %>%
      filter(participant_id != omitted_id) %>%
      group_by(metric, relative_day) %>%
      summarise(
        omission_mean = mean(participant_mean_change),
        participants_remaining = n_distinct(participant_id),
        events_remaining = sum(events),
        .groups = "drop"
      ) %>%
      mutate(omitted_participant = omitted_id)
  })
) %>%
  left_join(
    full_mean,
    by = c("metric", "relative_day")
  )

# Summarize the range of means across all participant omissions
sensitivity_summary <- omission_curves %>%
  group_by(metric, relative_day) %>%
  summarise(
    full_sample_mean = first(full_sample_mean),
    omission_min = min(omission_mean),
    omission_max = max(omission_mean),
    largest_absolute_shift = max(
      abs(omission_mean - full_sample_mean)
    ),
    .groups = "drop"
  )

# Express sleep changes in minutes for easier interpretation
display_summary <- sensitivity_summary %>%
  mutate(
    multiplier = if_else(metric == "sleep_hours", 60, 1),
    full_sample_mean = full_sample_mean * multiplier,
    omission_min = omission_min * multiplier,
    omission_max = omission_max * multiplier,
    largest_absolute_shift = largest_absolute_shift * multiplier,
    metric_label = factor(
      metric,
      levels = c("resting_hr", "sleep_hours", "readiness"),
      labels = c(
        "Resting heart rate (bpm)",
        "Sleep duration (minutes)",
        "Readiness (points)"
      )
    )
  ) %>%
  select(-multiplier)

# The shaded range describes sensitivity, not sampling uncertainty
sensitivity_plot <- ggplot(
  display_summary,
  aes(x = relative_day)
) +
  geom_hline(yintercept = 0, color = "grey65") +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "grey70"
  ) +
  geom_ribbon(
    aes(ymin = omission_min, ymax = omission_max),
    fill = "#2166AC",
    alpha = 0.18
  ) +
  geom_line(
    aes(y = full_sample_mean),
    color = "#2166AC",
    linewidth = 1
  ) +
  geom_point(
    aes(y = full_sample_mean),
    color = "#2166AC",
    size = 2
  ) +
  facet_wrap(~ metric_label, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = -1:3) +
  labs(
    title = "Sensitivity of trajectories to participant omission",
    subtitle = paste0(
      "Full mean from ", participant_count,
      " participants; omission means use ",
      participant_count - 1, " participants"
    ),
    x = "Calendar day relative to the training date",
    y = "Change from source date -1",
    caption = paste(
      "Line: full-sample mean. Shading: range after omitting one participant.\n",
      "This range is not a confidence interval. Source-date alignment remains unverified."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0)
  )

# Preserve numerical results and the diagnostic figure
saveRDS(
  list(
    omission_curves = omission_curves,
    sensitivity_summary = sensitivity_summary,
    display_summary = display_summary,
    method = "Omit one participant and all their events at a time"
  ),
  "data/intermediate/18_aim2_participant_sensitivity.rds"
)

readr::write_csv(
  display_summary,
  "results/aim2_participant_sensitivity.csv"
)

ggsave(
  "figures/18_aim2_participant_sensitivity.png",
  plot = sensitivity_plot,
  width = 10,
  height = 9,
  dpi = 300,
  bg = "white"
)

cat("\nParticipant-omission sensitivity on subsequent dates:\n")
print(
  as.data.frame(
    display_summary %>%
      filter(relative_day %in% 1:3) %>%
      select(
        metric_label, relative_day,
        full_sample_mean, omission_min,
        omission_max, largest_absolute_shift
      )
  ),
  row.names = FALSE
)

print(sensitivity_plot)

cat("\nStage 18 completed. Participant-omission results were saved.\n")