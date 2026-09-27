function binding = matchBinding(maps, unitName)
% matchBinding  Match independent Instrument and Sample binding maps.

    if maps.mode == "legacy"
        legacy = elab.pipeline.matchSample(maps.legacy, unitName);
        binding = localNormalizeLegacy(legacy);
        return
    end
    instrument = localMatch(maps.instruments, "instrument_title", unitName, "instrument");
    sample = localMatch(maps.samples, "sample_id", unitName, "sample");
    if instrument == "" && sample == ""
        binding = [];
        return
    end
    binding = localBinding();
    binding.instrument_title = instrument;
    binding.instrument_type = localValue(maps.instruments, "instrument_title", instrument, "instrument_type");
    binding.sample_id = sample;
    for name = ["operator", "project", "consumable_title", "consumable_qty"]
        binding.(name) = localValue(maps.samples, "sample_id", sample, name);
    end
end

function value = localMatch(map, targetName, unitName, side)
    value = "";
    if isempty(map)
        return
    end
    hits = false(height(map), 1);
    for k = 1:height(map)
        hits(k) = contains(string(unitName), string(map.match_substring(k)), ...
            IgnoreCase=true);
    end
    candidates = unique(string(map.(targetName)(hits)));
    candidates = candidates(~ismissing(candidates) & strlength(candidates) > 0);
    if numel(candidates) > 1
        logWarn("matchBinding: ambiguous %s binding was not applied.", side);
        return
    end
    if numel(candidates) == 1
        value = candidates(1);
    end
end

function value = localValue(map, targetName, target, valueName)
    if target == "" || isempty(map) || ~ismember(valueName, string(map.Properties.VariableNames))
        if valueName == "consumable_qty"
            value = NaN;
        else
            value = "";
        end
        return
    end
    row = find(string(map.(targetName)) == target, 1);
    value = map.(valueName)(row);
    value = localNormalizeValue(value, valueName);
end

function binding = localNormalizeLegacy(legacy)
    if isempty(legacy)
        binding = [];
        return
    end
    binding = localBinding();
    names = string(fieldnames(legacy));
    for name = string(fieldnames(binding))'
        if ismember(name, names)
            binding.(name) = localNormalizeValue(legacy.(name), name);
        end
    end
end

function value = localNormalizeValue(value, name)
    if name == "consumable_qty"
        value = double(string(value));
        if isnan(value)
            value = NaN;
        end
        return
    end
    value = string(value);
    if ismissing(value)
        value = "";
    end
end

function binding = localBinding()
    binding = struct("instrument_title", "", "instrument_type", "", ...
        "sample_id", "", "operator", "", "project", "", ...
        "consumable_title", "", "consumable_qty", NaN);
end
