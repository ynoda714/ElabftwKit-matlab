function consumeInventory(client, cfg, consumableTitle, quantity, opts)
% consumeInventory  Scenario D2: decrement a Consumable item's quantity and
%   flag it for re-order once it reaches its threshold.
%
%   elab.pipeline.consumeInventory(client, cfg, consumableTitle, quantity)

    arguments
        client
        cfg             (1,1) struct
        consumableTitle (1,1) string
        quantity        (1,1) double = 1
        opts.statusIds  (1,1) struct = struct()
    end
    if isnan(quantity) || quantity <= 0
        return
    end

    id = elab.client.ensureItem(client, ...
        cfg.elab.consumable_category, consumableTitle);
    item = client.getJson(sprintf("/items/%d", id));
    hasNativeStatus = localHasNativeStatus(item);

    ef = struct();
    if isfield(item, "metadata") && ~isempty(item.metadata)
        try
            ef = jsondecode(item.metadata);
        catch
        end
    end

    qty = localNum(ef, "quantity", NaN);
    thr = localNum(ef, "reorder_threshold", 0);
    if isnan(qty)
        logWarn("consumeInventory: '%s' has no numeric 'quantity' extra field; skipping.", ...
            consumableTitle);
        return
    end

    qty = qty - quantity;
    if qty < 0
        logWarn("consumeInventory: '%s' is below zero (%g); more was used than the ledger held", ...
            consumableTitle, qty);
    end
    fields = elab.util.fieldStruct("quantity", qty, "number");
    reorder = qty <= thr;
    elab.client.updateExtraFields(client, "items", id, fields, missing="warn");
    if reorder
        statusKey = "consumable_status_reorder";
        localAssignStatus(client, cfg, id, statusKey, opts.statusIds);
    elseif ~hasNativeStatus
        statusKey = "consumable_status_ok";
        localAssignStatus(client, cfg, id, statusKey, opts.statusIds);
    end
    logInfo("consumeInventory: %s -> %g (reorder: %d)", consumableTitle, qty, reorder);
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
        logWarn("consumeInventory: item #%d status was not changed: %s", ...
            itemId, exception.message);
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

function v = localNum(ef, name, default)
    v = default;
    if isstruct(ef) && isfield(ef, "extra_fields") && ...
            isstruct(ef.extra_fields) && isfield(ef.extra_fields, name) && ...
            isstruct(ef.extra_fields.(name)) && ...
            isfield(ef.extra_fields.(name), "value")
        raw = ef.extra_fields.(name).value;
        if isempty(raw) && ~ischar(raw) && ~isstring(raw)
            return
        end
        x = str2double(string(raw));
        if isscalar(x) && ~isnan(x)
            v = x;
        end
    end
end
