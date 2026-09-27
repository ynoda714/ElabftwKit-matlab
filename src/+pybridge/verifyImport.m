function ok = verifyImport(modules)
% verifyImport  Check that the given Python modules can be imported.
%
%   ok = pybridge.verifyImport()               % use cfg.python.verify_imports
%   ok = pybridge.verifyImport(["numpy" "scipy"])
%
%   Ensures pyenv is initialized (via pybridge.initPython), then attempts to
%   import each module with importlib.  Returns true only if every module
%   imports successfully.  Missing modules are reported via logWarn, not by
%   throwing, so callers can decide how to react.
%
%   Arguments:
%     modules (string array, optional) - module names to import-check.
%                                         Defaults to cfg.python.verify_imports.
%
%   Returns:
%     ok (logical) - true iff all requested modules imported.

    if nargin < 1 || isempty(modules)
        cfg = loadConfig();
        modules = string(cfg.python.verify_imports);
    end
    modules = reshape(string(modules), 1, []);

    if isempty(modules)
        logInfo("verifyImport: no modules requested -- nothing to check.");
        ok = true;
        return;
    end

    pybridge.initPython();

    ok = true;
    for m = modules
        try
            py.importlib.import_module(m);
            logInfo("verifyImport: '%s' OK", m);
        catch ME
            ok = false;
            logWarn("verifyImport: '%s' FAILED -- %s", m, string(ME.message));
        end
    end

    if ok
        logInfo("verifyImport: all %d module(s) importable.", numel(modules));
    else
        logWarn("verifyImport: one or more modules failed. Run pybridge.installPython().");
    end
end
