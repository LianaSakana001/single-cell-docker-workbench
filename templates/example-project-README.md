# Single-cell analysis project

This directory was created once with `./workbench init-project`. Container
startup does not recreate or rewrite it.

## Directory contract

- `notebooks/`: interactive Python notebooks.
- `scripts/`: repeatable Python or R scripts.
- `config/`: project-level YAML, CSV, or other parameter files.
- `data/interim/`: reproducible intermediate data.
- `data/processed/`: project-level processed data, not unique raw input.
- `results/h5ad/`: AnnData outputs.
- `results/figures/`: figures.
- `results/tables/`: result tables.
- `logs/`: batch and resource-usage logs.
- `tmp/`: disposable project-local temporary files.

Raw inputs are available read-only under `/inputs`. Keep all notebooks, scripts,
intermediate data, and results that must survive container replacement inside
this project directory.

For large h5ad outputs, write to a new temporary filename, close the file,
validate it, and only then rename it to the final filename. Do not overwrite the
only valid copy of an analysis result.
