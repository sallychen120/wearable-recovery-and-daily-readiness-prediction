# Stage 25: Plot chronological test prediction results
# Run from the RStudio project root

library(dplyr)
library(tidyr)
library(ggplot2)

input_path <- "data/intermediate/24_prediction_test_results.rds"

if (!file.exists(input_path)) {
  stop("Stage 24 output is missing.")
}

test_output <- readRDS(input_path)

comparison <- test_output$test_comparison
participant_metrics <- test_output$participant_metrics

dir.create("figures", recursive = TRUE, showWarnings = FALSE)

model_order <- c(
  "baseline_past_mean",
  "baseline_last_readiness",
  "B_absolute",
  "C_personal"
)

model_labels <- c(
  "Historical\nmean",
  "Last\nreadiness",
  "B: absolute\nfeatures",
  "C: personal\ndeviations"
)

model_colors <- c(
  "#999999",
  "#555555",
  "#56B4E9",
  "#0072B2"
)

# Plot overall MAE and RMSE for all four methods
overall_plot_data <- comparison %>%
  select(model, mae, rmse) %>%
  mutate(
    model_label = factor(
      model,
      levels = model_order,
      labels = model_labels
    )
  ) %>%
  pivot_longer(
    cols = c(mae, rmse),
    names_to = "metric",
    values_to = "prediction_error"
  ) %>%
  mutate(
    metric = factor(
      metric,
      levels = c("mae", "rmse"),
      labels = c("MAE", "RMSE")
    )
  )

overall_plot <- ggplot(
  overall_plot_data,
  aes(
    x = model_label,
    y = prediction_error,
    fill = model_label
  )
) +
  geom_col(width = 0.65) +
  geom_text(
    aes(label = sprintf("%.3f", prediction_error)),
    vjust = -0.5,
    size = 3.5
  ) +
  facet_wrap(~metric, nrow = 1) +
  scale_fill_manual(values = model_colors) +
  scale_y_continuous(
    expand = expansion(mult = c(0, 0.15))
  ) +
  labs(
    title = "Readiness prediction on the chronological test set",
    subtitle = "13 participants and 250 target observations",
    x = NULL,
    y = "Prediction error (readiness points)",
    caption = paste(
      "Lower values indicate better performance.",
      "MAE was the prespecified primary metric."
    )
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "none",
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank()
  )

ggsave(
  "figures/25_aim3_test_error_comparison.png",
  plot = overall_plot,
  width = 10,
  height = 5,
  dpi = 300,
  bg = "white"
)

# Compare each ridge model with both baselines within each participant
ridge_metrics <- participant_metrics %>%
  filter(model %in% c("B_absolute", "C_personal")) %>%
  select(
    model,
    participant_id,
    prediction_targets,
    mae
  )

reference_models <- c(
  "baseline_past_mean",
  "baseline_last_readiness"
)

participant_plot_data <- bind_rows(
  lapply(reference_models, function(reference_model) {
    reference_data <- participant_metrics %>%
      filter(model == reference_model) %>%
      transmute(
        participant_id,
        baseline_mae = mae
      )
    
    ridge_metrics %>%
      left_join(reference_data, by = "participant_id") %>%
      mutate(
        reference = reference_model,
        mae_change = mae - baseline_mae
      )
  })
) %>%
  mutate(
    model_label = factor(
      model,
      levels = c("B_absolute", "C_personal"),
      labels = c(
        "B: absolute features",
        "C: personal deviations"
      )
    ),
    reference_label = factor(
      reference,
      levels = reference_models,
      labels = c(
        "Compared with historical mean",
        "Compared with last readiness"
      )
    ),
    participant_id = factor(
      participant_id,
      levels = rev(sort(unique(participant_id)))
    )
  )

participant_plot <- ggplot(
  participant_plot_data,
  aes(
    x = mae_change,
    y = participant_id,
    color = mae_change < 0
  )
) +
  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    color = "grey50"
  ) +
  geom_point(size = 2.3) +
  facet_grid(model_label ~ reference_label) +
  scale_color_manual(
    values = c(
      "TRUE" = "#0072B2",
      "FALSE" = "#D55E00"
    ),
    breaks = c("TRUE", "FALSE"),
    labels = c("Lower MAE", "Higher MAE"),
    name = NULL
  ) +
  labs(
    title = "Participant-specific prediction differences",
    subtitle = "Negative values favor the ridge model",
    x = "Model MAE minus baseline MAE (readiness points)",
    y = "Participant",
    caption = paste(
      "Each point summarizes one participant.",
      "Participants contribute different numbers of target observations."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(
  "figures/25_aim3_test_error_comparison.png",
  plot = overall_plot,
  width = 10,
  height = 5,
  dpi = 300,
  bg = "white"
)

readr::write_csv(
  participant_plot_data,
  "results/aim3_participant_plot_data.csv"
)

print(overall_plot)
print(participant_plot)

cat("\nStage 25 completed. Two prediction result figures were saved.\n")