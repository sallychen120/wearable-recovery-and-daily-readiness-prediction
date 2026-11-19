# Analysis variable codebook

## Reading conventions

The daily panel contains one row per participant and source date. Training tables contain sessions or participant training dates; event tables contain high-load events and relative dates. Prediction tables contain participant target dates. Summary tables group these records by the identifiers shown in each file.

Dates use `YYYY-MM-DD`. Questionnaire and training timestamps are parsed as UTC. Fitbit sleep timestamps remain source text with an unverified time zone. Calendar-day offsets refer to source dates. Missing values appear as R `NA`, `NA` in CSV, or empty CSV cells, depending on the file writer. Readiness zero and a recorded training load of zero are valid values.

The definitions cover fields in the saved analysis tables and CSV results, including the encoded prediction matrix columns. Each table below names the source script or saved object that establishes the field's meaning. Temporary function arguments and optimizer internals are outside this dictionary.

## Daily measurements

Sources: [cleaning](../R/02_clean.R), [daily selection](../R/02b_make_daily.R), and [calendar merge](../R/03_merge.R). Saved tables: `02_cleaned.rds`, `02_daily.rds`, and `03_panel_draft.rds$daily_panel_draft` under `data/intermediate/`.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `participant_id` | Text; factor in association models | Original pseudonymous participant ID. The imported sample is p01 through p11, p14, p15, and p16. Used for joins, clustering, random intercepts, and prediction indicators. |
| `date` | Date | Daily join key. Wellness uses the UTC date in `effective_time_frame`; heart rate uses the source `dateTime` date; sleep uses `dateOfSleep`. In event windows it equals event date plus relative day. |
| `wellness_time_text` | Text timestamp | Original wellness `effective_time_frame` value for the selected report. |
| `wellness_time_utc` | UTC datetime | Parsed questionnaire timestamp. The earliest timestamp on each participant-date determines the main daily report. |
| `wellness_reports_that_day` | Integer count | Number of original wellness reports on the participant-date before selecting the earliest. |
| `readiness` | Numeric, 0 to 10 points | Self-reported readiness to exercise, with higher scores indicating greater readiness. Main outcome in Aim 1 and an Aim 2 trajectory measurement. |
| `fatigue` | Numeric, original 1 to 5 score | PMSys fatigue response retained on the source scale. Used for record review and range checks. |
| `self_report_sleep_hours` | Numeric, hours | Questionnaire `sleep_duration_h`, parsed as a number. Used for record review; the model sleep exposure is Fitbit `sleep_hours`. |
| `resting_hr` | Numeric, bpm | Fitbit `value$value` for daily resting heart rate, after exact deduplication and replacement of nonpositive values with missing. In `file_inventory.csv`, this same column name is a logical file-existence flag. |
| `resting_hr_raw` | Numeric, bpm | Heart rate before the nonpositive-value rule, retained alongside the cleaned measurement. |
| `resting_hr_invalid` | Logical | TRUE when the observed raw heart rate is zero or negative. Such a value produces missing `resting_hr`; an originally missing value is not marked invalid. |
| `log_id` | Text | Original Fitbit sleep `logId`. |
| `start_time` | Text timestamp | Original Fitbit sleep `startTime`; no time zone is assigned. |
| `end_time` | Text timestamp | Original Fitbit sleep `endTime`; no time zone is assigned. |
| `sleep_hours` | Numeric, hours | Fitbit `minutesAsleep / 60`. Daily analyses select `mainSleep == TRUE` after exact deduplication. |
| `main_sleep` | Logical | Original Fitbit `mainSleep` flag. TRUE records enter the daily panel; other episodes are not added to the selected sleep duration. |

## Aim 1 Baselines and model variables

Sources: [feature construction](../R/05_build_features.R), [initial model](../R/07_fit_aim1.R), and [residual structures](../R/09_check_robustness.R). Saved objects: `05_features.rds$feature_panel`, `05_features.rds$analysis_data`, `07_aim1_models.rds$model_data`, and `09_aim1_robustness.rds$full_data`.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `hr_observed_days` | Integer count | Valid heart-rate dates used to calculate the participant's full-period heart-rate mean. |
| `hr_person_mean` | Numeric, bpm | Participant's mean of all available valid resting-heart-rate observations, including dates outside the complete-case analysis sample. |
| `sleep_observed_days` | Integer count | Observed main-sleep dates used to calculate the participant's full-period sleep mean. |
| `sleep_person_mean` | Numeric, hours | Participant's mean main-sleep duration over all available valid dates. |
| `hr_deviation` | Numeric, bpm | `resting_hr - hr_person_mean`. Positive values mean heart rate above the person's full-period mean. |
| `sleep_deviation` | Numeric, hours | `sleep_hours - sleep_person_mean`. Positive values mean longer sleep than the person's full-period mean. |
| `readiness_reporting_review` | Logical | TRUE for p05. Review marker supporting the participant-exclusion sensitivity analysis; it does not change readiness scores. |
| `hr_person_mean_c` | Numeric, bpm | Personal heart-rate mean minus the unweighted mean of personal heart-rate means across the imported participants. Between-person predictor. |
| `sleep_person_mean_c` | Numeric, hours | Personal sleep mean minus the unweighted mean of personal sleep means across the imported participants. Between-person predictor. |
| `study_day_30` | Numeric, 30-day units | Days since the earliest date in the full calendar panel, divided by 30. Linear time adjustment. |
| `calendar_day` | Integer, days | Days since that same study start. AR(1) time index preserving gaps between complete observations. |

