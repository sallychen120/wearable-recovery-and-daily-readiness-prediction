# Run the complete Aim 3 pipeline
# Run from the RStudio project root

if (!file.exists("wearable-readiness.Rproj")) {
  stop("Open the wearable-readiness project before running this script.")
}

if (!file.exists("data/intermediate/03_panel_draft.rds")) {
  stop("The cleaned daily panel is missing. Run the Aim 1 pipeline first.")
}

# Check dependencies without installing or updating packages
aim3_packages <- c("dplyr", "readr", "tidyr", "ggplot2")

aim3_available <- vapply(
  aim3_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)

if (!all(aim3_available)) {
  stop(
    "Missing packages: ",
    paste(aim3_packages[!aim3_available], collapse = ", ")
  )
}

# Declare the execution order explicitly
aim3_scripts <- c(
  "R/19_audit_prediction_data.R",
  "R/20_make_prediction_features.R",
  "R/21_compare_prediction_baselines.R",
  "R/22_prepare_prediction_matrices.R",
  "R/23_fit_prediction_models.R",
  "R/24_evaluate_prediction_test.R",
  "R/25_plot_prediction_results.R"
)

if (!all(file.exists(aim3_scripts))) {
  stop(
    "Missing scripts: ",
    paste(
      aim3_scripts[!file.exists(aim3_scripts)],
      collapse = ", "
    )
  )
}

dir.create("results", showWarnings = FALSE)

aim3_log <- data.frame(
  script = character(),
  status = character(),
  seconds = numeric(),
  message = character()
)

# Run each stage in its own environment
# Stages exchange data through their saved output files
for (aim3_script in aim3_scripts) {
  cat("\nRunning:", aim3_script, "\n")
  
  aim3_stage_start <- Sys.time()
  
  aim3_error <- tryCatch(
    {
      source(
        aim3_script,
        local = new.env(parent = globalenv())
      )
      NA_character_
    },
    error = function(e) conditionMessage(e)
  )
  
  aim3_log <- rbind(
    aim3_log,
    data.frame(
      script = aim3_script,
      status = if (is.na(aim3_error)) "Completed" else "Failed",
      seconds = round(
        as.numeric(difftime(
          Sys.time(),
          aim3_stage_start,
          units = "secs"
        )),
        2
      ),
      message = if (is.na(aim3_error)) "" else aim3_error
    )
  )
  
  write.csv(
    aim3_log,
    "results/aim3_pipeline_log.csv",
    row.names = FALSE
  )
  
  if (!is.na(aim3_error)) {
    stop(
      "Pipeline stopped at ",
      aim3_script,
      ": ",
      aim3_error
    )
  }
}

cat("\nAim 3 pipeline completed successfully.\n")
print(aim3_log, row.names = FALSE)