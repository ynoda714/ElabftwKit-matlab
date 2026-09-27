function groups = fieldGroups(cfg)
% fieldGroups  Extra-field group ids and configured display names.

    arguments
        cfg (1,1) struct
    end

    groups.measurement = struct("id", 1, "name", ...
        localLabel(cfg, "field_group_measurement", "Measurement"));
    groups.instrumentParams = struct("id", 2, "name", ...
        localLabel(cfg, "field_group_instrument_params", ...
        "Instrument parameters"));
    groups.provenance = struct("id", 3, "name", ...
        localLabel(cfg, "field_group_provenance", "Provenance"));
end

function value = localLabel(cfg, key, fallback)
    value = string(fallback);
    if isfield(cfg, "elab") && isfield(cfg.elab, "labels") && ...
            isfield(cfg.elab.labels, key)
        value = string(cfg.elab.labels.(key));
    end
end