The association sample requires observed readiness, resting heart rate, and main-sleep duration. `analysis_without_p05` removes p05 from that sample. These full-period baselines belong to association analysis; Aim 3 uses the historical baselines defined below.

## Aim 1 Diagnostics and report selection

Sources: [initial diagnostics](../R/08_check_aim1.R), [AR(1) diagnostics](../R/09_check_robustness.R), and [earliest versus latest reports](../R/12_check_report_choice.R).

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `fitted_readiness` | Numeric, readiness points | Conditional fitted readiness from the relevant mixed model, including the participant random intercept. |
| `scaled_residual` | Numeric, unitless | Initial model's observed-minus-fitted residual divided by its estimated residual standard deviation. |
| `normalized_residual` | Numeric, unitless | `nlme` residual adjusted for the model's fitted covariance structure. |
| `previous_date` | Date | Previous observed model date within the participant and, where applicable, model version. |
| `previous_residual` | Numeric, unitless | Previous observed scaled residual in Stage 08 or normalized residual in Stage 09. |
| `gap_days` | Integer, days | Current date minus previous observed model date. Residual-pair diagnostics retain values equal to 1. |
| `scaled_residual_sd` | Numeric, unitless | Participant-specific standard deviation of initial-model scaled residuals. |
| `residuals_above_3_in_absolute_value` | Integer count | Model dates with absolute scaled residual greater than 3. |
| `fitted_values_outside_readiness_scale` | Integer count | Conditional fitted values below 0 or above 10. These fitted values are not the bounded Aim 3 predictions. |
| `consecutive_day_pairs` | Integer count | Residual pairs separated by exactly one calendar day. |
| `lag1_residual_correlation` | Numeric, -1 to 1 | Correlation of current and preceding residuals among consecutive-day pairs; missing if fewer than three pairs or either residual series has zero variance. |
| `earliest_report_time` | Text timestamp | Source timestamp of the earliest report on an original complete-case date. |
| `latest_report_time` | Text timestamp | Source timestamp of the latest report on that same date. |
| `readiness_earliest` | Numeric, 0 to 10 points | Earliest report's readiness score. |
| `readiness_latest` | Numeric, 0 to 10 points | Latest report's readiness score. |
| `report_rule` | Text category | `Earliest` or `Latest`, identifying the outcome-selection rule in the sensitivity coefficient table. |

## Training sessions and daily loads

Sources: [session preparation](../R/14_prepare_training_sessions.R) and [daily aggregation](../R/15_training_daily_coverage.R). Saved objects: `14_training_sessions.rds$sessions` and `15_training_daily.rds$daily_training`.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `source_row` | Integer | Row number in the participant's original training CSV before deduplication. |
| `end_time_text` | Text timestamp | Original training `end_date_time` field. |
| `activity_names` | Text | Original reported activity label, retained for review. |
| `rpe_text` | Text | Original `perceived_exertion` field before numeric parsing. |
| `duration_text` | Text | Original `duration_min` field before numeric parsing. |
| `session_id` | Text identifier | Participant ID joined to the original source row with an underscore. |
| `session_end_utc` | UTC datetime | Parsed training session end time. |
| `training_date_utc` | Date | UTC date of the session end; daily training aggregation key. |
| `rpe` | Numeric, 0 to 10 | Parsed rating of perceived exertion. Zero is accepted. |
| `duration_minutes` | Numeric, minutes | Parsed reported session duration. A finite value greater than zero is required for load calculation. |
| `rpe_outside_review_range` | Logical at session level; integer in quality summary | TRUE when an observed RPE is nonfinite or outside 0 to 10. The same name in `training_session_quality.csv` counts flagged sessions. |
| `duration_invalid` | Logical | TRUE when an observed duration is nonfinite or nonpositive. |
| `load_usable` | Logical | TRUE when session end time is parsed, RPE is observed and valid, and duration is observed and valid. |
| `session_load` | Numeric, RPE-minutes | `rpe * duration_minutes` for usable sessions; otherwise missing. |
| `logged_sessions` | Integer count | Reported sessions on a participant's UTC training date after exact deduplication. |
| `usable_sessions` | Integer count | Sessions with usable load within the grouping shown: participant-date in the daily table or participant in the quality summary. |
| `incomplete_sessions` | Integer count | Sessions on the training date with unusable load. |
| `logged_daily_load` | Numeric, RPE-minutes | Sum of session loads if every reported session on the date is usable; otherwise missing. Unreported dates have unknown load. |
| `logged_duration_minutes` | Numeric, minutes | Sum of reported durations on dates where every session is usable; otherwise missing. |
| `training_day_id` | Text identifier | Participant ID plus training date formatted as `YYYYMMDD`, separated by an underscore. |

## High-load events and window availability

