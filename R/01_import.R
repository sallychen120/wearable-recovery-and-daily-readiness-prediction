# Stage 01: Import participant data
# Run from the RStudio project root

# Select participants using the saved file inventory
inventory_path <- "results/file_inventory.csv"

if (!file.exists(inventory_path)) {
  stop("File inventory is missing. Run R/00_check_files.R first.")
}

file_inventory <- readr::read_csv(
  inventory_path,
  show_col_types = FALSE
)

# Import participants with all three required source files
participant_ids <- file_inventory$participant_id[
  file_inventory$ready_to_import %in% TRUE
]

if (length(participant_ids) == 0) {
  stop("No participants have all required input files.")
}

cat("Participants selected for import:",
    length(participant_ids), "\n")

# Define a reusable import function
import_participant <- function(participant_id) {
  
  input_paths <- c(
    wellness = file.path(
      "data/raw", participant_id, "pmsys", "wellness.csv"
    ),
    resting_hr = file.path(
      "data/raw", participant_id, "fitbit", "resting_heart_rate.json"
    ),
    sleep = file.path(
      "data/raw", participant_id, "fitbit", "sleep.json"
    )
  )
  
  # Check that all required files exist
  missing_paths <- input_paths[!file.exists(input_paths)]
  
  if (length(missing_paths) > 0) {
    stop(
      "Missing files for ", participant_id, ":\n",
      paste(missing_paths, collapse = "\n")
    )
  }
  
  # Preserve CSV values as text, including original timestamps
  wellness_raw <- readr::read_csv(
    input_paths[["wellness"]],
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  
  # Preserve the original JSON structures
  resting_hr_raw <- jsonlite::fromJSON(
    input_paths[["resting_hr"]],
    simplifyVector = FALSE
  )
  
  sleep_raw <- jsonlite::fromJSON(
    input_paths[["sleep"]],
    simplifyVector = FALSE
  )
  
  # Return the original data for this participant
  list(
    participant_id = participant_id,
    wellness_raw = wellness_raw,
    resting_hr_raw = resting_hr_raw,
    sleep_raw = sleep_raw
  )
}

# Apply the same import function to each selected participant
imported_data <- setNames(
  lapply(participant_ids, import_participant),
  participant_ids
)

# Create a record-count summary
import_summary <- do.call(
  rbind,
  lapply(imported_data, function(x) {
    data.frame(
      participant_id = x$participant_id,
      wellness_records = nrow(x$wellness_raw),
      resting_hr_records = length(x$resting_hr_raw),
      sleep_records = length(x$sleep_raw)
    )
  })
)

# Save the output for Stage 02
dir.create(
  "data/intermediate",
  recursive = TRUE,
  showWarnings = FALSE
)

output_path <- "data/intermediate/01_imported.rds"
saveRDS(imported_data, output_path)

# Display the import summary
print(import_summary, row.names = FALSE)
cat("\nStage 01 completed. Output saved to:", output_path, "\n")