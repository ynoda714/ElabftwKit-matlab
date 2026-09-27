function f = fieldStruct(name, value, type, group)
% fieldStruct  One extra-field spec for elab.client.setExtraFields.
%
%   Returns name/value/type and, when supplied, a group with id/name fields.
%
%   f = elab.util.fieldStruct("scans", 32, "number")
%   f = elab.util.fieldStruct("solvent", "CDCl3")     % type inferred
%   f = elab.util.fieldStruct("sample_id", "S-1", "text", group)

    arguments
        name  (1,1) string
        value
        type  (1,1) string = ""
        group (1,1) struct = struct()
    end
    if type == ""
        type = string(elab.util.inferType(value));
    end
    f = struct("name", name, "value", value, "type", type);
    if ~isempty(fieldnames(group))
        f.group = group;
    end
end