Sources: [follow-up coverage](../R/15_training_daily_coverage.R) and [event selection](../R/16_select_training_events.R). Saved objects: `15_training_daily.rds$followup_grid`, `16_aim2_event_candidates.rds$candidates`, `$event_windows`, and `$event_coverage`.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `high_load_threshold` | Numeric, RPE-minutes | Participant's 75th percentile of calculable recorded daily loads, using R quantile type 7. |
| `eligible_for_events` | Logical | TRUE with at least 20 calculable training dates and an available personal threshold. |
| `eligibility_reason` | Text category | `Eligible`, `Fewer than 20 calculable training dates`, or `No calculable logged load`. |
| `event_date` | Date | UTC training-end date with calculable daily load at or above the eligible participant's threshold. |
| `event_logged_load` | Numeric, RPE-minutes | Recorded daily load on the candidate event date. |
| `event_id` | Text identifier | Participant ID plus event date in `YYYYMMDD` format, separated by an underscore. |
| `days_since_previous_candidate` | Integer, days | Distance to the participant's preceding high-load candidate; missing for the first candidate. |
| `days_until_next_candidate` | Integer, days | Distance to the participant's next high-load candidate; missing for the last candidate. |
| `nonoverlapping_window` | Logical | TRUE if both neighboring candidate distances exceed four days, treating an absent neighbor as meeting that side of the rule. |
| `relative_day` | Integer, days | Date offset from the training date. Stage 15 uses 0 through +3; the high-load event analysis uses -1 through +3. |
| `logged_sessions_on_date` | Integer count | Number of reported training sessions on the matched window date; missing when no training date is recorded. |
| `logged_load_on_date` | Numeric, RPE-minutes | Calculable daily training load on the matched window date; missing for absent reports or incomplete load. |
| `readiness_complete_window` | Logical | Readiness is observed on all five event dates, -1 through +3. |
| `heart_rate_complete_window` | Logical | Heart rate is observed on all five event dates. |
| `sleep_complete_window` | Logical | Main-sleep duration is observed on all five event dates. |
| `all_metrics_complete_window` | Logical | All three measurements are observed on every date from -1 through +3. |
| `all_metrics_complete_post_days` | Logical | All three measurements are observed on dates +1, +2, and +3. |
| `later_training_reported` | Logical | At least one training record exists on an event's +1, +2, or +3 date, regardless of whether its load is calculable. |
| `readiness_all_three_days` | Logical | Readiness is observed on +1, +2, and +3 after a calculable training date in the preliminary coverage analysis. |
| `heart_rate_all_three_days` | Logical | Heart rate is observed on all three preliminary follow-up dates. |
| `sleep_all_three_days` | Logical | Sleep duration is observed on all three preliminary follow-up dates. |
| `all_metrics_all_three_days` | Logical | All three measurements are observed on all three preliminary follow-up dates. |

## Event changes and participant sensitivity

Sources: [event trajectories](../R/17_plot_training_trajectories.R) and [participant omission](../R/18_check_trajectory_sensitivity.R). Saved summaries: `17_aim2_trajectories.rds` and `18_aim2_participant_sensitivity.rds`.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `sample` | Text category | `Nonoverlapping` is the primary five-date complete sample passing the four-day candidate-spacing rule. `All complete` allows adjacent high-load candidates. |
| `metric` | Text category | Measurement identifier: `readiness`, `resting_hr`, or `sleep_hours` in measurement tables. Plotting code can also use it to distinguish MAE and RMSE. |
| `metric_label` | Text or factor | Display label specifying measurement and units. Check this label for the sleep-unit conversion in participant sensitivity results. |
| `value` | Numeric, measurement units | Measurement on a relative date in the long event table used during trajectory calculation. |
| `reference_value` | Numeric, measurement units | Same event's measurement at relative day -1. |
| `change` | Numeric, measurement units | `value - reference_value` for the event and measurement. |
| `participant_mean_change` | Numeric, measurement units | Mean event change within a participant, sample, measurement, and relative day. |
| `mean_change` | Numeric, measurement units | Unweighted mean of participant mean changes. In `aim2_trajectory_summary.csv`, sleep is in hours. |
| `participants` | Integer count | Distinct contributing participants in the row's sample or model comparison. For the grand trajectory this is the number of participant means. |
| `events` | Integer count | Contributing events. Participant summaries count that person's events; grand summaries sum event counts across participants. |
| `omission_mean` | Numeric, measurement units | Equal-participant mean after removing the named participant and all their events. Sleep remains in hours in the saved omission curves. |
| `participants_remaining` | Integer count | Participants contributing after the named omission. |
| `events_remaining` | Integer count | Events contributing after the named omission. |
| `omitted_participant` | Text identifier | Participant removed for that omission curve. |
| `full_sample_mean` | Numeric, displayed measurement units | Primary-sample mean before omission. Sleep is in hours in the internal sensitivity summary and minutes in `aim2_participant_sensitivity.csv`. |
| `omission_min` | Numeric, displayed measurement units | Lowest mean across single-participant omissions. Sleep is converted to minutes in the exported sensitivity CSV. |
| `omission_max` | Numeric, displayed measurement units | Highest mean across single-participant omissions; same unit convention as `omission_min`. |
| `largest_absolute_shift` | Numeric, displayed measurement units | Largest absolute difference between an omission mean and the full-sample mean; same sleep-unit convention. |

Omission ranges describe dependence on participant composition. They are not sampling confidence intervals. Event changes use the preceding date as their reference, whereas Aim 1 deviations use the participant's full-period mean.

## Aim 3 Historical prediction variables

Sources: [prediction audit](../R/19_audit_prediction_data.R) and [feature construction](../R/20_make_prediction_features.R). Main table: `data/processed/aim3_prediction_features.csv`, also saved as `20_prediction_features.rds$prediction_features`.

