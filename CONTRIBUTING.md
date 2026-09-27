# Contributing

Thank you for your interest in contributing!

## How to Contribute

### Reporting Bugs

Please use the [Bug Report](../../issues/new?template=bug_report.yml) issue template. Include:
- Steps to reproduce
- Expected vs actual behavior
- MATLAB version and OS

### Feature Requests

Please use the [Feature Request](../../issues/new?template=feature_request.yml) issue template.

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Follow the coding conventions below
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a Pull Request

## Coding Conventions

- **Language**: All `.m` file content (comments, logs, errors) must be in English
- **Naming**: `camelCase` for functions, `Test<Feature>.m` for test classes
- **Logging**: Use log helpers (`logInfo`, `logWarn`, `logError`). Never use `fprintf` directly
- **File placement**: All logic under `src/`. Domain logic in `src/+<pkg>/+<module>/`
- **Artifacts**: Output via `makeRunDir()` to `result/runs/`. Never hardcode paths

## Development Setup

```matlab
addpath(genpath("src"));
% Run unit tests
suite = testsuite("tests/unit");
runner = matlab.unittest.TestRunner.withNoPlugins;
results = runner.run(suite);
```

## Data in issues and pull requests

Do not attach real instrument files, a real eLabFTW server URL or API key, or personal information
(real names, host names, or file paths containing a username) to an issue or pull request. Use the
kit's synthetic example data (`elab.io.writeMockRuns`, `elab.io.writeDemoRuns`) to reproduce a
problem instead.

## Code of Conduct

Please be respectful and constructive in all interactions.
