function [acquiredAt, source] = readAcquiredAt(filePath, parsed, opts)
% readAcquiredAt  Read a local acquisition time or estimate it from mtime.
%
%   [acquiredAt, source] = elab.io.readAcquiredAt(filePath, parsed)
%
%   source is "file", "file_mtime", or "unknown". File values are treated
%   as offset-free local times. Values carrying a UTC offset are rejected.

    arguments
        filePath (1,1) string
        parsed (1,1) struct
        opts.timezone (1,1) string = ""
        opts.timezoneResolver (1,1) function_handle = @elab.util.resolveTimezone
    end

    acquiredAt = NaT;
    source = "unknown";
    if isfield(parsed, "acquisition")
        [acquiredAt, source] = localExperimentTime( ...
            parsed.acquisition, opts.timezone, opts.timezoneResolver);
        return
    end
    if isfield(parsed, "params") && ~isempty(parsed.params)
        [value, found] = localParam(parsed.params, "acquired_at");
        if found
            [acquiredAt, valid] = localParse(value, [ ...
                "yyyy-MM-dd'T'HH:mm:ss", ...
                "yyyy-MM-dd HH:mm:ss", ...
                "yyyy-MM-dd'T'HH:mm"], [ ...
                "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$", ...
                "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$", ...
                "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"]);
            if valid
                source = "file";
                return
            end
            localWarn(filePath, value);
        end

        [value, found] = localParam(parsed.params, "LONGDATE");
        if found
            [acquiredAt, valid] = localParse(value, "yyyy/MM/dd HH:mm:ss", ...
                "^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$");
            if valid
                source = "file";
                return
            end
            localWarn(filePath, value);
        end
    end

    info = dir(filePath);
    if ~isempty(info) && ~info(1).isdir
        acquiredAt = datetime(info(1).datenum, "ConvertFrom", "datenum");
        source = "file_mtime";
    end
end

function [acquiredAt, source] = localExperimentTime(acquisition, timezone, timezoneResolver)
    acquiredAt = NaT;
    source = "unknown";
    hasDate = isfield(acquisition, "date_epoch") && ...
        isfinite(acquisition.date_epoch) && acquisition.date_epoch > 0;
    if hasDate
        if timezone == ""
            timezone = timezoneResolver(struct());
        end
        if timezone == ""
            logWarn("readAcquiredAt: configured timezone is empty; using file modification time");
            [acquiredAt, source] = localMtime(acquisition);
            return
        end
        try
            utc = datetime( ...
                acquisition.date_epoch, ConvertFrom="posixtime", TimeZone="UTC");
            local = utc;
            local.TimeZone = char(timezone);
        catch cause
            throwAsCaller(MException( ...
                "elab:io:readAcquiredAt:invalidTimezone", ...
                "invalid timezone %s: %s", timezone, cause.message));
        end
        acquiredAt = datetime(year(local), month(local), day(local), hour(local), minute(local), second(local));
        source = "file";
        if isfield(acquisition, "header_offset_minutes") && isfinite(acquisition.header_offset_minutes) && ...
                round(minutes(tzoffset(local))) ~= round(acquisition.header_offset_minutes)
            logWarn("readAcquiredAt: header timezone offset differs from configured timezone");
        end
        return
    end
    [acquiredAt, source] = localMtime(acquisition);
end

function [acquiredAt, source] = localMtime(acquisition)
    acquiredAt = NaT;
    source = "unknown";
    if isfield(acquisition, "data_file") && isfile(acquisition.data_file)
        info = dir(acquisition.data_file);
        acquiredAt = datetime(info.datenum, ConvertFrom="datenum");
        source = "file_mtime";
    end
end

function [value, found] = localParam(params, wantedName)
    names = string({params.name});
    index = find(strcmpi(names, wantedName), 1, "first");
    found = ~isempty(index);
    value = "";
    if found
        value = string(params(index).value);
    end
end

function [value, valid] = localParse(rawValue, formats, patterns)
    value = NaT;
    valid = false;
    rawValue = string(rawValue);
    for k = 1:numel(formats)
        if isempty(regexp(rawValue, patterns(k), "once"))
            continue
        end
        try
            candidate = datetime(rawValue, "InputFormat", formats(k));
        catch
            continue
        end
        if isscalar(candidate) && ~isnat(candidate) && candidate.TimeZone == ""
            value = candidate;
            valid = true;
            return
        end
    end
end

function localWarn(filePath, value)
    [~, name, ext] = fileparts(filePath);
    logWarn("readAcquiredAt: could not parse acquisition time in %s: %s", ...
        name + ext, value);
end
