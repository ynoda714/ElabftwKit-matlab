function [minutesValue, source] = readRunMinutes(parsed, nominalMinutes)
% readRunMinutes  Return measured, calculated, or nominal duration in minutes.

    arguments
        parsed (1,1) struct
        nominalMinutes (1,1) double
    end
    if isfield(parsed, "t")
        minutesValue = max(parsed.t);
        source = "measured";
        return
    end
    if isfield(parsed, "acquisition")
        acquisition = parsed.acquisition;
        if localTimeValid(acquisition, "audit_started") && localTimeValid(acquisition, "audit_completed")
            delta = minutes(acquisition.audit_completed - acquisition.audit_started);
            if delta > 0
                minutesValue = delta;
                source = "measured";
                return
            end
            logWarn("readRunMinutes: audit completion is not after audit start");
        end
        needed = ["ns" "ds" "d1_s" "td" "sw_hz"];
        values = nan(1, numel(needed));
        for k = 1:numel(needed)
            if isfield(acquisition, needed(k)), values(k) = acquisition.(needed(k)); end
        end
        if all(isfinite(values)) && values(5) > 0
            minutesValue = (values(1) + values(2)) * (values(3) + values(4) / (2 * values(5))) / 60;
            source = "calculated";
            return
        end
    end
    minutesValue = nominalMinutes;
    source = "nominal";
end

function tf = localTimeValid(value, field)
    tf = isfield(value, field) && ~isnat(value.(field));
end