For target date `d`, readiness history ends before `d`, wearable values come from `d-2`, and wearable baseline windows cover `d-16` through `d-3`, inclusive. Each wearable baseline needs at least five finite observations in those 14 calendar dates. Histories may update from earlier validation or test observations; fitted model parameters stay fixed.

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `target_date` | Date | Date whose readiness is predicted. Renamed from the daily panel's `date`. |
| `split` | Category | `train`, `validation`, or `test`, assigned from common calendar boundaries before filtering observed targets. |
| `readiness_target` | Numeric, 0 to 10 points | Observed readiness on the target date. Outcome retained without imputation or scaling. |
| `weekday` | Text category | Target-date day of week: Mon, Tue, Wed, Thu, Fri, Sat, or Sun. Categorical predictor in B and C. |
| `last_readiness` | Numeric, 0 to 10 points | Participant's most recent observed readiness strictly before the target date. Standalone persistence baseline and predictor in B and C. |
| `last_readiness_date` | Date | Date of that most recent readiness report. Audit field. |
| `days_since_last_readiness` | Integer, days | Target date minus last readiness date. Predictor in B and C; may exceed one when reporting is intermittent. |
| `readiness_past_mean` | Numeric, readiness points | Mean of all observed readiness values before the target date. Standalone historical-mean baseline and predictor in B and C. |
| `readiness_past_count` | Integer count | Observed readiness scores contributing to the expanding past mean. Audit field. |
| `hr_lag2` | Numeric, bpm | Resting heart rate on source date `d-2`, not the second-most-recent nonmissing heart-rate record. Predictor in B and C. |
| `sleep_lag2` | Numeric, hours | Main-sleep duration on source date `d-2`. Predictor in B and C. |
| `wearable_source_date` | Date | Source date `d-2` when that date exists in the participant calendar. Audit field. |
| `hr_baseline_lag2` | Numeric, bpm | Mean of valid heart rates on `d-16` through `d-3`; missing when fewer than five observations are available. Audit field used to derive the deviation. |
| `sleep_baseline_lag2` | Numeric, hours | Mean of valid main-sleep durations in that same calendar window; the five-observation rule applies separately. |
| `hr_baseline_count_lag2` | Integer count | Finite heart-rate observations in the historical window, including counts below five. Audit field. |
| `sleep_baseline_count_lag2` | Integer count | Finite sleep observations in the historical window. Audit field. |
| `baseline_window_start` | Date | `target_date - 16`, the nominal first date of the wearable baseline window. |
| `baseline_window_end` | Date | `target_date - 3`, the last date of the wearable baseline window. |
| `hr_deviation_lag2` | Numeric, bpm | `hr_lag2 - hr_baseline_lag2`. Added predictor in Model C; missing if the source value or baseline is missing. |
| `sleep_deviation_lag2` | Numeric, hours | `sleep_lag2 - sleep_baseline_lag2`. Added predictor in Model C. |

The sample requires an observed target and an available `last_readiness`. Missing wearable inputs remain in the sample and receive the training-based preprocessing below. Raw personal baselines, counts, and audit dates are not additional model predictors.

## Prediction matrix coding

Sources: [training and validation matrices](../R/22_prepare_prediction_matrices.R) and [test transformation](../R/24_evaluate_prediction_test.R). Saved matrices: `22_prediction_designs.rds$designs`, with 31 columns for B and 35 for C.

Each numeric feature is imputed with its training median when nonfinite. Its missingness indicator records the value before imputation. Category levels come from training data, with a separate indicator for every participant and weekday. All matrix columns, including indicators, are then transformed as `(raw column - training column mean) / training column SD`; zero training SD is replaced by 1. Thus saved matrix indicators are standardized numeric values, while the definitions below describe their raw 0/1 coding.

| Variable | Type before scaling | Meaning and model use |
| --- | --- | --- |
| `last_readiness_missing` | Numeric, 0 or 1 | 1 when `last_readiness` is nonfinite before imputation. B and C. |
| `readiness_past_mean_missing` | Numeric, 0 or 1 | 1 when `readiness_past_mean` is nonfinite before imputation. B and C. |
| `days_since_last_readiness_missing` | Numeric, 0 or 1 | 1 when the reporting gap is nonfinite before imputation. B and C. |
| `hr_lag2_missing` | Numeric, 0 or 1 | 1 when lagged absolute heart rate is nonfinite before imputation. B and C. |
| `sleep_lag2_missing` | Numeric, 0 or 1 | 1 when lagged absolute sleep duration is nonfinite before imputation. B and C. |
| `hr_deviation_lag2_missing` | Numeric, 0 or 1 | 1 when the lagged personal heart-rate deviation is nonfinite before imputation. C. |
| `sleep_deviation_lag2_missing` | Numeric, 0 or 1 | 1 when the lagged personal sleep deviation is nonfinite before imputation. C. |
| `participant_id_p01` | Numeric, 0 or 1 | 1 for participant p01, otherwise 0. B and C. |
| `participant_id_p02` | Numeric, 0 or 1 | 1 for participant p02, otherwise 0. B and C. |
| `participant_id_p03` | Numeric, 0 or 1 | 1 for participant p03, otherwise 0. B and C. |
| `participant_id_p04` | Numeric, 0 or 1 | 1 for participant p04, otherwise 0. B and C. |
| `participant_id_p05` | Numeric, 0 or 1 | 1 for participant p05, otherwise 0. B and C. |
| `participant_id_p06` | Numeric, 0 or 1 | 1 for participant p06, otherwise 0. B and C. |
| `participant_id_p07` | Numeric, 0 or 1 | 1 for participant p07, otherwise 0. B and C. |
| `participant_id_p08` | Numeric, 0 or 1 | 1 for participant p08, otherwise 0. B and C. |
| `participant_id_p09` | Numeric, 0 or 1 | 1 for participant p09, otherwise 0. B and C. |
| `participant_id_p10` | Numeric, 0 or 1 | 1 for participant p10, otherwise 0. B and C. |
| `participant_id_p11` | Numeric, 0 or 1 | 1 for participant p11, otherwise 0. B and C. |
| `participant_id_p14` | Numeric, 0 or 1 | 1 for participant p14, otherwise 0. B and C. |
| `participant_id_p15` | Numeric, 0 or 1 | 1 for participant p15, otherwise 0. B and C. |
| `participant_id_p16` | Numeric, 0 or 1 | 1 for participant p16, otherwise 0. B and C. |
| `weekday_Mon` | Numeric, 0 or 1 | 1 for a Monday target, otherwise 0. B and C. |
| `weekday_Tue` | Numeric, 0 or 1 | 1 for a Tuesday target, otherwise 0. B and C. |
| `weekday_Wed` | Numeric, 0 or 1 | 1 for a Wednesday target, otherwise 0. B and C. |
| `weekday_Thu` | Numeric, 0 or 1 | 1 for a Thursday target, otherwise 0. B and C. |
| `weekday_Fri` | Numeric, 0 or 1 | 1 for a Friday target, otherwise 0. B and C. |
| `weekday_Sat` | Numeric, 0 or 1 | 1 for a Saturday target, otherwise 0. B and C. |
| `weekday_Sun` | Numeric, 0 or 1 | 1 for a Sunday target, otherwise 0. B and C. |

