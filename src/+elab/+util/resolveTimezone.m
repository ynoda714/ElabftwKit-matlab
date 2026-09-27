function timezone = resolveTimezone(cfg, opts)
% resolveTimezone  Use configured timezone or the execution environment.

    arguments
        cfg (1,1) struct
        opts.localTimezone (1,1) string = ""
    end

    timezone = "";
    if isfield(cfg, "elab") && isfield(cfg.elab, "timezone")
        timezone = string(cfg.elab.timezone);
    end
    if timezone == ""
        timezone = opts.localTimezone;
    end
    if timezone == ""
        try
            current = datetime("now", "TimeZone", "local");
            timezone = string(current.TimeZone);
        catch
            timezone = "";
        end
    end
    if timezone == ""
        logWarn("resolveTimezone: execution environment timezone was unavailable; " + ...
            "recording an empty timezone");
    end
end
