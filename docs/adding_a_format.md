# Adding an Instrument Format

Add a parser only after confirming the input unit, preserving the original data, and defining stable identity.

## Single-file format

Use this path when one measurement is represented by one file.

| Function | Role | Check |
| --- | --- | --- |
| `elab.io.detectFormat` | Recognize the extension and return the format identifier. | Confirm the new extension selects only the intended format. |
| `elab.io.parseAny` | Dispatch the format identifier to its parser. | Confirm the parser result retains the expected technique and values. |
| `elab.visualization.quickLook` | Render the format-specific quick-look attachment. | Confirm the PNG and profile while retaining every existing preview. |

Add isolated parser, identity, preview, and pipeline tests.
Document every public function in `docs/function_reference.md`.
Regenerate `docs/test_catalog.md` after adding or renaming tests.

## Folder format

Use this additional path when one measurement is a directory tree.

| Function | Role | Check |
| --- | --- | --- |
| `elab.io.listExperimentFolders` | Discover complete experiment directories in the inbox. | Confirm child directories and archive directories are not re-ingested. |
| `elab.io.experimentManifest` | Build the core and full hashes for stable folder identity. | Confirm auxiliary changes preserve the core hash and acquisition changes alter it. |
| `elab.io.parseBrukerExperiment` | Parse the folder metadata into normalized values. | Confirm the parser rejects unsupported experiment dimensions. |
| `elab.pipeline.readSessionFile` | Build one session and optionally add a preview spectrum. | Confirm a preview-reader failure logs once and preserves session metadata. |
| `elab.io.unitName` | Derive the display and archive names for a directory unit. | Confirm nested paths produce stable, collision-safe names. |
| `elab.io.shouldAttachRaw` | Choose whether the original unit is attached. | Confirm directory source data is not attached when archival is authoritative. |
| `elab.pipeline.createSessionExperiment` | Create fields, attachments, and optional preview provenance. | Confirm attachment order, metadata, and image insertion. |
| `elab.pipeline.writeSessionSidecar` | Persist the ingestion sidecar beside the archived unit. | Confirm optional provenance fields appear only with a preview. |
| `elab.pipeline.watchAndLog` | Coordinate logging, duplicate detection, and archive handling. | Confirm successful logging, skipped duplicates, and recovery from preview failure. |
| `elab.pipeline.archiveIngested` | Move a logged directory to the processed archive. | Confirm the archived full hash equals the source full hash. |
| `elab.io.archiveFile` | Move a failed directory or file to the failed archive. | Confirm malformed input is archived without creating an experiment. |
| `elab.io.writeElabSidecar` | Write the durable identity sidecar for a directory unit. | Confirm the sidecar supports future duplicate detection. |

The Bruker NMR folder format is the reference example.
It uses `elab.io.readBrukerSpectrum` only for an optional quick look.
If preview processing fails, `elab.pipeline.readSessionFile` warns and continues with a no-preview session.
This keeps identification, timestamps, duration, hashing, and archival independent from visualization.

Vendor external code only as an unmodified, version-pinned subset under `src/third_party/`.
Record its source, revision, license, file hashes, and aggregate hash in `UPSTREAM.json`.
Use `elab.util.anynmrInfo` with verification enabled to check that every vendored file remains unmodified.
