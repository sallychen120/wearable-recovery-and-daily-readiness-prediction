# Rebuild the implemented Aim 1, Aim 2, and Aim 3 analyses
# Run from the RStudio project root

if (!file.exists("wearable-readiness.Rproj")) {
  stop("Open the wearable-readiness project before running this script.")
}

source("R/00_run_aim1.R")
source("R/00_run_aim2.R")
source("R/00_run_aims3.R")

cat("\nFull project pipeline completed successfully.\n")
