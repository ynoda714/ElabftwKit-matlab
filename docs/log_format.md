# Log Format

## Console helpers

The helpers in `src/util/` write the following Command Window output. `msg`
arguments use `sprintf` formatting.

| Helper | Output |
|---|---|
| `logInfo(msg, ...)` | `[HH:MM:SS][INFO]  message` |
| `logWarn(msg, ...)` | `[HH:MM:SS][WARN]  message` |
| `logError(msg, ...)` | `[HH:MM:SS][ERROR] message` |
| `logDebug(msg, ...)` | `[HH:MM:SS][DEBUG] message` when `APP_LOG_VERBOSE=1`; otherwise no output |
| `logProgress(i, n, label)` | `\r[####------]  40% ( 4/10) label`; writes a newline when `i >= n` |
| `logSection(scriptId, label, layer)` | `[HH:MM:SS][INFO]  --- scriptId \| label  [layer] ---` |

`logError` prints a message only; callers that must stop also throw an error.
`logProgress` uses a ten-character bar, rounds its displayed percentage and
filled width, and overwrites the current console line until its final step.

Use the helpers for ordinary logging. Messages in MATLAB source are English.

## Per-run artifacts

`makeRunDir` creates a timestamped directory. Its default base directory is
`result/runs`, and callers may override the base with `BaseDir` or append a
suffix with `Prefix`. The following current callers create artifacts below their
run directory.

| Caller | Directory form | Contents written by that caller |
|---|---|---|
| `elab.pipeline.watchAndLog` | `result/runs/<timestamp>/`, or the configured `cfg.run.root_dir/<timestamp>/` | `watch_summary.csv` when at least one inbox file was considered; one `<base>_quicklook.png` for every newly logged session; `<base>.elab.json` when a logged session uses the leave policy |
| `elab.pipeline.monthlyUsageReport` | `result/runs/<timestamp>_report/` | `usage_<year><month>.csv` and `by_instrument.png` when the requested month contains at least one readable session |
| `scripts/quick_look.m` | `result/runs/<timestamp>_quicklook/` | One `<base>_quicklook.png` for each generated mock input |
| `scripts/example_custom_ingest.m` | `result/runs/<timestamp>_custom_ingest/` | One `<base>_quicklook.png` for every newly logged session and, when enabled for a spectrum or chromatogram, `<base>_custom.png`; `<base>.elab.json` when the leave policy is used |

The run directory is not the archive location for raw inputs. The configured
archive policy can instead place logged files and their sidecars in
`data/processed`; failures moved by that policy go to `data/failed`.
