function warnManifestChange(session, cfg)
% warnManifestChange  Warn when a duplicate folder changed outside its hash core.

    arguments
        session (1,1) struct
        cfg (1,1) struct
    end

    if ~isfield(session, "unit") || string(session.unit) ~= "folder" || ...
            ~isfield(session, "manifest")
        return
    end
    sidecarPath = elab.io.findElabSidecar(cfg.watch.processed_dir, session.hash);
    if sidecarPath == ""
        return
    end
    try
        payload = jsondecode(fileread(sidecarPath));
    catch
        return
    end
    if isfield(payload, "data_file_manifest_hash") && ...
            string(payload.data_file_manifest_hash) ~= string(session.manifest.fullHash)
        logWarn("watchAndLog: a duplicate folder changed outside the acquisition hash core");
    end
end
