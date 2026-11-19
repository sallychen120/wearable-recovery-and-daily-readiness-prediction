# Stage 22: Prepare training and validation matrices for ridge regression
# Run from the RStudio project root

library(dplyr)

feature_path <- "data/intermediate/20_prediction_features.rds"
baseline_path <- "data/intermediate/21_prediction_baselines.rds"

if (!file.exists(feature_path) || !file.exists(baseline_path)) {
  stop("Stage 20 and Stage 21 outputs are required.")
}

feature_output <- readRDS(feature_path)
baseline_output <- readRDS(baseline_path)

training_data <- feature_output$prediction_features %>%
  filter(split == "train") %>%
  arrange(participant_id, target_date)

validation_data <- feature_output$prediction_features %>%
  filter(split == "validation") %>%
  arrange(participant_id, target_date)

if (nrow(training_data) == 0L || nrow(validation_data) == 0L) {
  stop("Training and validation observations are required.")
}

if (max(training_data$target_date) >=
    min(validation_data$target_date)) {
  stop("Training dates must precede validation dates.")
}

# Use the predictor definitions saved in Stage 20
specification <- feature_output$feature_specification

model_definitions <- list(
  B_absolute = specification$feature[
    specification$model_B & specification$type == "numeric"
  ],
  C_personal = specification$feature[
    specification$model_C & specification$type == "numeric"
  ]
)

categorical_features <- c("participant_id", "weekday")

# Learn categorical levels from the training data only
category_levels <- setNames(
  lapply(categorical_features, function(feature) {
    sort(unique(as.character(training_data[[feature]])))
  }),
  categorical_features
)

# Construct numeric features, missingness indicators, and dummy variables
make_raw_matrix <- function(
    data,
    numeric_features,
    medians,
    category_levels
) {
  numeric_matrix <- as.matrix(
    as.data.frame(data[numeric_features])
  )
  
  storage.mode(numeric_matrix) <- "double"
  
  missing_matrix <- !is.finite(numeric_matrix)
  
  for (feature in numeric_features) {
    missing_rows <- missing_matrix[, feature]
    numeric_matrix[missing_rows, feature] <- medians[[feature]]
  }
  
  indicator_matrix <- missing_matrix * 1
  colnames(indicator_matrix) <- paste0(
    numeric_features,
    "_missing"
  )
  
  result <- cbind(numeric_matrix, indicator_matrix)
  
  for (feature in names(category_levels)) {
    values <- as.character(data[[feature]])
    levels <- category_levels[[feature]]
    
    if (anyNA(values) || any(!values %in% levels)) {
      stop(paste("Unknown or missing categorical values:", feature))
    }
    
    dummy_matrix <- vapply(
      levels,
      function(level) as.numeric(values == level),
      numeric(nrow(data))
    )
    
    colnames(dummy_matrix) <- paste0(feature, "_", levels)
    result <- cbind(result, dummy_matrix)
  }
  
  result
}

designs <- list()
feature_audit <- list()
matrix_audit <- list()

for (model_name in names(model_definitions)) {
  numeric_features <- model_definitions[[model_name]]
  
  # Learn imputation values from the training data only
  medians <- setNames(
    vapply(numeric_features, function(feature) {
      values <- training_data[[feature]]
      observed <- values[is.finite(values)]
      
      if (length(observed) == 0L) {
        stop(paste("No observed training values:", feature))
      }
      
      median(observed)
    }, numeric(1)),
    numeric_features
  )
  
  raw_train <- make_raw_matrix(
    training_data,
    numeric_features,
    medians,
    category_levels
  )
  
  raw_validation <- make_raw_matrix(
    validation_data,
    numeric_features,
    medians,
    category_levels
  )
  
  # Learn centering and scaling parameters from training rows only
  centers <- colMeans(raw_train)
  training_sd <- apply(raw_train, 2, sd)
  
  scales <- training_sd
  scales[!is.finite(scales) | scales == 0] <- 1
  
  x_train <- sweep(raw_train, 2, centers, "-")
  x_train <- sweep(x_train, 2, scales, "/")
  
  x_validation <- sweep(raw_validation, 2, centers, "-")
  x_validation <- sweep(x_validation, 2, scales, "/")
  
  if (!identical(colnames(x_train), colnames(x_validation))) {
    stop("Training and validation columns must match.")
  }
  
  if (!all(is.finite(x_train)) ||
      !all(is.finite(x_validation))) {
    stop("All prepared predictor values must be finite.")
  }
  
  designs[[model_name]] <- list(
    numeric_features = numeric_features,
    category_levels = category_levels,
    medians = medians,
    centers = centers,
    scales = scales,
    x_train = x_train,
    x_validation = x_validation
  )
  
  feature_audit[[model_name]] <- data.frame(
    model = model_name,
    feature = numeric_features,
    training_median = unname(medians),
    training_missing = vapply(
      numeric_features,
      function(feature) {
        sum(!is.finite(training_data[[feature]]))
      },
      integer(1)
    ),
    validation_missing = vapply(
      numeric_features,
      function(feature) {
        sum(!is.finite(validation_data[[feature]]))
      },
      integer(1)
    ),
    row.names = NULL
  )
  
  matrix_audit[[model_name]] <- data.frame(
    model = model_name,
    training_rows = nrow(x_train),
    validation_rows = nrow(x_validation),
    predictor_columns = ncol(x_train),
    constant_training_columns = sum(training_sd == 0),
    training_missing_after_processing = sum(!is.finite(x_train)),
    validation_missing_after_processing =
      sum(!is.finite(x_validation))
  )
}

feature_audit <- bind_rows(feature_audit)
matrix_audit <- bind_rows(matrix_audit)

# Preserve observed outcomes without imputation or scaling
y_train <- training_data$readiness_target
y_validation <- validation_data$readiness_target

if (!all(is.finite(y_train)) ||
    !all(is.finite(y_validation))) {
  stop("Observed readiness outcomes must be finite.")
}

saveRDS(
  list(
    designs = designs,
    y_train = y_train,
    y_validation = y_validation,
    training_keys = training_data %>%
      select(participant_id, target_date),
    validation_keys = validation_data %>%
      select(participant_id, target_date),
    selected_baseline = baseline_output$selected_baseline,
    baseline_validation_metrics =
      baseline_output$validation_metrics,
    evaluation_rules = baseline_output$evaluation_rules,
    split_boundaries = feature_output$split_boundaries,
    alignment_status = feature_output$alignment_status
  ),
  "data/intermediate/22_prediction_designs.rds"
)

readr::write_csv(
  feature_audit,
  "results/aim3_preprocessing_feature_audit.csv"
)

readr::write_csv(
  matrix_audit,
  "results/aim3_prediction_matrix_audit.csv"
)

cat("\nPrediction matrix audit:\n")
print(as.data.frame(matrix_audit), row.names = FALSE)

cat("\nTraining-only imputation values:\n")
print(as.data.frame(feature_audit), row.names = FALSE)

cat("\nStage 22 completed. Ridge input matrices were saved.\n")