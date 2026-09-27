function fields = sessionFields(session, binding, cfg, kitInfo, quickLookProfile, opts)
% sessionFields  Build session metadata fields without contacting a server.
%
%   fields = elab.pipeline.sessionFields(session, binding, cfg, kitInfo, quickLookProfile).

    arguments
        session (1,1) struct
        binding
        cfg (1,1) struct
        kitInfo (1,1) struct
        quickLookProfile (1,1) string
        opts.loggedAt (1,1) datetime = datetime("now")
        opts.anynmrVersion (1,1) string = ""
        opts.provenanceFile (1,1) string = ""
    end
    groups = elab.util.fieldGroups(cfg);
    parameterFields = elab.util.withoutCanonicalFields(session.parsed.params);
    canonicalNames = ["sample_id", "instrument_title", "operator", "project"];
    measurementFields = repmat(elab.util.fieldStruct("", "", "text", groups.measurement), 1, 0);
    for name = canonicalNames
        value = "";
        type = "text";
        if ~isempty(binding) && isfield(binding, name) && strlength(string(binding.(name))) > 0
            value = binding.(name);
        else
            hit = find(string({parameterFields.name}) == name, 1);
            if ~isempty(hit)
                value = parameterFields(hit).value;
                type = string(parameterFields(hit).type);
            end
        end
        if strlength(string(value)) > 0
            measurementFields(end + 1) = elab.util.fieldStruct(name, value, type, ...
                groups.measurement); %#ok<AGROW>
        end
    end
    if session.acquiredAtSource ~= "unknown"
        measurementFields(end + 1) = elab.util.fieldStruct("acquired_at", ...
            string(session.acquiredAt, "yyyy-MM-dd'T'HH:mm"), "datetime-local", ...
            groups.measurement); %#ok<AGROW>
    end
    measurementFields = [measurementFields, ...
        elab.util.fieldStruct("acquired_at_source", session.acquiredAtSource, "text", groups.measurement), ...
        elab.util.fieldStruct("timezone", session.timezone, "text", groups.measurement), ...
        elab.util.fieldStruct("run_minutes", session.runMinutes, "number", groups.measurement), ...
        elab.util.fieldStruct("run_minutes_source", session.runMinutesSource, "text", groups.measurement)];
    parameterNames = string({parameterFields.name});
    parameterFields = parameterFields(~ismember(parameterNames, canonicalNames));
    if isempty(parameterFields)
        parameterFields = repmat(elab.util.fieldStruct("", "", "text", ...
            groups.instrumentParams), 1, 0);
    else
        for k = 1:numel(parameterFields)
            parameterFields(k).group = groups.instrumentParams;
        end
    end
    provenanceFields = elab.util.provenanceFields(session, kitInfo, quickLookProfile, ...
        groups.provenance, loggedAt=opts.loggedAt, includeSessionContext=true, ...
        anynmrVersion=opts.anynmrVersion, provenanceFile=opts.provenanceFile);
    fields = [measurementFields, parameterFields, provenanceFields];
end
