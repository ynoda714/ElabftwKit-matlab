function [pass, expId] = qcCheck(client, cfg, filePath, spec, opts)
% qcCheck  Evaluate and record one standard-sample measurement.
%
%   [pass, expId] = elab.pipeline.qcCheck(client, cfg, filePath, spec)
%
%   spec fields:
%     .instrumentTitle  (string)
%     .instrumentType   (string)
%     .metric           "max_intensity" | "peak_x" | "area_total"
%     .target           (double)
%     .tolerance        (double)

    arguments
        client
        cfg      (1,1) struct
        filePath (1,1) string
        spec     (1,1) struct
        opts.statusIds (1,1) struct = struct()
        opts.kitInfo (1,1) struct = struct()
    end

    allowedMetrics = ["max_intensity", "peak_x", "area_total"];
    if ~ismember(string(spec.metric), allowedMetrics)
        error("elab:pipeline:qcCheck:unknownMetric", ...
            "unknown metric '%s'", spec.metric);
    end

    kitInfo = opts.kitInfo;
    if isempty(fieldnames(kitInfo))
        kitInfo = elab.util.kitVersion();
    end

    [parsed, info] = elab.io.parseAny(filePath);
    [acquiredAt, acquiredAtSource] = elab.io.readAcquiredAt(filePath, parsed);
    if ~ismember(string(info.format), ["spectrum", "chromatogram"])
        error("elab:pipeline:qcCheck:unsupportedFormat", ...
            "QC metric '%s' does not support format '%s'.", ...
            spec.metric, info.format);
    end

    x = localX(parsed);
    y = localY(parsed);
    switch string(spec.metric)
        case "max_intensity"
            measured = max(y);
        case "peak_x"
            [~, ix] = max(y);
            measured = x(ix);
        case "area_total"
            measured = trapz(x, y);
    end

    dev = measured - spec.target;
    pass = abs(dev) <= spec.tolerance;
    if pass
        verdict = "PASS";
        qcResult = "pass";
    else
        verdict = "FAIL";
        qcResult = "fail";
    end

    instrId = elab.client.ensureItem(client, ...
        string(spec.instrumentType), string(spec.instrumentTitle));
    currentStatus = "";
    if pass
        instrument = client.getJson("/items/" + instrId);
        currentStatus = localStatusValue(instrument);
    end

    [~, fileBase, fileExt] = fileparts(filePath);
    fileName = fileBase + fileExt;
    fileHash = elab.util.fileHash(filePath);
    if acquiredAtSource == "unknown"
        titleDate = string(datetime("today"), "yyyy-MM-dd");
    else
        titleDate = string(acquiredAt, "yyyy-MM-dd");
    end
    titleText = sprintf("QC %s  %s  %s", upper(info.technique), ...
        string(spec.instrumentTitle), titleDate);
    createOptions = {"status", cfg.elab.draft_status, ...
        "tags", [string(spec.instrumentTitle), string(cfg.elab.labels.qc_tag)]};
    if acquiredAtSource ~= "unknown"
        createOptions = [createOptions, {"date", titleDate}];
    end
    expId = elab.client.createExperiment(client, cfg.elab.qc_category, ...
        titleText, createOptions{:});

    groups = elab.util.fieldGroups(cfg);
    parameterFields = elab.util.withoutCanonicalFields(parsed.params);
    canonicalNames = ["sample_id", "instrument_title", "operator", "project"];
    measurementFields = repmat( ...
        elab.util.fieldStruct("", "", "text", groups.measurement), 1, 0);
    sampleHit = find(string({parameterFields.name}) == "sample_id", 1);
    if ~isempty(sampleHit)
        measurementFields(end + 1) = elab.util.fieldStruct( ...
            "sample_id", parameterFields(sampleHit).value, ...
            string(parameterFields(sampleHit).type), groups.measurement); %#ok<AGROW>
    end
    measurementFields(end + 1) = elab.util.fieldStruct( ...
        "instrument_title", spec.instrumentTitle, "text", groups.measurement);
    for canonicalName = ["operator", "project"]
        hit = find(string({parameterFields.name}) == canonicalName, 1);
        if ~isempty(hit)
            measurementFields(end + 1) = elab.util.fieldStruct( ...
                canonicalName, parameterFields(hit).value, ...
                string(parameterFields(hit).type), groups.measurement); %#ok<AGROW>
        end
    end
    if acquiredAtSource ~= "unknown"
        measurementFields(end + 1) = elab.util.fieldStruct("acquired_at", ...
            string(acquiredAt, "yyyy-MM-dd'T'HH:mm"), "datetime-local", ...
            groups.measurement);
    end
    measurementFields = [measurementFields, ...
        elab.util.fieldStruct("acquired_at_source", acquiredAtSource, ...
        "text", groups.measurement), ...
        elab.util.fieldStruct("metric", spec.metric, "text", groups.measurement), ...
        elab.util.fieldStruct("measured", measured, "number", groups.measurement), ...
        elab.util.fieldStruct("target", spec.target, "number", groups.measurement), ...
        elab.util.fieldStruct("deviation", dev, "number", groups.measurement), ...
        elab.util.fieldStruct("tolerance", spec.tolerance, "number", groups.measurement), ...
        elab.util.fieldStruct("qc_result", qcResult, "text", groups.measurement), ...
        elab.util.fieldStruct("qc_pass", logical(pass), "checkbox", groups.measurement)];
    parameterNames = string({parameterFields.name});
    parameterFields = parameterFields(~ismember(parameterNames, canonicalNames));
    for fieldIndex = 1:numel(parameterFields)
        parameterFields(fieldIndex).group = groups.instrumentParams;
    end
    provenanceSession = struct("fileName", string(fileName), "hash", string(fileHash), ...
        "info", info);
    provenanceFields = elab.util.provenanceFields(provenanceSession, kitInfo, ...
        "none", groups.provenance);
    fields = [measurementFields, parameterFields, provenanceFields];
    elab.client.setExtraFields(client, "experiments", expId, fields);
    [attachRaw, ~] = elab.io.shouldAttachRaw( ...
        filePath, cfg, pipeline="qcCheck");
    if attachRaw
        client.uploadFile("experiments", expId, filePath, "QC standard file");
    end
    client.linkTo("experiments", expId, "items", instrId);

    if ~pass
        localAssignStatus(client, cfg, instrId, ...
            "instrument_status_check", opts.statusIds);
    elseif currentStatus == string(cfg.elab.labels.instrument_status_check)
        localAssignStatus(client, cfg, instrId, ...
            "instrument_status_ok", opts.statusIds);
    else
        logInfo("qcCheck: instrument status is '%s'; QC passed and status was not changed", ...
            currentStatus);
    end

    logInfo("qcCheck %s: measured=%.4g target=%.4g dev=%.4g -> %s (exp #%d)", ...
        spec.metric, measured, spec.target, dev, verdict, expId);
end

function value = localStatusValue(item)
    value = "";
    if isstruct(item) && isfield(item, "status_title") && ...
            ~isempty(item.status_title)
        value = string(item.status_title);
    end
end

function localAssignStatus(client, cfg, itemId, key, statusIds)
    if ~isfield(statusIds, key)
        statusIds = elab.client.ensureConfiguredItemStatuses(client, cfg, key);
    end
    if isnan(statusIds.(key))
        return
    end
    try
        client.patchJson("items", itemId, struct("status", statusIds.(key)));
    catch exception
        logWarn("qcCheck: instrument #%d status was not changed: %s", ...
            itemId, exception.message);
    end
end

function value = localX(parsed)
    if isfield(parsed, "t")
        value = parsed.t;
    else
        value = parsed.x;
    end
end

function value = localY(parsed)
    if isfield(parsed, "intensity")
        value = parsed.intensity;
    else
        value = parsed.y;
    end
end
