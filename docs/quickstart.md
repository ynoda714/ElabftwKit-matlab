# Quick Start

This guide takes you from a new checkout to an offline preview or a complete
eLabFTW logging run.

## Prerequisites

- MATLAB R2022a or later. No add-ons are required.
- Python is not required.
- A reachable eLabFTW instance. For the local Docker environment, follow
  [Local eLabFTW setup](elabftw_setup.md). It uses self-signed HTTPS at
  `https://localhost:3148`.
- A Read/Write API key. Store it either in the environment variable named by
  `elab.api_key_env` (`ELAB_API_KEY` by default) or as the only line in
  `config/apiKey.txt`. Neither location is tracked by Git.

## Setup

1. Start eLabFTW. For the repository's local environment, follow
   [Local eLabFTW setup](elabftw_setup.md).
2. Create the experiment categories, experiment statuses, resource categories,
   and templates described in [eLabFTW structure](elab_structure.md). Every name
   must match the corresponding configuration value exactly, character for
   character. Do not pre-create Resource statuses: Section 1 creates the five
   configured definitions and their colors when they are missing.
   `elab.pipeline.bootstrapStructure` can create the configured categories and
   Draft experiment status before this item bootstrap; the setup details remain
   in [eLabFTW structure](elab_structure.md).
   Resource-category names are `elab.instrument_category`, `sample_category`,
   `consumable_category`, and `sop_category`.
3. From the project root, copy the configuration and all four master-data
   examples:

   ```powershell
   Copy-Item config\settings.example.json config\settings.json
   Copy-Item data\list\instruments.example.csv data\list\instruments.csv
   Copy-Item data\list\consumables.example.csv data\list\consumables.csv
   Copy-Item data\list\instrument_map.example.csv data\list\instrument_map.csv
   Copy-Item data\list\sample_map.example.csv data\list\sample_map.csv
   Copy-Item data\list\qc_specs.example.csv data\list\qc_specs.csv
   ```

Section 0b copies `instrument_map.example.csv` to `instrument_map.csv`, `sample_map.example.csv` to `sample_map.csv`, and
   `qc_specs.example.csv` to `qc_specs.csv` only when the destination is
   missing. It does not copy the instruments or consumables lists.
4. Edit `config/settings.json` to match your server. Set `elab.base_url`,
   `elab.ca_cert` (use `docker/certs/server.crt` for the local environment),
   the category names, and every value under `elab.labels.*`. Store the API
   key as described under Prerequisites, never in `settings.json`.

   The ingestion controls have these defaults:

   | Setting | Default | Effect |
   |---|---:|---|
   | `elab.timezone` | `""` | Record the execution environment's IANA timezone; set it explicitly when needed. |
   | `elab.instrument_category` | `"Instrument"` | Resource category for instruments. |
   | `elab.sample_category` | `"Sample"` | Resource category for samples. |
   | `elab.consumable_category` | `"Consumable"` | Resource category for consumables. |
   | `elab.sop_category` | `"SOP"` | Resource category for SOPs. |
   | `elab.item_search_limit` | `50` | Positive-integer candidate limit for `ensureItem`. At the limit, a missing exact match stops before a duplicate item is created. |
   | `elab.report_list_limit` | `1000` | Positive-integer session-list limit for reports. At the limit, the report is created with a Notes warning. |
   | `ingest.attach_raw` | `"auto"` | Attach raw files only when they are at or below the size limit. `always` and `never` override this. |
   | `ingest.attach_raw_max_mb` | `25` | Raw-file attachment limit for `auto`. Over-limit files are recorded without raw attachment. |
   | `ingest.archive_mode` | `"move"` | Move handled files; `copy` keeps the inbox original, and `leave` changes no input file. |

## Try it without a server

Run the offline quick-look script from the project root:

```matlab
addpath(genpath("src"));
run("scripts/quick_look.m")
```

It creates six mock instrument files, parses them, and writes preview figures
under `result/runs/<timestamp>_quicklook/`. It makes no API calls.

## Run the full loop

Open `main_elabftw.m` and set the MATLAB current folder to the project root.
Edit the four options in Section 0a if needed:

| Option | Default | Meaning |
|---|---:|---|
| `opt.generateMock` | `true` | Write the six deterministic mock files in Section 2. |
| `opt.doBootstrap` | `true` | Create missing Instrument and Consumable items in Section 1. |
| `opt.reportYear` | Current year | Select the report year used by Section 4. |
| `opt.reportMonth` | Current month | Select the report month used by Section 4. |

Starting with Section 0b, press Ctrl+Enter to run one section at a time. You
can instead press F5 to run every section once, in file order.

## Sections