## Coefficient tables and model identifiers

Sources: [initial coefficients](../R/07_fit_aim1.R), [model versions](../R/09_check_robustness.R), [CR2 intervals](../R/10_robust_intervals.R), and [display units](../R/11_plot_aim1_results.R).

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `(Intercept)` | Coefficient name | Model intercept. In Aim 1 it is the population intercept at zero deviations, centered person means, and study time. |
| `model` | Text identifier | Aim 1 uses `iid_all`, `ar1_all`, `iid_without_p05`, and `ar1_without_p05`. Prediction uses `baseline_last_readiness`, `baseline_past_mean`, `B_absolute`, and `C_personal`. |
| `inference` | Text category | `Model-based` or `Participant-clustered CR2`, identifying the covariance and interval method. |
| `term` | Text | Regression coefficient name. Units follow the named predictor and readiness outcome. |
| `estimate` | Numeric, readiness points per predictor unit | Fitted regression coefficient. Heart-rate coefficients are per 1 bpm except in `aim1_robust_estimates_display_units.csv`, where they are multiplied by 5. |
| `std_error` | Numeric, coefficient units | Standard error under the stated inference method. Scaled with the coefficient in the display-units table. |
| `df` | Numeric | Degrees of freedom used for the coefficient's t test and 95% interval; may be fractional under Satterthwaite adjustment. |
| `conf_low` | Numeric, coefficient units | Lower endpoint of the 95% t-based confidence interval. |
| `conf_high` | Numeric, coefficient units | Upper endpoint of the 95% t-based confidence interval. |
| `p_value` | Numeric, 0 to 1 | Two-sided test of a zero coefficient using the stated model and inference method. |
| `contrast` | Text | Display contrast, either 5 bpm above personal mean heart rate or 1 hour above personal mean sleep. |
| `ar1_rho` | Numeric, correlation | Shared one-calendar-day AR(1) residual correlation within the fitted model; missing for independent-residual versions. |

The two prediction baselines copy the latest readiness and the expanding historical mean, respectively. `B_absolute` is ridge regression with five numeric predictors and participant/weekday coding; `C_personal` adds two personal physiological deviations and their missingness indicators.

## Prediction results and evaluation settings

Sources: [baseline evaluation](../R/21_compare_prediction_baselines.R), [ridge tuning](../R/23_fit_prediction_models.R), [test evaluation](../R/24_evaluate_prediction_test.R), and [plot comparisons](../R/25_plot_prediction_results.R).

| Variable | Type and unit | Meaning and construction |
| --- | --- | --- |
| `observed` | Numeric, readiness points | Actual target readiness. |
| `predicted` | Numeric, readiness points | Model or baseline prediction, bounded to 0 through 10. |
| `error` | Numeric, readiness points; text in download manifests | Prediction minus observed readiness; positive values mean overprediction. In download manifests this column contains an error message or a missing/empty value. |
| `absolute_error` | Numeric, readiness points | Absolute value of the prediction error. |
| `squared_error` | Numeric, squared readiness points | Prediction error squared. |
| `prediction_targets` | Integer count | Target dates in the row's model, participant, or split. |
| `mae` | Numeric, readiness points | Mean absolute error over the row's target dates. Overall rows pool all dates; participant rows use that participant's dates. |
| `rmse` | Numeric, readiness points | Square root of mean squared error over the row's target dates. |
| `macro_mae` | Numeric, readiness points | Unweighted mean of participant-specific MAEs. |
| `reference_mae` | Numeric, readiness points | Participant's MAE for the validation-selected reference baseline, in the test participant comparison. |
| `mae_change_vs_reference` | Numeric, readiness points | Model MAE minus reference-baseline MAE, using pooled or participant MAE as appropriate. Negative values indicate lower error. |
| `mae_reduction_percent` | Numeric, percent | `100 * (reference MAE - model MAE) / reference MAE`. Positive values indicate lower pooled MAE. |
| `baseline_mae` | Numeric, readiness points | Participant MAE for the comparison baseline identified by `reference` in plot data. |
| `reference` | Text identifier | Baseline model used in a participant plot comparison. Both readiness-history baselines appear in the plot data. |
| `mae_change` | Numeric, readiness points | Participant model MAE minus `baseline_mae` for the selected plot comparison. |
| `model_label` | Text or factor | Human-readable model name used in a plot. |
| `reference_label` | Text or factor | Human-readable baseline comparison label used in a plot. |
| `lambda` | Numeric, positive | Ridge penalty in `mean squared training error + lambda * sum(squared slopes)`; the intercept is unpenalized. Missing for simple baselines in combined comparison tables. |
| `grid_boundary` | Logical | TRUE when the selected penalty equals the lowest or highest value in the candidate grid. |
| `selection_dataset` | Text | Dataset used to select the reference baseline: `validation`. |
| `selection_metric` | Text | Reference-baseline selection criterion: pooled MAE. |
| `fitting_data` | Text | Period used to estimate ridge coefficients: original training period. |
| `parameter_selection_data` | Text | Period used to select the ridge penalty: validation period. |
| `preprocessing_data` | Text | Period used to estimate medians, category levels, centers, and scales: original training period. |
| `history_updates` | Text | Rule allowing histories to use earlier observations before each target date. |
| `primary_metric` | Text | Primary model-selection and reporting metric: pooled MAE. |
| `reference_baseline` | Text identifier | Baseline selected on validation MAE; the current saved evaluation uses `baseline_past_mean`. |
| `first_target_date` | Date | Earliest actual observed target in the test comparison. |
| `last_target_date` | Date | Latest actual observed target in the test comparison; it may precede the split's calendar end. |

