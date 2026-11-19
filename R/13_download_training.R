# Stage 13: Download and inventory training-session files
# Run from the RStudio project root

library(dplyr)
library(readr)

# Read the participant selection from Aim 1
input_path <- "data/intermediate/05_features.rds"

if (!file.exists(input_path)) {
  stop("Stage 05 output is missing. Run the Aim 1 pipeline first.")
}

feature_output <- readRDS(input_path)
participant_ids <- feature_output$participant_baselines$participant_id

# Public OSF links and file sizes verified on 2026-11-07
training_sources <- tibble::tribble(
  ~participant_id, ~osf_id, ~expected_bytes,
  "p01", "2zmt4", 1993,
  "p02", "yhr2d", 5884,
  "p03", "xy827", 180,
  "p04", "xjefg", 5125,
  "p05", "drvhb", 614,
  "p06", "g8cen", 2780,
  "p07", "uyd2s", 6603,
  "p08", "6qcfv", 6909,
  "p09", "h7e34", 242,
  "p10", "6z4tn", 1854,
  "p11", "xv5sj", 2018,
  "p14", "y2hm7", 3735,
  "p15", "p7gm3", 6407,
  "p16", "de9fu", 414
) %>%
  mutate(
    source_url = paste0(
      "https://osf.io/download/", osf_id, "/"
    )
  )

if (!all(participant_ids %in% training_sources$participant_id)) {
  stop("A selected participant has no verified training-file link.")
}

training_sources <- training_sources %>%
  filter(participant_id %in% participant_ids)

# Download to a temporary file and validate before placing it in raw data
download_training <- function(participant_id, source_url, expected_bytes) {
  target_folder <- file.path(
    "data", "raw", participant_id, "pmsys"
  )
  
  dir.create(
    target_folder,
    recursive = TRUE,
    showWarnings = FALSE
  )
  
  target_path <- file.path(target_folder, "srpe.csv")
  already_exists <- file.exists(target_path)
  
  temporary_path <- tempfile(fileext = ".csv")
  on.exit(unlink(temporary_path), add = TRUE)
  
  previous_timeout <- getOption("timeout")
  on.exit(options(timeout = previous_timeout), add = TRUE)
  options(timeout = max(120, previous_timeout))
  
  if (already_exists) {
    candidate_path <- target_path
  } else {
    download_result <- download.file(
      url = source_url,
      destfile = temporary_path,
      method = "libcurl",
      mode = "wb",
      quiet = TRUE
    )
    
    if (download_result != 0) {
      stop("The download did not complete successfully.")
    }
    
    candidate_path <- temporary_path
  }
  
  if (!file.exists(candidate_path)) {
    stop("The downloaded file could not be found.")
  }
  
  actual_bytes <- file.info(candidate_path)$size
  
  if (actual_bytes != expected_bytes) {
    stop("File size differs from the verified source metadata.")
  }
  
  # Preserve all fields as text for the next inspection stage
  training_raw <- read_csv(
    candidate_path,
    col_types = cols(.default = col_character()),
    show_col_types = FALSE,
    progress = FALSE
  )
  
  required_columns <- c(
    "end_date_time",
    "activity_names",
    "perceived_exertion",
    "duration_min"
  )
  
  if (!all(required_columns %in% names(training_raw))) {
    stop("The file does not contain the expected training columns.")
  }
  
  if (nrow(problems(training_raw)) > 0) {
    stop("CSV parsing problems require review.")
  }
  
  if (!already_exists) {
    copied <- file.copy(
      candidate_path,
      target_path,
      overwrite = FALSE
    )
    
    if (!copied) {
      stop("The validated file could not be copied to its destination.")
    }
  }
  
  data.frame(
    participant_id = participant_id,
    source_url = source_url,
    expected_bytes = expected_bytes,
    bytes = actual_bytes,
    records = nrow(training_raw),
    md5 = unname(tools::md5sum(target_path)),
    status = if (already_exists) "Existing" else "Downloaded",
    error = "",
    stringsAsFactors = FALSE
  )
}

# Process each participant and record failures separately
download_results <- lapply(
  seq_len(nrow(training_sources)),
  function(i) {
    source <- training_sources[i, ]
    
    cat("\nChecking training file:", source$participant_id, "\n")
    
    tryCatch(
      download_training(
        participant_id = source$participant_id,
        source_url = source$source_url,
        expected_bytes = source$expected_bytes
      ),
      error = function(e) {
        data.frame(
          participant_id = source$participant_id,
          source_url = source$source_url,
          expected_bytes = source$expected_bytes,
          bytes = NA_real_,
          records = NA_integer_,
          md5 = NA_character_,
          status = "Failed",
          error = conditionMessage(e),
          stringsAsFactors = FALSE
        )
      }
    )
  }
)

training_manifest <- bind_rows(download_results)

training_manifest$checked_at_utc <- format(
  Sys.time(),
  tz = "UTC",
  usetz = TRUE
)

# Save provenance and the file inventory
write_csv(
  training_manifest,
  "data/training_download_manifest.csv"
)

cat("\nTraining-file inventory:\n")
print(
  as.data.frame(
    training_manifest %>%
      select(participant_id, records, bytes, status)
  ),
  row.names = FALSE
)

if (any(training_manifest$status == "Failed")) {
  print(
    as.data.frame(
      training_manifest %>%
        filter(status == "Failed") %>%
        select(participant_id, error)
    ),
    row.names = FALSE
  )
  
  stop("Some files failed. Review data/training_download_manifest.csv.")
}

# Show a small example without converting or cleaning the measurements
example_path <- file.path(
  "data", "raw",
  training_sources$participant_id[1],
  "pmsys", "srpe.csv"
)

example_training <- read_csv(
  example_path,
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
)

cat("\nExample training records:\n")
print(as.data.frame(head(example_training, 5)), row.names = FALSE)

cat("\nStage 13 completed. Training files and inventory were saved.\n")