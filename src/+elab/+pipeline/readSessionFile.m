function session = readSessionFile(filePath, cfg, opts)
% readSessionFile  Parse one measurement file without contacting a server.
%
%   session = elab.pipeline.readSessionFile(filePath, cfg) returns file and parse data.

    arguments
        filePath (1,1) string
        cfg (1,1) struct
        opts.timezoneResolver (1,1) function_handle = @elab.util.resolveTimezone
        opts.spectrumReader (1,1) function_handle = @elab.io.readBrukerSpectrum
    end
    [folder, baseName, extension] = fileparts(filePath);
    [parsed, info] = elab.io.parseAny(filePath);
    if isfolder(filePath)
        baseName = localFolderBaseName(filePath);
        manifest = elab.io.experimentManifest(filePath);
        [acquiredAt, acquiredAtSource] = elab.io.readAcquiredAt( ...
            filePath, parsed, timezone=opts.timezoneResolver(cfg));
        [runMinutes, runMinutesSource] = elab.io.readRunMinutes( ...
            parsed, cfg.watch.nominal_run_minutes);
        try
            parsed.spectrum = opts.spectrumReader(filePath);
        catch exception
            logWarn("readSessionFile: NMR preview was skipped: %s", ...
                replace(string(exception.message), filePath, "<folder>"));
        end
        [fileName, ~] = elab.io.unitName(filePath, cfg.watch.inbox_dir);
        session = struct("filePath", string(filePath), "fileName", fileName, ...
            "baseName", string(baseName), "folder", string(folder), "parsed", parsed, "info", info, ...
            "hash", string(manifest.coreHash), "acquiredAt", acquiredAt, ...
            "acquiredAtSource", string(acquiredAtSource), "runMinutes", runMinutes, ...
            "runMinutesSource", string(runMinutesSource), "unit", "folder", "manifest", manifest);
    else
        [acquiredAt, acquiredAtSource] = elab.io.readAcquiredAt(filePath, parsed);
        [runMinutes, runMinutesSource] = elab.io.readRunMinutes(parsed, cfg.watch.nominal_run_minutes);
        session = struct("filePath", string(filePath), ...
            "fileName", string(baseName + extension), "baseName", string(baseName), ...
            "folder", string(folder), "parsed", parsed, "info", info, ...
            "hash", string(elab.util.fileHash(filePath)), "acquiredAt", acquiredAt, ...
            "acquiredAtSource", string(acquiredAtSource), "runMinutes", runMinutes, ...
            "runMinutesSource", string(runMinutesSource), "unit", "file");
    end
end

function name = localFolderName(path, inbox, baseName)
    absolutePath = localAbsolutePath(path);
    absoluteInbox = localAbsolutePath(inbox);
    normalizedPath = localNormalizePath(absolutePath);
    normalizedInbox = localNormalizePath(absoluteInbox);
    prefix = normalizedInbox + "\";
    if startsWith(normalizedPath, prefix, IgnoreCase=ispc)
        name = extractAfter(normalizedPath, strlength(prefix));
        name = replace(name, "\", "/");
    else
        name = string(baseName);
    end
end

function name = localFolderBaseName(path)
    file = java.io.File(char(path));
    name = string(char(file.getName()));
end

function path = localAbsolutePath(value)
    file = java.io.File(char(value));
    path = string(char(file.getAbsolutePath()));
end

function path = localNormalizePath(value)
    path = replace(string(value), "/", "\");
    while strlength(path) > 3 && endsWith(path, "\")
        path = extractBefore(path, strlength(path));
    end
end
