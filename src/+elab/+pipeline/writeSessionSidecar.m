function writeSessionSidecar(session, experimentId, cfg, kitInfo, archivedPath, runDir, opts)
% writeSessionSidecar  Write a best-effort session sidecar after recording.
%
%   elab.pipeline.writeSessionSidecar(session, experimentId, cfg, kitInfo, archivedPath, runDir).

    arguments
        session (1,1) struct
        experimentId (1,1) double
        cfg (1,1) struct
        kitInfo (1,1) struct
        archivedPath (1,1) string
        runDir (1,1) string
        opts.sidecarWriter (1,1) function_handle = @elab.io.writeElabSidecar
    end
    dataUnit = "file";
    if isfield(session, "unit")
        dataUnit = string(session.unit);
    end
    if archivedPath == ""
        if dataUnit == "folder"
            [~, archiveName] = elab.io.unitName(session.filePath, cfg.watch.inbox_dir);
            dataPath = fullfile(runDir, archiveName);
        else
            dataPath = fullfile(runDir, session.fileName);
        end
    else
        dataPath = archivedPath;
    end
    acquiredAt = "";
    if session.acquiredAtSource ~= "unknown"
        acquiredAt = string(session.acquiredAt, "yyyy-MM-dd'T'HH:mm");
    end
    url = sprintf("%s/experiments.php?mode=view&id=%d", cfg.elab.base_url, experimentId);
    payload = struct("schema_version", elab.util.schemaVersion(), ...
        "source_path", session.source.source_path, "source_host", session.source.source_host, ...
        "source_mtime", session.source.source_mtime, "data_file_hash", session.hash, ...
        "data_unit", dataUnit, ...
        "metadata", session.parsed.params, "acquired_at", acquiredAt, ...
        "acquired_at_source", session.acquiredAtSource, "timezone", session.timezone, ...
        "experiment_id", experimentId, "experiment_url", string(url), ...
        "kit_version", kitInfo.version, "kit_commit", kitInfo.commit);
    if dataUnit == "folder"
        payload.data_file_manifest_hash = session.manifest.fullHash;
        payload.manifest = session.manifest.fullText;
        if isfield(session.parsed, "spectrum")
            archiveName = replace(string(session.fileName), "/", "_");
            payload.anynmr_version = elab.util.anynmrInfo().tag;
            payload.provenance_file = archiveName + "_provenance.json";
        end
    end
    try
        opts.sidecarWriter(dataPath, payload);
    catch exception
        logWarn("watchAndLog: could not write the eLab sidecar: %s", exception.message);
    end
end
