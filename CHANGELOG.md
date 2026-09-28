# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.2.0] - 2026-09-28

First public release. There is no v0.1.0; versioning starts at v0.2.0 by
project decision and this release folds in everything built and verified
so far.

Verification status for each feature is recorded in [docs/verification.md](docs/verification.md).

### Added
- Offline preview for six synthetic instrument formats, with quick-look figures
  and no server connection.
- Draft session logging that records structured measurement and provenance
  metadata, attaches permitted raw files and quick-look figures, and links
  matching Instrument and Sample items.
- Instrument-usage ledger updates, consumable-inventory updates, standard-sample
  QC checks, and monthly usage reports with CSV and chart attachments.
- Item bootstrap from facility-maintained CSV files, including configured
  resource categories and native resource statuses.
- Configurable raw-file attachment, retention, and reconstruction-sidecar
  handling for logged sessions.
- A staged-ingest API and an executable custom-ingest example for facilities
  that need to assemble their own workflow.
- Folder-based ingestion for NMR: a Bruker experiment folder is recorded as one measurement unit and identified by a manifest of per-file hashes.
  The acquisition time and duration are read from the folder (the duration is labelled as calculated), and the original folder is not modified or attached.
- An NMR quick-look figure and a `provenance.json` file (tool version, processing steps, and input hashes, without timestamps, user names, or paths),
  produced with a pinned, unmodified copy of AnyNMR-matlab under `src/third_party/`. A processing failure does not stop the record.
- A guide for adding a single-file or folder-based instrument format (`docs/adding_a_format.md`).
- Docker settings for running a second, separate eLabFTW server (for demonstrations) next to a development server without sharing its data, and a guide for it in `docs/elabftw_setup.md`.
- Demo structure bootstrap, deterministic synthetic inputs, and a dedicated
  demonstration entry script with a target guard and per-file progress output.
- An unofficial-project notice at the top of the README, since the public repository name starts with "Elabftw".
- A README data policy and no-server-changes statement, plus contributor guidance
  for keeping real data and personal information out of issues and pull requests.

### Changed
- Session experiments and monthly reports use the acquisition date when it is
  available, rather than treating registration time as the measurement date.
- Session metadata is organized into Measurement, Instrument parameters, and
  Provenance groups with stable field ordering.
- Resource category names, status labels, attachment limits, list limits, and
  retention behavior are configured instead of being fixed in code.
- Generated figures use a light appearance and preserve data-derived text such
  as underscores literally.
- Instrument and Sample bindings are now separate layers: `instrument_map.csv` binds files to an individual Instrument and `sample_map.csv` binds a
  measurement to a Sample. A legacy `sample_map.csv` with an `instrument_title` column is accepted with a warning.
- The session schema version is now `1.2`. It adds the optional fields `data_unit`, `anynmr_version`, and `provenance_file`, and `run_minutes_source` can be `calculated`.

### Fixed
- Duplicate detection is scoped to the appropriate Session or QC category, so a
  record in one category does not suppress a record in the other.
- Item searches stop at their configured candidate limit instead of creating a
  possible duplicate after an incomplete search.
- Monthly reports warn when their configured session-list limit may make the
  result incomplete.
- Archived files use collision-safe names, preventing an existing raw file or
  sidecar from being overwritten.

---
