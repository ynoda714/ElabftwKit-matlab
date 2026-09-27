# Function Reference

This reference lists the public MATLAB functions under `src`, except the
optional `+pybridge` package. Name-value arguments are shown after positional
arguments, with their implementation defaults. See [Algorithm guide](algorithm_guide.md)
for processing rationale, [Log format](log_format.md) for console output, and
[Assembly guide](assembly_guide.md) for a staged ingest example.

## NMR preview and provenance

- `elab.util.anynmrInfo(verify=true)` reads vendored AnyNMR identity and verifies copied files.
- `elab.io.readBrukerSpectrum(folder)` returns processed preview vectors and processing steps.
- `elab.util.provenanceDocument(session, kitInfo, profile)` builds the NMR processing provenance object.
- `elab.io.writeProvenanceJson(path, document)` writes deterministic provenance JSON.
- `elab.visualization.quickLook` accepts `"nmr_folder"`; `readSessionFile` accepts `spectrumReader`.
- Vendored AnyNMR dependencies are `loadBruker`, `validateNmrData`, `doFFT`, `autoPhase`, `correctPhase`, `calcAxes`, and `nucleusTable`.

## `src/config/`

### `cfg = loadConfig(opts)`

Loads built-in defaults, the optional local settings file, and environment
overrides in that priority order. The environment prefix is `ELAB`. Name-value
argument `SettingsFile` defaults to `config/settings.json`; a missing default
file logs at debug level and retains built-in defaults. A missing explicitly
selected file raises `elab:config:loadConfig:settingsNotFound`.

| Field | Default | Description |
|---|---|---|
| `cfg.elab.base_url` | `"https://localhost:3148"` | eLabFTW root URL without a trailing slash |
| `cfg.elab.api_key_env` | `"ELAB_API_KEY"` | Environment variable that holds the API key |
| `cfg.elab.ca_cert` | `""` | CA certificate file; empty uses the system trust store |
| `cfg.elab.allow_self_signed` | `false` | Skips hostname verification in `sendRaw`; it does not disable certificate-chain validation |
| `cfg.elab.session_category` | `"Session"` | Measurement-session experiment category |
| `cfg.elab.qc_category` / `report_category` | `"QC"` / `"Report"` | QC and report experiment categories |
| `cfg.elab.instrument_category` / `sample_category` | `"Instrument"` / `"Sample"` | Resource categories for instruments and samples |
| `cfg.elab.consumable_category` / `sop_category` | `"Consumable"` / `"SOP"` | Resource categories for consumables and SOPs |
| `cfg.elab.draft_status` | `"Draft"` | Status for new entries |
| `cfg.elab.extra_field_search_limit` | `400` | Candidate limit for an extra-field lookup |
| `cfg.elab.item_search_limit` | `50` | Candidate limit for `ensureItem`; must be a positive integer |
| `cfg.elab.report_list_limit` | `1000` | Session-list limit for `monthlyUsageReport`; must be a positive integer |
| `cfg.elab.timezone` | `""` | IANA timezone name; empty uses the execution environment |
| `cfg.elab.labels.*` | English defaults | Labels written to native resource statuses and field groups |
| `cfg.ingest.attach_raw` | `"auto"` | Raw attachment policy: `auto`, `always`, or `never` |
| `cfg.ingest.attach_raw_max_mb` | `25` | Maximum raw-file size in MB for `auto` |
| `cfg.ingest.archive_mode` | `"move"` | Post-ingestion policy: `move`, `copy`, or `leave` |
| `cfg.watch.inbox_dir` | `"data/inbox"` | Instrument-file inbox |
| `cfg.watch.processed_dir` / `failed_dir` | `"data/processed"` / `"data/failed"` | Archive directories |
| `cfg.watch.sample_map` | `"data/list/sample_map.csv"` | File-name-to-Sample and operator map |
| `cfg.watch.instrument_map` | `"data/list/instrument_map.csv"` | File-name-to-individual-Instrument map |
| `cfg.watch.nominal_run_minutes` | `10` | Duration for formats without a measured time axis |
| `cfg.qc.inbox_dir` | `"data/qc_inbox"` | Dedicated inbox for QC standard-sample files |
| `cfg.qc.spec_list` | `"data/list/qc_specs.csv"` | Filename-selected QC acceptance rules |

## `src/+elab/+client/`

### `obj = elab.client.Client(baseUrl, apiKey, allowSelfSigned, caCert)`

Constructs the REST client. `allowSelfSigned` defaults to `false`; `caCert`
defaults to `""`. `caCert` is passed to both `weboptions` and
`matlab.net.http.HTTPOptions`. `allowSelfSigned=true` skips hostname validation
only; certificate trust validation remains active.

