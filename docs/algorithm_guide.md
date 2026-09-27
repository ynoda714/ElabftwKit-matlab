# Algorithm Guide — eLabFTW x MATLAB facility logging kit

> Algorithm rationale, definitions, and test strategy for every function.
> For function signatures and options, see [function_reference.md](function_reference.md).

**Purpose of this document**: explain why the kit behaves as it does.
For usage details, see `function_reference.md`.

## NMR preview and provenance

Bruker folder previews use load, FFT, and automatic phase correction with upstream defaults.
No windowing, baseline correction, or peak picking is applied to a record-preview image.
The preview failure path logs a warning and records the session without a preview or provenance attachment.
Successful previews attach deterministic `provenance.json` content with input hashes, processing steps, and source-version identity.

---

## Contents

1. [Processing pipeline overview](#1-processing-pipeline-overview)
2. [elab.io — Instrument-file parsing](#2-elabio--instrument-file-parsing)
   - [NMR experiment folders](#27-nmr-experiment-folders)
3. [elab.client — eLabFTW REST API](#3-elabclient--elabftw-rest-api)
4. [elab.pipeline — Orchestration](#4-elabpipeline--orchestration)
5. [elab.visualization — Visualization](#5-elabvisualization--visualization)
6. [elab.util — Utilities](#6-elabutil--utilities)
7. [Appendix: synthetic data and tolerances](#7-appendix-synthetic-data-and-tolerances)

---

## 1. Processing pipeline overview

```
config/settings.json ──→ loadConfig() ──→ cfg
                                            │
data/inbox/<file> ──→ elab.io.parseAny() ──→ parsed {x,y | t,intensity,peaks | imagePath}, params
                                            │
                        elab.pipeline.watchAndLog(client, cfg)
                          ├─ SHA-256(file) → findExperimentByExtraField → skip if seen
                          ├─ createExperiment (Draft) + setExtraFields(params + provenance)
                          ├─ policy-gated uploadFile(raw) + uploadFile(quickLook PNG)
                          ├─ linkTo(Instrument), linkTo(Sample)
                          ├─ updateInstrumentLedger(minutes)
                          └─ consumeInventory(qty)
                                            │
                           makeRunDir() → result/runs/<ts>/  (PNG, watch_summary.csv)
```

**Design principles**:
- Parsers are non-destructive. The configured retention policy determines whether
  an input is moved, copied, or left after processing.
- MATLAB always creates Draft entries for human review and signing.
- Idempotency: a raw file can create only one session per configured category, keyed by `data_file_hash`.
- eLabFTW stores extra-field values as strings.

---

## 2. elab.io — Instrument-file parsing

### 2.1 `kvline` — Extract key/value lines

**Design intent**: XRD `.xy`, Raman `.txt`, JCAMP-DX-like `.dx`, and image
sidecar `.txt` files use different header notation (`# key: value` / `## KEY= value`).
One regular expression accepts them all.

**Algorithm summary**:
- Remove leading `#` characters, then split at the first `:` or `=` with `^([^:=]+?)\s*[:=]\s*(.+?)\s*$`.
- After extracting the name, ignore the pair when the name starts with two or more
  `-`, `*`, `~`, or `_` characters; these lines are decorated separators, not metadata.
- Ignore a line whose value contains `..`, or whose name starts with `XYDATA`, `XYPOINTS`, `PEAKTABLE`, or `END`; these are JCAMP-DX data markers.

**Parameter rationale**: the non-greedy match (`+?`) makes the first delimiter the
boundary, so a `:` inside the value does not corrupt the split.
The separator rule is deliberately limited to repeated `-`, `*`, `~`, and `_`
prefixes so that valid JCAMP-DX labels beginning with `.` or `$` remain available
as metadata; a single leading `_` is retained for the same reason.

**Test strategy**: `TestParsers` verifies that known header keys such as `anode`
and `magnification` appear in `params` for every generated format.

### 2.2 `parseSpectrum` — Two-column spectra

**Design intent**: process the common header-plus-two-numeric-columns layout of
XRD, Raman, FTIR, and NMR through one function.

**Algorithm summary**:
1. Scan lines; send lines starting with `#` to `kvline` as headers.
2. Split other lines on `[,;\t ]+`; when at least two numeric values exist, take the first two as `(x, y)`.
3. Calculate `n_points`, `x_min`, and `x_max` and add them to `params`.
4. Select axis labels from `technique`; `nmr` uses ppm and reverses its display axis.

**Known limitation**: compressed JCAMP-DX encoding, including `(X++(Y..Y))`
delta compression, is unsupported. The mock `.dx` input contains raw `x y` pairs.

**Test strategy**: a synthetic XRD spectrum with five Gaussian peaks and uniform
noise verifies `numel(x) == numel(y)` and import of the main header keys.

### 2.3 `parseChromatogram` — LC/GC-MS

**Algorithm summary**:
- The `[TRACE]` section maps `time,intensity` CSV data to `s.t` and `s.intensity`.
- In `[PEAKS]`, the first line is the header and subsequent lines are rows; numeric columns become numbers and `name` remains text.
- Add `run_minutes = max(t)`, `n_peaks = height(peaks)`, and `peak_names` to `params`.

**Test strategy**: a synthetic trace with four Gaussian peaks verifies
`height(peaks) > 0` and the presence of `run_minutes`.

### 2.4 `parseImageMeta` — SEM / microscopy

**Design intent**: image files can be large, so the ELN receives only a reduced
preview while acquisition conditions flow from the `*_meta.txt` sidecar to `extra_fields`.

**Algorithm summary**: obtain dimensions with `imfinfo` and add sidecar key/value
pairs from `kvline` to `params`.

### 2.5 `writeMockRuns` — Generate mock data

**Design intent**: make the complete pipeline testable and demonstrable without an instrument.

**Synthetic models** (fixed `rng(42)`):
- XRD: uniform noise plus Gaussian peaks (2theta = 21.3/28.4/40.5/50.1/62.9)
- Raman: normal noise plus Gaussian peaks (520/950/1350/1580 cm^-1)
- FTIR: Gaussian absorption bands (3400/2920/1720/1600/1100 cm^-1)
- NMR: Lorentzian peaks (delta 7.26/3.68/2.10/1.25 ppm)
- LC-MS: Gaussian chromatographic peaks (RT 1.83/2.71/5.44/8.90 min)
- SEM: grayscale image of a `sin`/`cos` pattern plus normal noise

The values are intended only to look plausible; they have no quantitative meaning.

The generated files carry an offset-free acquisition time. The default series
starts at 09:00 today and advances by 40 minutes in XRD, Raman, FTIR, NMR,
LC-MS, and SEM order. Callers can provide a scalar `acquiredAt` to anchor the
series elsewhere.

### 2.5.1 `writeDemoRuns` — Demonstration coverage

The demonstration generator assembles twelve unique synthetic measurement units
from the established single-file and Bruker-folder generators. It uses all seven
example Instrument bindings, all four example operators, all three projects, and
both samples that consume inventory. Acquisition dates are distributed through
one selected month, so the monthly report presents multiple dates rather than a
single batch. The inputs deliberately include measured and calculated or nominal
duration sources, which makes the duration-basis report columns visible.

**Test strategy**: offline tests parse every generated unit, check its binding,
acquisition month and distinct dates, duration source, content hash, repeated
byte-stable output, and absence of local user or computer identity text.

### 2.6 `readAcquiredAt` — acquisition-time provenance

The reader checks parser parameters case-insensitively. It accepts
`acquired_at` in `yyyy-MM-dd'T'HH:mm:ss`, `yyyy-MM-dd HH:mm:ss`, or
`yyyy-MM-dd'T'HH:mm`, then accepts JCAMP-DX `LONGDATE` in
`yyyy/MM/dd HH:mm:ss`. If neither produces a valid value, it uses the raw input
file's modification time; a missing file returns `NaT`. The corresponding
source is `file`, `file_mtime`, or `unknown`.

These values are local wall-clock times without an offset. Inputs containing
`Z` or a numeric offset are rejected until timezone handling is defined. A
present but invalid value, including an impossible calendar date, is logged
with its filename and value before the reader tries the next source.

### 2.7 NMR experiment folders

A Bruker one-dimensional experiment is a folder rather than a single file. It
is identified by immediate `acqus` and `fid` children; a `ser` input is found so
it can be reported as unsupported multidimensional data. Folder discovery stops
at an identified experiment, which prevents processed output below it from
being treated as another measurement.

The manifest has a fixed UTF-8, LF-terminated text form: `elab-manifest 1` on
the first line, then SHA-256, two spaces, byte count, two spaces, and a
slash-separated relative path. The full form records normal files except
processed data, hidden files, and desktop metadata. The core form includes only
the immediate acquisition parameters, data, and audit trail. Its hash remains
stable when post-processing or auxiliary files change, while the full hash can
detect those preservation changes.

The parameter reader extracts only acquisition identity and settings from
`acqus`; owner, host, and path text are not recorded as parameters. A positive
acquisition epoch is converted to the configured IANA timezone and returned as
an offset-free local wall-clock time. If it is unavailable, data-file modification
time is the fallback. An empty configured timezone is resolved from the execution
environment; if that is also unavailable, the reader warns and uses modification
time. Audit timestamps are used for duration only.

Duration uses three fallbacks after a chromatogram time axis: a single valid
audit start/completion pair is measured duration; complete Bruker timing settings
produce calculated duration; otherwise the configured nominal duration is used.
Multiple audit pairs are deliberately not selected arbitrarily.

**Test strategy**: synthetic folders verify byte-stable generation, recursive
discovery boundaries, manifest formatting and exclusion behavior, parser values
and error identifiers, timezone conversion including daylight saving time, and
all duration fallbacks. Existing single-file tests protect the file path from
these folder-specific branches.

---

## 3. elab.client — eLabFTW REST API

### 3.1 `Client` — transport boundary

`Client` keeps the version-sensitive API routes and transport behavior behind one
thin wrapper. GET requests use `webread` because it decodes JSON directly. PATCH and
POST requests use `matlab.net.http`; the live 5.6.12 checks showed that `webwrite`
cannot perform a working PATCH against this server. Creation methods recover the new
numeric id from the POST response's `Location` header rather than assuming an id in
the response body.

TLS configuration is selected for both transports. A configured CA certificate is
passed to `weboptions.CertificateFilename` for GET and to
`HTTPOptions.CertificateFilename` for raw requests. When self-signed operation is
enabled, `HTTPOptions.VerifyServerName` is disabled; certificate-chain verification
still uses the configured CA or system trust store.

### 3.2 `resolveId` — names to numeric ids

Numeric strings are returned immediately without a request. Named experiment
categories, experiment statuses, resource categories, and resource statuses are
looked up under `/teams/current/`, while top-level models such as `items_types`
use their top-level route. Titles are compared case-insensitively. Failure to find the name raises
`elab:client:resolveId:notFound` instead of allowing a later request to use an
ambiguous or empty id.

### 3.3 `createExperiment` — create, then configure

Experiment creation is deliberately two-stage: create an empty experiment with
POST, then PATCH its title, date, and resolved category. eLabFTW 5.6.12 does not
reliably apply the category during POST. The PATCH field is `category`, not
`category_id`. A requested status is resolved and added to the same PATCH; an omitted
status leaves the server default unchanged, while a named status that cannot be
resolved follows the warning fallback and also leaves the server default unchanged.

### 3.4 `setExtraFields` — encode typed metadata

Each supplied field is converted to an eLabFTW type and string value. An explicit
type is preserved; otherwise `elab.util.inferType` selects it, and
`elab.util.toElabValue` produces the stored representation. The complete
`extra_fields` object is JSON-encoded, and that JSON is sent as the value of the
`metadata` field. In other words, `metadata` is a JSON **string** inside the PATCH
payload, not a nested MATLAB struct. eLabFTW 5.6.12 replaces the complete
`extra_fields` object when this payload is PATCHed. This helper is therefore for
initializing new or metadata-empty entries, not for changing selected fields on an
existing entry.

If fields carry group descriptors, `setExtraFields` also writes each field's
numeric `group_id` and its one-based `position` within that group, plus the group
headings under `metadata.elabftw.extra_fields_groups`. The JSON member order is not
used for display order. Ungrouped callers keep the earlier JSON shape with no
`elabftw` member. This compatibility boundary is intentional because the layout is
opt-in: item metadata and older callers retain the earlier shape.

### 3.5 `updateExtraFields` — update values without rebuilding metadata

The helper first fetches the individual entry. If metadata is absent or empty,
there is nothing to preserve and `setExtraFields` initializes it. Otherwise, the
helper decodes metadata only to classify requested field names as present or
absent. All present values are converted with `toElabValue` and sent together in
one `action="updatemetadatafield"` PATCH. A second GET verifies every requested
value and turns eLabFTW's silent no-op into a `notApplied` error.

The default missing-field mode raises `fieldMissing` before the PATCH, which avoids
a partial update. `missing="warn"` logs absent names and updates only the names that
already exist. It never adds a field by rewriting the complete metadata object.

This restriction preserves metadata that MATLAB cannot round-trip faithfully.
With `jsondecode` followed by `jsonencode`, non-identifier keys (including Japanese
labels) are renamed, one-element arrays lose their array shape, and JSON `null`
becomes an empty MATLAB value. Writing that decoded object back would corrupt
administrator-managed metadata even if the requested values were merged correctly.

### 3.6 `ensureItem` — exact lookup or creation

The resource category name is resolved first. The helper searches items by category
and title, then performs its own case-insensitive exact-title and category check. If
no exact match exists, it creates an empty item and PATCHes `title` plus `category`;
the category cannot be trusted on POST. It reads the item back to verify the category
before writing initial extra fields only when it created the item. An exact existing
match is returned without writing supplied fields; this makes bootstrap reruns
non-destructive.

### 3.7 `findExperimentByExtraField` — narrowed and verified lookup

The helper first asks the server to narrow candidates with
`q=extrafield:<field>:<value>` and the configured result limit. A caller may also
provide a category name. In that case the helper resolves the category ID, adds
`cat=<id>`, and verifies each returned candidate's category as well as its decoded
extra-field value. `data_file_hash` is unique within an experiment category, not
across all experiments: `watchAndLog` searches the configured session category and
`qcInbox` searches the configured QC category. This lets the same raw file produce
one intended record in each category while repeated submission to either category
remains idempotent.

The client-side checks must not be removed. eLabFTW 5.6.12 silently ignores unknown
query parameters, so a mistyped or unsupported `q` or `cat` filter can return an
unfiltered 200 response. Trusting the first returned entry would then produce a
false match. If a listing omits both category fields, the helper fetches that entry
individually. A candidate whose category is still unknown is excluded with a
warning: a duplicate Draft remains visible for human review, whereas suppressing a
record because of an unverified candidate leaves no record to review.

Reaching the configured limit emits a warning because a valid match may have been
truncated. No verified match returns empty. Multiple verified matches also warn, and
the lowest numeric id is returned deterministically.

### 3.8 `uploadImageHtml` — resolve an uploaded image for body HTML

`uploadFile` does not return the attachment metadata needed by eLabFTW's image
download URL. After an upload, `uploadImageHtml` therefore fetches the experiment
or item again and selects the matching `real_name`; if retries or previous runs
left duplicate names, the greatest upload id selects the newest one
deterministically. The `name` and `f` query values are URL-encoded before the
complete `src` attribute is HTML-escaped. The `alt` attribute is escaped
separately. Keeping URL encoding and HTML attribute escaping as distinct steps
prevents spaces or ampersands in filenames from changing the query or markup.

### 3.9 Contract-test strategy

[`tests/unit/TestElabClient.m`](../tests/unit/TestElabClient.m) uses the recording
`FakeElabClient` test double to verify the request-side contract without a live
server. Tests assert route selection, query pairs, call order, PATCH field names,
encoded metadata shape, omitted-status behavior, client-side extra-field
revalidation, limit warnings, and deterministic duplicate handling. The fake throws
for any unconfigured GET route, so an unexpected lookup also fails the test. Live
transport checks remain necessary for behavior below this boundary, including HTTP
method handling, response headers, TLS, and server-version route differences.

---

## 4. elab.pipeline — Orchestration

### 4.1 `watchAndLog` — Idempotent session ingestion (A1)

`watchAndLog` is the assembly example, not a monolith: it reads independent binding
maps, matches them, reads the session, checks its hash, adds context, creates and populates the
experiment, links items, applies ledger and inventory updates, archives, then
writes the sidecar. The independently callable stages keep the same order and
partial-failure behavior. This keeps each workflow boundary reusable without
changing the standard assembly's order.

**Binding layers**: `instrument_map.csv` binds a stable unit-name substring to one
individual Instrument ID, while `sample_map.csv` binds a measurement-specific
substring to one Sample ID. The two matches are independent and case-insensitive.
Use a device-specific prefix or an inbox-relative folder name when two instruments
share a technique. A record with only an Instrument binding still receives the
Instrument link and ledger update. A record with only a Sample binding receives the
Sample link without a ledger update. When different targets match on one side, that
side warns and remains unbound; choosing the first target could write a false link.
An old sample map that includes `instrument_title` remains accepted only when no
Instrument map exists and logs one migration warning.

**Test strategy**: unit tests cover split, sample-only, legacy, missing, mixed, and
empty mapping inputs, independent matches, case handling, partial bindings, and
ambiguous targets. The offline binding smoke test uses the recording client to run
the standard watcher with split, partial, and legacy inputs.

**Inbox listing**: Files whose names start with `.` and files named `Thumbs.db`
or `desktop.ini` (case-insensitive) are not inputs. They remain in the inbox and
do not produce result rows. This keeps Git's `.gitkeep` and files created by
Windows Explorer from becoming false failures.

**Folder sessions**: The watcher lists ordinary files first and then Bruker
experiment folders. A folder uses its inbox-relative `/` name for mapping and its
core manifest hash for idempotency. It is never uploaded as a raw attachment and
when NMR processing succeeds, it uploads a quick-look figure and provenance file
and adds the quick-look image to the record body. A processing failure warns and
continues without either output. Archive names replace `/` with `_`; the sidecar
is written next to the archived folder and retains the full manifest.
When a duplicate has the same core hash but a different full manifest, the watcher
logs a warning before archiving it without creating another record. Folders below
processed and failed directories are excluded when those directories are inside
the inbox.

**Idempotency key**: SHA-256 of the raw data file (`elab.util.fileHash`, Java
`MessageDigest`). `findExperimentByExtraField` uses the server-side `extrafield:`
query to narrow candidates, then verifies
`metadata.extra_fields.data_file_hash.value` locally within the configured session
category. A match is skipped and moved to `processed/` without creating another
experiment. A same-hash QC experiment is not a session duplicate.

**Scope of the guarantee**: This duplicate protection assumes one workflow run
at a time. Reintroducing the same file keeps one experiment in the configured
category, and a skipped file does not reach the ledger or inventory updates.
Concurrent MATLAB sessions, computers, or overlapping scheduled runs are outside
this guarantee. Two runs can both search before either creates the experiment,
so both can conclude that the hash is absent and create duplicates. The ledger
and inventory updates are read-modify-write operations; concurrent writers can
read the same old value and one writer can overwrite the other's increment or
decrement. Concurrency control is planned for a later version.

**Field layout**: The session metadata is assembled in user-reading order before
encoding. Group 1 (Measurement) puts sample, mapped instrument, operator, project,
acquisition time, and duration first. Group 2 (Instrument parameters) preserves
the parser's header order. Group 3 (Provenance) contains the raw filename, SHA-256,
and logging time. The source-header `instrument` and mapped `instrument_title` keep
their existing names but appear in groups 2 and 1 respectively. Group headings
come from `cfg.elab.labels.*`; existing records are not migrated.

**Producer provenance**: `watchAndLog` resolves the kit version and Git state once
at the beginning of the run, then reuses that value for every input. Each session
records the root `VERSION`, best-effort short commit, MATLAB `version`, the parser
function selected by `parseAny`, and the profile returned by `quickLook`. The commit
is deliberately empty when Git is unavailable; losing source-control detail must
not lose the measurement record. A dirty checkout appends `-dirty` so a nominal
commit does not overstate reproducibility. This deliberately limited provenance
preserves the measurement record even when
source-control detail is unavailable.

Restarting an interrupted run is also outside the guarantee. If execution stops
after storing `data_file_hash` but before updating the ledger, the next run skips
the file and leaves the ledger unchanged. If it stops after creating the
experiment but before storing the hash, the next run can create a duplicate.
Automated recovery from partial runs is planned for a later version.

**Workflow state**: File location represents processing state: `inbox` means not
yet processed, `processed` means recorded or skipped as a duplicate, and `failed`
means processing failed under the default `move` mode. `copy` retains successful
inputs and creates one processed copy, while `leave` changes neither location.
For duplicates and failures, `copy` and `leave` do nothing so retries cannot
accumulate processed copies and correctable failures remain available. A move or
copy collision becomes `<name>__<yyyyMMddTHHmmss><ext>`, then `_2`, `_3`, and so
on; an image `*_meta.txt` sidecar receives the same suffix. The per-run summary
CSV in `result/runs/<ts>/` records every outcome. These rules preserve a recoverable
raw-input trail while making duplicate and
partial-processing behavior visible.

**Raw attachment and reconstruction sidecar**: `always` attaches the raw input,
`never` omits it without warning, and the default `auto` attaches only at or
below `attach_raw_max_mb` (25 MB by default). An over-limit `auto` file warns,
but its hash, source location, metadata, experiment, and quick-look remain. Each
successful measurement writes `<name>.elab.json` with schema version, source,
hash, parsed metadata, acquisition context, experiment identity, and kit version.
Move/copy place it beside the archived name; leave places it in the run directory,
never beside a shared original. Sidecar failure warns without failing the record.

**Rationale**: a content hash survives renaming and copying. An instrument ID plus
time could be used instead, but risks collisions and clock differences.

**Duration provenance**: Chromatograms use `max(parsed.t)` and record
`run_minutes_source = "measured"`. Spectra and images have no recoverable time
axis, so they use `cfg.watch.nominal_run_minutes` and record
`run_minutes_source = "nominal"`. The watcher removes any parser-provided
duration keys before appending this canonical pair, preventing duplicate
`run_minutes` fields. A sample-map match adds `instrument_title`; no match leaves
that field absent so the report's `(unknown)` value means the instrument was
genuinely unresolved.

**Acquisition date**: `readAcquiredAt` runs immediately after parsing, before
the input is archived. When it returns a time, the experiment `date` is its
calendar date and the session records `acquired_at` as an offset-free
`datetime-local` string plus `acquired_at_source`. With source `unknown`, the
experiment keeps the registration date, records that source, and omits
`acquired_at`. Parser-provided acquisition keys are removed before the
canonical pair is appended once. `logged_at` remains the registration time.

**Quick-look in the body**: The experiment is first created with its original
text-only body. The watcher then renders and uploads the quick-look, refetches the
attachment metadata, and sends exactly one body PATCH containing the same
auto-log paragraph followed by the image. If the refetch or body PATCH fails, the
watcher logs a warning and continues with links, ledger and inventory updates,
and archiving. Treating this display-only failure as a file failure would move an
already-recorded input to `failed/`; resubmission would then be skipped by its
stored hash before the operational updates could run.

**Failure handling**: Per-file errors remain isolated. `move` sends the input to
`failed/`; `copy` and `leave` keep it in the inbox and record the failure in the
summary CSV.

### 4.2 `qcCheck` — Standard-sample assessment (A3)

QC specifications live in `data/list/qc_specs.csv`. The first case-insensitive
`match_substring` match against the filename selects the instrument, metric,
target, and tolerance. Keeping this row-oriented master data outside MATLAB
source supports multiple instruments without hard-coded acceptance values.

Metric definitions are `max(y)` for `max_intensity`, the x coordinate at
`argmax(y)` for `peak_x`, and `trapz(x,y)` for `area_total`. A check passes when
`abs(measured - target) <= tolerance`, including equality at the boundary.

The QC experiment records `qc_result` as the authoritative text value (`pass`
or `fail`). The `qc_pass` checkbox remains as a display aid; its empty false
value must not be interpreted as "not run." A check that was not run has no QC
experiment.

Failure assigns the instrument's native resource status to the configured check
label. Success reads `status_title` and restores the native OK status only when
the current value is the check status. This prevents a successful standard
measurement from erasing an independent state such as calibration overdue. The
legacy custom `status` extra field is not read or changed. Native resource status
is authoritative, so a QC check does not overwrite an independent operational state.

`qcInbox` performs the duplicate lookup by `data_file_hash` within the configured
QC category before calling `qcCheck`. A QC-category duplicate is moved only under
the `move` retention mode, without creating another experiment. A same-hash
measurement session does not suppress the
QC record. A file with no matching specification remains in `data/qc_inbox` as
`no_spec`, so an administrator can add or correct a specification and rerun it; no
experiment is created for an unperformed check.

The QC experiment follows the same acquisition-time rules as a measurement
session. Its `date` and the date in its title use the acquisition date, and its
metadata records `acquired_at` and `acquired_at_source`. Unknown values retain
today's date and omit `acquired_at`.

The QC record uses the same layout as a session. Its metric inputs and result are
Measurement fields, parser header fields are Instrument parameters, and file
identity is Provenance. This keeps the decision visible before low-level acquisition
settings while preserving every field's existing name, value, and type.
It records the same five producer fields as a session. `parser` remains the actual
function name rather than the broad format. QC creates no preview, so it truthfully
records `quicklook_profile = "none"`. QC shares raw attachment and retention
policies with measurement ingestion but does not add the measurement-only
`timezone`, `source_*`, or `schema_version` fields and does not write an eLab JSON
sidecar.

### 4.3 `updateInstrumentLedger` (D1) / `consumeInventory` (D2)

- Usage is accumulated without rounding in `usage_minutes_total`. The display
  value is recalculated after every session as
  `usage_hours_total = round(usage_minutes_total / 60, 2)`; an already rounded
  hour value is never used as the next input.
- An older Instrument without the minute field starts at zero on its first update.
  The helper adds the field without reconstructing metadata, warns that the old
  display hours were not migrated, and includes the current session. Null or empty
  minute values also start at zero with a warning. Nonnumeric text is an error and
  is left unchanged.
- Calibration days are `floor(days(calibration_due - today))`. If the native
  status is empty, a negative result assigns calibration-overdue and a
  nonnegative result assigns OK. An existing status is not overwritten, so a
  QC-assigned Check state survives a ledger update.
- Inventory is `quantity -= qty`. If the native status is empty, values at or
  below the reorder threshold receive Reorder and values above it receive
  InStock. An existing status is not overwritten.
  A negative result is retained and warned about because clamping would hide that
  more material was used than the ledger held. A null quantity is treated as
  nonnumeric and is not updated.
- Both pipelines GET and decode existing metadata to read current values. eLabFTW
  stores numeric extra-field values as strings, so they are parsed with
  `str2double`.
- Both pipelines write calculated values with
  `updateExtraFields(..., missing="warn")`. Existing values are changed with a
  field-level PATCH, preserving all bootstrap and administrator-managed fields.
  Optional fields that are absent are logged and skipped, while transport and
  read-back verification failures propagate to the caller.
- Bootstrap creates every Instrument ledger field up front, including
  `usage_minutes_total = 0` and empty
  `last_used` (`datetime-local`) and `days_to_calibration` (`number`) values. It
  does not reseed an existing item, so rerunning it cannot reset accumulated usage
  or inventory.
- Resource status definitions are listed once per pipeline run. Missing definitions
  are created with their fixed semantic colors and read back before assignment.
  A status creation or assignment failure emits a warning after the ledger,
  inventory, or QC record has been written; status is not the primary record.
  Native status is only assigned when empty, so the ledger, inventory, and QC
  pipelines do not overwrite one another's operational state.

### 4.4 `monthlyUsageReport` (R1)

The report experiment writes a provenance-only extra-field layout containing the
kit version, MATLAB version, and requested `yyyy-MM` period. These values identify
the producer of the distributed report without changing the body tables or CSV.

The aggregation does not filter on experiment state: Draft and signed experiments
both count. Sessions are always created as Draft for human review, and limiting the
report to signed entries would make measured facility use depend on review progress.
This keeps measured facility use independent of review progress.

The report month is defined by each experiment's `date` field, which session
and QC ingestion set from the acquisition date when available: dates greater than
or equal to the first day of the month and strictly earlier than the first day of
the next month. Both boundaries are calculated once. The server query uses them in
`extended=date:>={month-start} AND date:<{next-month-start}`, and the returned dates
are checked against the same half-open interval again on the client. Entries with a
missing or invalid date are excluded with a warning count. After this date check,
an entry whose listing result has missing or empty `metadata` is fetched again from
`GET /experiments/<id>`. The number of refetched entries is warned about because it
can reveal a change in listing API behavior; a failed detail request stops the
report instead of silently substituting estimates. The retained
`instrument_title` / `project` / `operator` x `run_minutes` rows are summed with
`groupsummary`; the raw rows are attached to the report experiment as CSV. Display
values in `Time (h)` are computed by summing minutes first, dividing that sum by
60, and then rounding to two decimal places. Total rows repeat that calculation
from the underlying minute values; they do not add already rounded display rows.

`run_minutes_source` is retained in the raw CSV as a row attribute, but it is not
an identity or grouping key. Instrument, project, and operator totals therefore
remain single aggregates. Each raw row also records a derived `duration_basis`:
`measured` and `nominal` require a numeric `run_minutes` and an exactly matching
source, `calculated` is a numeric duration derived from instrument parameters,
and `filled` means the report replaced a missing or nonnumeric value with the
configured nominal duration regardless of the recorded source, and `unknown`
means a numeric value had no recognized source. The instrument table reports the
count and percentage of `nominal` plus `filled` rows and separately reports the
count of `unknown` rows and separately reports the count of `calculated` rows.
The chart stacks recorded time by the four display groups: `measured`, `nominal`
plus `filled`, `unknown`, and `calculated`. It uses minutes when
the largest instrument total is below 120 minutes and hours otherwise. Its upper
limit is 115% of the largest stack, or 1 when every stack is zero. The output
describes totals as recorded duration, never as measured duration.
Legacy sessions with no source retain `"unspecified"`; if they have no canonical
`run_minutes`, they are classified as `filled`. The undocumented `duration_min`
key is not read.

A JSON `null` extra-field value is treated like an absent value, so the same
defaults apply to instrument, project, operator, duration, duration source, and
acquisition-date source. A session with nonempty metadata that cannot be decoded
is excluded from the aggregates and CSV, and the excluded count is logged as a
warning. This warning does not alter the accepted report-body structure.

The raw CSV also retains `acquired_at_source`, using `unspecified` for records
created before this field existed. The instrument table appends
`date_estimated_count` for `file_mtime` rows and `date_unknown_count` for
`unknown` plus `unspecified` rows. A nonzero unknown total is warned because
those entries used registration date for month membership.

The report query uses `cfg.elab.report_list_limit` (default `1000`). When its
returned count reaches that positive-integer limit, the pipeline logs a warning
and adds a Notes entry with the limit and `elab.report_list_limit`; the report is
still created as the available snapshot. This makes a possible aggregate
shortfall visible to readers as well as to the person who ran MATLAB. The
find-or-create item lookup uses the separate `cfg.elab.item_search_limit`
  (default `50`): an exact match at the limit is reused with a warning, while a
  missing exact match stops before creating a possible duplicate.

The report experiment is initially created with the summary, tables, and notes so
those results do not depend on image display. After both artifacts are uploaded,
the uploaded chart URL is resolved and the complete body is resent with the image
between the summary and tables. Image lookup or body-update failure is only a
warning: the report, CSV, and chart attachment already exist and remain useful.

Each run creates a new report experiment; it does not find, overwrite, or delete an
existing report for the same month. This preserves a history of report snapshots.

### 4.5 `reconcileBookings` (D3 sketch)

This provisional implementation compares `events` and measurement sessions only by
date. Operational use requires both sides' Instrument item IDs and overlap of the
time ranges on that day.
Both source lists retain their fixed limit of `500` until this unwired sketch is
redesigned; reaching either limit emits a warning.

---

## 5. elab.visualization — Visualization

### 5.1 `quickLook`

**Design intent**: keep ELN attachments to a quick preview that can be checked at a
glance, while preservation of the raw input follows the configured retention and
attachment policy. To avoid requiring Image Processing Toolbox, image reduction
uses decimation (`img(1:step:end, ...)`).

Spectrum and chromatogram previews are created through `lightFigure`. On MATLAB
releases with figure themes, it explicitly applies the light theme; on older
supported releases, figures are already light and no unavailable API is called.
This prevents the operator's desktop theme from becoming part of the stored ELN
record and makes identical inputs produce consistently light previews.

`quickLook` returns a profile assembled from the renderer constants: canvas size,
resolution, theme, and literal-text policy for plots, or the maximum copied image
dimension for image inputs. This avoids a hand-maintained description drifting from
the code. Flat producer provenance remains in extra fields. For a successful NMR
folder preview, the AnyNMR version, processing steps, and input hashes are written
to an attached `provenance.json` without timestamps, user names, or paths.

**Test strategy**: `test_pipeline_smoke` verifies PNG creation for all six formats.
Theme tests temporarily set the default graphics theme to dark without changing
the user's personal setting, then verify the figure theme and exported brightness.

**Do not interpret data-derived plot text as TeX.** Titles use
`title(..., "Interpreter", "none")`, and monthly-report bar-chart tick labels use
`ax.TickLabelInterpreter = "none"`. Titles and tick labels may contain sample,
file, or instrument names; interpreting `_` or `^` as subscripts or superscripts
would alter the meaning of the record.
Axis labels retain the default `tex` interpreter because they intentionally contain
mathematical notation such as `2\theta`.
**Test strategy**: interpreter settings cannot be read from a PNG, so tests inspect
the axes before the figure closes and assert `Interpreter` and `TickLabelInterpreter`.

---

## 6. elab.util — Utilities

### 6.1 `inferType` / `toElabValue`

**Design intent**: an eLabFTW extra field has a type tag (`text`, `number`, `date`,
`checkbox`, and others) and a string value. MATLAB `double`, `string`, `logical`,
and `datetime` values are converted mechanically to the tag and string representation.

- `logical` -> `checkbox`, with value `"on"` or `""`
- `datetime` with a time component -> `datetime-local`; otherwise -> `date`
- Scalar numeric value -> `number`; all other values -> `text`

### 6.2 `fileHash`

The complete file is hashed with Java `java.security.MessageDigest("SHA-256")`.
The result is 64 hexadecimal characters. `TestElabUtil` verifies repeatability for
the same file, length, and character set.

### 6.3 `toItems`

JSON decoding by `webread` or `matlab.net.http` returns a struct array for homogeneous
data and a cell array otherwise, so this helper always normalizes the result to a
cell array of structs.

---

## 7. Appendix: synthetic data and tolerances

### Tolerance table

| Function | AbsTol | RelTol | Rationale |
|---|---|---|---|
| `TestParsers` | Exact equality / structural checks only | — | Parsers only convert numeric text and introduce no numerical error |
| `qcCheck` | `spec.tolerance` (from `data/list/qc_specs.csv`) | — | Defined per standard-sample filename and instrument; equality passes |

### Synthetic-data template

```matlab
% See elab.io.writeMockRuns for details. Common pattern:
rng(42);
x = (x0:dx:x1).';
y = baseline + noise(size(x));
for c = peakCentres
    y = y + amp * exp(-((x - c).^2) / (2 * sigma^2));   % Gaussian
end
```
