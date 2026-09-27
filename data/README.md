# Data Directory

This directory contains input data for the project.

## Structure

```
data/
├─ inbox/         # Normal instrument-file inbox
├─ qc_inbox/      # QC standard-sample inbox
├─ list/          # Input lists, registries, master data
└─ README.md      # This file
```

## For Users

Place your input data files in the appropriate subdirectory.
See [docs/quickstart.md](../docs/quickstart.md) for data format requirements.
Place normal instrument output files in `data/inbox/`. Place standard-sample
files in `data/qc_inbox/`; `elab.pipeline.qcInbox` creates QC experiments from
them. Both inboxes exclude dotfiles, the exact names `Thumbs.db` and
`desktop.ini` case-insensitively, and names ending in `_meta.txt`.

Copy `data/list/qc_specs.example.csv` to `data/list/qc_specs.csv` and edit its
rows for the facility. Each row maps a filename substring to an instrument,
metric, target, and tolerance. The operational CSV is user-specific and is not
tracked by Git.

Copy `data/list/instrument_map.example.csv` to `data/list/instrument_map.csv` and
copy `data/list/sample_map.example.csv` to `data/list/sample_map.csv`. The first
maps a stable unit-name substring to an individual Instrument ID. The second maps
a measurement-specific substring to a Sample ID and optional operator, project, or
consumable values.

## Example Data

The records in `data/list/*.example.csv` and the mock measurement files generated
by `elab.io.writeMockRuns` are entirely fictional. Instrument names use real
product names for illustration, but the examples do not represent the equipment,
users, samples, projects, or inventory of any specific facility.

Real instrument data is neither committed nor distributed; keep it in the ignored
inbox directories. Every input example in this repository is synthetic. Generate
a synthetic NMR experiment folder with `elab.io.writeMockNmrRun`.

## Git Policy

- `data/list/` — Tracked (small managed files: CSVs, registries)
- Large binary files and external datasets — Not tracked (add to `.gitignore`)
- Use `.gitkeep` to preserve empty directory structure
