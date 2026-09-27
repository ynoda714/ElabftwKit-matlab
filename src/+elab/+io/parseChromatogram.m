function s = parseChromatogram(filePath, technique)
% parseChromatogram  Read a mock LC/GC-MS file with [TRACE] and [PEAKS] sections.
%
%   s = elab.io.parseChromatogram(filePath, technique)
%     s.t, s.intensity : trace column vectors
%     s.peaks          : table (rt_min, area, height, name, ...)
%     s.params         : struct array for extra_fields

    arguments
        filePath  (1,1) string
        technique (1,1) string = "lcms" %#ok<INUSA>
    end

    lines = readlines(filePath);
    section = "header";
    hdr = repmat(struct("name", "", "value", "", "type", "text"), 0, 1);
    traceRows = zeros(0, 2);
    peakHeader = strings(1, 0);
    peakCells = {};

    for i = 1:numel(lines)
        L = strtrim(lines(i));
        if L == ""
            continue
        end
        if startsWith(L, "[") && endsWith(L, "]")
            sec = lower(extractBetween(L, "[", "]"));
            section = sec(1);
            continue
        end
        switch section
            case "header"
                if startsWith(L, "#")
                    [nm, vl] = elab.io.kvline(L);
                    if nm ~= ""
                        hdr(end + 1) = struct("name", nm, "value", vl, "type", "text"); %#ok<AGROW>
                    end
                end
            case "trace"
                v = str2double(split(L, ","));
                if numel(v) >= 2 && all(~isnan(v(1:2)))
                    traceRows(end + 1, 1:2) = v(1:2).'; %#ok<AGROW>
                end
            case "peaks"
                parts = strtrim(split(L, ",")).';
                if isempty(peakHeader)
                    peakHeader = parts;                     % first peaks line = header
                else
                    peakCells{end + 1} = parts; %#ok<AGROW>
                end
        end
    end

    if isempty(traceRows)
        error("elab:io:parseChromatogram:noTrace", ...
            "no [TRACE] rows found in %s", filePath);
    end
    s.t = traceRows(:, 1);
    s.intensity = traceRows(:, 2);

    s.peaks = table();
    if ~isempty(peakCells)
        P = vertcat(peakCells{:});
        vn = cellstr(matlab.lang.makeValidName(peakHeader));
        s.peaks = array2table(P, "VariableNames", vn);
        for c = 1:width(s.peaks)
            col = double(string(s.peaks{:, c}));
            if all(~isnan(col))
                s.peaks.(vn{c}) = col;
            end
        end
    end

    nPk = height(s.peaks);
    params = reshape(hdr, 1, []);
    params = [params, ...
        struct("name", "n_peaks",     "value", nPk,      "type", "number"), ...
        struct("name", "run_minutes", "value", max(s.t), "type", "number")];
    if nPk > 0 && any(strcmpi(s.peaks.Properties.VariableNames, "name"))
        params(end + 1) = struct("name", "peak_names", ...
            "value", strjoin(string(s.peaks.name), "; "), "type", "text");
    end
    s.params = params;
    s.xlabel = "Retention time (min)";
    s.ylabel = "Total ion current";
end
