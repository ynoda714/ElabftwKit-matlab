function map = readSampleMap(cfg)
% readSampleMap  Read the session sample map and resolve item types.
%
%   map = elab.pipeline.readSampleMap(cfg) returns a table for matching.

    map = readtable(cfg.watch.sample_map, "TextType", "string", "Delimiter", ",");
    types = strings(height(map), 1);
    hasCompatibilityColumn = ismember("instrument_type", ...
        string(map.Properties.VariableNames));
    for k = 1:height(map)
        value = missing;
        if hasCompatibilityColumn
            value = map.instrument_type(k);
        end
        types(k) = elab.io.resolveConfiguredItemType( ...
            string(cfg.watch.sample_map), k + 1, "instrument_type", value, ...
            "elab.instrument_category", cfg.elab.instrument_category);
    end
    map.instrument_type = types;
end
