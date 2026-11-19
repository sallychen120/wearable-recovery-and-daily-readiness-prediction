# Stage 00: Check required files for all expected participants
# Run from the RStudio project root

expected_ids <- sprintf("p%02d", 1:16)

# Check the required files for one participant
check_participant_files <- function(participant_id) {
  data.frame(
    participant_id = participant_id,
    wellness = file.exists(file.path(
      "data/raw", participant_id, "pmsys", "wellness.csv"
    )),
    resting_hr = file.exists(file.path(
      "data/raw", participant_id, "fitbit", "resting_heart_rate.json"
    )),
    sleep = file.exists(file.path(
      "data/raw", participant_id, "fitbit", "sleep.json"
    ))
  )
}

# Apply the same check to every expected participant
file_inventory <- do.call(
  rbind,
  lapply(expected_ids, check_participant_files)
)

file_inventory$ready_to_import <- with(
  file_inventory,
  wellness & resting_hr & sleep
)

# Save and display the inventory
dir.create("results", showWarnings = FALSE)

readr::write_csv(
  file_inventory,
  "results/file_inventory.csv"
)

print(file_inventory, row.names = FALSE)

cat(
  "\nParticipants with all required files:",
  sum(file_inventory$ready_to_import),
  "of",
  nrow(file_inventory),
  "\n"
)