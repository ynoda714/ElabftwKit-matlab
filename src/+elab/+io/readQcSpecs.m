function specs = readQcSpecs(csvPath, cfg)
% readQcSpecs  Read and validate QC standard-sample specifications.
%
%   specs = elab.io.readQcSpecs(csvPath, cfg)

    arguments
        csvPath (1,1) string
        cfg (1,1) struct = struct()
    end
    if isempty(fieldnames(cfg))
        cfg = loadConfig();
    end

    if ~isfile(csvPath)
        error("elab:io:readQcSpecs:notFound", ...
            "QC specification file not found: %s", csvPath);
    end

    tableData = readtable(csvPath, "TextType", "string", "Delimiter", ",");
    required = ["match_substring", "instrument_title", "metric", "target", "tolerance"];
    available = string(tableData.Properties.VariableNames);
    missing = required(~ismember(required, available));
    if ~isempty(missing)
        error("elab:io:readQcSpecs:missingColumn", ...
            "QC specification file is missing column(s): %s", ...
            strjoin(missing, ", "));
    end

    template = struct("matchSubstring", "", "instrumentTitle", "", ...
        "instrumentType", "", "metric", "", "target", NaN, ...
        "tolerance", NaN);
    specs = repmat(template, height(tableData), 1);
    allowedMetrics = ["max_intensity", "peak_x", "area_total"];

    for k = 1:height(tableData)
        rowNumber = k + 1;
        specs(k).matchSubstring = string(tableData.match_substring(k));
        specs(k).instrumentTitle = string(tableData.instrument_title(k));
        instrumentType = missing;
        if ismember("instrument_type", available)
            instrumentType = tableData.instrument_type(k);
        end
        specs(k).instrumentType = elab.io.resolveConfiguredItemType( ...
            csvPath, rowNumber, "instrument_type", instrumentType, ...
            "elab.instrument_category", cfg.elab.instrument_category);
        specs(k).metric = string(tableData.metric(k));
        specs(k).target = double(string(tableData.target(k)));
        specs(k).tolerance = double(string(tableData.tolerance(k)));

        localRequireText(specs(k).matchSubstring, rowNumber, "match_substring");
        localRequireText(specs(k).instrumentTitle, rowNumber, "instrument_title");
        if ~ismember(specs(k).metric, allowedMetrics)
            localInvalid(rowNumber, "metric", ...
                "must be max_intensity, peak_x, or area_total");
        end
        if ~isfinite(specs(k).target)
            localInvalid(rowNumber, "target", "must be a finite number");
        end
        if ~isfinite(specs(k).tolerance) || specs(k).tolerance < 0
            localInvalid(rowNumber, "tolerance", ...
                "must be a finite nonnegative number");
        end
    end
end

function localRequireText(value, rowNumber, columnName)
    if ismissing(value) || strlength(strtrim(value)) == 0
        localInvalid(rowNumber, columnName, "must not be empty");
    end
end

function localInvalid(rowNumber, columnName, reason)
    error("elab:io:readQcSpecs:invalidSpec", ...
        "Invalid QC specification at CSV row %d, column '%s': %s.", ...
        rowNumber, columnName, reason);
end
