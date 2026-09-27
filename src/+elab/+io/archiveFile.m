function archivedPath = archiveFile(filePath, destDir, mode, opts)
% archiveFile  Move, copy, or leave an ingested file without overwriting.
%
%   archivedPath = elab.io.archiveFile(filePath, destDir, mode)
%
%   An image metadata sidecar named <base>_meta.txt follows the data file
%   and receives the same collision suffix.

    arguments
        filePath (1,1) string
        destDir  (1,1) string
        mode     (1,1) string
        opts.timestamp (1,1) string = ""
        opts.name (1,1) string = ""
    end

    if ~ismember(mode, ["move", "copy", "leave"])
        error("elab:io:archiveFile:invalidMode", ...
            "mode must be one of: move, copy, leave.");
    end
    if mode == "leave"
        archivedPath = "";
        return
    end
    if ~isfolder(destDir)
        mkdir(destDir);
    end
    if isfolder(filePath)
        archivedPath = localArchiveFolder(filePath, destDir, mode, opts);
        return
    end

    [sourceDir, base, ext] = fileparts(filePath);
    sourceMeta = fullfile(sourceDir, base + "_meta.txt");
    hasMeta = isfile(sourceMeta);
    targetBase = base;
    targetPath = fullfile(destDir, targetBase + ext);
    targetMeta = fullfile(destDir, targetBase + "_meta.txt");
    if isfile(targetPath) || (hasMeta && isfile(targetMeta))
        timestamp = opts.timestamp;
        if timestamp == ""
            timestamp = string(datetime("now"), "yyyyMMdd'T'HHmmss");
        end
        targetBase = base + "__" + timestamp;
        targetPath = fullfile(destDir, targetBase + ext);
        targetMeta = fullfile(destDir, targetBase + "_meta.txt");
        suffix = 1;
        while isfile(targetPath) || (hasMeta && isfile(targetMeta))
            suffix = suffix + 1;
            targetBase = base + "__" + timestamp + "_" + suffix;
            targetPath = fullfile(destDir, targetBase + ext);
            targetMeta = fullfile(destDir, targetBase + "_meta.txt");
        end
    end

    if mode == "move"
        movefile(filePath, targetPath);
        if hasMeta
            movefile(sourceMeta, targetMeta);
        end
    else
        copyfile(filePath, targetPath);
        if hasMeta
            copyfile(sourceMeta, targetMeta);
        end
    end
    archivedPath = string(targetPath);
end

function archivedPath = localArchiveFolder(filePath, destDir, mode, opts)
    sourceName = string(char(java.io.File(char(filePath)).getName()));
    targetName = opts.name;
    if targetName == ""
        targetName = sourceName;
    end
    targetPath = fullfile(destDir, targetName);
    if isfolder(targetPath) || isfile(targetPath)
        timestamp = opts.timestamp;
        if timestamp == ""
            timestamp = string(datetime("now"), "yyyyMMdd'T'HHmmss");
        end
        targetName = targetName + "__" + timestamp;
        targetPath = fullfile(destDir, targetName);
        suffix = 1;
        while isfolder(targetPath) || isfile(targetPath)
            suffix = suffix + 1;
            targetPath = fullfile(destDir, targetName + "_" + suffix);
        end
    end
    if mode == "move"
        movefile(filePath, targetPath);
    else
        copyfile(filePath, targetPath);
    end
    archivedPath = string(targetPath);
end
