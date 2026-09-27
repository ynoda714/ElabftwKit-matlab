function results = qcInbox(client, cfg)
% qcInbox  Process one pass over the dedicated QC inbox.
%
%   results = elab.pipeline.qcInbox(client, cfg)

    arguments
        client
        cfg (1,1) struct
    end

    inbox = string(cfg.qc.inbox_dir);
    processed = string(cfg.watch.processed_dir);
    failed = string(cfg.watch.failed_dir);
    for folder = [inbox, processed, failed]
        if ~isfolder(folder)
            mkdir(folder);
        end
    end

    specs = elab.io.readQcSpecs(string(cfg.qc.spec_list), cfg);
    files = elab.io.listInbox(inbox);
    kitInfo = elab.util.kitVersion();
    statusIds = elab.client.ensureConfiguredItemStatuses(client, cfg, [ ...
        "instrument_status_check", "instrument_status_ok"]);
    results = repmat(struct("file", "", "status", "", "qcResult", "", ...
        "experimentId", NaN, "message", ""), 0, 1);

    for k = 1:numel(files)
        filePath = files(k);
        [~, fileBase, fileExt] = fileparts(filePath);
        fileName = fileBase + fileExt;
        spec = localMatchSpec(specs, fileName);
        record = struct("file", fileName, "status", "", "qcResult", "", ...
            "experimentId", NaN, "message", "");

        if isempty(spec)
            record.status = "no_spec";
            record.message = "no matching QC specification";
            logWarn("qcInbox: no QC specification for %s; file left in inbox", ...
                fileName);
            results(end + 1) = record; %#ok<AGROW>
            continue
        end

        try
            fileHash = elab.util.fileHash(filePath);
            existing = elab.client.findExperimentByExtraField(client, ...
                "experiments", "data_file_hash", string(fileHash), ...
                category=cfg.elab.qc_category);
            if ~isempty(existing)
                record.status = "skipped";
                record.experimentId = existing;
                record.message = "already recorded as a QC experiment";
                elab.pipeline.archiveIngested(filePath, "skipped", cfg);
            else
                [pass, expId] = elab.pipeline.qcCheck(client, cfg, filePath, spec, ...
                    statusIds=statusIds, kitInfo=kitInfo);
                record.status = "logged";
                record.qcResult = localQcResult(pass);
                record.experimentId = expId;
                record.message = sprintf("%s/experiments.php?mode=view&id=%d", ...
                    cfg.elab.base_url, expId);
                elab.pipeline.archiveIngested(filePath, "logged", cfg);
            end
        catch exception
            record.status = "failed";
            record.message = exception.message;
            elab.pipeline.archiveIngested(filePath, "failed", cfg);
        end
        results(end + 1) = record; %#ok<AGROW>
    end

    localLogSummary(results);
end

function spec = localMatchSpec(specs, fileName)
    spec = [];
    for k = 1:numel(specs)
        if contains(fileName, specs(k).matchSubstring, "IgnoreCase", true)
            spec = specs(k);
            return
        end
    end
end

function result = localQcResult(pass)
    if pass
        result = "pass";
    else
        result = "fail";
    end
end

function localLogSummary(results)
    logInfo("qcInbox: %d file(s)", numel(results));
    for k = 1:numel(results)
        logInfo("  [%s] %s  %s", ...
            results(k).status, results(k).file, results(k).message);
    end
end
