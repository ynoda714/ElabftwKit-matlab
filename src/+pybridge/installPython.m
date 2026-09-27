function installPython()
% installPython  Provision the Python environment for this project.
%
%   pybridge.installPython()
%
%   Library-agnostic setup.  The packages installed come from
%   cfg.python.packages (settings.json); this function knows nothing about
%   any specific library.  Behaviour by platform / track:
%
%     Online          : bootstrap pip (get-pip.py), pip install --user the
%                        configured packages, then insert the --user
%                        site-packages onto py.sys.path.
%     external_path    : do NOT provision; assume the external env is managed
%                        by the user.  Just verify the configured imports.
%     embedded (Win)   : download python.org Embeddable Package into
%                        python_env/, enable site-packages via the ._pth file,
%                        bootstrap pip, then pip install the configured packages.
%
%   Rationale for the embedded track (see docs/python_integration.md):
%     - zip-extract only; never touches registry, PATH, or env vars
%     - cleanup is a single folder delete (no uninstaller)
%     - isolated by construction, so a venv would be redundant
%
%   Error IDs:
%     pybridge:installPython:unsupportedPlatform - non-Windows Desktop
%     pybridge:installPython:pathTooLong         - MAX_PATH risk (Windows)
%     pybridge:installPython:downloadFailed      - network / websave failure

    cfg = loadConfig();
    projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    packages = reshape(string(cfg.python.packages), 1, []);

    % --- Track selection ---------------------------------------------------
    if pybridge.isOnline()
        installOnline_(cfg, packages);
    elseif strlength(strtrim(string(cfg.python.external_path))) > 0
        logInfo("installPython: external_path set -- skipping provisioning.");
        logInfo("installPython: verifying configured imports in external env.");
        pybridge.verifyImport();
    elseif ispc()
        installEmbeddedWindows_(cfg, projectRoot, packages);
    else
        error("pybridge:installPython:unsupportedPlatform", ...
            "macOS/Linux Desktop is not supported by the embedded track.\n" + ...
            "Set python.external_path to a venv, or use MATLAB Online.");
    end

    % --- Post-install verification ----------------------------------------
    if ~isempty(string(cfg.python.verify_imports))
        pybridge.verifyImport();
    end
end

% =========================================================================
% Windows embedded track
% =========================================================================
function installEmbeddedWindows_(cfg, projectRoot, packages)
    pyVer   = string(cfg.python.version);      % e.g. "3.10"
    envDir  = fullfile(projectRoot, cfg.python.embedded_dir);
    pyExe   = fullfile(envDir, "python.exe");

    % --- MAX_PATH guard (Windows 260-char limit) --------------------------
    probe = fullfile(envDir, "Lib", "site-packages", "some_package");
    if strlength(probe) > 240
        error("pybridge:installPython:pathTooLong", ...
            "Project path is too long for Windows MAX_PATH: %d chars.\n" + ...
            "Move the project closer to the drive root.", strlength(probe));
    elseif strlength(probe) > 200
        logWarn("installPython: project path is long (%d chars); watch for MAX_PATH issues.", ...
            strlength(probe));
    end

    if isfile(pyExe)
        logInfo("installPython: embedded Python already present at %s", pyExe);
    else
        if ~isfolder(envDir); mkdir(envDir); end

        % Resolve a concrete patch version for the embeddable zip. Projects
        % may pin an exact "3.10.11" in settings.json; otherwise default here.
        fullVer = resolveFullVersion_(pyVer);
        zipName = sprintf("python-%s-embed-amd64.zip", fullVer);
        url     = "https://www.python.org/ftp/python/" + fullVer + "/" + zipName;
        zipPath = fullfile(envDir, zipName);

        logInfo("installPython: downloading %s", url);
        try
            websave(zipPath, url);
        catch ME
            error("pybridge:installPython:downloadFailed", ...
                "Failed to download embeddable package: %s", ME.message);
        end
        unzip(zipPath, envDir);
        delete(zipPath);
        enableSitePackages_(envDir, pyVer);
        logInfo("installPython: embedded Python %s extracted to %s", fullVer, envDir);
    end

    % --- Bootstrap pip -----------------------------------------------------
    bootstrapPip_(pyExe);

    % --- Install configured packages --------------------------------------
    pipInstall_(pyExe, packages, string(cfg.python.proxy));
