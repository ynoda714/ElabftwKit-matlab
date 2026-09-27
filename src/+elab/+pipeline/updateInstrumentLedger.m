function updateInstrumentLedger(client, cfg, instrumentId, sessionMinutes, opts)
% updateInstrumentLedger  Scenario D1: bump usage minutes / display hours / last-used /
%   calibration countdown on an Instrument database item.
%
%   elab.pipeline.updateInstrumentLedger(client, cfg, instrumentId, sessionMinutes)

    arguments
        client
        cfg            (1,1) struct
        instrumentId   (1,1) double
        sessionMinutes (1,1) double = 0
        opts.statusIds (1,1) struct = struct()
    end

    item = client.getJson(sprintf("/items/%d", instrumentId));
    hasNativeStatus = localHasNativeStatus(item);
    [ef, hasMetadata] = localMeta(item);
    [previousMinutes, minutesState] = localMinutes(ef);
    if minutesState == "invalid"
        error("elab:pipeline:updateInstrumentLedger:invalidMinutes", ...
            "Instrument #%d has a nonnumeric usage_minutes_total value.", instrumentId);
    end
    if hasMetadata && minutesState == "missing"
        elab.client.addExtraField(client, "items", instrumentId, ...
            "usage_minutes_total", 0, "number");
        localWarnMigration(instrumentId, ef);
    elseif minutesState == "empty"
        localWarnMigration(instrumentId, ef);
    end

    minutes = previousMinutes + sessionMinutes;
    hours = round(minutes / 60, 2);
    fields = [ ...
        elab.util.fieldStruct("usage_minutes_total", minutes, "number"), ...
        elab.util.fieldStruct("usage_hours_total", hours, "number"), ...
        elab.util.fieldStruct("last_used", datetime("now"), "datetime-local")];

    calDue = localTxt(ef, "calibration_due", "");
    overdue = false;
    if calDue ~= ""
        try
            dleft = floor(days(datetime(calDue) - datetime("today")));
            fields(end + 1) = elab.util.fieldStruct("days_to_calibration", dleft, "number");
            if dleft < 0
                overdue = true;
            end
        catch
        end
    end

    elab.client.updateExtraFields(client, "items", instrumentId, fields, missing="warn");
    if overdue
        statusKey = "instrument_status_calibration_overdue";
        localAssignStatus(client, cfg, instrumentId, statusKey, opts.statusIds);
    elseif ~hasNativeStatus
        statusKey = "instrument_status_ok";
        localAssignStatus(client, cfg, instrumentId, statusKey, opts.statusIds);
    end
end

function localAssignStatus(client, cfg, instrumentId, key, statusIds)
    if ~isfield(statusIds, key)
        statusIds = elab.client.ensureConfiguredItemStatuses(client, cfg, key);
    end
    if isnan(statusIds.(key))
        return
    end
    try
        client.patchJson("items", instrumentId, struct("status", statusIds.(key)));
    catch exception
        logWarn("updateInstrumentLedger: instrument #%d status was not changed: %s", ...
            instrumentId, exception.message);
    end
end

function tf = localHasNativeStatus(item)
    tf = false;
    if ~isstruct(item)
        return
    end
    if isfield(item, "status") && ~isempty(item.status)
        value = double(item.status);
        tf = isscalar(value) && ~isnan(value);
    end
    if ~tf && isfield(item, "status_title") && ~isempty(item.status_title)
        tf = strlength(string(item.status_title)) > 0;
    end
end

function [ef, hasMetadata] = localMeta(item)
    ef = struct();
    hasMetadata = isfield(item, "metadata") && ~isempty(item.metadata) && ...
        strlength(string(item.metadata)) > 0;
    if hasMetadata
        try
            ef = jsondecode(item.metadata);
        catch
        end
    end
end

function [value, state] = localMinutes(ef)
    value = 0;
    state = "missing";
    if ~isstruct(ef) || ~isfield(ef, "extra_fields") || ...
            ~isstruct(ef.extra_fields) || ...
            ~isfield(ef.extra_fields, "usage_minutes_total")
        return
    end
    field = ef.extra_fields.usage_minutes_total;
    if ~isstruct(field) || ~isfield(field, "value")
        state = "empty";
        return
    end
    raw = field.value;
    if (~ischar(raw) && ~isstring(raw) && isempty(raw)) || ...
            ((ischar(raw) || isstring(raw)) && strlength(string(raw)) == 0)
        state = "empty";
        return
    end
    parsed = str2double(string(raw));
    if ~isscalar(parsed) || isnan(parsed)
        state = "invalid";
        return
    end
    value = parsed;
    state = "numeric";
end

function localWarnMigration(instrumentId, ef)
    priorHours = localTxt(ef, "usage_hours_total", "(missing)");
    if strlength(priorHours) == 0
        priorHours = "(empty)";
    end
    logWarn( ...
        "updateInstrumentLedger: instrument #%d had no usage_minutes_total; " + ...
        "counting from this session (usage_hours_total %s was not carried over)", ...
        instrumentId, priorHours);
end

function v = localTxt(ef, name, default)
    v = string(default);
    if isstruct(ef) && isfield(ef, "extra_fields") && ...
            isstruct(ef.extra_fields) && isfield(ef.extra_fields, name) && ...
            isstruct(ef.extra_fields.(name)) && ...
            isfield(ef.extra_fields.(name), "value") && ...
            ~isempty(ef.extra_fields.(name).value)
        v = string(ef.extra_fields.(name).value);
    end
end
