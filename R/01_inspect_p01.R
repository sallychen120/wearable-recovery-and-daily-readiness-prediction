library(readr)
library(jsonlite)
#read original files
wellness <- read_csv(
  paths[["wellness"]],
  show_col_types = FALSE
)

resting_hr_raw <- fromJSON(
  paths[["resting_hr"]],
  simplifyVector = FALSE
)

sleep_raw <- fromJSON(
  paths[["sleep"]],
  simplifyVector = FALSE
)
#check wellness data
nrow(wellness)
names(wellness)
head(wellness, 6)
#check sleep and resting hr
str(resting_hr_raw, max.level = 2, list.len = 5)
str(sleep_raw, max.level = 2, list.len = 5)

# view wellness columns
names(wellness)

# view resting hr row 1
str(resting_hr_raw[[1]], max.level = 2)

# view sleep row 1
str(sleep_raw[[1]], max.level = 1)

#turn resting hr records into table
resting_hr <- do.call(rbind, lapply(resting_hr_raw, function(x) {
  data.frame(
    participant_id = "p01",
    date = as.Date(substr(x$dateTime, 1, 10)),
    resting_hr = x$value$value
  )
}))

#turn sleep into table
sleep_episodes <- do.call(rbind, lapply(sleep_raw, function(x) {
  data.frame(
    participant_id = "p01",
    date = as.Date(x$dateOfSleep),
    start_time = x$startTime,
    end_time = x$endTime,
    sleep_hours = x$minutesAsleep / 60,
    main_sleep = x$mainSleep
  )
}))

head(resting_hr, 4)

head(
  sleep_episodes[c("date", "sleep_hours", "main_sleep")],
  4
)

cat("number of hr retetitive date：",
    sum(duplicated(resting_hr$date)), "\n")

cat("number of sleep retetitive date：",
    sum(duplicated(sleep_episodes$date)), "\n")
table(sleep_episodes$main_sleep, useNA = "ifany")

library(dplyr)

# add record number to sleep
sleep_episodes$log_id <- vapply(
  sleep_raw,
  function(x) as.character(x$logId),
  character(1)
)

# find out multiple records under one date
sleep_duplicates <- sleep_episodes %>%
  group_by(date) %>%
  filter(n() > 1) %>%
  ungroup() %>%
  arrange(date, start_time) %>%
  select(date, log_id, start_time, end_time, sleep_hours)

print(as.data.frame(sleep_duplicates), row.names = FALSE)

cat("number of date：",
    n_distinct(sleep_duplicates$date), "\n")

cat("number of log_id number：",
    sum(duplicated(sleep_episodes$log_id)), "\n")

# Remove rows that are identical across all extracted columns
sleep_daily <- sleep_episodes %>%
  distinct() %>%
  arrange(date)

# Check the result of deduplication
cat("Sleep records before:", nrow(sleep_episodes), "\n")
cat("Sleep records after:", nrow(sleep_daily), "\n")
cat("Remaining duplicate dates:",
    sum(duplicated(sleep_daily$date)), "\n")

# Prepare wellness records while preserving the reported timestamp
wellness_records <- wellness %>%
  mutate(
    participant_id = "p01",
    report_time_text = as.character(effective_time_frame),
    date = as.Date(substr(report_time_text, 1, 10))
  ) %>%
  select(
    participant_id,
    date,
    report_time_text,
    readiness,
    fatigue,
    self_report_sleep_hours = sleep_duration_h
  ) %>%
  arrange(date, report_time_text)

# Inspect the first few wellness records
print(as.data.frame(head(wellness_records, 6)), row.names = FALSE)

# Check for multiple wellness reports on the same date
cat("Wellness records:", nrow(wellness_records), "\n")
cat("Wellness duplicate dates:",
    sum(duplicated(wellness_records$date)), "\n")

# Check the timestamp type and its assigned time zone
print(class(wellness$effective_time_frame))
print(attr(wellness$effective_time_frame, "tzone"))

# Read the CSV as text to inspect timestamps without automatic parsing
wellness_text <- readr::read_csv(
  paths[["wellness"]],
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
)

# Inspect the original wellness timestamps
cat("Original wellness timestamps:\n")
print(head(wellness_text$effective_time_frame, 6))

# Inspect the original sleep end timestamps
cat("\nOriginal sleep end timestamps:\n")
print(head(sleep_daily$end_time, 6))

