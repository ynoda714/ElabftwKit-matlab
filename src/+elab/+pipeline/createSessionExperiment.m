function [experimentId, png] = createSessionExperiment(client, cfg, session, binding, runDir, kitInfo, opts)
% createSessionExperiment  Create, populate, and attach one session experiment.
%
%   [experimentId, png] = elab.pipeline.createSessionExperiment(client, cfg, session, binding, runDir, kitInfo, extraFields=...).

    arguments
        client
        cfg (1,1) struct
        session (1,1) struct
        binding
        runDir (1,1) string
        kitInfo (1,1) struct
        opts.extraFields = struct([])
    end

    if isempty(binding)
        label = session.baseName;
        if isfield(session, "unit") && string(session.unit) == "folder"
            label = session.fileName;
        end
        tags = string(upper(session.info.technique));
    else
        label = string(binding.sample_id);
        if label == ""
            label = session.baseName;
            if isfield(session, "unit") && string(session.unit) == "folder"
                label = session.fileName;
            end
        end
        tags = [string(binding.project), string(binding.instrument_title), ...
            string(upper(session.info.technique))];
        tags = tags(strlength(tags) > 0);
    end
    body = sprintf("Auto-logged from %s by watchAndLog (%s).", session.fileName, ...
        string(datetime("now"), "yyyy-MM-dd HH:mm:ss"));
    options = {"status", cfg.elab.draft_status, "tags", tags, "body", body};
    if session.acquiredAtSource ~= "unknown"
        options = [options, {"date", string(session.acquiredAt, "yyyy-MM-dd")}]; %#ok<AGROW>
    end
    experimentId = elab.client.createExperiment(client, cfg.elab.session_category, ...
        sprintf("%s  %s", upper(session.info.technique), label), options{:});
    isFolderSession = session.info.format == "nmr_folder";
    png = "";
    profile = "none";
    hasNmrPreview = isFolderSession && isfield(session.parsed, "spectrum");
    if ~isFolderSession || hasNmrPreview
        png = string(fullfile(runDir, session.baseName + "_quicklook.png"));
    end
    title = string(sprintf("%s  %s", upper(session.info.technique), label));
    if session.acquiredAtSource ~= "unknown"
        title = title + "  " + string(session.acquiredAt, "yyyy-MM-dd HH:mm");
    end
    if ~isFolderSession || hasNmrPreview
        [~, profile] = elab.visualization.quickLook(session.info.format, ...
            session.parsed, png, title=title);
    end
    provenancePath = "";
    provenanceName = "";
    anynmrVersion = "";
    if hasNmrPreview
        [~, archiveName] = elab.io.unitName(session.filePath, cfg.watch.inbox_dir);
        provenanceName = archiveName + "_provenance.json";
        provenancePath = string(fullfile(runDir, provenanceName));
        info = elab.util.anynmrInfo(verify=true);
        if ~info.files_verified
            logWarn("createSessionExperiment: vendored AnyNMR files did not verify.");
        end
        document = elab.util.provenanceDocument(session, kitInfo, profile, anynmrInfo=info);
        elab.io.writeProvenanceJson(provenancePath, document);
        anynmrVersion = string(info.tag);
    end
    extraFields = opts.extraFields;
    if ~isempty(extraFields) && ~isfield(extraFields, "group")
        [extraFields.group] = deal(struct());
    end
    fields = [elab.pipeline.sessionFields(session, binding, cfg, kitInfo, profile, ...
        anynmrVersion=anynmrVersion, provenanceFile=provenanceName), extraFields];
    elab.client.setExtraFields(client, "experiments", experimentId, fields);
    [attachRaw, ~] = elab.io.shouldAttachRaw(session.filePath, cfg, pipeline="watchAndLog");
    if attachRaw
        client.uploadFile("experiments", experimentId, session.filePath, "raw instrument file");
    end
    if isFolderSession
        if hasNmrPreview
            client.uploadFile("experiments", experimentId, png, "quick look");
            client.uploadFile("experiments", experimentId, provenancePath, "provenance");
            try
                imageHtml = elab.client.uploadImageHtml(client, "experiments", experimentId, ...
                    session.baseName + "_quicklook.png", alt="quick look");
                client.patchJson("experiments", experimentId, struct("body", body + "<p>" + imageHtml + "</p>"));
            catch exception
                logWarn("watchAndLog: could not show the quick look in the body of #%d: %s", ...
                    experimentId, exception.message);
            end
        end
        return
    end
    client.uploadFile("experiments", experimentId, png, "quick look");
    try
        imageHtml = elab.client.uploadImageHtml(client, "experiments", experimentId, ...
            session.baseName + "_quicklook.png", alt="quick look");
        client.patchJson("experiments", experimentId, struct("body", body + "<p>" + imageHtml + "</p>"));
    catch exception
        logWarn("watchAndLog: could not show the quick look in the body of #%d: %s", ...
            experimentId, exception.message);
    end
end
