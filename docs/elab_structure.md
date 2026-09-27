# eLabFTW Structure for a Shared Facility

This document describes the eLabFTW structure assumed by the kit: the setup
steps in the eLabFTW interface and the field lists. Create the following
categories and statuses before MATLAB writes records. All displayed names are
configuration values; the tables use the shipped English defaults. Keep each
configured name exactly the same in eLabFTW and in the local settings file
because lookups use exact title matches.

## NMR provenance fields

For processed NMR folders, provenance group 3 adds `anynmr_version` and `provenance_file` after `quicklook_profile`.
Both fields are optional and appear only when an NMR preview was created.
New records use schema version `1.2`.

The interface and API notes below apply to eLabFTW 5.6.12. Names and routes can
vary between server versions, so inspect the server's API documentation when a
route behaves differently.

## 0. Interface and API mapping (eLabFTW 5.6.12)

The category and status controls are in the top navigation drop-downs, not in
the Admin panel. The Admin panel tabs are TEAM, USER GROUPS, USERS, EXPORT, TAG
MANAGER, and BATCH ACTIONS; category controls are not located there.

| Object | Interface | URL | API endpoint |
|---|---|---|---|
| Experiment category | **Experiments** > *Experiment categories* | `/experiments-categories.php` | `/teams/current/experiments_categories` |
| Experiment status | **Experiments** > *Experiment status* | `/experiments-status.php` | `/teams/current/experiments_status` |
| Resource category | **Resources** > *Resource categories* | `/resources-categories.php` | `/teams/current/resources_categories` |
| Resource status | **Resources** > *Resource status* | `/resources-status.php` | `/teams/current/items_status` |

The interface calls the resource categories singular, while the API endpoint is
`resources_categories`. `items_types` is the Resource templates endpoint, not a
resource-category endpoint.

An `extra_fields` template is not required for API writes. `setExtraFields` can
write and read back values for an entry without a template or category. Templates
make human data entry and review more consistent, so create them before routine
use even though a trial only needs the category names.

Create categories and the `Draft` experiment status manually, or call
`elab.pipeline.bootstrapStructure` to create the configured categories and
status when missing. Resource statuses are created on demand from the configured
labels when the bootstrap, session, or QC workflows run.

## 1. Resource categories

Create these four resource categories. The listed extra fields are a practical
screen template; the API can write extra fields without a template.

Their configuration keys are `elab.instrument_category`,
`elab.sample_category`, `elab.consumable_category`, and `elab.sop_category`.

| Category | Extra fields |
|---|---|
| `Instrument` | `model` (text), `serial` (text), `location` (text), `manager` (text), `install_date` (date), `calibration_due` (date), `usage_minutes_total` (number), `usage_hours_total` (number), `last_used` (datetime-local), `days_to_calibration` (number), `hourly_rate` (number) |
| `Sample` | `sample_id` (text), `owner` (text), `lab` (text), `form` (select: Powder, Film, Solution, Bulk), `prepared_date` (date), `status` (select: Available, Consumed, Disposed), `storage_location` (text) |
| `Consumable` | `name` (text), `lot` (text), `quantity` (number), `unit` (text), `reorder_threshold` (number), `supplier` (text), `catalog_no` (text) |
| `SOP` | `version` (text), `applies_to` (text: instrument name), `approved_by` (text), `approved_on` (date) |

`bootstrapItems` initializes a new Instrument with `model`, `location`,
`calibration_due`, `usage_minutes_total`, `usage_hours_total`, `last_used`, and
`days_to_calibration`. It initializes a new Consumable with `quantity`,
`reorder_threshold`, and `unit`. Existing items are not reseeded.

`usage_minutes_total` is the accumulated value. The ledger recalculates
`usage_hours_total` as `round(usage_minutes_total / 60, 2)`.

Resource state is the native resource status, not an `extra_fields.status`
value. The status label configuration keys and their fixed colors are:

| Configuration key | Default title | Color |
|---|---|---|
| `elab.labels.instrument_status_ok` | `OK` | `28a745` |
| `elab.labels.instrument_status_check` | `Check` | `ffc107` |
| `elab.labels.instrument_status_calibration_overdue` | `CalibrationOverdue` | `dc3545` |
| `elab.labels.consumable_status_ok` | `InStock` | `28a745` |
| `elab.labels.consumable_status_reorder` | `Reorder` | `fd7e14` |

`bootstrapItems` creates missing definitions and assigns configured OK or
InStock statuses to new items. Existing custom `status` extra fields are left in
place but ignored. An existing item with no native status receives its current
OK, overdue, InStock, or Reorder status on the next ledger or inventory update;
an existing native status is never overwritten.

The fixed colors express state meaning rather than a local display preference.
Only the displayed titles are configured, allowing a facility to choose its own
language while keeping a stable state model.

## 2. Experiment categories and templates

The configuration keys for experiment categories are
`elab.session_category`, `elab.qc_category`, and `elab.report_category`; their
default values are `Session`, `QC`, and `Report`. The default group labels come
from `elab.labels.field_group_measurement`,
`elab.labels.field_group_instrument_params`, and
`elab.labels.field_group_provenance`.