end

% =========================================================================
% MATLAB Online track
% =========================================================================
function installOnline_(cfg, packages)
    logInfo("installPython: MATLAB Online -- bootstrapping pip (--user).");
    getPip = "get-pip.py";
    try
        websave(getPip, "https://bootstrap.pypa.io/get-pip.py");
    catch ME
        error("pybridge:installPython:downloadFailed", ...
            "Failed to download get-pip.py: %s", ME.message);
    end
    system("python " + getPip + " --user");

    proxyArg = proxyArg_(string(cfg.python.proxy));
    for p = packages
        logInfo("installPython: pip install --user %s", p);
        system("~/.local/bin/pip install --user " + proxyArg + p);
    end

    % --user packages are not visible to pyenv automatically -> add to sys.path.
    pybridge.initPython();
    userSite = "/home/matlab/.local/lib/python" + string(cfg.python.version) + "/site-packages";
    insert(py.sys.path, int32(0), char(userSite));
    logInfo("installPython: inserted user site-packages onto sys.path.");
end

% =========================================================================
% Shared helpers
% =========================================================================
function bootstrapPip_(pyExe)
    [rc, ~] = system("""" + pyExe + """ -m pip --version");
    if rc == 0
        logInfo("installPython: pip already available.");
        return;
    end
    logInfo("installPython: bootstrapping pip via get-pip.py");
    getPip = fullfile(fileparts(pyExe), "get-pip.py");
    try
        websave(getPip, "https://bootstrap.pypa.io/get-pip.py");
    catch ME
        error("pybridge:installPython:downloadFailed", ...
            "Failed to download get-pip.py: %s", ME.message);
    end
    system("""" + pyExe + """ """ + getPip + """");
end

function pipInstall_(pyExe, packages, proxy)
    if isempty(packages)
        logInfo("installPython: no packages configured -- skipping pip install.");
        return;
    end
    proxyArg = proxyArg_(proxy);
    for p = packages
        logInfo("installPython: pip install %s", p);
        cmd = """" + pyExe + """ -m pip install " + proxyArg + p;
        rc  = system(cmd);
        if rc ~= 0
            logWarn("installPython: pip install failed for %s (exit %d).", p, rc);
        end
    end
end

function arg = proxyArg_(proxy)
    if strlength(strtrim(proxy)) > 0
        arg = "--proxy " + proxy + " ";
    else
        arg = "";
    end
end

function enableSitePackages_(envDir, pyVer)
% Uncomment 'import site' in pythonNNN._pth so pip-installed packages resolve.
% The embeddable package ships this line commented out by default.
    tag = "python" + replace(pyVer, ".", "") + "._pth";
    pthFiles = dir(fullfile(envDir, tag));
    if isempty(pthFiles)
        pthFiles = dir(fullfile(envDir, "python*._pth"));
    end
    if isempty(pthFiles)
        logWarn("installPython: no ._pth file found; site-packages may be disabled.");
        return;
    end
    pthPath = fullfile(envDir, pthFiles(1).name);
    txt = string(fileread(pthPath));
    txt = replace(txt, "#import site", "import site");
    fid = fopen(pthPath, "w");
    fwrite(fid, char(txt));
    fclose(fid);
    logInfo("installPython: enabled site-packages in %s", pthFiles(1).name);
end

function fullVer = resolveFullVersion_(pyVer)
% Map a "major.minor" to a concrete patch for the embeddable download.
% Projects that need a different patch should pin the full version in
% settings.json (python.version = "3.10.11").
    if count(pyVer, ".") >= 2
        fullVer = pyVer;   % already a full version
        return;
    end
    switch pyVer
        case "3.10"; fullVer = "3.10.11";
        case "3.11"; fullVer = "3.11.9";
        case "3.12"; fullVer = "3.12.7";
        otherwise
            fullVer = pyVer + ".0";
            logWarn("installPython: no known patch for %s; trying %s.", pyVer, fullVer);
    end
end
