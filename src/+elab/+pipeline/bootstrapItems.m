function bootstrapItems(client, cfg, opts)
% bootstrapItems  One-time setup: create the Instrument / Consumable database
%   items this project uses, and check that the required experiment and
%   resource categories already exist in the target eLabFTW.
%
%   elab.pipeline.bootstrapItems(client, cfg)
%   elab.pipeline.bootstrapItems(client, cfg, instrumentsCsv=..., consumablesCsv=...)
%
%   Seed rows are read from CSV master data (see data/list/*.example.csv):
%     instruments : title,model,location,calibration_due[,item_type]
%     consumables : title,quantity,reorder_threshold,unit

    arguments
        client
        cfg (1,1) struct
        opts.instrumentsCsv (1,1) string = string(fullfile("data", "list", "instruments.csv"))
        opts.consumablesCsv (1,1) string = string(fullfile("data", "list", "consumables.csv"))
    end

    % --- 1. sanity-check the structure ---
    needCats = [cfg.elab.session_category, cfg.elab.qc_category, cfg.elab.report_category];
    needTypes = [cfg.elab.instrument_category, cfg.elab.sample_category, ...
        cfg.elab.consumable_category, cfg.elab.sop_category];
    for name = string(needCats)
        localCheck(client, "experiments_categories", name);
    end
    for name = needTypes
        localCheck(client, "resources_categories", name);
    end
    % --- 2. instruments ---
    Ti = table();
    instrumentTypes = strings(0, 1);
    if isfile(opts.instrumentsCsv)
        Ti = readtable(opts.instrumentsCsv, "TextType", "string", "Delimiter", ",");
        localRequireInstrumentColumns(Ti, opts.instrumentsCsv);
        instrumentTypes = localInstrumentTypes(Ti, opts.instrumentsCsv, cfg);
    end
    statusIds = elab.client.ensureConfiguredItemStatuses(client, cfg, [ ...
        "instrument_status_ok", "instrument_status_check", ...
        "instrument_status_calibration_overdue", ...
        "consumable_status_ok", "consumable_status_reorder"]);
    if ~isempty(Ti)
        for k = 1:height(Ti)
            r = Ti(k, :);
            if contains(string(r.title), " ")
                logWarn("bootstrapItems: instrument title '%s' contains spaces; use an individual asset ID.", r.title);
            end
            [id, created] = elab.client.ensureItem(client, instrumentTypes(k), r.title, [ ...
                elab.util.fieldStruct("model", r.model, "text"), ...
                elab.util.fieldStruct("location", r.location, "text"), ...
                elab.util.fieldStruct("calibration_due", r.calibration_due, "date"), ...
                elab.util.fieldStruct("usage_minutes_total", 0, "number"), ...
                elab.util.fieldStruct("usage_hours_total", 0, "number"), ...
                elab.util.fieldStruct("last_used", "", "datetime-local"), ...
                elab.util.fieldStruct("days_to_calibration", "", "number")]);
            if created
                localAssignStatus(client, id, statusIds.instrument_status_ok);
            end
            logInfo("bootstrapItems: instrument #%d  %s", id, r.title);
        end
    else
        logWarn("bootstrapItems: %s not found; skipping instruments", opts.instrumentsCsv);
    end

    % --- 3. consumables ---
    if isfile(opts.consumablesCsv)
        Tc = readtable(opts.consumablesCsv, "TextType", "string", "Delimiter", ",");
        for k = 1:height(Tc)
            r = Tc(k, :);
            [id, created] = elab.client.ensureItem(client, ...
                cfg.elab.consumable_category, r.title, [ ...
                elab.util.fieldStruct("quantity", r.quantity, "number"), ...
                elab.util.fieldStruct("reorder_threshold", r.reorder_threshold, "number"), ...
                elab.util.fieldStruct("unit", r.unit, "text")]);
            if created
                localAssignStatus(client, id, statusIds.consumable_status_ok);
            end
            logInfo("bootstrapItems: consumable #%d  %s", id, r.title);
        end
    else
        logWarn("bootstrapItems: %s not found; skipping consumables", opts.consumablesCsv);
    end

    logInfo("bootstrapItems: done");
end

function localRequireInstrumentColumns(instruments, csvPath)
    required = ["title", "model", "location", "calibration_due"];
    names = string(instruments.Properties.VariableNames);
    missing = required(~ismember(required, names));
    if ~isempty(missing)
        error("elab:pipeline:bootstrapItems:missingColumn", ...
            "CSV %s is missing required column %s.", csvPath, missing(1));
    end
end

function itemTypes = localInstrumentTypes(instruments, csvPath, cfg)
    itemTypes = strings(height(instruments), 1);
    hasCompatibilityColumn = ismember("item_type", ...
        string(instruments.Properties.VariableNames));
    for k = 1:height(instruments)
        value = missing;
        if hasCompatibilityColumn
            value = instruments.item_type(k);
        end
        itemTypes(k) = elab.io.resolveConfiguredItemType( ...
            string(csvPath), k + 1, "item_type", value, ...
            "elab.instrument_category", cfg.elab.instrument_category);
    end
end

function localAssignStatus(client, itemId, statusId)
    if isnan(statusId)
        return
    end
    try
        client.patchJson("items", itemId, struct("status", statusId));
    catch exception
        logWarn("bootstrapItems: item #%d status was not changed: %s", ...
            itemId, exception.message);
    end
end

function localCheck(client, endpoint, name)
    try
        elab.client.resolveId(client, endpoint, name);
        logInfo("bootstrapItems: %s OK -- %s", endpoint, name);
    catch
        logWarn("bootstrapItems: %s MISSING -- '%s' (create it in the admin panel)", endpoint, name);
    end
end
