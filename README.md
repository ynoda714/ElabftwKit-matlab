# eLabFTW x MATLAB Facility Logging Kit

> **This is an unofficial, community-maintained project.** It is not affiliated with, endorsed by, or
> supported by Deltablot, the developer of eLabFTW. "eLabFTW" is a registered trademark of Deltablot.

[Japanese README](docs/ja/README.ja.md)

This kit turns instrument-output files into structured eLabFTW records for
shared instrument facilities and university laboratories. MATLAB reads a
measurement file, creates a Draft record, attaches the source file and a
quick-look figure, and can update facility records such as usage and inventory.

## What this is, and what it is not

- **A set of parts, not a finished product.** The kit shows how instrument output files can become structured eLabFTW records, with a usage ledger,
  a consumable inventory, and a monthly report built on those records. Most of it has been checked with synthetic files only; see
  [What has been checked](#what-has-been-checked).
- **NMR is the deepest part.** A Bruker experiment folder is recorded as one measurement unit, with a hash for each file, the acquisition time read from
  the data, a quick-look figure, and a provenance record produced with a pinned, unmodified copy of an open-source NMR processing library
  (see [Third-Party Notices](THIRD_PARTY_NOTICES.md) and [Platform Support](docs/platform_support.md)). This was checked with real experiment
  files, including against a live server. It has not been checked with a connected instrument.
- **The other readers are examples.** The XRD, Raman, FTIR, LC-MS, and SEM readers handle simple layouts defined by this kit for demonstration,
  not the native formats of any instrument. To adapt them, follow [Adding a Format](docs/adding_a_format.md).
- **Not provided:** booking reconciliation, billing, access control, and spectrum editing. Every record is created as Draft for a person to review.

## Try it without a server

Run this from the project root:

```matlab
addpath(genpath("src"));
run("scripts/quick_look.m")
```

The script creates synthetic measurement files, parses them, and renders
quick-look figures. It does not need eLabFTW or make any network calls.

## Connect to eLabFTW

You need MATLAB R2022a or later and an eLabFTW instance. No MATLAB add-ons are
required. The kit talks to a stock eLabFTW server over its REST API v2 only: no server-side changes,
plugins, or admin-side installation are required beyond an API key. The supported connection path has been checked with eLabFTW 5.6.12.
For server setup, configuration, and a first logging run, follow the
[Quick Start](docs/quickstart.md).

If you do not have a server yet, the repository includes a Docker Compose file for a local trial server
(Windows, Docker Desktop). In outline: copy `docker/.env.example` to `docker/.env` and set the secrets, create the
localhost certificate, run `docker compose up -d` from the `docker` directory, initialize the database, then create the
first account and an API key at `https://localhost:3148`. The full steps, and how to run a second, separate server
for demonstrations, are in [Local eLabFTW setup](docs/elabftw_setup.md).

## What works today

| Scenario | What it does | Status |
|---|---|---|
| Offline preview | Creates synthetic inputs, parses them, and writes quick-look figures. | [Available now](docs/verification.md#offline-preview) |
| A1 session logging | Creates Draft session records from inbox files and skips duplicate files. | [Available now](docs/verification.md#session-logging) |
| A3 QC | Checks standard-sample files and records the decision. | [Available now](docs/verification.md#qc-check) |
| D1 instrument ledger | Updates usage and calibration fields for linked instruments. | [Available now](docs/verification.md#instrument-ledger) |
| D2 consumable inventory | Updates quantities and applies the configured re-order status. | [Available now](docs/verification.md#consumable-inventory) |
| R1 monthly usage report | Creates a report record with a CSV summary and chart. | [Available now](docs/verification.md#monthly-report) |
| NMR experiment folders | Records a Bruker experiment folder as one unit, with hashes, a quick-look figure, and a provenance file. | [Available now](docs/verification.md#nmr-folders-live) |
| D3 booking reconciliation | Compares bookings with recorded sessions. | Planned |

## What has been checked

The server checks above use synthetic input files produced by this kit, except the NMR check. No real instrument has been connected yet.

Real NMR experiment folders taken from public datasets were checked against a live server
([live server](docs/verification.md#nmr-folders-live)) and, separately, offline without a server
([synthetic input](docs/verification.md#nmr-folders-synthetic), [real files](docs/verification.md#nmr-folders-real)).
See the [Verification Record](docs/verification.md) for the environments, procedures, and results.

## Build your own workflow

The [Assembly Guide](docs/assembly_guide.md) presents four ways to assemble the
provided parts, from a manual batch to a custom ingest workflow.

## How records are created

- Every record is created as Draft; a person reviews and signs it.
- `data_file_hash` identifies the same input file and prevents duplicate records.
- Each run writes its artifacts under `result/runs/<timestamp>/`.
- Attachment, archiving, category names, and limits are configured without
  editing MATLAB source files.

## Data policy

The original instrument file is authoritative, not the eLabFTW record. The kit reads it from the
instrument PC or a shared folder as read-only; eLabFTW receives one record derived from it, not
the only copy. A raw file is attached to that record only when it is a single file at or under a
configured size limit (25 MB by default); larger or multi-file inputs are recorded by hash and
location instead. After a successful run, the input is moved by default (configurable to copy it or
leave it in place), and an existing file with the same name is never overwritten. Measurement times
are kept in their original time zone rather than normalized to UTC. See
[Function Reference](docs/function_reference.md) and [Algorithm Guide](docs/algorithm_guide.md) for
the exact configuration keys.

## Documents

| Document | Purpose |
|---|---|
| [Quick Start](docs/quickstart.md) | Configure a server and run the supplied workflow. |
| [Local eLabFTW setup](docs/elabftw_setup.md) | Run a local trial server with Docker, and a separate demo server. |
| [Demo Guide](docs/demo_guide.md) | Reproduce a demonstration from an empty server. |
| [Assembly Guide](docs/assembly_guide.md) | Choose or compose a workflow from the provided parts. |
| [Adding a Format](docs/adding_a_format.md) | Add a single-file or folder-based instrument format. |
| [eLabFTW Structure](docs/elab_structure.md) | Set up the required categories, fields, and items. |
| [Function Reference](docs/function_reference.md) | Look up public MATLAB functions and options. |
| [Algorithm Guide](docs/algorithm_guide.md) | Understand parsing, metrics, and test rationale. |
| [Log Format](docs/log_format.md) | Interpret console output and per-run artifacts. |
| [Platform Support](docs/platform_support.md) | Check the MATLAB releases and platforms the kit was run on. |
| [Verification Record](docs/verification.md) | Read the checked environments, procedures, and results. |
| [Third-Party Notices](THIRD_PARTY_NOTICES.md) | Review external software and prior-art notices. |

## License and relationship to eLabFTW

This kit is released under the [MIT License](LICENSE). It communicates with a
user-provided eLabFTW server through its REST API; eLabFTW itself is neither
bundled nor forked by this project.
