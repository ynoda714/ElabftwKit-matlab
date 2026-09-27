function updateExtraFields(client, kind, id, fields, opts)
% updateExtraFields  Update existing eLabFTW extra-field values in place.
%
%   elab.client.updateExtraFields(client, "items", id, fields)
%   elab.client.updateExtraFields(client, "items", id, fields, missing="warn")
%
%   Existing metadata is never decoded and written back as a whole. Fields
%   that already exist are changed with one updatemetadatafield PATCH, then
%   read back to verify that the server applied every value. If the entry has
%   no metadata, setExtraFields initializes it because there is nothing to
%   preserve.

    arguments
        client
        kind (1,1) string
        id (1,1) double
        fields struct
        opts.missing (1,1) string {mustBeMember(opts.missing, ["error", "warn"])} = "error"
    end

    names = strings(1, numel(fields));
    values = strings(1, numel(fields));
    for k = 1:numel(fields)
        names(k) = string(fields(k).name);
        if ~isvarname(names(k))
            error("elab:client:updateExtraFields:invalidFieldName", ...
                "Extra-field name '%s' is not a valid MATLAB identifier.", names(k));
        end
        values(k) = string(elab.util.toElabValue(fields(k).value));
    end

    entry = client.getJson(sprintf("/%s/%d", kind, id));
    if ~isfield(entry, "metadata") || isempty(entry.metadata) || ...
            strlength(string(entry.metadata)) == 0
        elab.client.setExtraFields(client, kind, id, fields);
        localVerify(client, kind, id, names, values, 1:numel(fields));
        return
    end

    try
        metadata = jsondecode(entry.metadata);
    catch cause
        error("elab:client:updateExtraFields:invalidMetadata", ...
            "Cannot inspect metadata for %s item %d: %s", kind, id, cause.message);
    end

    present = false(1, numel(fields));
    if isstruct(metadata) && isfield(metadata, "extra_fields") && ...
            isstruct(metadata.extra_fields)
        for k = 1:numel(fields)
            present(k) = isfield(metadata.extra_fields, names(k));
        end
    end

    missingNames = names(~present);
    if ~isempty(missingNames) && opts.missing == "error"
        error("elab:client:updateExtraFields:fieldMissing", ...
            "Entry %s/%d has no extra field(s): %s", ...
            kind, id, strjoin(missingNames, ", "));
    elseif ~isempty(missingNames)
        logWarn("updateExtraFields: entry %s/%d has no extra field(s): %s; skipping them", ...
            kind, id, strjoin(missingNames, ", "));
    end

    if ~any(present)
        return
    end

    payload = struct("action", "updatemetadatafield");
    presentIndexes = find(present);
    for k = presentIndexes
        payload.(names(k)) = char(values(k));
    end
    client.patchJson(kind, id, payload);

    localVerify(client, kind, id, names, values, presentIndexes);
end

function localVerify(client, kind, id, names, values, indexes)
    updated = client.getJson(sprintf("/%s/%d", kind, id));
    updatedFields = localExtraFields(updated);
    for k = indexes
        name = names(k);
        if ~isfield(updatedFields, name) || ~isstruct(updatedFields.(name)) || ...
                ~isfield(updatedFields.(name), "value") || ...
                string(updatedFields.(name).value) ~= values(k)
            error("elab:client:updateExtraFields:notApplied", ...
                "Entry %s/%d did not apply extra field '%s' value '%s'.", ...
                kind, id, name, values(k));
        end
    end
end

function extraFields = localExtraFields(entry)
    extraFields = struct();
    if ~isfield(entry, "metadata") || isempty(entry.metadata)
        return
    end
    try
        metadata = jsondecode(entry.metadata);
    catch
        return
    end
    if isstruct(metadata) && isfield(metadata, "extra_fields") && ...
            isstruct(metadata.extra_fields)
        extraFields = metadata.extra_fields;
    end
end