| Call | Result |
|---|---|
| `data = obj.getJson(path, query)` | Sends GET. `query` defaults to `{}`. |
| `data = obj.patchJson(kind, id, fields)` | Sends JSON PATCH to an entry. |
| `id = obj.createEntry(kind, payload)` | Creates an entry and returns its identifier. |
| `up = obj.uploadFile(kind, id, filePath, comment)` | Uploads a file; `comment` defaults to `""`. |
| `obj.linkTo(fromKind, fromId, toKind, toId)` | Creates an entry link. |
| `obj.tag(kind, id, tagText)` | Adds a tag. |
| `obj.deleteEntry(kind, id)` | Deletes an entry. |
| `resp = obj.sendRaw(method, url, payload, isMultipart)` | Sends a raw HTTP request. |

### `elab.client.addExtraField(client, kind, id, name, value, type)`

Adds an extra field without reconstructing an existing metadata object. It
initializes empty metadata through `setExtraFields` and reads the result back.
For existing metadata it inserts the new JSON member after the `extra_fields`
opening brace, then checks both new and prior values. An existing same-name field
is unchanged. Malformed JSON raises
`elab:client:addExtraField:invalidMetadata`; a UI edit between GET and PATCH can
be overwritten because this helper provides no concurrency control.

### `id = elab.client.createExperiment(client, categoryName, titleStr, opts)`

Creates an experiment. Name-value arguments are `body = ""`,
`date = ""`, `status = ""`, and `tags = strings(1, 0)`.
Categories and statuses are written through the eLabFTW PATCH contract using
the `category` and `status` fields. An empty status is not resolved, leaving the
server default unchanged; callers pass the configured Draft status explicitly.

### `ids = elab.client.ensureConfiguredItemStatuses(client, cfg, keys)`

Fetches the resource-status list once and ensures the configured definitions
named by `keys`; returns a struct of status identifiers. Individual status
failures log a warning and leave the corresponding identifier as `NaN`.
The helper uses configured label text and the fixed semantic colors for OK,
Check, CalibrationOverdue, InStock, and Reorder.

### `[id, created] = elab.client.ensureItem(client, itemType, title, fields)`

Finds an exact resource title in `itemType` or creates it. `fields` defaults to
`struct([])` and is written only for a new item. A truncated candidate list
without an exact match raises an error instead of creating a possible duplicate.
The new item is read back after its category PATCH. Existing exact matches retain
their fields and log that supplied fields were not written. Pipeline callers use
the configured Instrument, Sample, Consumable, and SOP category names rather
than source literals.

### `[id, items] = elab.client.ensureItemStatus(client, title, color, opts)`

Finds or creates one native resource status. `opts.items` defaults to `{}` and
can provide an already fetched status list. `color` is a six-digit hexadecimal
string without `#`.
Creation uses the two-step API: POST under `/teams/current/items_status`, then a
PATCH with title and color. The result is read back and raises
`elab:client:ensureItemStatus:notApplied` when the title was not retained.

### `id = elab.client.ensureCategory(client, endpoint, title, opts)`

Finds an exact title or creates a configured experiment category, resource
category, or experiment status. `endpoint` is one of
`experiments_categories`, `resources_categories`, or `experiments_status`.
`opts.color` defaults to `"29aeb9"` and must be six hexadecimal digits. New
entries use a POST followed by a title/color PATCH and a read-back check; a
failed title update raises `elab:client:ensureCategory:notApplied`.

### `id = elab.client.findExperimentByExtraField(client, kind, fieldName, value, opts)`

Searches for an exact extra-field value and returns the lowest matching id or
`[]`. `opts.category` defaults to `""`; a supplied category constrains both the
server query and the local check. `opts.limit` defaults to `400`.
The helper uses the server-side `extrafield:` query and then checks candidate
metadata locally. Category-scoped searches use the `cat` filter and compare
either numeric category or exact case-insensitive `category_title`. Candidates
without category data are fetched individually; unknown categories are excluded.
Multiple matches warn and return the lowest id.

### `id = elab.client.resolveId(client, endpoint, name)`

Maps a configured title to a numeric identifier for the supported category and
status endpoints. `experiments_categories`, `experiments_status`,
`resources_categories`, and `items_status` are team-scoped endpoints under
`/teams/current/`. `items_types` is the Resource-template endpoint and is not a
resource-category endpoint. Numeric strings are returned without a request; a
missing title raises `elab:client:resolveId:notFound`.

