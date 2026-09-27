function archivedPath = archiveIngested(filePath, outcome, cfg)
% archiveIngested  Apply the configured archive policy for one ingest outcome.
%
%   archivedPath = elab.pipeline.archiveIngested(filePath, outcome, cfg) returns the archive path or "".

    mode = localArchiveMode(cfg);
    [~, archiveName] = elab.io.unitName(filePath, cfg.watch.inbox_dir);
    archivedPath = "";
    switch string(outcome)
        case "logged"
            archivedPath = localArchive(filePath, cfg.watch.processed_dir, mode, archiveName);
        case "skipped"
            if mode == "move"
                archivedPath = localArchive(filePath, cfg.watch.processed_dir, mode, archiveName);
            end
        case "failed"
            if mode == "move"
                try
                    archivedPath = localArchive(filePath, cfg.watch.failed_dir, mode, archiveName);
                catch
                end
            end
        otherwise
            error("elab:pipeline:archiveIngested:invalidOutcome", ...
                "outcome must be logged, skipped, or failed.");
    end
end

function archivedPath = localArchive(filePath, destination, mode, archiveName)
    if isfolder(filePath)
        archivedPath = elab.io.archiveFile(filePath, destination, mode, name=archiveName);
    else
        archivedPath = elab.io.archiveFile(filePath, destination, mode);
    end
end

function mode = localArchiveMode(cfg)
    mode = "move";
    if isfield(cfg, "ingest") && isfield(cfg.ingest, "archive_mode")
        mode = string(cfg.ingest.archive_mode);
    end
    if ~ismember(mode, ["move", "copy", "leave"])
        error("elab:pipeline:archiveIngested:invalidArchiveMode", ...
            "cfg.ingest.archive_mode must be one of: move, copy, leave.");
    end
end