## Coverage and quality summary fields

These columns describe samples and checks. Counts refer to the participant, period, source, measurement, or event grouping shown in the file.

### File availability and daily coverage

Sources: [file inventory](../R/00_check_files.R), [merge](../R/03_merge.R), and [complete-case counts](../R/05_build_features.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `wellness` | Logical | Required wellness CSV exists for the participant. |
| `sleep` | Logical | Required sleep JSON exists for the participant. |
| `ready_to_import` | Logical | Wellness, heart-rate, and sleep files all exist. |
| `calendar_days` | Integer count | Dates in the participant's continuous calendar, or dates in a zero-readiness run when used in the run table. |
| `wellness_days` | Integer count | Calendar dates with a selected wellness report. |
| `readiness_days` | Integer count | Calendar dates with observed selected readiness. |
| `resting_hr_days` | Integer count | Calendar dates with valid resting heart rate. |
| `sleep_days` | Integer count | Calendar dates with selected main-sleep duration. |
| `complete_days` | Integer count | Dates with observed readiness, valid heart rate, and main-sleep duration; diagnostic and report-choice tables retain this analysis sample. |
| `readiness_zero_days` | Integer count | Observed readiness scores equal to zero, within the file's panel or complete-case sample. |
| `readiness_distinct_values` | Integer count | Distinct readiness scores in the participant's complete-case sample. |
| `readiness_sd` | Numeric, readiness points | Sample standard deviation of readiness in that complete-case sample. |

### Cleaning and daily record selection

Sources: [cleaning audit](../R/02_clean.R), [sleep duplicate checks](../R/02a_review_duplicates.R), and [daily selection](../R/02b_make_daily.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `source` | Text category | Measurement stream: wellness, resting heart rate, or sleep. |
| `records_before` | Integer count | Stream records before exact deduplication. |
| `records_after` | Integer count | Stream records after exact deduplication, before daily selection. |
| `duplicates_removed` | Integer count | `records_before - records_after`. |
| `invalid_values_set_missing` | Integer count | Raw nonpositive heart rates changed to missing; zero for the other streams. |
| `repeated_date_rows` | Integer count | Rows beyond the first sharing a date within the participant-stream or main-sleep check. |
| `missing_date_rows` | Integer count | Records with missing parsed source dates. |
| `wellness_before` | Integer count | Cleaned wellness records before selecting one report per day. |
| `wellness_selected` | Integer count | Daily wellness reports retained by the earliest-timestamp rule. |
| `sleep_before` | Integer count | Deduplicated sleep episodes before selecting main sleep. |
| `sleep_selected` | Integer count | Main-sleep records retained for the daily panel. |
| `sleep_unknown_main_flags` | Integer count | Sleep records whose main-sleep flag is missing. |
| `main_records` | Integer count | Main-sleep records in the duplicate review. |
| `main_dates` | Integer count | Distinct dates among those main-sleep records. |

### Measurement descriptions and flags

Sources: [descriptive statistics](../R/04_describe.R), [measurement quality](../R/04a_quality_review.R), [timing review](../R/04b_review_timing.R), and [readiness review](../R/04c_review_readiness.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `observed_days` | Integer count | Nonmissing values for the participant and measurement. |
| `missing_days` | Integer count | Missing values for that participant and measurement across the calendar. |
| `mean` | Numeric, measurement units | Mean of observed values, rounded to two decimals in `metric_summary.csv`. |
| `sd` | Numeric, measurement units | Sample standard deviation of observed values, rounded to two decimals. |
| `minimum` | Numeric, measurement units | Smallest observed value, rounded to two decimals. |
| `maximum` | Numeric, measurement units | Largest observed value, rounded to two decimals. |
| `hr_missing_days` | Integer count | Missing cleaned heart-rate values, including raw nonpositive values set to missing. |
| `hr_nonpositive` | Logical | Observed cleaned heart rate is nonpositive. This post-cleaning check differs from the raw-value flag `resting_hr_invalid`. |
| `hr_nonpositive_days` | Integer count | Dates flagged by `hr_nonpositive`; excludes invalid raw values already set to missing. |
| `hr_positive_days` | Integer count | Dates with positive cleaned heart rate. |
| `readiness_out_of_range` | Logical | Observed readiness is below 0 or above 10. |
| `readiness_out_of_range_days` | Integer count | Dates with readiness outside the accepted range. |
| `fatigue_out_of_range` | Logical | Observed fatigue is below 1 or above 5. |
| `fatigue_out_of_range_days` | Integer count | Dates with fatigue outside the checked source range. |
| `wellness_records` | Integer count | Selected calendar-panel wellness reports with source timestamps. |
| `wellness_hour_utc` | Integer, 0 to 23 | Hour extracted from the parsed questionnaire timestamp in UTC. |
| `wellness_before_06_utc` | Integer count | Selected reports with questionnaire hour below 6 UTC; review flag only. |
| `sleep_records` | Integer count | Calendar-panel sleep records with end timestamps. |
| `sleep_end_hour_label` | Integer, 0 to 23 | Hour characters from the source sleep-end text, without time-zone conversion. |
| `sleep_ending_at_or_after_12_source_clock` | Integer count | Sleep records whose source end-hour label is at least 12; review flag only. |
| `sleep_date_mismatch` | Logical | Date characters in the sleep-end timestamp differ from the panel sleep date. |
| `sleep_date_mismatch_records` | Integer count | Records with that source-date mismatch. |
| `month` | Text, YYYY-MM | Calendar month of the source date. |
| `observed_readiness_days` | Integer count | Nonmissing readiness dates within participant-month. |
| `zero_readiness_days` | Integer count | Zero readiness dates within participant-month. |
| `nonzero_readiness_days` | Integer count | Readiness dates above zero within participant-month. |
| `readiness_state` | Text category | `Missing`, `Zero`, or `Nonzero`; the exported zero-run table retains `Zero`. |
| `run_id` | Integer identifier | Participant-specific consecutive run number, incremented when readiness state changes. |
| `start_date` | Date | Inclusive start of a prediction split, or first date of a zero-readiness run, according to the file. |
| `end_date` | Date | Inclusive end of that split or run. |
| `days_with_multiple_reports` | Integer count | Original complete-case dates with more than one wellness report. |
| `days_with_changed_readiness` | Integer count | Original complete-case dates whose latest readiness differs from earliest readiness. |

### Mixed-model fitting checks

Source: [initial fitting checks](../R/07_fit_aim1.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `observations` | Integer count | Complete participant-dates fitted by the mixed model. |
| `singular_fit` | Logical | Result of the initial model's singularity check at tolerance 0.0001. |
| `optimizer_converged` | Logical | TRUE when the initial optimizer's convergence code is zero. |
| `lme4_messages` | Text | Initial model's stored convergence messages, or `None`. |

### Training and event summary counts

Sources: [training quality](../R/14_prepare_training_sessions.R), [daily coverage](../R/15_training_daily_coverage.R), and [event coverage](../R/16_select_training_events.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `raw_records` | Integer count | Training CSV rows before deduplication. |
| `records_after_deduplication` | Integer count | Distinct training sessions retained. |
| `exact_duplicates_removed` | Integer count | Raw training rows minus retained distinct sessions. |
| `missing_end_times` | Integer count | Sessions without a parsed end timestamp. |
| `missing_rpe` | Integer count | Sessions with missing parsed RPE. |
| `missing_duration` | Integer count | Sessions with missing parsed duration. |
| `invalid_duration` | Integer count | Sessions flagged by `duration_invalid`; missing duration is counted separately. |
| `dates_with_training_records` | Integer count | UTC dates with at least one retained training session. |
| `sessions_recorded` | Integer count | Total retained sessions across those training dates. |
| `usable_load_days` | Integer count | Recorded training dates with calculable total load. |
| `days_with_multiple_sessions` | Integer count | Recorded training dates with more than one session. |
| `days_with_incomplete_load` | Integer count | Recorded training dates with unknown total load because a session is unusable. |
| `load_p25` | Numeric, RPE-minutes | Personal 25th percentile of calculable recorded daily loads, using quantile type 7. |
| `load_median` | Numeric, RPE-minutes | Personal 50th percentile of calculable recorded daily loads. |
| `load_p75` | Numeric, RPE-minutes | Personal 75th percentile of calculable recorded daily loads; becomes the high-load threshold. |
| `training_dates` | Integer count | Calculable training dates represented at the given relative date in follow-up availability. |
| `readiness_available` | Integer count | Those training dates with observed readiness at the specified offset. |
| `heart_rate_available` | Integer count | Those training dates with observed heart rate at the specified offset. |
| `sleep_available` | Integer count | Those training dates with observed sleep at the specified offset. |
| `all_three_available` | Integer count | Those training dates with all three measurements at the specified offset. |
| `usable_training_dates` | Integer count | Calculable training dates assessed for complete +1 through +3 coverage. |
| `readiness_complete_windows` | Integer count | Complete readiness windows: +1 through +3 in `training_three_day_coverage.csv`, or -1 through +3 in `aim2_event_counts.csv`. |
| `heart_rate_complete_windows` | Integer count | Complete heart-rate windows, using the same file-specific date ranges. |
| `sleep_complete_windows` | Integer count | Complete sleep windows, using the same file-specific date ranges. |
| `all_metrics_complete_windows` | Integer count | Calculable training dates with all three measurements on +1 through +3 in the preliminary coverage summary. |
| `candidate_events` | Integer count | Eligible high-load dates at or above personal threshold. |
| `nonoverlapping_events` | Integer count | High-load candidates passing the four-day spacing rule, before requiring complete measurements. |
| `all_metrics_complete_post_windows` | Integer count | High-load candidates with all measurements on +1, +2, and +3. |
| `all_metrics_complete_five_day_windows` | Integer count | High-load candidates with all measurements on -1 through +3. |
| `nonoverlapping_complete_five_day_windows` | Integer count | Candidates meeting both five-date completeness and spacing rules; primary trajectory events. |
| `events_with_later_training_records` | Integer count | Events with any training report at +1 through +3, within the file's candidate or trajectory sample. |

### Prediction availability and preprocessing summaries

Sources: [sample audit](../R/19_audit_prediction_data.R), [feature specification](../R/20_make_prediction_features.R), and [preprocessing audit](../R/22_prepare_prediction_matrices.R).

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `observed_targets` | Integer count | Observed readiness dates in the participant-split or split before requiring readiness history. |
| `baseline_available` | Integer count | Observed target dates with an available earlier readiness score. |
| `hr_lag2_available` | Integer count | Observed target dates with heart rate at target date minus two days. |
| `sleep_lag2_available` | Integer count | Observed target dates with main-sleep duration at target date minus two days. |
| `baseline_and_wearables_available` | Integer count | Observed target dates with last readiness and both lagged absolute wearable values. |
| `participants_with_targets` | Integer count | Participants with at least one observed readiness target in the split. |
| `both_absolute_wearables_available` | Integer count | Retained prediction targets with both lagged absolute heart rate and sleep. |
| `both_personal_deviations_available` | Integer count | Retained targets with both lagged historical physiological deviations. |
| `feature` | Text | Predictor name in specification or numeric-preprocessing audit. |
| `type` | Text category | Declared predictor type, `categorical` or `numeric`. |
| `model_B` | Logical | Predictor is included in the absolute-feature ridge model. |
| `model_C` | Logical | Predictor is included in the personal-deviation ridge model. |
| `training_median` | Numeric, feature units | Finite training-value median used to impute that numeric feature. |
| `training_missing` | Integer count | Nonfinite values for the numeric feature before training imputation. |
| `validation_missing` | Integer count | Nonfinite values for the feature before validation imputation. |
| `training_rows` | Integer count | Target rows in the training design matrix. |
| `validation_rows` | Integer count | Target rows in the validation design matrix. |
| `predictor_columns` | Integer count | Numeric, missingness, and category columns in the model's design matrix. |
| `constant_training_columns` | Integer count | Matrix columns with zero training standard deviation before scaling. |
| `training_missing_after_processing` | Integer count | Nonfinite training matrix entries after imputation and scaling. |
| `validation_missing_after_processing` | Integer count | Nonfinite validation matrix entries after imputation and scaling. |

### Downloads and pipeline logs

Sources: [file inventory](../R/00_check_files.R), [training download](../R/13_download_training.R), and the three aim entry scripts. The original source-file manifest is `data/download_manifest.csv`; the training manifest is `data/training_download_manifest.csv`.

| Variable | Type and unit | Meaning |
| --- | --- | --- |
| `file` | Text path | Source filename relative to the participant folder in the original download manifest. |
| `source_url` | Text URL | Public source used for the file download. |
| `expected_bytes` | Integer, bytes | Expected source-file size recorded in the manifest or download script. |
| `bytes` | Integer, bytes | Observed local file size. |
| `sha256` | Text hash | SHA-256 checksum recorded for an original downloaded source file. |
| `md5` | Text hash | MD5 checksum of the validated local training file. |
| `records` | Integer count | Records reported for the downloaded or validated file. |
| `checked_at_utc` | UTC timestamp | Time of the local training-file validation check. |
| `script` | Text path | Analysis script executed by an aim pipeline. |
| `status` | Text category | Pipeline stage: `Completed` or `Failed`. Training download: `Existing` or `Downloaded` after validation, or `Failed`. The original source manifest uses its recorded download-status spelling. |
| `seconds` | Numeric, seconds | Elapsed execution time of the pipeline stage, rounded to two decimals. |
| `message` | Text | Pipeline error text on failure; empty string on success. |

## Analysis settings and saved model components

These names identify saved parameters or vectors rather than participant-level measurements.

| Name | Meaning |
| --- | --- |
| `hr_reference`, `sleep_reference` | Unweighted means of participant means used to center the Aim 1 between-person terms. |
| `study_start` | Earliest date in the full panel, used for both time variables. |
| `minimum_training_days` | Event eligibility requirement: 20 calculable recorded training dates. |
| `window_days`, `minimum_observations` | Predictive physiological baseline settings: 14 calendar dates and at least 5 finite observations. |
| `lambda_grid` | Thirteen candidate ridge penalties, `10^seq(-4, 2, by = 0.5)`. |
| `numeric_features`, `category_levels` | Saved names of numeric predictors and training-observed category levels for each ridge model. |
| `medians`, `centers`, `scales` | Training imputation values, raw-matrix column means, and scaling factors used for later transformations. |
| `x_train`, `x_validation`, `x_test` | Preprocessed predictor matrices. The test matrix is constructed during test evaluation. |
| `y_train`, `y_validation` | Unscaled observed target readiness vectors matching the training and validation matrix rows. |
| `intercept`, `coefficients` | Fitted ridge intercept and named slopes for standardized matrix columns. The intercept is the mean training outcome and is unpenalized. |
| `selected_baseline` | Baseline selected using pooled validation MAE, with last readiness preferred for exact ties. |

For the study questions and planned comparisons, see the [research proposal](research_proposal.md). For the observed findings, see the [report](report.md).
