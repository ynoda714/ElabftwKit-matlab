# Third-Party Notices

This project uses or references the following third-party resources.

## External Systems (not bundled, not linked)

| System | License | Usage |
|---|---|---|
| eLabFTW | AGPL-3.0-or-later | Target electronic lab notebook. This project communicates with a user-provided eLabFTW instance over its HTTP REST API v2 only. No eLabFTW code is included, copied, or linked. |

## Prior Implementations Referenced

| Resource | Notes |
|---|---|
| `elabapi` (MATLAB File Exchange ID 115865) | A MATLAB client for the eLabFTW API. Reviewed as prior art; **not used** because this project uses its own thin `webread`/`webwrite` + `matlab.net.http` wrapper. |
| eLabFTW API documentation (https://doc.elabftw.net/api/v2/) | Route shapes and request bodies. |

## Software Libraries / Toolboxes

| Library | License | Usage |
|---|---|---|
| MATLAB base (`matlab.net.http`, `webread`/`webwrite`, `readlines`, `jsondecode`) | MathWorks Commercial | HTTP client, file parsing, JSON. No add-on toolboxes are required. |
| Java `java.security.MessageDigest` (bundled JRE) | Oracle / OpenJDK | SHA-256 file hashing for idempotency. |
| AnyNMR-matlab v1.0.0 (`e9332b5aa154136961189617b16723a8e353ed61`) | MIT | Vendored, unmodified dependency closure for Bruker loading, FFT, automatic phase correction, and axis calculation. Source: https://github.com/ynoda714/AnyNMR-matlab |

## Data Sources

| Source | License | Usage |
|---|---|---|
| Synthetic mock instrument data (`elab.io.writeMockRuns`) | This project | Generated locally for demos and offline tests. Not derived from any real dataset. |

---

All trademarks are the property of their respective owners.
