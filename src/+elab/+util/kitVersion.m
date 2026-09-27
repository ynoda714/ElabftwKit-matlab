function info = kitVersion(opts)
% kitVersion  Read the kit version and best-effort Git revision.

    arguments
        opts.projectRoot (1,1) string = ""
        opts.commandRunner (1,1) function_handle = @localRunCommand
    end

    projectRoot = opts.projectRoot;
    if projectRoot == ""
        projectRoot = string(fileparts(fileparts(fileparts(fileparts( ...
            mfilename("fullpath"))))));
    end
    versionPath = fullfile(projectRoot, "VERSION");
    if ~isfile(versionPath)
        error("elab:util:kitVersion:missingVersion", ...
            "VERSION was not found at %s.", versionPath);
    end
    versionLines = splitlines(strip(string(fileread(versionPath))));
    info = struct("version", versionLines(1), "commit", "");

    revisionCommand = sprintf('git -C "%s" rev-parse --short HEAD', projectRoot);
    [revisionStatus, revisionOutput] = opts.commandRunner(revisionCommand);
    if revisionStatus ~= 0
        return
    end
    revisionLines = splitlines(strip(string(revisionOutput)));
    if isempty(revisionLines) || strlength(revisionLines(1)) == 0
        return
    end

    statusCommand = sprintf('git -C "%s" status --porcelain', projectRoot);
    [statusStatus, statusOutput] = opts.commandRunner(statusCommand);
    if statusStatus ~= 0
        return
    end
    info.commit = revisionLines(1);
    if strlength(strip(string(statusOutput))) > 0
        info.commit = info.commit + "-dirty";
    end
end

function [status, output] = localRunCommand(command)
    [status, output] = system(command);
end
