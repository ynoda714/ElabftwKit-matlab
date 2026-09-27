# Verification Record

What has been checked against a running eLabFTW, when, and how. Other documents
link here whenever they call a feature *verified*.

Every entry below was produced by running the kit and reading the result, not by
reading the code. A feature that is implemented but not listed here has not been
checked against a server.

**Environment for every entry**: MATLAB R2026a Update 2 on Windows 11 Home
(26200), against a self-hosted eLabFTW 5.6.12 in Docker on the same machine.
Input files are synthetic instrument files written by the kit's mock-run writer, except where an entry says otherwise;
no real instrument has been connected yet.

| Feature | Date | How it was checked | Result |
|---|---|---|---|
| <a id="offline-preview"></a>Offline preview (no server) | 2026-09-18 | `scripts/quick_look.m` over the six synthetic formats | Parsed every format and wrote quick-look PNGs |
| <a id="session-logging"></a>Session logging (A1) | 2026-09-19 | Two consecutive runs of the inbox watcher from an empty start | Six files logged as Draft experiments; the second run skipped all six as duplicates |
| <a id="instrument-ledger"></a>Instrument ledger (D1) | 2026-09-20 | Expected values written down before the run, then compared with the items | Usage minutes and calibration fields matched the expected values |
| <a id="consumable-inventory"></a>Consumable inventory (D2) | 2026-09-20 | Same run as the ledger check | Quantity decreased once per session; re-order status applied at the threshold |
| <a id="monthly-report"></a>Monthly usage report (R1) | 2026-09-20 | `monthlyUsageReport` for one month, then the report read in a browser | Report experiment created with summary, tables, notes, CSV and chart; totals matched the sessions |
| <a id="qc-check"></a>QC / standard-sample check (A3) | 2026-09-21 | QC inbox run against a standard-sample file | QC experiment created with the decision fields; instrument status updated on failure only |
| <a id="field-groups"></a>Custom-field groups and order | 2026-09-21 | A logged session opened in a browser | Fields appeared under Measurement, Instrument parameters and Provenance, in the documented order |
| <a id="provenance"></a>Producer provenance | 2026-09-21 | Same records | Kit version, kit commit, MATLAB version, parser and quick-look profile were present |
| <a id="retention"></a>Retention and attachment policy | 2026-09-21 | Runs with each retention mode, and with the attachment size limit lowered | `move`, `copy` and `leave` behaved as documented; an over-limit raw file was recorded without being attached; same-name files were archived under a timestamped name instead of being overwritten |
| <a id="sidecar"></a>Reconstruction sidecar | 2026-09-21 | Same runs | A sidecar JSON was written next to the archived file, with the source location, hash, parsed metadata and record link |
| <a id="resource-categories"></a>Configurable resource categories | 2026-09-21 | A throwaway resource category created on the server, then selected in the configuration | The sample was linked under the configured category; a conflicting value in the master-data CSV stopped the run before any file was processed |
| <a id="list-limits"></a>List-limit reporting | 2026-09-21 | Report limit lowered to two; item search limit lowered to one | The report was created with a note that it may be incomplete; the find-or-create item lookup stopped instead of creating a possible duplicate |
| <a id="staged-ingest"></a>Staged ingest assembly | 2026-09-22 | A logged session compared field by field with one logged before the stages were split out | Identical field names, groups, positions and types; links, ledger, inventory, archiving and sidecar unchanged |
| <a id="build-your-own"></a>Build-your-own example | 2026-09-22 | `scripts/example_custom_ingest.m` run twice against the server | Records created with an extra field and a custom figure; ledger and inventory untouched; the second run skipped both files as duplicates |
| <a id="nmr-folders-live"></a>NMR experiment folders from real files (live server) | 2026-09-26 (opened in a browser 2026-09-27) | Five one-dimensional Bruker experiment folders from a local collection of public-dataset files (one with an empty `prosol_History` file), copied to a temporary location (not distributed), run through the inbox watcher against the server and then run a second time; the records were read back through the API and opened in a browser | All five were logged as Draft experiments with the quick-look figure shown in the body, a provenance file attached, no raw-data attachment, and the instrument and sample linked. The stored fields, groups, and order matched the documented schema, and every provenance file recorded the vendored code as verified. The ledger total equalled the sum of the five durations, a monthly report for one of the months showed the calculated duration, and the second run skipped all five and created nothing |
| <a id="demo-server"></a>Separate demo server | 2026-09-27 | A second server started from the same Compose file with its own environment file (different project name, port, and volume names) beside the running development server, initialized, and then removed with `down -v` | The demo server started and served HTTPS with the shared certificate, and its database was empty. After the first Sysadmin and a Read/Write API key were created on it, the MATLAB client connected with that key (through `127.0.0.1`, see the setup guide). Removing it left the development server unchanged: the same running containers, volumes, attachment count and size, and record counts |

## Checked offline, without a server

The entries above ran against a live eLabFTW server. The entries below did not: the
eLabFTW client was replaced by the kit's test double, so they show what the kit
builds and sends, not what a server stores.

**Environment for every entry**: MATLAB R2026a Update 2 on Windows 11 Home (26200).

| Feature | Date | How it was checked | Result |
|---|---|---|---|
| <a id="nmr-folders-synthetic"></a>NMR experiment folders with quick look and provenance (synthetic input) | 2026-09-26 | The full test suite (508 tests), including an offline run of the inbox watcher over synthetic Bruker-style folders, and 20 deliberate breakages of the code, each of which made a test fail | All 508 tests passed; every breakage was caught by the test written for it |
| <a id="nmr-folders-real"></a>NMR experiment folders from real files | 2026-09-26 | 40 one-dimensional Bruker experiment folders from a local collection of public-dataset files, copied to a temporary location (not distributed), run through the inbox watcher, then run a second time | 40 of 40 were logged, each with a quick-look figure and a provenance file and no raw-data attachment; every archived folder had the same hashes as before ingest; the second run skipped all 40 and created no new record |
| <a id="vendored-nmr-code"></a>Vendored NMR processing code is unmodified | 2026-09-25 | Every file compared byte for byte with an independent clone of the upstream release tag, and the recorded file hashes recomputed | All files identical; the test suite repeats the hash check and fails if a vendored file is changed |

## Not verified yet

- A real instrument connected to the kit. The server checks above used synthetic input, except the NMR entry, which used real experiment folders; no instrument was connected.
- Unattended or scheduled operation, and two ingests running at the same time.
- Recovery from a partial failure (for example a record created but not linked).
- Booking reconciliation, which exists only as a sketch.
