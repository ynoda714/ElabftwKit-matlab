function parsed = parseBrukerExperiment(folder)
% parseBrukerExperiment  Read minimal identification fields from Bruker files.

    arguments
        folder (1,1) string
    end
    if ~isfolder(folder)
        error("elab:io:parseBrukerExperiment:notFolder", "not a folder: %s", folder);
    end
    acqusPath = string(fullfile(folder, "acqus"));
    if ~isfile(acqusPath)
        error("elab:io:parseBrukerExperiment:noAcqus", "missing acqus in %s", folder);
    end
    if isfile(fullfile(folder, "ser")) || isfile(fullfile(folder, "acqu2s"))
        error("elab:io:parseBrukerExperiment:unsupportedDimension", ...
            "unsupported experiment dimension in %s", folder);
    end
    fidPath = string(fullfile(folder, "fid"));
    if ~isfile(fidPath)
        error("elab:io:parseBrukerExperiment:noFid", "missing fid in %s", folder);
    end
    fidInfo = dir(fidPath);
    if fidInfo.bytes == 0
        error("elab:io:parseBrukerExperiment:emptyFid", "empty fid in %s", folder);
    end
    lines = string(readlines(acqusPath));
    parsed.params = localParams(lines);
    parsed.acquisition = localAcquisition(lines, folder, fidPath, parsed.params);
end

function params = localParams(lines)
    params = repmat(struct("name", "", "value", "", "type", "text"), 0, 1);
    params(end + 1) = struct("name", "vendor", "value", "Bruker", "type", "text");
    [title, foundTitle] = localValue(lines, "TITLE");
    specs = [ ...
        "NUC1" "bf1_mhz" "BF1" "sw_hz" "SW_h" "td" "TD" "ns" "NS" ...
        "ds" "DS" "solvent" "SOLVENT" "temperature_k" "TE" ...
        "pulse_program" "PULPROG" "instrument" "INSTRUM"];
    wanted = [ ...
        "nucleus" "bf1_mhz" "bf1_mhz" "sw_hz" "sw_hz" "td" "td" ...
        "ns" "ns" "ds" "ds" "solvent" "solvent" "temperature_k" ...
        "temperature_k" "pulse_program" "pulse_program" "instrument" "instrument"];
    numeric = [false true true true true true true true true true true false false true true false false false false];
    result = struct();
    for k = 1:numel(specs)
        [value, found] = localValue(lines, specs(k));
        name = wanted(k);
        if found && ~isfield(result, name)
            value = localUnwrap(value);
            if name == "solvent" && strcmpi(value, "None")
                continue
            end
            if numeric(k)
                number = str2double(value);
                if isnan(number)
                    logWarn("parseBrukerExperiment: ignored nonnumeric parameter %s", specs(k));
                    continue
                end
                result.(name) = localField(name, number, "number");
            else
                result.(name) = localField(name, value, "text");
            end
        end
    end
    d1 = localD1(lines);
    if ~isnan(d1)
        result.d1_s = localField("d1_s", d1, "number");
    end
    order = [ ...
        "nucleus" "bf1_mhz" "sw_hz" "td" "ns" "ds" "d1_s" ...
        "solvent" "temperature_k" "pulse_program" "instrument"];
    for name = order
        if isfield(result, name)
            params(end + 1) = result.(name);
        end
    end
    if foundTitle
        token = regexp(title, "(TopSpin\s+[^,\r\n]+)", "tokens", "once");
        if ~isempty(token)
            params(end + 1) = localField( ...
                "acquisition_software", string(token{1}), "text");
        end
    end
end

function acquisition = localAcquisition(lines, folder, fidPath, params)
    acquisition = struct( ...
        "date_epoch", NaN, ...
        "header_offset_minutes", NaN, ...
        "audit_started", NaT, ...
        "audit_completed", NaT, ...
        "audit_entry_count", 0, ...
        "ns", localNumeric(params, "ns"), ...
        "ds", localNumeric(params, "ds"), ...
        "d1_s", localNumeric(params, "d1_s"), ...
        "td", localNumeric(params, "td"), ...
        "sw_hz", localNumeric(params, "sw_hz"), ...
        "data_file", fidPath);
    [dateValue, hasDate] = localValue(lines, "DATE");
    if hasDate
        epoch = str2double(dateValue);
        if isfinite(epoch) && epoch > 0
            acquisition.date_epoch = epoch;
        end
    end
    comments = lines(startsWith(strtrim(lines), "$$"));
    if ~isempty(comments)
        token = regexp(comments(1), "([+-])(\d{2})(\d{2})", "tokens", "once");
        if ~isempty(token)
            acquisition.header_offset_minutes = str2double(token{2}) * 60 + str2double(token{3});
            if token{1} == "-"
                acquisition.header_offset_minutes = -acquisition.header_offset_minutes;
            end
        end
    end
    auditPath = string(fullfile(folder, "audita.txt"));
    if isfile(auditPath)
        auditLines = string(readlines(auditPath));
        starts = localAuditTimes(auditLines, "started at");
        completes = localAuditTimes(auditLines, "completed at");
        acquisition.audit_entry_count = numel(starts);
        if numel(starts) == 1 && numel(completes) == 1
            acquisition.audit_started = starts(1);
            acquisition.audit_completed = completes(1);
        end
    end
end

function [value, found] = localValue(lines, key)
    if key == "TITLE"
        pattern = "^##TITLE=\s*(.*)$";
    else
        pattern = "^##\$" + regexptranslate("escape", key) + "=\s*(.*)$";
    end
    value = "";
    found = false;
    for k = 1:numel(lines)
        token = regexp(lines(k), pattern, "tokens", "once");
        if ~isempty(token)
            value = string(token{1});
            found = true;
            return
        end
    end
end

function value = localUnwrap(value)
    value = strtrim(value);
    if startsWith(value, "<") && endsWith(value, ">")
        value = extractBetween(value, 2, strlength(value) - 1);
    end
end

function field = localField(name, value, type)
    field = struct("name", string(name), "value", value, "type", string(type));
end

function value = localD1(lines)
    value = NaN;
    index = find(startsWith(strtrim(lines), "##$D="), 1);
    if isempty(index) || index == numel(lines)
        return
    end
    tokens = regexp(lines(index + 1), "\S+", "match");
    if numel(tokens) >= 2
        value = str2double(tokens{2});
    end
end

function value = localNumeric(params, name)
    value = NaN;
    if isempty(params)
        return
    end
    index = find(string({params.name}) == name, 1);
    if ~isempty(index)
        value = params(index).value;
    end
end

function values = localAuditTimes(lines, label)
    values = NaT(0, 1, "TimeZone", "UTC");
    pattern = label + "\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+[+-]\d{4})";
    for k = 1:numel(lines)
        token = regexp(lines(k), pattern, "tokens", "once");
        if isempty(token)
            continue
        end
        try
            value = datetime(token{1}, InputFormat="yyyy-MM-dd HH:mm:ss.SSS Z", TimeZone="UTC");
        catch
            try
                value = datetime(token{1}, InputFormat="yyyy-MM-dd HH:mm:ss Z", TimeZone="UTC");
            catch
                continue
            end
        end
        values(end + 1, 1) = value; %#ok<AGROW>
    end
end
