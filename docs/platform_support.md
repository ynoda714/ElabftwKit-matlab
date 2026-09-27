# Platform Support

MATLAB version, eLabFTW connectivity, data access, and what has actually been
verified on each platform. This kit uses no Python (see
[python_integration.md](python_integration.md)), so there is no
platform-specific deployment step to document here; the sections below are
about running the kit itself, not about provisioning a language runtime.

## 1. MATLAB version

- Minimum: **R2022a**. No toolboxes or add-ons are required —
  `webread`/`webwrite` and `matlab.net.http` are base MATLAB.
- The template baseline for projects generated from this kit is R2025a+.
- Verified against **R2026a Update 2** (see [verification.md](verification.md)).
- The optional Bruker NMR preview uses vendored AnyNMR-matlab code and was checked on R2026a.
  Its upstream project targets R2025b, requires base MATLAB only, and remains unverified below R2026a.

## 2. Platforms

| Platform | Priority | Status |
|---|---|---|
| Windows Desktop | P0 | **Verified** — every entry in [verification.md](verification.md) ran here |
| MATLAB Online | P0 | Implemented, not verified |
| macOS / Linux Desktop | Deferred | Implemented, not verified |

`src/+elab/` has no OS-specific branches: it calls only base MATLAB and REST
functions, so nothing in the kit itself distinguishes Desktop from Online, or
Windows from macOS/Linux. The open question for the unverified platforms is
network reachability, covered next.

## 3. Connection to eLabFTW

The kit talks to eLabFTW over its REST API v2 using `webread`/`webwrite` and
`matlab.net.http` only — no bundled client library. `elab.base_url` and the
API key are read from configuration (env var > `config/settings.json` >
defaults), never hard-coded.

Every entry in [verification.md](verification.md) was run from a MATLAB
Desktop session against a self-hosted eLabFTW in Docker **on the same
machine** (`https://localhost:3148`, see
[elabftw_setup.md](elabftw_setup.md)). This matters for the unverified
platforms:

- MATLAB Online runs in MathWorks Cloud and cannot reach a `localhost`
  server. Reaching a self-hosted eLabFTW from MATLAB Online requires the
  server to be reachable from MathWorks Cloud (for example a public host,
  or a network the cloud session can route to); this has not been set up or
  tested.
- A cloud-hosted eLabFTW instance (or any server reachable over the public
  internet) should be reachable from either Desktop or Online, but that has
  not been tested either.

## 4. Data access

Input files are read from the local filesystem (`data/inbox/`,
`data/qc_inbox/`, `data/list/*.csv`) with plain MATLAB file I/O (`dir`,
`fopen`/`fread`, `readtable`, etc.) — there is no platform-specific access
layer. On MATLAB Online this means the input files and `result/` output
directory must be reachable from the Online filesystem (for example under
MATLAB Drive); this has not been tested.

## 5. Verification status

See [verification.md](verification.md) for the dated, per-feature record.
In short: every verified feature ran on Windows Desktop against a local
Docker eLabFTW. MATLAB Online and macOS/Linux Desktop are implemented but
not yet run.
