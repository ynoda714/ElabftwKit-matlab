function setExtraFields(client, kind, id, fields)
% setExtraFields  Write eLabFTW metadata.extra_fields from a struct array.
%
%   elab.client.setExtraFields(client, "experiments", id, fields)
%
%   fields is a struct array whose elements have:
%     .name  (string)  required
%     .value (any)      required   (numbers/datetimes/logicals are stringified)
%     .type  (string)   optional   ("text","number","date","checkbox",...)
%     .group (struct)   optional   (.id numeric, .name text)
%
%   This helper replaces the entry's complete extra_fields object. Use
%   updateExtraFields when changing selected fields on an existing entry.

    arguments
        client
        kind   (1,1) string
        id     (1,1) double
        fields struct
    end

    ef = containers.Map("KeyType", "char", "ValueType", "any");
    hasGroups = isfield(fields, "group") && ...
        any(arrayfun(@(f) ~isempty(fieldnames(f.group)), fields));
    groupIds = zeros(1, 0);
    groupNames = strings(1, 0);
    groupPositions = containers.Map("KeyType", "double", "ValueType", "double");
    for k = 1:numel(fields)
        f = fields(k);
        entry = containers.Map("KeyType", "char", "ValueType", "any");
        if isfield(f, "type") && strlength(string(f.type)) > 0
            entry("type") = char(f.type);
        else
            entry("type") = char(elab.util.inferType(f.value));
        end
        entry("value") = char(elab.util.toElabValue(f.value));
        if isfield(f, "unit") && strlength(string(f.unit)) > 0
            entry("unit") = char(f.unit);   % honoured if a caller supplies it
        end
        if hasGroups && ~isempty(fieldnames(f.group))
            groupId = double(f.group.id);
            if ~isKey(groupPositions, groupId)
                groupPositions(groupId) = 0;
                groupIds(end + 1) = groupId; %#ok<AGROW>
                groupNames(end + 1) = string(f.group.name); %#ok<AGROW>
            end
            groupPositions(groupId) = groupPositions(groupId) + 1;
            entry("group_id") = groupId;
            entry("position") = groupPositions(groupId);
        end
        ef(char(f.name)) = entry;
    end

    metadata = containers.Map({'extra_fields'}, {ef});
    if hasGroups
        [groupIds, order] = sort(groupIds);
        groupNames = groupNames(order);
        definitions = repmat(struct("id", 0, "name", ""), 1, numel(groupIds));
        for k = 1:numel(groupIds)
            definitions(k) = struct("id", groupIds(k), ...
                "name", char(groupNames(k)));
        end
        metadata("elabftw") = struct("extra_fields_groups", definitions);
    end
    % eLabFTW stores the metadata column as JSON text, so send it as a string.
    client.patchJson(kind, id, struct("metadata", jsonencode(metadata)));
end
