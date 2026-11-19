# Stage 14: Prepare training-session records and session load
# Run from the RStudio project root

library(dplyr)
library(readr)

# Read the download inventory from Stage 13
input_path <- "data/training_download_manifest.csv"

if (!file.exists(input_path)) {
  stop("Stage 13 output is missing. Run R/13_download_training.R first.")
}

training_manifest <- read_csv(
  input_path,
  show_col_types = FALSE
)

if (any(!(training_manifest$status %in% c("Downloaded", "Existing")))) {
  stop("Some training files were not validated in Stage 13.")
}

# Import one participant while preserving the original field values
import_training <- function(participant_id) {
  file_path <- file.path(
    "data", "raw", participant_id, "pmsys", "srpe.csv"
  )
  
  raw <- read_csv(
    file_path,
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
  
  raw %>%
    transmute(
      participant_id = participant_id,
      source_row = row_number(),
      end_time_text = end_date_time,
      activity_names = activity_names,
      rpe_text = perceived_exertion,
      duration_text = duration_min
    )
}

training_raw <- bind_rows(
  lapply(training_manifest$participant_id, import_training)
)

raw_counts <- training_raw %>%
  count(participant_id, name = "raw_records")

# Remove records identical across all original training fields
# Parse session end timestamps as UTC and retain the source text
training_sessions <- training_raw %>%
  distinct(
    participant_id, end_time_text, activity_names,
    rpe_text, duration_text,
    .keep_all = TRUE
  ) %>%
  mutate(
    session_id = paste(participant_id, source_row, sep = "_"),
    session_end_utc = parse_datetime(
      end_time_text,
      locale = locale(tz = "UTC")
    ),
    training_date_utc = as.Date(session_end_utc, tz = "UTC"),
    rpe = parse_double(rpe_text),
    duration_minutes = parse_double(duration_text),
    rpe_outside_review_range =
      !is.na(rpe) & (!is.finite(rpe) | rpe < 0 | rpe > 10),
    duration_invalid =
      !is.na(duration_minutes) &
      (!is.finite(duration_minutes) | duration_minutes <= 0),
    load_usable =
      !is.na(session_end_utc) &
      !is.na(rpe) &
      !rpe_outside_review_range &
      !is.na(duration_minutes) &
      !duration_invalid,
    session_load = if_else(
      load_usable,
      rpe * duration_minutes,
      NA_real_
    )
  ) %>%
  arrange(participant_id, session_end_utc, source_row)

# Require distinct known end timestamps within participants
known_times <- training_sessions %>%
  filter(!is.na(session_end_utc))

if (anyDuplicated(
  known_times[c("participant_id", "session_end_utc")]
) > 0) {
  stop("Multiple records share an end timestamp. Review before aggregation.")
}

# Summarize missingness and measurement flags
training_quality <- training_sessions %>%
  group_by(participant_id) %>%
  summarise(
    records_after_deduplication = n(),
    missing_end_times = sum(is.na(session_end_utc)),
    missing_rpe = sum(is.na(rpe)),
    missing_duration = sum(is.na(duration_minutes)),
    rpe_outside_review_range = sum(rpe_outside_review_range),
    invalid_duration = sum(duration_invalid),
    usable_sessions = sum(load_usable),
    .groups = "drop"
  ) %>%
  left_join(raw_counts, by = "participant_id") %>%
  mutate(
    exact_duplicates_removed =
      raw_records - records_after_deduplication
  )

usable_sessions <- training_sessions %>%
  filter(load_usable)

training_review <- training_sessions %>%
  filter(!load_usable)

# Save session-level data for daily aggregation in the next stage
training_output <- list(
  sessions = training_sessions,
  usable_sessions = usable_sessions,
  quality_summary = training_quality,
  date_definition = "UTC date of the reported session end",
  load_definition = "Reported RPE multiplied by duration in minutes",
  alignment_status =
    "Training timestamps parsed as UTC; Fitbit time alignment unverified"
)

saveRDS(
  training_output,
  "data/intermediate/14_training_sessions.rds"
)

write_csv(
  training_quality,
  "results/training_session_quality.csv"
)

write_csv(
  training_review,
  "data/intermediate/14_training_review.csv"
)

# Display the quality checks and example load calculations
cat("\nTraining-session quality summary:\n")
print(
  as.data.frame(
    training_quality %>%
      select(
        participant_id, raw_records, exact_duplicates_removed,
        missing_rpe, missing_duration, usable_sessions
      )
  ),
  row.names = FALSE
)

cat("\nTotal usable sessions:", nrow(usable_sessions), "\n")

cat("\nFirst six usable sessions:\n")
print(
  as.data.frame(
    usable_sessions %>%
      select(
        participant_id, training_date_utc,
        rpe, duration_minutes, session_load
      ) %>%
      head(6)
  ),
  row.names = FALSE
)

cat("\nStage 14 completed. Session records and quality tables were saved.\n")