| Section | What it does | Effects in eLabFTW and on files |
|---|---|---|
| Section 0a | Defines the four user options. | Changes no files and makes no API calls. |
| Section 0b | Adds `src/` to the path, resolves the project root, loads configuration and the API key, prepares missing list files, and constructs the client. | May copy the `instrument_map.csv`, `sample_map.csv`, and `qc_specs.csv` examples; it creates no eLabFTW entry. |
| Section 1 | Bootstraps items when `opt.doBootstrap` is `true`. | Creates the five native Resource statuses, then creates Instrument and Consumable items from their CSV lists and assigns colored OK/InStock status to new items; existing same-title items are left unchanged. Missing lists produce warnings and are skipped. |
| Section 2 | Generates mock runs when `opt.generateMock` is `true`. | Writes deterministic XRD, Raman, FTIR, NMR, LC-MS, and SEM files to `data/inbox/`, acquired at 40-minute intervals from 09:00 today. The NMR file is a synthetic text spectrum, not a Bruker experiment folder. |
| Section 3 | Processes the measurement inbox. | Creates Draft session experiments, conditionally uploads raw files, always uploads quick-look figures, links matching items, updates the ledger and inventory, applies the configured retention policy, and writes an `.elab.json` sidecar. |
| Section 4 | Builds the report for `opt.reportYear` and `opt.reportMonth`. | Selects sessions by acquisition date and creates one Report experiment and its CSV and chart outputs every time the section runs. |
| Section 5 | Checks standard-sample files in `data/qc_inbox/` against `qc_specs.csv`. | Creates Draft QC experiments for matched files; files without an acceptance rule remain in the inbox. |

## What to expect

- Section 1 reads `data/list/instruments.csv` and
  `data/list/consumables.csv`. It creates Instrument and Consumable items but
  does not overwrite an existing item with the same title. If either file is
  absent, it logs a warning and skips that list. The five Resource statuses need
  no manual setup. They appear as colored markers in the Resources list, where
  they can also be used for filtering. Existing items keep any legacy custom
  `status` value. If their native status is empty, the next ledger or inventory
  update assigns the current OK/overdue or InStock/Reorder state. An existing
  native status is not overwritten.
- Section 2 writes six files for XRD, Raman, FTIR, NMR, LC-MS, and SEM to
  `data/inbox/`. Their acquisition times start at 09:00 today and advance by
  40 minutes. Their contents are identical for repeated generation on the same
  day; generating on another day changes the contents and records new measurements.
  The NMR file is a synthetic text spectrum, not a Bruker experiment folder.
- The first Section 3 run creates six Draft measurement-session experiments.
  Each receives a quick-look figure, and raw files no larger than 25 MB are
  attached under the default `auto` policy. The quick-look appears
  in the body of each experiment. Its custom fields are headed Measurement,
  Instrument parameters, and Provenance; the first group puts the session summary
  first, while Provenance identifies the kit, MATLAB, parser, and preview settings.
`instrument_map.csv` binds a stable file pattern to an individual Instrument, while
`sample_map.csv` binds a measurement pattern to a Sample. Use distinct substrings
such as a device-specific prefix or folder name when two instruments use one technique.
A record may have either binding: an Instrument-only record updates its ledger, and a
Sample-only record does not. Ambiguous matches are not linked. A legacy sample map
with `instrument_title` is accepted with a warning while it is migrated. Processed files move
  to `data/processed/` by default, and a reconstruction sidecar is written beside
  each moved file. Existing names are never overwritten; collisions receive a
  timestamp suffix. `copy` retains the inbox original, while `leave` writes the
  sidecar under the run directory and changes no input file. Reintroducing the same file produces `skipped` because
  its `data_file_hash` already exists within the measurement-session category.
  A QC experiment with the same hash does not cause a measurement session to be
  skipped. Consequently, running Section 2 and then Section 3 a second time skips
  all six deterministic mock files that Section 3 recorded on its first run.
- Section 4 aggregates measurement sessions whose acquisition dates fall in the
  selected month and creates a Report experiment. Its body shows a period and
  totals summary, a stacked instrument-time chart, readable instrument/project/
  operator tables, and notes that explain estimated values. It does not search
  for an existing report, so every run creates one more Report experiment.
  Pressing F5 twice therefore creates two reports for the selected month.
- Section 5 evaluates files in `data/qc_inbox/` using `qc_specs.csv` and creates
  Draft experiments in the QC category. Files with no matching rule remain in
  the inbox. A file is `skipped` only when an experiment within the QC category
  already has the same `data_file_hash`. A deterministic mock file already
  recorded by Section 3 therefore still creates one QC experiment when placed in
  `data/qc_inbox/`; submitting that same standard-sample file to Section 5 again
  is then skipped.

### Running it again

