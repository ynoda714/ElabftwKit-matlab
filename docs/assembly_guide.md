# Assembly Guide

## Principle

`src/` provides parts for reading instrument files, creating records, linking
items, and rendering figures. Entry scripts are assembly examples rather than a
single fixed product, so a facility can choose the flow that fits its practice.

## The four assemblies

| Assembly | What it does | Status | Entry point |
|---|---|---|---|
| A. Watch and log automatically (recommended) | Records inbox files without a person starting each run. | Planned | — |
| B. Manual batch | Runs selected workflow sections in a batch. | Available now | [`main_elabftw.m`](../main_elabftw.m) |
| C. GUI | Starts workflows from a graphical interface. | Planned | — |
| D. Build your own | Combines selected parts into a local workflow. | Available now | [`scripts/example_custom_ingest.m`](../scripts/example_custom_ingest.m) |

## A. Watch and log automatically (recommended)

Automatic logging is the recommended ideal because it preserves a record without
requiring a person to begin each run. It is Planned and is not provided yet. For
now, have a person run Section 3 of the manual batch regularly.

Do not run two ingests at the same time. Duplicate detection assumes one run at a
time.

## B. Manual batch

[`main_elabftw.m`](../main_elabftw.m) can be run one section at a time:

| Section | Purpose |
|---|---|
| 0a | Set user parameters. |
| 0b | Set up the path, configuration, and client. |
| 1 | Create initial Instrument and Consumable items. |
| 2 | Generate synthetic files for a trial. |
| 3 | Log measurement files in the inbox. |
| 4 | Create a monthly usage report. |
| 5 | Process QC files. |

For setup and a first run, see the [Quick Start](quickstart.md).

## C. GUI

A GUI is Planned.

## D. Build your own

The ingest stages below are the parts used by the supplied workflow. Their full
contracts are in the [Session ingest stages](function_reference.md#session-ingest-stages).

| Stage | Call | Input to output | Example replacement |
|---|---|---|---|
| Read the map | `readSampleMap` | configuration to sample-map table | Use a locally maintained map. |
| Match a file | `matchSample` | map and file name to `binding` | Match a barcode instead of a file name. |
| Read a file | `readSessionFile` | file path to `session` | Read a locally supported file format. |
| Check duplicates | `findLoggedSession` | client, configuration, and `session` to an existing id or empty | Keep the check while changing the search source. |
| Add context | `addSessionContext` | `session` to `session` with source and timezone | Add local provenance values. |
| Create a record | `createSessionExperiment` | `session`, `binding`, and run context to experiment id | Add fields with `extraFields`. |
| Link items | `linkSessionItems` | experiment id and `binding` to linked item ids | Omit links for a record-only flow. |
| Archive | `archiveIngested` | file, outcome, and configuration to archive path | Use a site-specific retention policy. |
| Write a sidecar | `writeSessionSidecar` | session, record id, and archive context to a sidecar | Omit sidecar output. |

A `session` is the structured result of reading one instrument file; context adds
its source location and timezone. A `binding` is one matching row from the sample
map, or empty when no row matches.

Build the stages in this order: read the map, list files, match each file, read
it, check for an existing record, add context, create the record, link items,
then archive it and write its sidecar. You may omit or replace item links,
`updateInstrumentLedger`, `consumeInventory`, and the sidecar JSON. Do not omit
the duplicate check: otherwise one file can create two records. Do not omit
archiving: otherwise a later run reads the same file again. With the `leave`
retention setting, archiving intentionally makes no file move or copy.

Pass additional site fields to `createSessionExperiment(..., extraFields=...)`.
The fields are appended after the standard fields.

[`scripts/example_custom_ingest.m`](../scripts/example_custom_ingest.m) is a
runnable section-by-section example. Edit Section 0 to set an additional field
and choose whether to attach a custom figure, then run Sections 1 through 4 in
order. It reads and creates records, links matching items, archives files, and
writes a sidecar; it intentionally does not update instrument or consumable
ledgers.

When making a custom spectrum or chromatogram figure, use
[`lightFigure`](function_reference.md#srcelabvisualization) rather than calling
`figure` directly. A direct figure can preserve the runner's MATLAB theme, such
as a dark theme, in the saved image. For data-derived text such as a file or
sample name, use `Interpreter="none"` so underscores are not treated as TeX.
See [`lightFigure` and `quickLook`](function_reference.md#srcelabvisualization)
for the rendering behavior.

## Rules that apply to every assembly

- Check for duplicates with `findLoggedSession` before creating a record. Skipping
  this step can create two records for the same file.
- Run one ingest at a time.
- Create figures with `lightFigure`, and use `Interpreter="none"` for
  data-derived text so the saved figure has a light theme and literal labels.
- Records are always created as Draft. A person reviews and signs them.
