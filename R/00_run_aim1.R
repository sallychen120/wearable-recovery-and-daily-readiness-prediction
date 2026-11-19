# Run the complete Aim 1 pipeline
# Run from the RStudio project root

if (!file.exists("wearable-readiness.Rproj")) {
  stop("Open the wearable-readiness project before running this script.")
}

# Check dependencies without installing or updating packages
pipeline_packages <- c(
  "dplyr", "readr", "jsonlite", "tidyr", "ggplot2",
  "lme4", "lmerTest", "nlme", "clubSandwich"
)

pipeline_available <- vapply(
  pipeline_packages,
  requireNamespace,
  logical(1),
  quietly = TRUE
)

if (!all(pipeline_available)) {
  stop(
    "Missing packages: ",
    paste(pipeline_packages[!pipeline_available], collapse = ", ")
  )
}

# Declare the execution order explicitly
pipeline_scripts <- c(
  "R/00_check_files.R",
  "R/01_import.R",
  "R/02_clean.R",
  "R/02a_review_duplicates.R",
  "R/02b_make_daily.R",
  "R/03_merge.R",
  "R/04_describe.R",
  "R/04a_quality_review.R",
  "R/04b_review_timing.R",
  "R/04c_review_readiness.R",
  "R/05_build_features.R",
  "R/06_plot_associations.R",
  "R/07_fit_aim1.R",
  "R/08_check_aim1.R",
  "R/09_check_robustness.R",
  "R/10_robust_intervals.R",
  "R/11_plot_aim1_results.R",
  "R/12_check_report_choice.R"
)

if (!all(file.exists(pipeline_scripts))) {
  stop(
    "Missing scripts: ",
    paste(
      pipeline_scripts[!file.exists(pipeline_scripts)],
      collapse = ", "
    )
  )
}

# Record completion or failure for each stage
dir.create("results", showWarnings = FALSE)

pipeline_log <- data.frame(
  script = character(),
  status = character(),
  seconds = numeric(),
  message = character()
)

for (pipeline_script in pipeline_scripts) {
  cat("\nRunning:", pipeline_script, "\n")
  pipeline_stage_start <- Sys.time()
  
  pipeline_error <- tryCatch(
    {
      source(pipeline_script, local = FALSE)
      NA_character_
    },
    error = function(e) conditionMessage(e)
  )
  
  pipeline_log <- rbind(
    pipeline_log,
    data.frame(
      script = pipeline_script,
      status = if (is.na(pipeline_error)) "Completed" else "Failed",
      seconds = round(
        as.numeric(difftime(
          Sys.time(),
          pipeline_stage_start,
          units = "secs"
        )),
        2
      ),
      message = if (is.na(pipeline_error)) "" else pipeline_error
    )
  )
  
  write.csv(
    pipeline_log,
    "results/aim1_pipeline_log.csv",
    row.names = FALSE
  )
  
  if (!is.na(pipeline_error)) {
    stop(
      "Pipeline stopped at ", pipeline_script,
      ": ", pipeline_error
    )
  }
}

cat("\nAim 1 pipeline completed successfully.\n")
print(pipeline_log, row.names = FALSE)