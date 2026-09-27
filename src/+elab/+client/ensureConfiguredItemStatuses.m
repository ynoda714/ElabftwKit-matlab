function ids = ensureConfiguredItemStatuses(client, cfg, keys)
% ensureConfiguredItemStatuses  Resolve configured resource statuses once.
%
%   ids = elab.client.ensureConfiguredItemStatuses(client, cfg, keys)
%
%   The status list is fetched once. Missing definitions are created and
%   verified. Failures are warnings because status is secondary to the
%   measurement, ledger, or inventory record.

    arguments
        client
        cfg (1,1) struct
        keys (1,:) string
    end

    ids = struct();
    for key = keys
        ids.(key) = NaN;
    end

    try
        items = elab.util.toItems( ...
            client.getJson("/teams/current/items_status"));
    catch exception
        logWarn("resource statuses could not be listed; status was not changed: %s", ...
            exception.message);
        return
    end

    for key = keys
        [title, color] = localDefinition(cfg, key);
        try
            [ids.(key), items] = elab.client.ensureItemStatus( ...
                client, title, color, items=items);
        catch exception
            logWarn("resource status '%s' could not be prepared; status was not changed: %s", ...
                title, exception.message);
        end
    end
end

function [title, color] = localDefinition(cfg, key)
    if ~isfield(cfg.elab.labels, key)
        error("elab:client:ensureConfiguredItemStatuses:missingLabel", ...
            "Missing configured resource status label '%s'.", key);
    end
    title = string(cfg.elab.labels.(key));
    switch key
        case "instrument_status_ok"
            color = "28a745";
        case "instrument_status_check"
            color = "ffc107";
        case "instrument_status_calibration_overdue"
            color = "dc3545";
        case "consumable_status_ok"
            color = "28a745";
        case "consumable_status_reorder"
            color = "fd7e14";
        otherwise
            error("elab:client:ensureConfiguredItemStatuses:unknownKey", ...
                "Unknown resource status key '%s'.", key);
    end
end
