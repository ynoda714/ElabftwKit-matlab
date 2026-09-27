function fields = withoutCanonicalFields(fields)
% withoutCanonicalFields  Remove canonical duration and acquisition fields.
%
%   fields = elab.util.withoutCanonicalFields(fields) preserves other parser fields.

    if isempty(fields)
        return
    end
    names = string({fields.name});
    fields = fields(~ismember(lower(names), ...
        ["run_minutes", "run_minutes_source", "acquired_at", "acquired_at_source"]));
end
