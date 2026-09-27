# Demonstration Guide

Use this guide to reproduce a screen-material or product demonstration from an
empty eLabFTW server. Start a separate demo server as described in
[Local eLabFTW setup](elabftw_setup.md#run-a-separate-demo-server), and create
its Sysadmin account and Read/Write API key before starting MATLAB.

Open the demo server at `https://127.0.0.1:3149`, not `localhost`. The separate
host avoids the browser cookie collision described in the setup guide.

## Prepare MATLAB

Set the demo API key only for the PowerShell session that starts MATLAB. Keep it
separate from a development-server key.

```powershell
$env:ELAB_API_KEY = "paste-the-demo-key-here"
```

Open `scripts/demo_run.m` in MATLAB with the project root as the current
folder. The script uses the shipped English configuration values and a
certificate at `docker/certs/server.crt`.

## Run the sections in order

Run Section 0a and edit only its server URL or reporting month when needed.
Then run Sections 0b through 4 with Run Section (Ctrl+Enter).

| Section | Action | Result |
|---|---|---|
| 0b | Loads the example configuration, reads the session-only API-key environment variable, and checks the empty target against the fixed `https://127.0.0.1:3149` demo URL. | Stops before any write when the URL set in Section 0a is not the allowed demo URL or the server already has experiments. |
| 1 | Creates the configured experiment/resource categories and Draft status, then creates the Instrument and Consumable items from the example lists. | Seven Instrument items and two Consumable items are available. |
| 2 | Writes synthetic measurement inputs into `data/demo_inbox`. | Twelve distinct measurement units cover seven Instruments, seven Samples, four operators, and three projects. |
| 3 | Logs the demo inbox. | Twelve Draft Session experiments have raw inputs, quick looks, item links, ledger or inventory updates where applicable, and progress messages. A neutral source locator prevents the operator's PC path and host name from being included in the demo records. |
| 4 | Builds the monthly report for the selected month. | One Draft Report experiment contains usage summaries, a CSV attachment, and a chart attachment. |

The generated run artifacts are stored beneath `result/runs/`. The demo inbox
and its processed and failed folders are local generated data and are not part
of the repository.

Sections 0b through 4 together took about 2 minutes 20 seconds against a
locally hosted eLabFTW 5.6.12 (measured 2026-09-27; actual timing depends on
server and network conditions).

## Target guard messages

`elab:demo:wrongServer` means that the URL configured in Section 0a differs
from the fixed demo URL allowed by the script. Check Section 0a and use
`https://127.0.0.1:3149`.

`elab:demo:serverNotEmpty` means that the server already contains one or more
experiments. Do not mix a new demonstration with an existing one. Recreate the
demo server using the deletion procedure at the end of [Run a separate demo server](elabftw_setup.md#run-a-separate-demo-server).
Deleting its volumes also deletes the account and API key, so create both again
before repeating this guide.
