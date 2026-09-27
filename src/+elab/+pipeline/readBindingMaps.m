function maps = readBindingMaps(cfg)
% readBindingMaps  Read split binding maps or the deprecated legacy map.

    samplePath = string(cfg.watch.sample_map);
    instrumentPath = localInstrumentPath(cfg);
    hasSamples = isfile(samplePath);
    hasInstruments = isfile(instrumentPath);
    if ~hasSamples && ~hasInstruments
        error("elab:pipeline:readBindingMaps:noMap", ...
            "No binding map exists at %s or %s.", instrumentPath, samplePath);
    end
    samples = table();
    if hasSamples
        samples = readtable(samplePath, "TextType", "string", "Delimiter", ",");
    end
    if hasInstruments
        if ismember("instrument_title", string(samples.Properties.VariableNames))
            error("elab:pipeline:readBindingMaps:mixedFormats", ...
                "sample_map.csv cannot contain instrument_title with instrument_map.csv.");
        end
        maps = localSplit(instrumentPath, samples, cfg);
        return
    end
    if ismember("instrument_title", string(samples.Properties.VariableNames))
        localValidateMatch(samples, samplePath);
        logWarn("readBindingMaps: legacy sample_map.csv is deprecated; use instrument_map.csv and sample_map.csv.");
        maps = localEmptyMaps("legacy");
        maps.legacy = elab.pipeline.readSampleMap(cfg);
        return
    end
    maps = localSplit("", samples, cfg);
end

function maps = localSplit(instrumentPath, samples, cfg)
    maps = localEmptyMaps("split");
    if instrumentPath ~= ""
        instruments = readtable(instrumentPath, "TextType", "string", "Delimiter", ",");
        localRequireColumns(instruments, ["match_substring", "instrument_id"], instrumentPath);
        localValidateMatch(instruments, instrumentPath);
        types = strings(height(instruments), 1);
        hasType = ismember("instrument_type", string(instruments.Properties.VariableNames));
        for k = 1:height(instruments)
            value = missing;
            if hasType
                value = instruments.instrument_type(k);
            end
            if ismissing(value) || strlength(strtrim(string(value))) == 0
                types(k) = "";
            else
                types(k) = elab.io.resolveConfiguredItemType(instrumentPath, k + 1, ...
                    "instrument_type", value, "elab.instrument_category", cfg.elab.instrument_category);
            end
        end
        maps.instruments = table(localText(instruments.match_substring), ...
            localText(instruments.instrument_id), localText(types), VariableNames=[ ...
            "match_substring", "instrument_title", "instrument_type"]);
    end
    if ~isempty(samples)
        localRequireColumns(samples, ["match_substring", "sample_id"], string(cfg.watch.sample_map));
        localValidateMatch(samples, string(cfg.watch.sample_map));
        maps.samples = localSampleColumns(samples);
    end
end

function samples = localSampleColumns(input)
    count = height(input);
    samples = table(localText(input.match_substring), localText(input.sample_id), ...
        strings(count, 1), strings(count, 1), strings(count, 1), nan(count, 1), ...
        VariableNames=["match_substring", "sample_id", "operator", "project", ...
        "consumable_title", "consumable_qty"]);
    names = string(input.Properties.VariableNames);
    for name = ["operator", "project", "consumable_title"]
        if ismember(name, names)
            samples.(name) = localText(input.(name));
        end
    end
    if ismember("consumable_qty", names)
        samples.consumable_qty = localQuantity(input.consumable_qty);
    end
end

function maps = localEmptyMaps(mode)
    maps = struct("mode", string(mode), ...
        "instruments", table(strings(0,1), strings(0,1), strings(0,1), ...
        VariableNames=["match_substring", "instrument_title", "instrument_type"]), ...
        "samples", table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        strings(0,1), nan(0,1), VariableNames=["match_substring", "sample_id", ...
        "operator", "project", "consumable_title", "consumable_qty"]), ...
        "legacy", table());
end

function localRequireColumns(map, required, path)
    names = string(map.Properties.VariableNames);
    missing = required(~ismember(required, names));
    if ~isempty(missing)
        error("elab:pipeline:readBindingMaps:missingColumn", ...
            "CSV %s is missing required column %s.", path, missing(1));
    end
end

function localValidateMatch(map, path)
    localRequireColumns(map, "match_substring", path);
    values = string(map.match_substring);
    row = find(ismissing(values) | strlength(strtrim(values)) == 0, 1);
    if ~isempty(row)
        error("elab:pipeline:readBindingMaps:emptyMatch", ...
            "CSV %s row %d has an empty match_substring.", path, row + 1);
    end
end

function path = localInstrumentPath(cfg)
    if isfield(cfg.watch, "instrument_map")
        path = string(cfg.watch.instrument_map);
    else
        path = "data/list/instrument_map.csv";
    end
end

function value = localText(value)
    value = string(value);
    value(ismissing(value)) = "";
end

function value = localQuantity(value)
    value = str2double(string(value));
    value(isnan(value)) = NaN;
end