Reintroducing the same file keeps one experiment in the same category.
Because a skipped file does not reach the ledger or inventory steps, its usage and consumption are not applied twice.
Run only one copy of this workflow at a time: do not use two MATLAB sessions, two computers, or overlapping scheduled runs.
Concurrent runs can both pass the duplicate check, create duplicate experiments, and lose a ledger or inventory update.
Restarting an interrupted run is also outside this guarantee because the result depends on where execution stopped; recovery is planned for a later version.
Mock data generated on another day has a different acquisition time and is recorded as a new measurement.
Section 4 is intentionally different: every run creates one more Report experiment.

All MATLAB-generated eLabFTW entries are Drafts for human review.

## Log an NMR experiment folder

Place one Bruker one-dimensional experiment folder under `data/inbox/`. The folder
itself is one measurement and must contain `acqus` plus `fid`. Folders with `ser`
contain two-dimensional data, which is unsupported and moved to `data/failed/`.

To create a synthetic folder for an offline trial, run:

```matlab
addpath(genpath("src"));
folderPath = elab.io.writeMockNmrRun("data/inbox");
```

This example creates synthetic data only; it neither uses nor distributes real
experiment data.

For an eligible folder, the record uses the acquisition time from `##$DATE` and
records a duration calculated from the acquisition settings with source
`calculated` when a single valid audit duration is unavailable. It records a hash
for the complete folder without changing the original, a quick-look figure, and a
`provenance.json` file containing the AnyNMR version and processing conditions.
The provenance file omits timestamps, user names, and paths. The folder itself is
not attached; its source location and hash are recorded instead.

If AnyNMR processing fails, the record continues with a warning but without a
preview or `provenance.json`. Use the existing `instrument_map.csv` and
`sample_map.csv` guidance in [What to expect](#what-to-expect) to bind an
Instrument and Sample. Writing NMR records to a live server was checked with real
experiment folders ([Verification Record](verification.md#nmr-folders-live)); connecting a
real instrument has not been checked. See [Platform Support](platform_support.md) for
the MATLAB releases and platforms that were run.

## Call the API directly

This example follows the same API-key lookup order as `main_elabftw.m` and
passes both TLS settings from the configuration:

```matlab
addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));
cfg = loadConfig();

apiKey = string(getenv(cfg.elab.api_key_env));
if apiKey == ""
    keyFile = fullfile("config", "apiKey.txt");
    if isfile(keyFile)
        apiKey = strtrim(string(fileread(keyFile)));
    else
        error("elab:main:apiKeyMissing", ...
            "No API key. Set env var %s or create config/apiKey.txt.", ...
            cfg.elab.api_key_env);
    end
end

client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);
info = client.getJson("/info")
```

## Run the tests

The unit and offline smoke tests run as one suite:

```matlab
addpath(genpath("src"));
suite = [testsuite("tests/unit"), testsuite("tests/smoke")];
runner = matlab.unittest.TestRunner.withNoPlugins;
results = runner.run(suite);
fprintf("RESULT: %d PASS / %d FAIL / %d Total\n", ...
    sum([results.Passed]), sum([results.Failed]), numel(results));
```

## Troubleshooting

**`elab:main:apiKeyMissing`**

Set the environment variable named by `elab.api_key_env`, or put the key on
one line in `config/apiKey.txt`.

**`elab:client:resolveId:notFound`**

The configured category or resource-category name must exactly match eLabFTW.
Copy the name rather than retyping it. For example, the Japanese name
`QC・校正` contains U+30FB KATAKANA MIDDLE DOT, not another middle-dot
character. See [eLabFTW structure](elab_structure.md).

**`MATLAB:webservices:SSLConnectionSystemFailure` or `SEC_E_UNTRUSTED_ROOT`**

Set `elab.ca_cert` to the issuing certificate file. For the local environment,
use `docker/certs/server.crt`. `elab.allow_self_signed` only disables host-name
verification; it does not disable certificate-chain verification and does not
solve an untrusted-root error by itself.

**An API operation returns an HTTP error**

Compare the live Swagger documentation at `<base_url>/api/v2/` with the routes
in `src/+elab/+client/Client.m`; eLabFTW API routes can vary by server version.

**Where are the generated files?**

Run artifacts are under `result/runs/`, in timestamped directories.

## Log format

Normal output uses the repository logging helpers. A run looks like this:

```text
[HH:MM:SS][INFO]  --- MAIN | Section 3: Watch and log  [eLabFTW] ---
[HH:MM:SS][INFO]  watchAndLog: 6 file(s)
[HH:MM:SS][INFO]    [logged] xrd_SMP-2026-001.xy  https://localhost:3148/experiments.php?mode=view&id=12
[HH:MM:SS][WARN]  consumeInventory: 'X' has no numeric 'quantity' extra field; skipping.
```