### `elab.client.setExtraFields(client, kind, id, fields)`

Initializes `metadata.extra_fields` from a field struct array. Grouped input
writes group definitions and one-based positions; use `updateExtraFields` for
changes to existing metadata. On eLabFTW 5.6.12 this replaces the complete
`extra_fields` object. Group definitions are sorted by numeric id; positions
restart in each group and follow the input order. Ungrouped fields preserve the
legacy metadata shape without an `elabftw` member.

### `elab.client.updateExtraFields(client, kind, id, fields, opts)`

Updates selected existing fields. `opts.missing` defaults to `"error"`; set it
to `"warn"` to update present fields and log absent ones. It checks that every
field name is a valid MATLAB identifier, sends present fields in one
`action="updatemetadatafield"` PATCH, converts values through
`elab.util.toElabValue`, then reads the entry back. Empty metadata is initialized
with `setExtraFields`; existing metadata is never reconstructed and rewritten.

### `html = elab.client.uploadImageHtml(client, kind, id, realName, opts)`

Returns an escaped HTML `img` element for an uploaded image. `opts.width`
defaults to `600` and `opts.alt` defaults to `""`. It fetches the entry because
uploads do not return usable metadata, selects the matching `real_name` with the
highest upload id, URL-encodes download query values, and escapes HTML
attributes. An empty alt value uses `realName`.

## `src/+elab/+io/`

### `archivedPath = elab.io.archiveFile(filePath, destDir, mode, opts)`

Applies `move`, `copy`, or `leave`. `opts.timestamp` defaults to `""`; move and
copy avoid collisions by adding timestamp and counter suffixes. An image
`*_meta.txt` sidecar follows its data file using the same suffix. `leave` changes
nothing and returns an empty string.

### `info = elab.io.detectFormat(filePath)`

Classifies an input file or NMR experiment folder and returns its format,
technique, metadata sidecar path, and parser information. A folder containing
`acqus` plus `fid` or `ser` is `nmr_folder`; file formats are `spectrum`,
`chromatogram`, `image`, or `unknown`.

### `paths = elab.io.listExperimentFolders(inboxDir)`

Recursively returns sorted Bruker experiment folders below `inboxDir`. A folder
is an experiment when `acqus` and either `fid` or `ser` are immediate children.
Discovery does not descend into a found experiment, and a missing inbox returns
an empty column string array.

### `m = elab.io.experimentManifest(folder)`

Builds a preservation manifest for an experiment folder. `m.entries` records
relative slash-separated paths, byte counts, SHA-256 values, and core membership.
`m.fullText` includes ordinary files except processed data, hidden names, and
desktop files; `m.coreText` includes only immediate acquisition parameter,
data, and audit files. `fullHash` and `coreHash` are SHA-256 hashes of UTF-8
manifest text.

### `[name, value] = elab.io.kvline(L)`

Splits a header line of the form `key: value` or `key = value`; a non-field line
returns two empty strings.

### `files = elab.io.listInbox(folder)`

Returns full input-file paths as a column string array. Dotfiles, common desktop
files, and `_meta.txt` sidecars are excluded.

### `[parsed, info] = elab.io.parseAny(filePath)`

Detects the format and dispatches to the matching parser.
`info.parser` records the parser that read the input and is distinct from
`info.format`, which describes the data shape.

### `parsed = elab.io.parseBrukerExperiment(folder)`

Reads a one-dimensional Bruker experiment folder without server access. The
result has typed `params` for identity and acquisition settings plus raw
`acquisition` facts used for time and duration. Missing `acqus` or `fid`, an
empty `fid`, and multidimensional inputs raise specific errors.

### `s = elab.io.parseChromatogram(filePath, technique)`

Parses the trace and peaks sections of a chromatogram. `technique` defaults to
`"lcms"`. The result contains `s.t`, `s.intensity`, `s.peaks`, and `s.params`.

### `s = elab.io.parseImageMeta(imagePath, metaPath)`

Parses an image and its optional metadata sidecar. `metaPath` defaults to `""`.
The result contains `s.imagePath` and key-value parameters.

### `s = elab.io.parseSpectrum(filePath, technique)`

Parses a two-column spectrum and header parameters. `technique` defaults to
`"unknown"`. The result contains `s.x`, `s.y`, `s.params`, `s.xlabel`, and
`s.ylabel`; it supports XRD, Raman, FTIR, and NMR inputs.

### `[acquiredAt, source] = elab.io.readAcquiredAt(filePath, parsed, opts)`

