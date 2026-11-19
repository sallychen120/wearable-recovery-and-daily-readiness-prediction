# Stage 03: Build the draft participant-day panel
# Run from the RStudio project root

library(dplyr)

# Read the daily records selected in Stage 02b
input_path <- "data/intermediate/02_daily.rds"

if (!file.exists(input_path)) {
  stop("Stage 02b output is missing. Run R/02b_make_daily.R first.")
}

cleaned_data <- readRDS(input_path)

# Define a reusable merge function
merge_participant <- function(x) {
  
  participant_id <- x$participant_id
  source_names <- c("wellness", "resting_hr", "sleep")
  
  # Require valid dates and one record per participant-date
  for (source_name in source_names) {
    source_table <- x[[source_name]]
    
    if (nrow(source_table) == 0 || anyNA(source_table$date)) {
      stop("Empty data or missing dates: ",
           participant_id, " / ", source_name)
    }
    
    if (anyDuplicated(source_table[c("participant_id", "date")]) > 0) {
      stop("Unresolved duplicate dates: ",
           participant_id, " / ", source_name)
    }
  }
  
  # Find this participant's observed date range
  date_range <- range(c(
    x$wellness$date,
    x$resting_hr$date,
    x$sleep$date
  ))
  
  # Create one row for every calendar day
  calendar <- tibble(
    participant_id = participant_id,
    date = seq(date_range[1], date_range[2], by = "day")
  )
  
  # Match records using participant ID and source date labels
  # Cross-stream time alignment remains unverified
  calendar %>%
    left_join(x$wellness, by = c("participant_id", "date")) %>%
    left_join(x$resting_hr, by = c("participant_id", "date")) %>%
    left_join(x$sleep, by = c("participant_id", "date"))
}

# Build each participant's panel, then stack the panels
participant_panels <- lapply(cleaned_data, merge_participant)
daily_panel_draft <- bind_rows(participant_panels)

# Summarize availability over the complete calendar
coverage_summary <- daily_panel_draft %>%
  group_by(participant_id) %>%
  summarise(
    calendar_days = n(),
    wellness_days = sum(!is.na(wellness_time_text)),
    readiness_days = sum(!is.na(readiness)),
    resting_hr_days = sum(!is.na(resting_hr)),
    sleep_days = sum(!is.na(sleep_hours)),
    complete_days = sum(
      complete.cases(readiness, resting_hr, sleep_hours)
    ),
    .groups = "drop"
  )

# Save the panel and its coverage summary for Stage 04
merge_output <- list(
  daily_panel_draft = daily_panel_draft,
  coverage_summary = coverage_summary,
  alignment_status = "Source date labels; sleep timezone unverified"
)

output_path <- "data/intermediate/03_panel_draft.rds"
saveRDS(merge_output, output_path)

# Display the results
print(as.data.frame(coverage_summary), row.names = FALSE)

cat("\nFirst six panel rows:\n")
print(
  as.data.frame(
    daily_panel_draft %>%
      select(participant_id, date, readiness, resting_hr, sleep_hours) %>%
      head(6)
  ),
  row.names = FALSE
)

cat("\nStage 03 completed. Output saved to:", output_path, "\n")