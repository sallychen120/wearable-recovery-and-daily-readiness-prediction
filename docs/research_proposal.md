# Personal physiological baselines and daily exercise readiness

## Research question

People differ in their usual resting heart rate and sleep duration. A measurement becomes easier to interpret when it is compared with that person's own history. This study will examine whether deviations from personal physiological baselines are associated with daily readiness to exercise, describe changes around higher training loads, and test whether historical deviations improve readiness prediction.

The study will connect an interpretable analysis of daily variation with a chronological prediction task. The association analysis will distinguish changes within a person from differences between people. The prediction analysis will then assess the information available from past observations.

## Data and study design

The project will use [PMData](https://datasets.simula.no/pmdata/), a public sports logging dataset containing repeated observations from 16 participants over approximately five months. The original data are available through [OSF](https://osf.io/vx4bk/). The design is an exploratory observational study, with participant-days as the unit of analysis for Aims 1 and 3 and training events as the unit for Aim 2.

| Source file | Measurements | Role |
| --- | --- | --- |
| `pmsys/wellness.csv` | Readiness to exercise, questionnaire time, fatigue, and self-reported sleep duration | Readiness, scored from 0 to 10, will be the outcome. The other fields will support record review. |
| `fitbit/resting_heart_rate.json` | Daily resting heart rate | Physiological exposure and historical predictor, in beats per minute. |
| `fitbit/sleep.json` | Minutes asleep, main-sleep flag, sleep dates and timestamps | Main-sleep duration, converted to hours, and checks on date alignment. |
| `pmsys/srpe.csv` | Session end time, perceived exertion, duration, and activity | Training load, calculated as session RPE multiplied by duration in minutes. |

Participants will enter the daily panel when wellness, resting-heart-rate, and sleep files are available. Each panel will contain a continuous calendar so that lagged features correspond to calendar days. Exact duplicate wearable records will be removed, and nonpositive heart-rate measurements will be set to missing. The earliest wellness report on each UTC date and the Fitbit main-sleep record will define the daily measurements. Zero readiness scores will be retained as valid responses.

Questionnaire and training timestamps will be parsed as UTC. Fitbit sleep records will retain their source date labels because their time zone has not been verified. Analyses will therefore use source dates; the prediction design will place wearable measurements two source dates before the target.

## Aim 1 Personal deviations and daily readiness

This aim will estimate how resting heart rate and sleep relative to a person's usual levels are associated with readiness on the same source date.

For each participant, the mean resting heart rate and mean sleep duration will be calculated from all available valid observations. Daily deviations will equal the observed value minus that person's mean. A random-intercept linear mixed model will include both deviations, both person means centered across participants, and a linear study-time term:

```r
readiness ~ hr_deviation + sleep_deviation +
  hr_person_mean_c + sleep_person_mean_c +
  study_day_30 + (1 | participant_id)
```

The model will be fitted by restricted maximum likelihood. Independent and AR(1) residual structures will be compared, with AR(1) distances based on actual calendar days. Participant-clustered CR2 standard errors and Satterthwaite degrees of freedom will provide 95% confidence intervals. Results will be expressed per 5 bpm above personal mean heart rate and per additional hour above personal mean sleep.

This aim will use complete cases. Sensitivity analyses will exclude participant `p05`, whose readiness reporting pattern prompted review, and replace the earliest daily readiness report with the latest while retaining the same analysis dates and predictors.

## Aim 2 Changes around higher training loads

This aim will describe readiness, heart rate, and sleep around training days with a higher load relative to the participant's own recorded training.

Session loads will be summed within each participant and UTC session-end date. A day's total will be unknown if any reported session has unusable load information. Dates without training reports will also have unknown load. Participants with at least 20 calculable training dates will be eligible. A load at or above the person's 75th percentile of recorded daily loads will define a candidate event.

The event window will cover source dates -1 through +3. The primary sample will require all three measurements on all five dates and no other high-load candidate within four calendar days of the event. Each measurement will be expressed as a change from the event's preceding date. Event changes will be averaged within participants, followed by an equal-participant mean.

This aim will use descriptive event trajectories. A broader sample allowing adjacent high-load events and a leave-one-participant-out analysis will assess how the trajectories depend on event selection and participant composition.

## Aim 3 Prediction from historical observations

This aim will test whether personal physiological deviations add predictive information for future readiness among previously observed participants.

The common calendar will be divided chronologically into approximately 60% training, 20% validation, and 20% test periods before filtering target observations. Questionnaire history will end before target date `d`; wearable values will come from `d-2`. Their personal baselines will use the preceding 14 calendar dates, `d-16` through `d-3`, with at least five valid observations per measurement.

| Method | Inputs |
| --- | --- |
| Last-readiness baseline | Most recent observed readiness before the target date. |
| Historical-mean baseline | Mean of all observed readiness scores before the target date. |
| Model B, absolute features | Participant, weekday, readiness history, time since the last readiness report, and lagged absolute heart rate and sleep. |
| Model C, personal deviations | All Model B inputs plus lagged heart-rate and sleep deviations from historical personal baselines. |

Models B and C will use ridge regression. Numeric predictors will receive training-median imputation and missingness indicators. Participant and weekday will use full indicator coding; all matrix columns will be centered and scaled using training data. The ridge penalty will be chosen by pooled validation MAE from `10^seq(-4, 2, by = 0.5)`, with the larger penalty preferred for exact ties.

Both simple baselines will be reported, and the one with lower validation MAE will serve as the fixed reference. Test evaluation will retain the original training coefficients and preprocessing parameters while allowing earlier observations to update later histories. Predictions will be bounded to 0 through 10. Pooled MAE will be the primary metric, with RMSE and equal-participant macro MAE as secondary summaries. Model C versus Model B will measure the incremental contribution of personal physiological deviations.

## Outputs

All analyses will use R. The repository will contain the analysis scripts, variable codebook, model and sample summaries, figures, and a short research report. Original participant files and generated analysis datasets will remain local, with data-access instructions provided in the repository.

## Reference

Thambawita et al. (2020). *PMData: A Sports Logging Dataset*. Proceedings of MMSys 2020. [Publication](https://doi.org/10.1145/3339825.3394926).
