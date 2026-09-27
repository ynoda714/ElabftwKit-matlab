# Python Integration Architecture

> **Unused reference material for this project.** This kit uses no Python.
> `src/+pybridge/` is retained dormant, for template parity only: the entry
> point is always MATLAB, and nothing in this project calls into it. This
> document describes the bridge's design so a fork that genuinely needs
> Python can pick it up; it is not documentation of this project's current
> behavior.
>
> **Premise: Python is optional.** This template defaults to MATLAB-first,
> reproducibility-first, and most projects generated from it use no Python
> at all. This document exists only for the case where a task genuinely
> cannot be done well in MATLAB, to handle the minimum necessary Python
> libraries in a small, reproducible way.
> `src/+pybridge/` is the implementation core (domain-agnostic) for that
> case; if nothing calls it, it stays dormant.

---

## 0. Design Rationale (why it is built this way)

- **The entry point is always MATLAB.** A user should never need to be aware
  of Python's existence or manage it themselves.
- **Python is a "delegate for specific processing"**, never a place to put
  core logic.
- **Deployment prioritizes reproducibility above all**: zip extraction only,
  no registry/PATH pollution, cleanup by deleting a folder.
- **Library-agnostic.** `pybridge` itself knows nothing about any specific
  library. The packages to install and the import names to verify are given
  through `config/settings.json`'s `python.packages` / `python.verify_imports`.

```
caller -> <pkg>.<module>.func(...)
             -> pybridge.initPython()  (pyenv setup happens once)
                 -> py.<library>.<...>
             <- result converted back to native MATLAB types
        <- the caller never sees a Python type
```

---

## 1. pyenv Execution Modes

| Mode | Description | Default |
|---|---|---|
| **OutOfProcess** | Runs Python in a separate process. Crash-resilient | Yes |
| InProcess | Runs inside the MATLAB process. Faster, but a crash takes MATLAB down with it | No |

Libraries with native (C/C++) extensions can occasionally segfault, so
OutOfProcess is the default.

> **Important constraint**: within one MATLAB session, `pyenv(Version=...)`
> can be **set only once**. Changing it requires restarting MATLAB.
> `pybridge.initPython()` checks `Status` and makes a second call a harmless
> no-op (the intended usage is to call it once, right after startup).

---

## 2. Deployment Tracks (two)

The track is selected by whether `settings.json`'s `python.external_path` is
set.

### Track 1: Embedded Python (Windows / default)

Uses python.org's **Embeddable Package**, extracted from a zip into
`python_env/` (not tracked by Git).

```
ProjectRoot/
└─ python_env/            <- not tracked by Git
   ├─ python.exe
   ├─ pythonNNN.zip       <- standard library
   ├─ pythonNNN._pth      <- enables 'import site' (see below)
   └─ Lib/site-packages/  <- pip install target
```

Deployment flow (`pybridge.installPython`):
1. Guard against Windows' MAX_PATH (260 characters): warn past 200
   characters, error past 240.
2. Download the Embeddable zip from python.org and extract it into
   `python_env/`.
3. **Rewrite `pythonNNN._pth`'s `#import site` to `import site`**
   (skipping this leaves site-packages disabled — the embedded package
   ships with it commented out by default).
4. Bootstrap pip with `get-pip.py`.
5. `pip install` the packages in `python.packages` (reflecting `proxy`
   into `--proxy` if set).
6. Verify imports for `python.verify_imports`.

> venv is not used here — the Embeddable Package is already an isolated
> environment, so a venv on top of it would be redundant.

### Track 2: External / venv Python

Pointing `python.external_path` at an existing CPython/venv `python.exe`
routes through `pybridge.useExternal()` to use it. Choose this when a
library needs a full CPython, or to reuse an environment that already
exists. On this track `installPython` does not create an environment; it
only verifies imports (environment management is the caller's
responsibility).

---

## 3. Platform Detection

`pybridge.isOnline()` determines Desktop vs. MATLAB Online (see
[platform_support.md](platform_support.md)). On Online, the system Python
is used and only `pyenv(ExecutionMode=...)` is set (no `Version`).

---

## 4. MATLAB <-> Python Type Conversion

### 4.1 Automatic Conversion

| MATLAB type | Python type | Direction |
|---|---|---|
| `double` | `float` / `int` | both ways |
| `string` | `str` | both ways |
| `logical` | `bool` | both ways |
| `cell` | `list` | MATLAB -> Python |

### 4.2 Conversion Policy (recommended pattern)

- **Keep intermediate objects as Python references** (avoid round-tripping
  conversions that aren't needed).
- Use a single conversion layer that converts **only at the final output
  step**, to native MATLAB types in one pass
  (`py.int`/`py.float` -> `double`, `py.str` -> `string`,
  `py.list` -> `cell`/`table`, `py.dict` -> `struct`, `py.None` -> `missing`,
  `numpy.ndarray` -> `double`).
- Never handle Python `list`/`dict` directly; always go through the
  conversion layer.

### 4.3 Converting Python Exceptions to MATLAB

```matlab
try
    pyObj = py.<library>.<func>(arg);
catch pyErr
    throwAsCaller(MException("<pkg>:<module>:<func>:pythonError", ...
        "Python call failed: %s", string(pyErr.message)));
end
```

---

## 5. Performance (minimize IPC principle)

- OutOfProcess incurs inter-process communication on every `py.*` call
  (a few ms/call).
- For large batches, **do the work in one Python-side pass and return an
  array in bulk**.
- Avoid a MATLAB-side loop calling `py.*` once per element — the IPC cost
  accumulates.
- Batch-oriented Python helpers live under `src/+pybridge/python/` (or
  `src/+<pkg>/python/`).

---

## 6. Security

- Embeddable Python is downloaded **only from python.org**.
- `pip install` uses **only the official PyPI** (a custom index is disabled
  by default).
- Deployment requires a network connection; offline deployment is a
  possible future option.
- Writing files outside ProjectRoot is forbidden (no absolute paths).

---

## 7. API (`src/+pybridge/`)

| Function | Role |
|---|---|
| `pybridge.initPython()` | Configures pyenv (auto-selects Online / external / embedded). Safe to call twice |
| `pybridge.installPython()` | Deploys an environment per configuration (embedded extraction / Online pip / external verification) |
| `pybridge.useExternal(path)` | Connects an external Python to pyenv (Track 2) |
| `pybridge.verifyImport(mods)` | Verifies whether the given modules can be imported |
| `pybridge.isOnline()` | Detects MATLAB Online |
