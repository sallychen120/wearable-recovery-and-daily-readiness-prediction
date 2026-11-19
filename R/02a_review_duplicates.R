# Stage 02a: Review multiple sleep records on the same date
# Run from the RStudio project root

library(dplyr)

input_path <- "data/intermediate/02_cleaned.rds"

if (!file.exists(input_path)) {
  stop("Stage 02 output is missing. Run R/02_clean.R first.")
}

cleaned_data <- readRDS(input_path)

# Collect all cleaned sleep records
all_sleep <- bind_rows(
  lapply(cleaned_data, function(x) x$sleep)
)

# Keep all records belonging to participant-dates with multiple entries
duplicate_sleep <- all_sleep %>%
  group_by(participant_id, date) %>%
  filter(n() > 1) %>%
  ungroup() %>%
  arrange(participant_id, date, start_time)

# Summarize the affected dates and main-sleep flags
duplicate_summary <- duplicate_sleep %>%
  group_by(participant_id) %>%
  summarise(
    affected_dates = n_distinct(date),
    records = n(),
    main_records = sum(main_sleep %in% TRUE),
    non_main_records = sum(main_sleep %in% FALSE),
    unknown_main_flags = sum(is.na(main_sleep)),
    .groups = "drop"
  )

# Save the record-level review data locally
readr::write_csv(
  duplicate_sleep,
  "data/intermediate/02a_sleep_duplicates.csv"
)

cat("Summary of multiple sleep records:\n")
print(as.data.frame(duplicate_summary), row.names = FALSE)

# Inspect the first two affected dates for p04
focus_dates <- duplicate_sleep %>%
  filter(participant_id == "p04") %>%
  distinct(date) %>%
  arrange(date) %>%
  head(2) %>%
  pull(date)

p04_examples <- duplicate_sleep %>%
  filter(participant_id == "p04", date %in% focus_dates) %>%
  select(
    date, log_id, start_time, end_time,
    sleep_hours, main_sleep
  )

cat("\np04 example records:\n")
print(as.data.frame(p04_examples), row.names = FALSE)

# Check whether main-sleep selection gives one record per date
sleep_main_check <- all_sleep %>%
  filter(main_sleep %in% TRUE) %>%
  group_by(participant_id) %>%
  summarise(
    main_records = n(),
    main_dates = n_distinct(date),
    repeated_date_rows = sum(duplicated(date)),
    .groups = "drop"
  )

readr::write_csv(
  sleep_main_check,
  "results/sleep_main_check.csv"
)

cat("\nMain-sleep date checks:\n")
print(as.data.frame(sleep_main_check), row.names = FALSE)

# Collect wellness records from dates with multiple entries
duplicate_wellness <- bind_rows(
  lapply(cleaned_data, function(x) x$wellness)
) %>%
  group_by(participant_id, date) %>%
  filter(n() > 1) %>%
  ungroup() %>%
  arrange(participant_id, date, wellness_time_text)

readr::write_csv(
  duplicate_wellness,
  "data/intermediate/02a_wellness_duplicates.csv"
)

# Summarize the affected wellness dates
wellness_duplicate_summary <- duplicate_wellness %>%
  group_by(participant_id) %>%
  summarise(
    affected_dates = n_distinct(date),
    records = n(),
    .groups = "drop"
  )

cat("\nMultiple wellness reports:\n")
print(as.data.frame(wellness_duplicate_summary), row.names = FALSE)

# Inspect the first two affected dates for p03
wellness_focus_dates <- duplicate_wellness %>%
  filter(participant_id == "p03") %>%
  distinct(date) %>%
  arrange(date) %>%
  head(2) %>%
  pull(date)

cat("\np03 example wellness records:\n")
print(
  as.data.frame(
    duplicate_wellness %>%
      filter(
        participant_id == "p03",
        date %in% wellness_focus_dates
      )
  ),
  row.names = FALSE
)