Reads an acquisition timestamp from supported headers, then file modification
time. It searches an `acquired_at` parameter in supported ISO local formats,
then `LONGDATE` in `yyyy/MM/dd HH:mm:ss`. `source` is `"file"`, `"file_mtime"`,
or `"unknown"`; the last case returns `NaT`. For ordinary single-file parser
results, UTC-designated and offset values are rejected and an invalid value is
warned about before fallback.

For an experiment parser result, `opts.timezone` selects an IANA timezone for a
valid acquisition epoch and returns its offset-free local wall-clock time.
An invalid timezone raises an error; absent or invalid epochs fall back to the
data-file modification time. When `opts.timezone` is empty, the optional
`opts.timezoneResolver` supplies the timezone; if it also returns empty, the
reader warns once and uses the data-file modification time.

### `[minutes, source] = elab.io.readRunMinutes(parsed, nominalMinutes)`

Returns duration in minutes. A time axis is measured duration; a valid audit
start and completion pair is also measured duration. Otherwise complete Bruker
acquisition settings produce a calculated duration, and incomplete data returns
`nominalMinutes` with source `"nominal"`.

### `specs = elab.io.readQcSpecs(csvPath, cfg)`

Reads QC specifications. `cfg` defaults to `loadConfig()`.
It validates `match_substring`, `instrument_title`, `metric`, `target`, and
`tolerance`. An optional `instrument_type` compatibility value is checked
against `cfg.elab.instrument_category`. Invalid rows identify the CSV row and
column; missing files and columns have distinct error identifiers.

### `itemType = elab.io.resolveConfiguredItemType(csvPath, rowNumber, columnName, csvValue, configKey, configuredValue)`

Resolves an optional CSV compatibility value against its configured resource
category and raises an error on a mismatch.

### `[attach, reason] = elab.io.shouldAttachRaw(filePath, cfg, opts)`

Applies the raw-file attachment policy. `opts.pipeline` defaults to `"ingest"`.
`always` attaches regardless of size, `never` skips silently, and `auto` attaches
at or below `cfg.ingest.attach_raw_max_mb` while warning only when over the limit.

### `source = elab.io.sourceLocation(filePath, opts)`

Returns `source_path`, `source_host`, and `source_mtime`. Optional test seams
are `opts.computerName = ""`, `opts.environmentReader = @getenv`, and
`opts.fileInfo = struct()`. The path is absolute as seen at ingestion; the host
is the UNC server or local computer name, and modification time uses local
`yyyy-MM-dd'T'HH:mm` formatting.

### `sidecarPath = elab.io.writeElabSidecar(dataPath, payload)`

Best-effort writer for `<base>.elab.json`; it warns and returns `""` when it
cannot write the sidecar. The sidecar stores the information needed to relate an
archived input, its parsed metadata, and its eLabFTW experiment back to one run.

### `files = elab.io.writeMockRuns(outDir, opts)`

Writes deterministic mock files for six techniques. `outDir` defaults to
`"data/inbox"`; `opts.acquiredAt` defaults to 09:00 on the current day. The
files are stamped at 40-minute intervals and are byte-for-byte identical for the
same acquisition time.

### `files = elab.io.writeDemoRuns(outDir, opts)`

Writes twelve deterministic synthetic measurement units for a demonstration:
eleven single files and one Bruker experiment folder. `opts.month` defaults to
the preceding calendar month. The inputs cover every shipped example binding,
multiple acquisition dates, duration sources, operators, and projects without
using workstation identity or facility data.

### `folderPath = elab.io.writeMockNmrRun(outDir, opts)`

Writes one deterministic synthetic Bruker 1D experiment folder. `outDir` defaults
to `"data/inbox"`; `opts.acquiredAt` defaults to 09:00 on the current day and
`opts.name` defaults to `"nmr_bruker_SMP-2026-007"`. The returned folder contains
`acqus`, an interleaved int32 `fid`, audit and auxiliary files, processed
parameter placeholders, and `elab_mock_meta.txt`. `opts.timezone` defaults to
`"Asia/Tokyo"`; `opts.variant` supplies deterministic malformed or
multidimensional fixtures. This helper is not wired to a pipeline.

## `src/+elab/+visualization/`

### `f = elab.visualization.lightFigure(position)`

Creates a hidden light-background figure. `position` defaults to
`[100 100 900 460]`; the caller closes the figure. On supported releases with a
theme API it explicitly applies `theme(f, "light")`, so exported figures do not
inherit the user's MATLAB theme.

### `[pngPath, profile] = elab.visualization.quickLook(format, parsed, outPngPath, opts)`

