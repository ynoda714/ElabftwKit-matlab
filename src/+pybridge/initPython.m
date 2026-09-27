function initPython()
% initPython  Configure pyenv for this project (OutOfProcess by default).
%
%   pybridge.initPython()
%
%   Platform-aware, library-agnostic Python environment initialization.
%   The bridge chooses a target Python by this precedence:
%     1. Online          : system Python (pre-installed in MATLAB Online)
%     2. external_path    : Track 2 external / venv Python (settings.json)
%     3. embedded_dir     : Track 1 repo-local Embedded Python (Windows)
%
%   pyenv(Version, ExecutionMode) can only be changed before Python is first
%   used in a MATLAB session (Status == "NotLoaded").  A second call when
%   Python is already active is silently skipped so scripts can call this
%   repeatedly without error.
%
%   Error IDs:
%     pybridge:initPython:notInstalled  - embedded python_env/ not found
%     pybridge:initPython:pyenvFailed   - pyenv() call threw an error

    % --- Double-call guard: must be FIRST to guarantee idempotency ---
    % pyenv() with no args is always safe (does not start Python).
    % Any Status other than "NotLoaded" means Python is already configured;
    % further calls to pyenv(Version=...) would fail.
    pe = pyenv();
    if ~strcmp(string(pe.Status), "NotLoaded")
        logInfo("initPython: Python %s already active (Status: %s) -- skipping.", ...
            string(pe.Version), string(pe.Status));
        return;
    end

    cfg    = loadConfig();
    online = pybridge.isOnline();

    % --- Online: use system Python, no path needed ---
    if online
        logInfo("initPython: MATLAB Online detected -- using system Python");
        configurePyenv_("", cfg.python.execution_mode);
        return;
    end

    % Desktop: resolve project root from this file's location.
    % src/+pybridge/initPython.m -> 3 fileparts -> project root
    projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));

    % --- Track 2: external / venv Python (settings.json python.external_path) ---
    if isfield(cfg, "python") && isfield(cfg.python, "external_path")
        extPath = string(cfg.python.external_path);
        if strlength(strtrim(extPath)) > 0
            if ~isAbsolutePath_(extPath)
                extPath = fullfile(projectRoot, char(extPath));
            end
            if ~isfile(char(extPath))
                logWarn("initPython: external_path not found: %s", extPath);
                logWarn("             Falling back to embedded Python.");
            else
                logInfo("initPython: Track 2 external Python: %s", extPath);
                pybridge.useExternal(extPath);
                return;
            end
        end
    end

    % --- Track 1: embedded Python (Windows) ---
    pyPath = fullfile(projectRoot, cfg.python.embedded_dir, "python.exe");
    if ~isfile(pyPath)
        error("pybridge:initPython:notInstalled", ...
            "Embedded Python not found at: %s\n" + ...
            "Run pybridge.installPython() first, or set python.external_path.", pyPath);
    end
    logInfo("initPython: Desktop mode -- embedded Python: %s", pyPath);
    configurePyenv_(pyPath, cfg.python.execution_mode);
end

% =========================================================================
% Private helpers
% =========================================================================

function configurePyenv_(pyPath, execMode)
% Configure pyenv, tolerating the Online case where pyPath is empty ("").
    try
        % strlength("")==0 (isempty("") is false for a 1x1 string scalar).
        if strlength(pyPath) == 0
            pe = pyenv(ExecutionMode=execMode);
        else
            pe = pyenv(Version=pyPath, ExecutionMode=execMode);
        end
        logInfo("initPython: Python %s configured (mode: %s)", ...
            string(pe.Version), string(pe.ExecutionMode));
    catch ME
        error("pybridge:initPython:pyenvFailed", ...
            "pyenv configuration failed: %s", ME.message);
    end
end

function tf = isAbsolutePath_(p)
% Return true when p is an absolute Windows, UNC, or Unix path.
    p = char(p);
    tf = (numel(p) >= 2 && p(2) == ':') || ...            % Drive-letter: C:\
         (numel(p) >= 2 && p(1) == '\' && p(2) == '\') || ... % UNC: \\
         (numel(p) >= 1 && p(1) == '/');                   % Unix-style /
end
