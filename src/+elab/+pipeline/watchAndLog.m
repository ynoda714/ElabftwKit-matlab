function results = watchAndLog(client, cfg, opts)
% watchAndLog  Scenario A1: assemble the standard session-ingest workflow.
%
%   results = elab.pipeline.watchAndLog(client, cfg, opts) scans the inbox,
%   invokes independently callable session stages, and returns one record per file.

    arguments
        client
        cfg (1,1) struct
        opts.sourceLocator (1,1) function_handle = @elab.io.sourceLocation
        opts.timezoneResolver (1,1) function_handle = @elab.util.resolveTimezone
        opts.sidecarWriter (1,1) function_handle = @elab.io.writeElabSidecar
        opts.spectrumReader (1,1) function_handle = @elab.io.readBrukerSpectrum
    end
    inbox = string(cfg.watch.inbox_dir);
    for folder = [inbox, string(cfg.watch.processed_dir), string(cfg.watch.failed_dir)]
        if ~isfolder(folder)
            mkdir(folder);
        end
    end
    if isfield(cfg, "run") && isfield(cfg.run, "root_dir")
        runDir = makeRunDir("BaseDir", cfg.run.root_dir);
    else
        runDir = makeRunDir();
    end
    kitInfo = elab.util.kitVersion();
    maps = elab.pipeline.readBindingMaps(cfg);
    files = [elab.io.listInbox(inbox); elab.io.listExperimentFolders(inbox)];
    files = files(~localIsArchivedPath(files, cfg));
    statusIds = elab.client.ensureConfiguredItemStatuses(client, cfg, [ ...
        "instrument_status_ok", "instrument_status_calibration_overdue", ...
        "consumable_status_ok", "consumable_status_reorder"]);
    results = repmat(struct("file", "", "status", "", "experimentId", NaN, "message", ""), 0, 1);
    for k = 1:numel(files)
        filePath = files(k);
        [fileName, ~] = elab.io.unitName(filePath, inbox);
        logInfo("watchAndLog: [%d/%d] %s", k, numel(files), fileName);
        binding = elab.pipeline.matchBinding(maps, fileName);
        record = struct("file", fileName, "status", "", "experimentId", NaN, "message", "");
        try
            session = elab.pipeline.readSessionFile(filePath, cfg, spectrumReader=opts.spectrumReader);
            existingId = elab.pipeline.findLoggedSession(client, cfg, session);
            if ~isempty(existingId)
                record.status = "skipped";
                record.experimentId = existingId;
                record.message = "already logged";
                elab.pipeline.warnManifestChange(session, cfg);
                elab.pipeline.archiveIngested(filePath, "skipped", cfg);
                results(end + 1) = record; %#ok<AGROW>
                continue
            end
            session = elab.pipeline.addSessionContext(session, cfg, ...
                sourceLocator=opts.sourceLocator, timezoneResolver=opts.timezoneResolver);
            [experimentId, ~] = elab.pipeline.createSessionExperiment( ...
                client, cfg, session, binding, runDir, kitInfo);
            [instrumentId, ~] = elab.pipeline.linkSessionItems(client, cfg, experimentId, binding);
            if ~isempty(instrumentId)
                elab.pipeline.updateInstrumentLedger(client, cfg, instrumentId, session.runMinutes, statusIds=statusIds);
            end
            if ~isempty(binding) && isfield(binding, "consumable_title") && ...
                    strlength(string(binding.consumable_title)) > 0
                quantity = double(string(binding.consumable_qty));
                if isnan(quantity)
                    quantity = 1;
                end
                elab.pipeline.consumeInventory(client, cfg, string(binding.consumable_title), ...
                    quantity, statusIds=statusIds);
            end
            archivedPath = elab.pipeline.archiveIngested(filePath, "logged", cfg);
            elab.pipeline.writeSessionSidecar(session, experimentId, cfg, kitInfo, ...
                archivedPath, runDir, sidecarWriter=opts.sidecarWriter);
            record.status = "logged";
            record.experimentId = experimentId;
            record.message = sprintf("%s/experiments.php?mode=view&id=%d", cfg.elab.base_url, experimentId);
        catch exception
            record.status = "failed";
            record.message = exception.message;
            elab.pipeline.archiveIngested(filePath, "failed", cfg);
        end
        results(end + 1) = record; %#ok<AGROW>
    end
    localWriteSummary(results, runDir);
    localLogSummary(results);
end

function excluded = localIsArchivedPath(paths, cfg)
    excluded = false(size(paths));
    archiveRoots = [string(cfg.watch.processed_dir), string(cfg.watch.failed_dir)];
    for k = 1:numel(paths)
        candidate = localNormalizePath(localAbsolutePath(paths(k)));
        for root = archiveRoots
            normalizedRoot = localNormalizePath(localAbsolutePath(root));
            prefix = normalizedRoot + "\";
            if startsWith(candidate, prefix, IgnoreCase=ispc)
                excluded(k) = true;
                break
            end
        end
    end
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

function localWriteSummary(results, runDir)
    if isempty(results)
        return
    end
    writetable(struct2table(results, "AsArray", true), fullfile(runDir, "watch_summary.csv"));
end

function localLogSummary(results)
    logInfo("watchAndLog: %d file(s)", numel(results));
    for k = 1:numel(results)
        logInfo("  [%s] %s  %s", results(k).status, results(k).file, results(k).message);
    end
end
