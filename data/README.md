# PMData access and local file layout

Download PMData from the [official Simula dataset page](https://datasets.simula.no/pmdata/) or its [OSF repository](https://osf.io/vx4bk/). Follow the original creators' published use and attribution terms.

## Required files

Extract the participant folders into `data/raw/` so the paths below are relative to the RStudio project root:

```text
data/raw/
├── p01/
│   ├── fitbit/
│   │   ├── resting_heart_rate.json
│   │   └── sleep.json
│   └── pmsys/
│       ├── wellness.csv
│       └── srpe.csv
├── p02/
└── ...
```

Aim 1 checks participant IDs `p01` through `p16` and imports those with all three required streams: `wellness.csv`, `resting_heart_rate.json`, and `sleep.json`. Preserve the source participant IDs and filenames. Some source participants may lack a required stream; the pipeline records file availability in `results/file_inventory.csv`.

Aim 2 uses `pmsys/srpe.csv` for the selected participants. `R/13_download_training.R` downloads missing training files from the public OSF URLs defined in that script and checks their sizes and required columns.

The existing [download manifest](download_manifest.csv) records source URLs, sizes, and checksums for a subset of the source files. Use the official dataset archive for the complete source collection. The [training manifest](training_download_manifest.csv) records the training-file checks from the local analysis.

## Generated files

The analysis writes intermediate objects to `data/intermediate/` and prediction features to `data/processed/`. Run the pipelines from the project root to regenerate these files after obtaining the source data.

The repository's `.gitignore` excludes `data/raw/`, `data/intermediate/`, `data/processed/`, and serialized R objects. These files remain available locally when the project is uploaded using Git or GitHub Desktop.
