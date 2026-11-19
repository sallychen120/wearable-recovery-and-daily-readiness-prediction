# Stage 12: Compare earliest and latest daily readiness reports
# Run from the RStudio project root

library(dplyr)
library(nlme)

if (!requireNamespace("clubSandwich", quietly = TRUE)) {
  stop("Install clubSandwich before running this script.")
}

# Read the full cleaned reports and previous model outputs
input_paths <- c(
  cleaned = "data/intermediate/02_cleaned.rds",
  models = "data/intermediate/09_aim1_robustness.rds",
  intervals = "data/intermediate/10_aim1_robust_intervals.rds"
)

if (!all(file.exists(input_paths))) {
  stop("Required outputs from Stages 02, 09, or 10 are missing.")
}

cleaned_data <- readRDS(input_paths[["cleaned"]])
robustness_output <- readRDS(input_paths[["models"]])
interval_output <- readRDS(input_paths[["intervals"]])

# Parse all original questionnaire timestamps as UTC
all_reports <- bind_rows(
  lapply(cleaned_data, function(x) x$wellness)
) %>%
  mutate(
    report_time_utc = readr::parse_datetime(
      wellness_time_text,
      locale = readr::locale(tz = "UTC")
    )
  )

if (anyNA(all_reports$report_time_utc)) {
  stop("Some questionnaire timestamps could not be parsed.")
}

# Identify the latest report on each source UTC date
daily_choices <- all_reports %>%
  arrange(participant_id, date, report_time_utc) %>%
  group_by(participant_id, date) %>%
  summarise(
    n_reports = n(),
    latest_readiness = last(readiness),
    latest_report_time = last(wellness_time_text),
    latest_ties = sum(report_time_utc == max(report_time_utc)),
    .groups = "drop"
  )

if (any(daily_choices$latest_ties > 1)) {
  stop("Tied latest questionnaire timestamps require review.")
}

# Preserve the original complete-case dates and predictor values
latest_data <- robustness_output$full_data %>%
  select(
    participant_id, date, readiness, wellness_time_text,
    hr_deviation, sleep_deviation,
    hr_person_mean_c, sleep_person_mean_c,
    study_day_30, calendar_day
  ) %>%
  rename(
    readiness_earliest = readiness,
    earliest_report_time = wellness_time_text
  ) %>%
  left_join(
    daily_choices %>%
      select(
        participant_id, date, n_reports,
        readiness = latest_readiness,
        latest_report_time
      ),
    by = c("participant_id", "date")
  ) %>%
  mutate(participant_id = factor(participant_id)) %>%
  arrange(participant_id, date) %>%
  as.data.frame()

# Stop rather than silently change the analysis sample
if (anyNA(latest_data$readiness)) {
  stop("Latest readiness is missing for an original analysis date.")
}

latest_data$readiness_changed <-
  latest_data$readiness != latest_data$readiness_earliest

choice_summary <- latest_data %>%
  group_by(participant_id) %>%
  summarise(
    complete_days = n(),
    days_with_multiple_reports = sum(n_reports > 1),
    days_with_changed_readiness = sum(readiness_changed),
    .groups = "drop"
  )

changed_records <- latest_data %>%
  filter(readiness_changed) %>%
  select(
    participant_id, date,
    earliest_report_time, latest_report_time,
    readiness_earliest, readiness_latest = readiness
  )

# Reuse the exact fixed-effects formula from Stage 09
fixed_formula <- formula(robustness_output$models$iid_all)

# Fit each latest-report version and calculate CR2 intervals
fit_latest <- function(data, use_ar1, model_name) {
  cat("\nFitting latest-report model:", model_name, "\n")
  
  correlation_structure <- if (use_ar1) {
    nlme::corAR1(
      value = 0.2,
      form = ~ calendar_day | participant_id,
      fixed = FALSE
    )
  } else {
    NULL
  }
  
  fit <- nlme::lme(
    fixed = fixed_formula,
    random = ~ 1 | participant_id,
    correlation = correlation_structure,
    data = data,
    method = "REML",
    na.action = na.fail,
    control = nlme::lmeControl(
      opt = "nlminb",
      maxIter = 100,
      msMaxIter = 200,
      msMaxEval = 1000,
      returnObject = FALSE
    )
  )
  
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
  
  critical_t <- qt(0.975, df = coefficient_test$df_Satt)
  
  result <- data.frame(
    model = model_name,
    report_rule = "Latest",
    term = names(nlme::fixef(fit)),
    estimate = coefficient_test$beta,
    std_error = coefficient_test$SE,
    df = coefficient_test$df_Satt,
    conf_low =
      coefficient_test$beta - critical_t * coefficient_test$SE,
    conf_high =
      coefficient_test$beta + critical_t * coefficient_test$SE,
    p_value = coefficient_test$p_Satt,
    row.names = NULL
  )
  
  list(model = fit, coefficients = result)
}

latest_without_p05 <- latest_data %>%
  filter(participant_id != "p05") %>%
  droplevels()

latest_fits <- list(
  iid_all = fit_latest(latest_data, FALSE, "iid_all"),
  ar1_all = fit_latest(latest_data, TRUE, "ar1_all"),
  iid_without_p05 = fit_latest(
    latest_without_p05, FALSE, "iid_without_p05"
  ),
  ar1_without_p05 = fit_latest(
    latest_without_p05, TRUE, "ar1_without_p05"
  )
)

# Compare both rules using the same robust inference method
latest_results <- bind_rows(
  lapply(latest_fits, function(x) x$coefficients)
) %>%
  filter(term %in% c("hr_deviation", "sleep_deviation"))

earliest_results <- interval_output$primary_comparison %>%
  filter(inference == "Participant-clustered CR2") %>%
  mutate(report_rule = "Earliest") %>%
  select(
    model, report_rule, term, estimate,
    std_error, df, conf_low, conf_high, p_value
  )

report_choice_comparison <- bind_rows(
  earliest_results,
  latest_results
) %>%
  arrange(term, model, report_rule)

# Save aggregate results and local record-level review data
readr::write_csv(
  choice_summary,
  "results/aim1_report_choice_counts.csv"
)

readr::write_csv(
  changed_records,
  "data/intermediate/12_changed_readiness_records.csv"
)

readr::write_csv(
  report_choice_comparison,
  "results/aim1_report_choice_comparison.csv"
)

saveRDS(
  list(
    latest_fits = latest_fits,
    choice_summary = choice_summary,
    changed_records = changed_records,
    report_choice_comparison = report_choice_comparison,
    design = "Same analysis dates and predictors; readiness report rule changed"
  ),
  "data/intermediate/12_aim1_report_choice.rds"
)

# Display the changes and association estimates
cat("\nQuestionnaire choice changes within the analysis sample:\n")
print(as.data.frame(choice_summary), row.names = FALSE)

cat("\nEarliest versus latest readiness results:\n")
print(
  as.data.frame(
    report_choice_comparison %>%
      select(model, report_rule, term, estimate, conf_low, conf_high)
  ),
  row.names = FALSE
)

cat("\nHeart rate coefficients are per 1 bpm; sleep coefficients are per 1 hour.\n")
cat("Stage 12 completed. Report-choice sensitivity results were saved.\n")