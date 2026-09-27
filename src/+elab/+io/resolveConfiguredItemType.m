function itemType = resolveConfiguredItemType( ...
        csvPath, rowNumber, columnName, csvValue, configKey, configuredValue)
% resolveConfiguredItemType  Resolve an optional CSV resource type against config.
%
%   itemType = elab.io.resolveConfiguredItemType(csvPath, rowNumber, ...
%       columnName, csvValue, configKey, configuredValue)
%
%   A missing or empty CSV value uses configuredValue. A present value must
%   exactly equal configuredValue so a stale CSV cannot override config.

    arguments
        csvPath (1,1) string
        rowNumber (1,1) double {mustBeInteger, mustBePositive}
        columnName (1,1) string
        csvValue
        configKey (1,1) string
        configuredValue (1,1) string
    end

    value = string(csvValue);
    if isempty(value) || all(ismissing(value)) || all(strlength(value) == 0)
        itemType = configuredValue;
        return
    end
    if value == configuredValue
        itemType = value;
        return
    end

    error("elab:io:resolveConfiguredItemType:itemTypeMismatch", ...
        ["CSV %s row %d column %s is '%s', but %s is '%s'. " + ...
        "Use the configured value or leave the compatibility column empty."], ...
        csvPath, rowNumber, columnName, value, configKey, configuredValue);
end