Writes a quick-look PNG and its rendering profile. `opts.title` defaults to
`"Quick look"`. Spectrum previews plot x and y, reverse a ppm axis, and draw
chromatogram traces with peak markers; image previews make a reduced copy without
requiring Image Processing Toolbox. The returned profile is
`light;900x460;120dpi;interp=none` for spectrum and chromatogram output, and
`copy;maxdim=1200` for an image copy.

**Figure text is literal.** Titles use `Interpreter="none"`, so a filename such
as `xrd_SMP-2026-001` retains underscores rather than creating subscripts. Axis
labels retain the default TeX interpreter for expressions such as `2 theta`.
Every new figure follows both rules: create it with `lightFigure`, and give
data-derived titles, tick labels, and legends a literal interpreter.

## `src/+elab/+pipeline/`

For a staged ingest assembly, see [Build your own](assembly_guide.md#d-build-your-own)
and [`scripts/example_custom_ingest.m`](../scripts/example_custom_ingest.m).

### `session = elab.pipeline.addSessionContext(session, cfg, opts)`

Adds source location and timezone. `opts.sourceLocator` defaults to
`@elab.io.sourceLocation`; `opts.timezoneResolver` defaults to
`@elab.util.resolveTimezone`.

### `archivedPath = elab.pipeline.archiveIngested(filePath, outcome, cfg)`

Applies the configured retention policy for `"logged"`, `"skipped"`, or
`"failed"` outcomes.

### `elab.pipeline.bootstrapItems(client, cfg, opts)`

Checks configured categories, creates configured resource statuses, and seeds
Instrument and Consumable items. `opts.instrumentsCsv` and `opts.consumablesCsv`
default to their files in `data/list`. New Instruments receive `model`,
`location`, `calibration_due`, `usage_minutes_total`, `usage_hours_total`,
`last_used`, and `days_to_calibration`; new Consumables receive `quantity`,
`reorder_threshold`, and `unit`. Existing items are not reseeded, so reruns do
not reset accumulated use or UI-maintained fields.

Titles containing spaces warn because an individual asset ID is expected, but rows
continue to be created. Missing required Instrument columns name the missing column
in `elab:pipeline:bootstrapItems:missingColumn`.

### `ids = elab.pipeline.bootstrapStructure(client, cfg)`

Ensures the configured Session, QC, Report, Instrument, Sample, Consumable,
SOP, and Draft definitions exist. It returns their numeric identifiers in a
struct and leaves existing exact-title definitions unchanged.

### `elab.pipeline.consumeInventory(client, cfg, consumableTitle, quantity, opts)`

Subtracts from a Consumable quantity. `quantity` defaults to `1` and
`opts.statusIds` defaults to `struct()`. A value at or below
`reorder_threshold` receives the configured native Reorder status when the
resource has no native status; a higher value receives the configured InStock
state. Existing native statuses are not overwritten. A result below zero is kept
and warned about. A missing or nonnumeric quantity is not changed.

### `[experimentId, png] = elab.pipeline.createSessionExperiment(client, cfg, session, binding, runDir, kitInfo, opts)`

Creates and populates one Session experiment, writes its quick look, and uploads
the permitted files. `opts.extraFields` defaults to `struct([])`. A partial binding
uses `sample_id` as the label only when it is nonempty and emits tags only for
nonempty project and Instrument values.

### `id = elab.pipeline.findLoggedSession(client, cfg, session)`

Returns the id of a same-hash Session record in the configured category, or `[]`.

### `[instrumentId, sampleId] = elab.pipeline.linkSessionItems(client, cfg, experimentId, binding)`

Creates or finds and links each nonempty bound Instrument and Sample independently.
An empty side returns an empty identifier without a request.

### `maps = elab.pipeline.readBindingMaps(cfg)`

Reads the split `instrument_map.csv` and `sample_map.csv` files into independent
tables. An Instrument map has `match_substring` and `instrument_id`; a Sample map
has `match_substring`, `sample_id`, and optional operational columns. Missing maps,
missing required columns, empty match strings, and mixed split/legacy columns raise
named errors. A map with `instrument_title` is accepted only as a legacy map when
no Instrument map exists and logs one deprecation warning.

### `binding = elab.pipeline.matchBinding(maps, unitName)`

Matches the two split tables independently against an inbox-relative unit name.
Matching ignores case. Different matching target IDs on one side warn and leave
that side unbound; repeated rows for the same target remain valid. The returned
binding has empty values for an unmatched side and is `[]` only when neither side
matches. Legacy maps retain their first-match behavior through `matchSample`.

### `binding = elab.pipeline.matchSample(map, fileName)`

Returns the first case-insensitive filename match from a sample-map table, or
`[]`.

### `reportId = elab.pipeline.monthlyUsageReport(client, cfg, year, month)`

Builds a monthly report and uploads its CSV and chart. It returns `NaN` when no
readable sessions fall in the requested month. It aggregates Session records by
instrument, project, and operator, creates a report experiment, and writes a CSV
and chart under `result/runs/<timestamp>_report/`. Its Provenance group contains
`kit_version`, `matlab_version`, and `report_period`.

Month membership uses experiment `date` and a half-open interval from the first
day of the requested month through the first day of the next. The same boundaries
drive server filtering and the client recheck. Invalid dates are excluded and
warned about. Listing metadata that is absent or empty is refetched per entry; an
unreadable nonempty metadata value excludes the row.

The report preserves recorded `run_minutes_source`; `duration_basis` describes
the value used by aggregation. `measured` and `nominal` are numeric values with
their recorded source, `filled` is the configured nominal duration supplied for a
missing or nonnumeric value, `calculated` is a numeric value derived from
instrument parameters, and `unknown` is a numeric value whose source is
absent or unrecognized. The CSV also retains `acquired_at_source`; older records
without it use `"unspecified"`. Duration fields are not aggregation identity
keys.

The instrument table reports sessions, time, nominal count and share, calculated
count, unknown basis count, and estimated or unknown acquisition-date counts.
Project and operator tables report sessions and time. The chart stacks Measured,
Nominal or filled, Basis unknown, and Calculated durations, uses minutes below 120 total minutes and
hours otherwise, reserves headroom, and preserves literal instrument labels. A
failure to embed the uploaded chart in the report body warns without failing the
report.

### `[pass, expId] = elab.pipeline.qcCheck(client, cfg, filePath, spec, opts)`

Evaluates one QC file. `opts.statusIds` and `opts.kitInfo` both default to
`struct()`. `spec` supplies `instrumentTitle`, `instrumentType`, `metric`,
`target`, and `tolerance`; supported metrics are `max_intensity`, `peak_x`, and
`area_total`. The function validates the metric, format, and instrument before
creating a Draft QC experiment.

It writes decision fields, `instrument_title`, filename, and hash; links the
instrument; and uploads the raw standard file when the attachment policy permits.
It uses the acquisition date for the experiment date and title when known, and
writes the same `acquired_at` and `acquired_at_source` fields as the watcher.
Failure assigns the configured native Check status. Success restores native OK
only when the current status is Check; other existing native statuses are left
unchanged.

QC uses the same three groups: decision fields are Measurement fields, remaining
parser headers are Instrument parameters, and the filename and hash are
Provenance. It writes producer fields with `quicklook_profile="none"`; `qcInbox`
obtains kit information once and passes it to every check.

### `results = elab.pipeline.qcInbox(client, cfg)`

Processes the dedicated QC inbox and returns one result record per considered
input file. The first case-insensitive filename match in `cfg.qc.spec_list`
supplies the specification. A same hash in the configured QC category is skipped.
Successful files use the shared move/copy/leave policy; processing failures move
to the failed directory only in move mode. QC uses collision-safe archiving and
the raw attachment decision but does not write measurement-session fields or a
sidecar. Files without a specification remain in the QC inbox with
`status="no_spec"`.

### `map = elab.pipeline.readSampleMap(cfg)`

Reads the sample-map CSV and resolves its optional compatibility column.

### `session = elab.pipeline.readSessionFile(filePath, cfg, opts)`

Parses one file, calculates its hash and duration, and reads acquisition time
without contacting the server.

### `T = elab.pipeline.reconcileBookings(client, cfg, sinceDate, beforeDate)`

Compares events and Session dates. `beforeDate` defaults to today's date; the
current sketch uses a fixed list limit of `500`. It lists days with a booking but
no data and days with data but no booking, and warns when either list reaches its
limit instead of treating the comparison as complete.

### `fields = elab.pipeline.sessionFields(session, binding, cfg, kitInfo, quickLookProfile, opts)`

Builds grouped Session metadata. Each canonical measurement field uses a nonempty
binding value first, then its parsed header value, and is omitted when both are
empty. `opts.loggedAt` defaults to `datetime("now")`.

### `elab.pipeline.updateInstrumentLedger(client, cfg, instrumentId, sessionMinutes, opts)`

Adds usage minutes and updates calibration fields. `sessionMinutes` defaults to
`0`; `opts.statusIds` defaults to `struct()`. It adds unrounded minutes to
`usage_minutes_total`, recalculates `usage_hours_total` as
`round(usage_minutes_total / 60, 2)`, updates `last_used`, and derives
`days_to_calibration`. An empty native status receives the applicable configured
OK or overdue state; an existing native status is not overwritten.

An older Instrument without `usage_minutes_total` starts at zero and produces a
warning rather than carrying over display hours. Null or empty minutes follow the
same rule. A nonnumeric minute value raises
`elab:pipeline:updateInstrumentLedger:invalidMinutes` before any PATCH.

### `results = elab.pipeline.watchAndLog(client, cfg, opts)`

Runs the standard session workflow over the configured inbox. Optional test
seams are `opts.sourceLocator`, `opts.timezoneResolver`, `opts.sidecarWriter`, and `opts.spectrumReader`.
It reads binding maps once, matches a file, reads a session, checks
the hash, adds context, creates an experiment, links items, updates the ledger
and inventory, archives the input, and writes a sidecar in that order.
Before each input it logs `watchAndLog: [k/n] name`; the final summary and
workflow order are unchanged.

### Session ingest stages

`readBindingMaps(cfg)` reads independent binding layers. `matchBinding(maps,
fileName)` returns the normalized binding or `[]`. `readSampleMap(cfg)` and
`matchSample(map, fileName)` remain available for legacy maps.
`readSessionFile(filePath, cfg)` reads one file without a server. It adds
`unit="file"` for files. For an NMR experiment folder it uses the core manifest
hash, returns `unit="folder"` and the complete manifest, and resolves the
acquisition timezone through `opts.timezoneResolver`.
`findLoggedSession` checks its hash only in the configured Session category.
`addSessionContext` adds source and timezone through optional resolvers.
`sessionFields(session, binding, cfg, kitInfo, quickLookProfile, opts)` builds
metadata without a server; `opts.loggedAt` defaults to now.
`createSessionExperiment` creates, renders, writes fields, and attaches files,
but does not link items, update ledgers, or archive. `linkSessionItems` returns
empty identifiers and makes no requests for an empty binding.

### `[name, archiveName] = elab.io.unitName(path, inboxDir)`

Returns a file name unchanged for a file. For a folder it returns the normalized
inbox-relative name with `/` separators and an archive-safe name with `_` separators.

### `source = elab.io.sourceLocation(filePath, opts)`

Returns the absolute source path, host, and modification time. A folder uses the
modification time of `fid`, or `ser` when `fid` is absent.

### `[attach, reason] = elab.io.shouldAttachRaw(filePath, cfg, opts)`

Applies the raw attachment policy. Folders are never attached and return
`reason="folder"`; only the `always` policy emits a warning for a folder.

### `archivedPath = elab.io.archiveFile(filePath, destDir, mode, opts)`

Moves, copies, or leaves a data file or folder without overwriting a collision.
`opts.name` selects a folder archive name while files retain their existing naming rule.

### `path = elab.io.findElabSidecar(folder, dataFileHash)`

Returns the newest direct `.elab.json` sidecar whose `data_file_hash` matches.
Unreadable JSON and missing folders return no path without raising an error.

### `value = elab.util.schemaVersion()`

Returns the current Session metadata and sidecar schema version.

### `elab.pipeline.warnManifestChange(session, cfg)`

Warns when a duplicate folder has the same acquisition hash but a different full
manifest than its previously archived sidecar. It does not create a record.

The watcher scans `cfg.watch.inbox_dir` once. It creates a Draft experiment,
writes extra fields, uploads a permitted raw file and an always-present quick
look, links Instrument and Sample items, updates the ledger and inventory, and
applies the retention policy. After the quick-look upload it embeds the image in
the experiment body. A failure to embed the image warns but does not stop later
steps because the experiment and attachment already exist.

`data_file_hash` is the SHA-256 idempotency key. A same hash is skipped and the
duplicate lookup passes `cfg.elab.session_category`, so a QC record with the same
hash does not suppress a Session record. PNG previews and `watch_summary.csv` are
written below the run directory. Each result has `file`, `status`,
`experimentId`, and `message`. Dotfiles, `Thumbs.db`, and `desktop.ini` remain in
the inbox and do not appear in results.

`cfg.ingest.archive_mode` is shared with `qcInbox`. Logged files are moved,
copied, or left in place. Skipped and failed files move only in move mode. A
successful Session also writes `<base>.elab.json` beside an archived file or in
the run directory for leave mode; a sidecar failure only warns.

Each new Session writes `run_minutes` and `run_minutes_source`. Chromatograms
use `max(parsed.t)` and receive `"measured"`; other formats use
`cfg.watch.nominal_run_minutes` and receive `"nominal"`. Parser fields with
these names are removed before canonical fields are appended. The experiment date
uses acquisition date when available. `acquired_at_source` is always recorded;
`acquired_at` is an offset-free `datetime-local` value only for `"file"` or
`"file_mtime"`. `"unknown"` omits `acquired_at` and uses the registration day.

Session fields appear in Measurement, Instrument parameters, and Provenance
groups. Measurement contains context and duration fields in a fixed order;
parser header fields retain parser order in Instrument parameters. Provenance
contains the filename, hash, source location, registration time, schema version,
kit version, commit, MATLAB version, actual parser, and quick-look profile. A
missing Git executable or repository leaves `kit_commit` empty without stopping
the record.

### `elab.pipeline.writeSessionSidecar(session, experimentId, cfg, kitInfo, archivedPath, runDir, opts)`

Writes the best-effort session sidecar after a record is created.
`opts.sidecarWriter` defaults to `@elab.io.writeElabSidecar`.

## `src/+elab/+util/`

### `elab.util.assertDemoTarget(client, cfg, opts)`

Checks that `cfg.elab.base_url` exactly equals required
`opts.allowedBaseUrl`, then checks that `/experiments` is empty unless
`opts.allowNonEmpty=true`. It raises `elab:demo:wrongServer` or
`elab:demo:serverNotEmpty` before a demonstration entry point writes data.

### `s = elab.util.bodyText(resp)`

Returns readable HTTP response body text for diagnostics.

### `groups = elab.util.fieldGroups(cfg)`

Returns the configured Measurement, Instrument parameters, and Provenance group
definitions with fixed ids 1, 2, and 3. Display names come from
`cfg.elab.labels.field_group_measurement`,
`cfg.elab.labels.field_group_instrument_params`, and
`cfg.elab.labels.field_group_provenance`.

### `f = elab.util.fieldStruct(name, value, type, group)`

Creates one extra-field struct. `type` defaults to `""` and is inferred;
`group` defaults to `struct()`.

### `hex = elab.util.fileHash(filePath)`

Returns a lowercase hexadecimal SHA-256 digest.
For a zero-byte file, it returns the standard SHA-256 digest of an empty input.

### `t = elab.util.inferType(v)`

Maps a MATLAB value to an eLabFTW field type.

### `info = elab.util.kitVersion(opts)`

Reads `VERSION` and obtains a best-effort commit identifier. `opts.projectRoot`
defaults to `""`; `opts.commandRunner` defaults to the internal command runner.
The commit is empty when Git cannot be used and gains a `-dirty` suffix when the
working tree has changes.

### `fields = elab.util.provenanceFields(session, kitInfo, quickLookProfile, group, opts)`

Builds ordered producer provenance fields. `opts.loggedAt` defaults to
`datetime("now")`; `opts.includeSessionContext` defaults to `false`. Session
context adds source location, registration time, and schema version before kit,
MATLAB, parser, and quick-look values.

### `timezone = elab.util.resolveTimezone(cfg, opts)`

Uses the configured timezone or the execution environment. `opts.localTimezone`
defaults to `""`.

### `s = elab.util.toElabValue(v)`

Converts a MATLAB value to the string representation stored by eLabFTW.

### `items = elab.util.toItems(data)`

Normalizes decoded JSON data into a cell array of structs.

### `fields = elab.util.withoutCanonicalFields(fields)`

Removes parser fields whose names collide with canonical duration or acquisition
fields.

## `src/util/`

The console helpers use the formats documented in [Log format](log_format.md).
`makeRunDir` is the common timestamped output-directory creator; all generated
artifacts belong under its returned directory. `resolveProjectRoot` finds the
repository root independently of the active working folder.

### `md = buildTestCatalog(projectRoot)`

Builds the Markdown test catalog from the unit and smoke test folders.

### `logDebug(msg, varargin)`

Prints a debug message only when `APP_LOG_VERBOSE` is exactly `"1"`.

### `logError(msg, varargin)`

Prints one error-level message without throwing an exception.

### `logInfo(msg, varargin)`

Prints one information-level message.

### `logProgress(i, n, label)`

Prints or updates a ten-character progress bar.

### `logSection(scriptId, label, layer)`

Prints an information-level section banner.

### `logWarn(msg, varargin)`

Prints one warning-level message.

### `runDir = makeRunDir(varargin)`

Creates a timestamped run directory. Name-value options are `Prefix = ""` and
`BaseDir = "result/runs"`.

### `projectRoot = resolveProjectRoot()`

Finds the project root independently of the current working folder.