| Category | Purpose | Extra-field groups and order |
|---|---|---|
| `Session` | One instrument data unit recorded by `watchAndLog` | **Measurement (1):** `sample_id`, `instrument_title`, `operator`, `project`, `acquired_at`, `acquired_at_source`, `timezone`, `run_minutes`, `run_minutes_source`, when present. **Instrument parameters (2):** remaining parser header fields in parser order. **Provenance (3):** `data_file_name`, `data_file_hash`, `data_unit`, `source_path`, `source_host`, `source_mtime`, `logged_at`, `schema_version`, `kit_version`, `kit_commit`, `matlab_version`, `parser`, `quicklook_profile`, plus optional `anynmr_version` and `provenance_file` when an NMR preview was created. |
| `QC` | One standard-sample decision recorded by `qcCheck` | **Measurement (1):** parsed `sample_id`, `instrument_title`, parsed `operator` and `project`, `acquired_at` when available, `acquired_at_source`, `metric`, `measured`, `target`, `deviation`, `tolerance`, `qc_result`, `qc_pass`. **Instrument parameters (2):** remaining parser header fields. **Provenance (3):** `data_file_name`, `data_file_hash`, `kit_version`, `kit_commit`, `matlab_version`, `parser`, `quicklook_profile`. |
| `Report` | A monthly usage report | **Provenance (3):** `kit_version`, `matlab_version`, `report_period`. The body contains summary tables and the chart; attachments contain the CSV and chart image. |

`data_unit` is `file` for a single-file record and `folder` when one record covers a
multi-file measurement folder; it tells a reader whether `data_file_hash` is the hash of
a file or of a folder manifest.

New Session records use `schema_version` `1.2`. QC records do not add Session context
fields such as `data_unit` or `schema_version`.

The pipeline writes all new experiments with the configured `elab.draft_status`
value. A person reviews and signs the entry in eLabFTW when appropriate. For an
instrument-specific template, use instrument-specific fields such as anode,
voltage, and current for XRD, or nucleus, frequency, solvent, and scans for NMR.
The shared template can initially retain all parser header fields instead.

Create experiment templates through **Experiments** > *Experiment templates*
at `/templates.php`. Names are exact-match configuration values, so copy the
configured category text rather than retyping a visually similar punctuation
character.

An optional `Maintenance` category can use `severity` (select), `symptom`,
`action_taken`, `down_from` (datetime-local), and `restored_at` (datetime-local)
for manual incident records.

## 3. Tags

- Project code, such as `PRJ-A`
- Laboratory or instrument abbreviation, such as `XRD-01`
- Technique abbreviation, such as `XRD`, `NMR`, or `LCMS`

`watchAndLog` automatically tags a Session with the matched map's `project` and
`instrument_title` values and its technique abbreviation.

## 4. API keys

Keep the API key in the environment variable named by `elab.api_key_env`, or in
the ignored local `config/apiKey.txt` file. Use a read/write key restricted to
the instrument and facility team, preferably for a dedicated service account,
for automatic recording. Use a read-only key for report-only work where the
server permissions allow it.

## 5. Idempotency key

Every Session template must contain `data_file_hash` as a text field.
`watchAndLog` writes the raw-file SHA-256 there and searches the configured
Session category before creating another record.

## 6. Master data (`data/list/`)

Copy the example files in `data/list` before use.

| File | Required columns | Purpose |
|---|---|---|
| `instrument_map.csv` | `match_substring`, `instrument_id` | Selects one stable Instrument ID from a case-insensitive relative unit-name substring |
| `sample_map.csv` | `match_substring`, `sample_id` | Selects a measurement-specific Sample ID; optional columns are `operator`, `project`, `consumable_title`, and `consumable_qty` |
| `instruments.csv` | `title`, `model`, `location`, `calibration_due` | Seeds Instrument records; `title` is an individual asset ID and `model` is the model name |
| `consumables.csv` | `title`, `quantity`, `reorder_threshold`, `unit` | Seeds Consumable records |
| `qc_specs.csv` | `match_substring`, `instrument_title`, `metric`, `target`, `tolerance` | Selects a standard-sample acceptance rule from a case-insensitive filename substring |

`instruments.csv:item_type`, `instrument_map.csv:instrument_type`, and
`qc_specs.csv:instrument_type` are optional compatibility columns. If present,
their values must exactly equal `elab.instrument_category`; a mismatch stops the
workflow before it creates or processes entries.

The distributed `*.example.csv` files are starting points. Copy them to the
corresponding `.csv` filenames and adapt the rows for the facility before the
first bootstrap or ingest run.

## 7. Human review

MATLAB creates entries as `Draft`; a person reviews the content and can sign the
entry with eLabFTW's `action: sign`. Create `Draft` under **Experiments** >
*Experiment status*, or use `elab.pipeline.bootstrapStructure`; the initial statuses are `Running`,
`Success`, `Need to be redone`, and `Fail`. If the configured status is absent,
`createExperiment` warns and leaves the server default in place rather than
stopping the workflow.