# Check whether sleep dates match the dates of sleep completion
cat("\nSleep dates differing from end dates:",
    sum(
      sleep_daily$date != as.Date(substr(sleep_daily$end_time, 1, 10)),
      na.rm = TRUE
    ),
    "\n")

# Look for downloaded documentation or metadata files
cat("\nAvailable documentation files:\n")
print(list.files(
  "data/raw",
  pattern = "info|readme|description|metadata",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
))

# Create a draft panel using the existing date labels
# Sleep timezone and cross-stream time alignment remain unverified
daily_panel_draft <- wellness_records %>%
  left_join(
    resting_hr,
    by = c("participant_id", "date")
  ) %>%
  left_join(
    sleep_daily %>%
      select(participant_id, date, sleep_hours, end_time),
    by = c("participant_id", "date")
  )

# Check that the joins did not multiply wellness records
stopifnot(nrow(daily_panel_draft) == nrow(wellness_records))

# Summarize data availability
coverage_summary <- daily_panel_draft %>%
  summarise(
    wellness_days = n(),
    days_with_readiness = sum(!is.na(readiness)),
    days_with_resting_hr = sum(!is.na(resting_hr)),
    days_with_sleep = sum(!is.na(sleep_hours)),
    complete_days = sum(
      complete.cases(readiness, resting_hr, sleep_hours)
    )
  )

print(as.data.frame(coverage_summary), row.names = FALSE)

# Inspect the first eight rows
print(
  as.data.frame(
    daily_panel_draft %>%
      select(date, readiness, resting_hr, sleep_hours) %>%
      head(8)
  ),
  row.names = FALSE
)

library(ggplot2)

# Find the date range across all three data sources
date_range <- range(
  c(wellness_records$date, resting_hr$date, sleep_daily$date),
  na.rm = TRUE
)

# Create a complete calendar and attach each data source
daily_calendar_draft <- tibble(
  participant_id = "p01",
  date = seq(date_range[1], date_range[2], by = "day")
) %>%
  left_join(wellness_records, by = c("participant_id", "date")) %>%
  left_join(resting_hr, by = c("participant_id", "date")) %>%
  left_join(
    sleep_daily %>%
      select(participant_id, date, sleep_hours),
    by = c("participant_id", "date")
  )

# Reshape the three measurements for plotting
trajectory_data <- daily_calendar_draft %>%
  select(date, readiness, resting_hr, sleep_hours) %>%
  tidyr::pivot_longer(
    cols = c(readiness, resting_hr, sleep_hours),
    names_to = "metric",
    values_to = "value"
  ) %>%
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

# Plot the observed measurements with a separate scale for each metric
p01_trajectories <- ggplot(
  trajectory_data,
  aes(x = date, y = value)
) +
  geom_point(size = 1.2, alpha = 0.7, na.rm = TRUE) +
  facet_wrap(~ metric, ncol = 1, scales = "free_y") +
  labs(
    title = "p01: Daily wearable and readiness measurements",
    subtitle = "Draft: source date labels; time alignment remains unverified",
    x = "Date",
    y = NULL
  ) +
  theme_minimal(base_size = 12)

print(p01_trajectories)

# Summarize each metric using its available observations
metric_summary <- trajectory_data %>%
  group_by(metric) %>%
  summarise(
    observed_days = sum(!is.na(value)),
    missing_days = sum(is.na(value)),
    mean = round(mean(value, na.rm = TRUE), 2),
    sd = round(sd(value, na.rm = TRUE), 2),
    minimum = round(min(value, na.rm = TRUE), 2),
    maximum = round(max(value, na.rm = TRUE), 2),
    .groups = "drop"
  )

print(as.data.frame(metric_summary), row.names = FALSE)

# List short sleep records for manual review
# This is a review threshold, not an exclusion rule
sleep_to_review <- daily_calendar_draft %>%
  filter(!is.na(sleep_hours), sleep_hours < 4) %>%
  select(date, sleep_hours)

cat("\nSleep records below four hours:\n")
print(as.data.frame(sleep_to_review), row.names = FALSE)

# Save the draft figure
dir.create("figures", showWarnings = FALSE)

ggsave(
  filename = "figures/p01_trajectories_draft.png",
  plot = p01_trajectories,
  width = 10,
  height = 8,
  units = "in",
  dpi = 300
)

cat("\nDraft figure saved to figures/p01_trajectories_draft.png\n")
