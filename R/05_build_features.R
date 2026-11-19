# Stage 05: Build participant means and within-person deviations
# Run from the RStudio project root

library(dplyr)

# Read the checked draft panel from Stage 03
input_path <- "data/intermediate/03_panel_draft.rds"

if (!file.exists(input_path)) {
  stop("Stage 03 output is missing. Run R/03_merge.R first.")
}

merge_output <- readRDS(input_path)
daily_panel <- merge_output$daily_panel_draft

# Calculate a mean using available observations
mean_available <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }
  
  mean(x, na.rm = TRUE)
}

# Estimate each participant's typical level from all valid observed days
# These full-period means are for association analysis, not prediction
participant_baselines <- daily_panel %>%
  group_by(participant_id) %>%
  summarise(
    hr_observed_days = sum(!is.na(resting_hr)),
    hr_person_mean = mean_available(resting_hr),
    sleep_observed_days = sum(!is.na(sleep_hours)),
    sleep_person_mean = mean_available(sleep_hours),
    .groups = "drop"
  )

# Keep absolute values and add deviations from participant means
feature_panel <- daily_panel %>%
  left_join(participant_baselines, by = "participant_id") %>%
  mutate(
    hr_deviation = resting_hr - hr_person_mean,
    sleep_deviation = sleep_hours - sleep_person_mean,
    readiness_reporting_review = participant_id == "p05"
  ) %>%
  arrange(participant_id, date)

# Select days with all three core measurements
# No missing values are imputed
analysis_data <- feature_panel %>%
  filter(
    !is.na(readiness),
    !is.na(resting_hr),
    !is.na(sleep_hours)
  )

# Prepare the prespecified participant-exclusion sensitivity dataset
analysis_without_p05 <- analysis_data %>%
  filter(participant_id != "p05")

# Summarize the available association-analysis sample
analysis_counts <- analysis_data %>%
  group_by(participant_id) %>%
  summarise(
    complete_days = n(),
    readiness_zero_days = sum(readiness == 0),
    readiness_distinct_values = n_distinct(readiness),
    readiness_sd = sd(readiness),
    .groups = "drop"
  )

# Save features and analysis datasets for the next stage
feature_output <- list(
  feature_panel = feature_panel,
  participant_baselines = participant_baselines,
  analysis_data = analysis_data,
  analysis_without_p05 = analysis_without_p05,
  analysis_counts = analysis_counts,
  alignment_status = merge_output$alignment_status,
  baseline_definition =
    "Full-period means from all available valid days per participant",
  readiness_rule =
    "Retain zero values; exclude p05 in a sensitivity analysis"
)

dir.create("data/intermediate", recursive = TRUE, showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

saveRDS(
  feature_output,
  "data/intermediate/05_features.rds"
)

readr::write_csv(
  participant_baselines,
  "results/participant_baselines.csv"
)

readr::write_csv(
  analysis_counts,
  "results/analysis_sample_counts.csv"
)

# Display the participant means and sample sizes
cat("\nParticipant baselines:\n")
print(as.data.frame(participant_baselines), row.names = FALSE)

cat("\nAssociation-analysis sample:\n")
print(as.data.frame(analysis_counts), row.names = FALSE)

cat("\nMain analysis days:", nrow(analysis_data), "\n")
cat("Sensitivity analysis days:", nrow(analysis_without_p05), "\n")

cat("\nFirst six complete records with deviations:\n")
print(
  as.data.frame(
    analysis_data %>%
      select(
        participant_id, date, readiness,
        resting_hr, hr_person_mean, hr_deviation,
        sleep_hours, sleep_person_mean, sleep_deviation
      ) %>%
      head(6)
  ),
  row.names = FALSE
)

cat("\nStage 05 completed. Output saved to data/intermediate/05_features.rds\n")