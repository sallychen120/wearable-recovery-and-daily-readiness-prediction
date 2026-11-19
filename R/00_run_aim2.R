# Run the complete Aim 2 pipeline
# Run from the RStudio project root

if (!file.exists("wearable-readiness.Rproj")) {
  stop("Open the wearable-readiness project before running this script.")
}

if (!file.exists("data/intermediate/05_features.rds")) {
  stop("Aim 1 output is missing. Run R/00_run_aim1.R first.")
}

# Check required packages
aim2_packages <- c("dplyr", "readr", "tidyr", "ggplot2")

aim2_available <- vapply(
  aim2_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)

if (!all(aim2_available)) {
  stop(
    "Missing packages: ",
    paste(aim2_packages[!aim2_available], collapse = ", ")
  )
}

# Declare the execution order explicitly
aim2_scripts <- c(
  "R/13_download_training.R",
  "R/14_prepare_training_sessions.R",
  "R/15_training_daily_coverage.R",
  "R/16_select_training_events.R",
  "R/17_plot_training_trajectories.R",
  "R/18_check_trajectory_sensitivity.R"
)

if (!all(file.exists(aim2_scripts))) {
  stop(
    "Missing scripts: ",
    paste(aim2_scripts[!file.exists(aim2_scripts)], collapse = ", ")
  )
}

dir.create("results", showWarnings = FALSE)

aim2_log <- data.frame(
  script = character(),
  status = character(),
  seconds = numeric(),
  message = character()
)

# Run each stage and preserve the completion or failure record
for (aim2_script in aim2_scripts) {
  cat("\nRunning:", aim2_script, "\n")
  aim2_stage_start <- Sys.time()
  
  aim2_error <- tryCatch(
    {
      source(aim2_script, local = FALSE)
      NA_character_
    },
    error = function(e) conditionMessage(e)
  )
  
  aim2_log <- rbind(
    aim2_log,
    data.frame(
      script = aim2_script,
      status = if (is.na(aim2_error)) "Completed" else "Failed",
      seconds = round(
        as.numeric(difftime(
          Sys.time(),
          aim2_stage_start,
          units = "secs"
        )),
        2
      ),
      message = if (is.na(aim2_error)) "" else aim2_error
    )
  )
  
  write.csv(
    aim2_log,
    "results/aim2_pipeline_log.csv",
    row.names = FALSE
  )
  
  if (!is.na(aim2_error)) {
    stop("Pipeline stopped at ", aim2_script, ": ", aim2_error)
  }
}

cat("\nAim 2 pipeline completed successfully.\n")
print(aim2_log, row.names = FALSE)