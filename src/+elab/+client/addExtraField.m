function addExtraField(client, kind, id, name, value, type)
% addExtraField  Add one field without reconstructing existing metadata.
%
%   elab.client.addExtraField(client, "items", id, name, value, type)
%
%   The new JSON member is inserted directly after the opening brace of the
%   existing extra_fields object. This preserves keys and value shapes that
%   MATLAB's JSON decoder cannot round-trip. The entry is read back and all
%   previous extra fields plus the new value are verified. A concurrent UI
%   edit between the initial read and the PATCH can still be overwritten.

    arguments
        client
        kind  (1,1) string
        id    (1,1) double
        name  (1,1) string
        value
        type  (1,1) string
    end

    if ~isvarname(name)
        error("elab:client:addExtraField:invalidFieldName", ...
            "Extra-field name '%s' is not a valid MATLAB identifier.", name);
    end
    expectedValue = string(elab.util.toElabValue(value));
    entry = client.getJson(sprintf("/%s/%d", kind, id));
    if ~isfield(entry, "metadata") || isempty(entry.metadata) || ...
            strlength(string(entry.metadata)) == 0
        field = elab.util.fieldStruct(name, value, type);
        elab.client.setExtraFields(client, kind, id, field);
        localVerify(client, kind, id, name, expectedValue, struct());
        return
    end

    metadataText = char(string(entry.metadata));
    try
        metadata = jsondecode(metadataText);
    catch cause
        error("elab:client:addExtraField:invalidMetadata", ...
            "Cannot inspect metadata for %s item %d: %s", kind, id, cause.message);
    end
    if ~isstruct(metadata) || ~isfield(metadata, "extra_fields") || ...
            ~isstruct(metadata.extra_fields)
        error("elab:client:addExtraField:unsupportedMetadata", ...
            "Entry %s/%d does not contain an extra_fields object.", kind, id);
    end
    previousFields = metadata.extra_fields;
    if isfield(previousFields, char(name))
        return
    end

    openPosition = regexp(metadataText, ...
        '"extra_fields"\s*:\s*\{', 'once', 'end');
    if isempty(openPosition)
        error("elab:client:addExtraField:unsupportedMetadata", ...
            "Entry %s/%d does not contain an extra_fields object.", kind, id);
    end

    fieldValue = containers.Map("KeyType", "char", "ValueType", "any");
    fieldValue("type") = char(type);
    fieldValue("value") = char(expectedValue);
    wrapper = containers.Map({char(name)}, {fieldValue});
    encodedWrapper = jsonencode(wrapper);
    encodedMember = encodedWrapper(2:end - 1);
    remainder = metadataText(openPosition + 1:end);
    if isempty(regexp(remainder, '^\s*\}', 'once'))
        encodedMember = [encodedMember ', '];
    end
    updatedText = [metadataText(1:openPosition) encodedMember remainder];

    client.patchJson(kind, id, struct("metadata", updatedText));
    localVerify(client, kind, id, name, expectedValue, previousFields);
end

function localVerify(client, kind, id, name, expectedValue, previousFields)
    updated = client.getJson(sprintf("/%s/%d", kind, id));
    updatedFields = localExtraFields(updated);
    previousNames = string(fieldnames(previousFields));
    for k = 1:numel(previousNames)
        previousName = previousNames(k);
        if ~isfield(updatedFields, char(previousName)) || ...
                ~isequaln(updatedFields.(previousName), previousFields.(previousName))
            error("elab:client:addExtraField:notApplied", ...
                "Entry %s/%d did not preserve extra field '%s'.", ...
                kind, id, previousName);
        end
    end
    if ~isfield(updatedFields, char(name)) || ...
            ~isstruct(updatedFields.(name)) || ...
            ~isfield(updatedFields.(name), "value") || ...
            string(updatedFields.(name).value) ~= expectedValue
        error("elab:client:addExtraField:notApplied", ...
            "Entry %s/%d did not add extra field '%s' value '%s'.", ...
            kind, id, name, expectedValue);
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
