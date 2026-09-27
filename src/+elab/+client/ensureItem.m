function [id, created] = ensureItem(client, itemType, title, fields)
% ensureItem  Find a database item by exact title within its type, or create it.
%
%   id = elab.client.ensureItem(client, "Instrument", "XRD-01 Rigaku MiniFlex")
%   id = elab.client.ensureItem(client, "Instrument", "XRD-01 Rigaku MiniFlex", fieldsStruct)

    arguments
        client
        itemType (1,1) string
        title    (1,1) string
        fields   struct = struct([])
    end

    cfg = loadConfig();
    limit = cfg.elab.item_search_limit;
    typeId = elab.client.resolveId(client, "resources_categories", itemType);
    list = client.getJson("/items", {"cat", typeId, "q", title, "limit", limit});
    items = elab.util.toItems(list);

    id = [];
    for k = 1:numel(items)
        it = items{k};
        if isfield(it, "title") && strcmpi(string(it.title), title) && ...
                localHasCategory(it, typeId, itemType)
            id = double(it.id);
            break
        end
    end

    created = isempty(id);
    if ~created && numel(items) >= limit
        logWarn("ensureItem: search returned the configured limit of %d entries; " + ...
            "the exact title match may not be unique", limit);
    end
    if created && numel(items) >= limit
        error("elab:client:ensureItem:truncated", ...
            ["Item search returned the configured limit of %d entries without an " + ...
            "exact match. Increase elab.item_search_limit and retry."], limit);
    end
    if created
        id = client.createEntry("items", struct());
        client.patchJson("items", id, struct("title", title, "category", typeId));
    end

    item = client.getJson("/items/" + id);
    if ~localHasCategory(item, typeId, itemType)
        error("elab:client:ensureItem:categoryMismatch", ...
            "Item %d does not belong to resource category '%s' (id %d).", ...
            id, itemType, typeId);
    end

    if created && ~isempty(fieldnames(fields))
        elab.client.setExtraFields(client, "items", id, fields);
    elseif ~created && ~isempty(fieldnames(fields))
        logInfo("ensureItem: existing item #%d '%s'; supplied fields were not written", ...
            id, title);
    end
end

function tf = localHasCategory(item, typeId, itemType)
    tf = false;
    if ~isstruct(item)
        return
    end
    if isfield(item, "category_title")
        tf = strcmpi(string(item.category_title), itemType);
    elseif isfield(item, "category")
        tf = isequal(double(item.category), typeId);
    elseif isfield(item, "category_id")
        tf = isequal(double(item.category_id), typeId);
    end
end
