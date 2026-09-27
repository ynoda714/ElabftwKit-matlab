function useExternal(pythonPath)
% useExternal  Connect this project to an external Python environment (Track 2).
%
%   pybridge.useExternal(pythonPath)
%
%   Configures pyenv to use the specified external CPython executable (for
%   example a venv or conda environment) instead of the repo-local Embedded
%   Python.  Use this for libraries that need a full CPython install and
%   cannot be dropped into the Embedded Python environment.
%
%   If Python is already loaded in this MATLAB session, the call is silently
%   ignored with a warning (pyenv cannot be reconfigured once loaded).
%
%   Arguments:
%     pythonPath  (string | char) - absolute path to the Python executable
%                                   (e.g., "C:\envs\myenv\python.exe")
%
%   Error IDs:
%     pybridge:useExternal:invalidInput  - pythonPath not a string/char or empty
%     pybridge:useExternal:fileNotFound  - executable not found at path
%     pybridge:useExternal:pyenvFailed   - pyenv() call threw an error
%
%   See also: pybridge.initPython, pybridge.verifyImport

    % --- Input validation (manual; handles string and char) ---
    if ~(ischar(pythonPath) || isStringScalar(pythonPath))
        error("pybridge:useExternal:invalidInput", ...
            "pythonPath must be a string or char scalar, got %s.", class(pythonPath));
    end
    pythonPath = string(pythonPath);
    if strlength(strtrim(pythonPath)) == 0
        error("pybridge:useExternal:invalidInput", ...
            "pythonPath must be a non-empty path string.");
    end

    % --- Idempotency guard ---
    pe = pyenv();
    if ~strcmp(string(pe.Status), "NotLoaded")
        logWarn("useExternal: Python %s already active (Status: %s). " + ...
            "Cannot change pyenv after Python is loaded -- ignoring.", ...
            string(pe.Version), string(pe.Status));
        return;
    end

    % --- Verify executable exists ---
    if ~isfile(pythonPath)
        error("pybridge:useExternal:fileNotFound", ...
            "Python executable not found: %s", pythonPath);
    end

    % --- Configure pyenv ---
    cfg      = loadConfig();
    execMode = cfg.python.execution_mode;
    logInfo("useExternal: Connecting to external Python: %s", pythonPath);
    try
        pe = pyenv(Version=pythonPath, ExecutionMode=execMode);
        logInfo("useExternal: Python %s configured (mode: %s).", ...
            string(pe.Version), string(pe.ExecutionMode));
    catch ME
        error("pybridge:useExternal:pyenvFailed", ...
            "pyenv configuration failed: %s", ME.message);
    end
end
