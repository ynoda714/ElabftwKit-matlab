function tests = test_pybridge_smoke()
% test_pybridge_smoke  Smoke tests for the MATLAB<->Python bridge core.
%
%   These tests do NOT require a provisioned Python environment.  They check
%   that the config layer and the bridge API load and behave sensibly.
%   Python-dependent checks are guarded and skipped when Python is absent.
%
%   Run:
%     addpath(genpath("src"));
%     results = runtests("tests/smoke/test_pybridge_smoke.m");

    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    % Resolve project root from this test file's own location so the suite
    % runs regardless of the session's current directory.
    thisDir = fileparts(mfilename("fullpath"));        % tests/smoke
    projectRoot = fileparts(fileparts(thisDir));        % -> project root
    tc.TestData.projectRoot = projectRoot;
    tc.TestData.origDir = cd(projectRoot);
    addpath(genpath(fullfile(projectRoot, "src")));
end

function teardownOnce(tc)
    cd(tc.TestData.origDir);
end

function test_loadConfig_defaultSettings_returnsExpectedPythonConfig(tc)
    cfg = loadConfig();
    verifyEqual(tc, cfg.python.execution_mode, "OutOfProcess");
    verifyTrue(tc, isstring(cfg.python.version));
    verifyTrue(tc, isstring(cfg.python.packages));
    verifyTrue(tc, isstring(cfg.python.verify_imports));
end

function test_pybridgeApi_coreFunctions_areOnPath(tc)
    % Package-qualified names must be checked with which(); exist(...,"file")
    % returns 0 for them.
    verifyNotEmpty(tc, which("pybridge.initPython"));
    verifyNotEmpty(tc, which("pybridge.useExternal"));
    verifyNotEmpty(tc, which("pybridge.installPython"));
    verifyNotEmpty(tc, which("pybridge.verifyImport"));
    verifyNotEmpty(tc, which("pybridge.isOnline"));
end

function test_isOnline_noArgs_returnsScalarLogical(tc)
    tf = pybridge.isOnline();
    verifyTrue(tc, islogical(tf) && isscalar(tf));
end

function test_verifyImport_emptyModuleList_returnsTrueWithoutTouchingPython(tc)
    % With no modules requested, verifyImport should not touch Python.
    ok = pybridge.verifyImport(strings(1, 0));
    verifyTrue(tc, ok);
end
