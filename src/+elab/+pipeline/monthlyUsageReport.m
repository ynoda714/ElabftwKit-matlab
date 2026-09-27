function reportId = monthlyUsageReport(client, cfg, year, month)
% monthlyUsageReport  Scenario R1: aggregate logged sessions for one month by
%   instrument / project / operator and post a report experiment with a
%   CSV of the raw rows and a usage-by-instrument chart.
%
%   reportId = elab.pipeline.monthlyUsageReport(client, cfg, year, month)
%
%   Artifacts are written under result/runs/<ts>_report/.

    arguments
        client
        cfg   (1,1) struct
        year  (1,1) double
        month (1,1) double
    end

    d0 = datetime(year, month, 1);
    d1 = dateshift(d0, "start", "month", "next");
    dateFilter = "date:>=" + string(d0, "yyyy-MM-dd") + ...
        " AND date:<" + string(d1, "yyyy-MM-dd");
    catId = elab.client.resolveId(client, "experiments_categories", cfg.elab.session_category);
    reportListLimit = localPositiveInteger( ...
        cfg.elab.report_list_limit, "elab.report_list_limit");
    raw = elab.util.toItems(client.getJson("/experiments", ...
        {"cat", catId, "extended", dateFilter, "limit", reportListLimit}));
    listTruncated = numel(raw) >= reportListLimit;
    if listTruncated
        logWarn("monthlyUsageReport: list returned the configured limit of %d sessions; " + ...
            "the report may be incomplete", reportListLimit);
    end

    rows = table('Size', [0 7], ...
        'VariableTypes', ["string" "string" "string" "double" "string" "string" "string"], ...
        'VariableNames', ["instrument" "project" "operator" ...
                          "run_minutes" "run_minutes_source" "duration_basis" ...
                          "acquired_at_source"]);
    invalidDateCount = 0;
    metadataRefetchCount = 0;
    unreadableMetadataCount = 0;
    for k = 1:numel(raw)
        [isInMonth, isInvalidDate] = localDateInRange(raw{k}, d0, d1);
        if isInvalidDate
            invalidDateCount = invalidDateCount + 1;
            continue
        end
        if ~isInMonth
            continue
        end
        entry = raw{k};
        if localMetadataMissing(entry)
            entry = localRefetchMetadata(client, entry);
            metadataRefetchCount = metadataRefetchCount + 1;
        end
        [ef, metadataReadable] = localMeta(entry);
        if ~metadataReadable
            unreadableMetadataCount = unreadableMetadataCount + 1;
            continue
        end
        [minutes, source, basis] = localDurationBasis( ...
            ef, cfg.watch.nominal_run_minutes);
        rows(end + 1, :) = { ...
            localEf(ef, "instrument_title", "(unknown)"), ...
            localEf(ef, "project", "(none)"), ...
            localEf(ef, "operator", "(none)"), minutes, ...
            source, basis, localEf(ef, "acquired_at_source", "unspecified")}; %#ok<AGROW>
    end

    if metadataRefetchCount > 0
        logWarn("monthlyUsageReport: refetched metadata for %d sessions", ...
            metadataRefetchCount);
    end
    if invalidDateCount > 0
        logWarn("monthlyUsageReport: excluded %d sessions with missing or invalid dates", ...
            invalidDateCount);
    end
    if unreadableMetadataCount > 0
        logWarn("monthlyUsageReport: excluded %d sessions with unreadable metadata", ...
            unreadableMetadataCount);
    end

    if isempty(rows)
        logWarn("monthlyUsageReport: no sessions found for %04d-%02d", year, month);
        reportId = NaN;
        return
    end

    byInstr = groupsummary(rows, "instrument", "sum", "run_minutes");
    nominalCounts = zeros(height(byInstr), 1);
    calculatedCounts = zeros(height(byInstr), 1);
    unknownCounts = zeros(height(byInstr), 1);
    dateEstimatedCounts = zeros(height(byInstr), 1);
    dateUnknownCounts = zeros(height(byInstr), 1);
    for k = 1:height(byInstr)
        nominalCounts(k) = sum(rows.instrument == byInstr.instrument(k) & ...
            (rows.duration_basis == "nominal" | rows.duration_basis == "filled"));
        calculatedCounts(k) = sum(rows.instrument == byInstr.instrument(k) & ...
            rows.duration_basis == "calculated");
        unknownCounts(k) = sum(rows.instrument == byInstr.instrument(k) & ...
            rows.duration_basis == "unknown");
        dateEstimatedCounts(k) = sum(rows.instrument == byInstr.instrument(k) & ...
            rows.acquired_at_source == "file_mtime");
        dateUnknownCounts(k) = sum(rows.instrument == byInstr.instrument(k) & ...
            ismember(rows.acquired_at_source, ["unknown", "unspecified"]));
    end
    byInstr.nominal_session_count = nominalCounts;
    byInstr.calculated_session_count = calculatedCounts;
    byInstr.nominal_session_share_pct = ...
        100 * nominalCounts ./ byInstr.GroupCount;
    byInstr.unknown_source_count = unknownCounts;
    byInstr.date_estimated_count = dateEstimatedCounts;
    byInstr.date_unknown_count = dateUnknownCounts;
    totalDateUnknownCount = sum(dateUnknownCounts);
    if totalDateUnknownCount > 0
        logWarn("monthlyUsageReport: %d sessions have unknown acquisition dates", ...
            totalDateUnknownCount);
    end
    byProj = groupsummary(rows, "project", "sum", "run_minutes");
    byOp = groupsummary(rows, "operator", "sum", "run_minutes");

    runDir = makeRunDir("Prefix", "report");
    csvPath = fullfile(runDir, sprintf("usage_%04d%02d.csv", year, month));
    writetable(rows, csvPath);

    chartPath = fullfile(runDir, "by_instrument.png");
    f = localChart(rows, byInstr.instrument, year, month);
    exportgraphics(f, chartPath, "Resolution", 120);
    close(f)

    [summaryHtml, tablesHtml, notesHtml] = localHtmlParts( ...
        rows, byInstr, byProj, byOp, cfg.watch.nominal_run_minutes, d0, d1, ...
        listTruncated, reportListLimit);
    bodyWithoutChart = summaryHtml + tablesHtml + notesHtml;
    reportId = elab.client.createExperiment(client, cfg.elab.report_category, ...
        sprintf("Usage report %04d-%02d", year, month), ...
        status = cfg.elab.draft_status, ...
        body = bodyWithoutChart);

    groups = elab.util.fieldGroups(cfg);
    kitInfo = elab.util.kitVersion();
    reportPeriod = sprintf("%04d-%02d", year, month);
    provenanceFields = [ ...
        elab.util.fieldStruct("kit_version", kitInfo.version, ...
        "text", groups.provenance), ...
        elab.util.fieldStruct("matlab_version", string(version), ...
        "text", groups.provenance), ...
        elab.util.fieldStruct("report_period", reportPeriod, ...
        "text", groups.provenance)];
    elab.client.setExtraFields( ...
        client, "experiments", reportId, provenanceFields);

    client.uploadFile("experiments", reportId, string(csvPath), "raw session rows");
    client.uploadFile("experiments", reportId, string(chartPath), "usage by instrument");
    try
        imageHtml = elab.client.uploadImageHtml(client, "experiments", ...
            reportId, "by_instrument.png", alt="usage by instrument");
        bodyWithChart = summaryHtml + "<p>" + imageHtml + "</p>" + ...
            tablesHtml + notesHtml;
        client.patchJson("experiments", reportId, struct("body", bodyWithChart));
    catch cause
        logWarn("monthlyUsageReport: could not show the chart in the body of #%d: %s", ...
            reportId, cause.message);
    end
    logInfo("monthlyUsageReport: posted as experiment #%d (%d sessions)", reportId, height(rows));
end

% ---------------------------------------------------------------------------

function [ef, readable] = localMeta(entry)
    ef = struct();
    readable = true;
    if isfield(entry, "metadata") && ~isempty(entry.metadata)
        try
            ef = jsondecode(entry.metadata);
        catch
            readable = false;
        end
    end
end

function tf = localMetadataMissing(entry)
    tf = ~isfield(entry, "metadata") || isempty(entry.metadata);
    if ~tf && (ischar(entry.metadata) || isstring(entry.metadata))
        tf = strlength(string(entry.metadata)) == 0;
    end
end

function entry = localRefetchMetadata(client, listedEntry)
    if ~isfield(listedEntry, "id") || isempty(listedEntry.id)
        error("elab:pipeline:monthlyUsageReport:metadataRefetchFailed", ...
            "Cannot refetch metadata for a session without an id.");
    end
    route = "/experiments/" + string(listedEntry.id);
    try
        detail = elab.util.toItems(client.getJson(route));
    catch cause
        err = MException( ...
            "elab:pipeline:monthlyUsageReport:metadataRefetchFailed", ...
            "Failed to refetch session metadata from %s.", route);
        throw(addCause(err, cause));
    end
    if numel(detail) ~= 1
        error("elab:pipeline:monthlyUsageReport:metadataRefetchFailed", ...
            "Expected one session from %s, received %d.", route, numel(detail));
    end
    entry = detail{1};
end

function [isInRange, isInvalid] = localDateInRange(entry, rangeStart, rangeEnd)
    isInRange = false;
    isInvalid = true;
    if ~isfield(entry, "date") || isempty(entry.date)
        return
    end
    try
        entryDate = datetime(string(entry.date), "InputFormat", "yyyy-MM-dd");
    catch
        return
    end
    if ~isscalar(entryDate) || isnat(entryDate)
        return
    end
    isInvalid = false;
    isInRange = rangeStart <= entryDate && entryDate < rangeEnd;
end

function v = localEf(ef, name, default)
    v = string(default);
    if isstruct(ef) && isfield(ef, "extra_fields")
        key = matlab.lang.makeValidName(name);
        if isfield(ef.extra_fields, key) && isfield(ef.extra_fields.(key), "value")
            raw = ef.extra_fields.(key).value;
            if isempty(raw) && ~ischar(raw) && ~isstring(raw)
                return
            end
            candidate = string(raw);
            if isempty(candidate)
                return
            end
            v = candidate;
        end
    end
end

function [minutes, source, basis] = localDurationBasis(ef, nominalMinutes)
    source = localEf(ef, "run_minutes_source", "unspecified");
    minutes = str2double(localEf(ef, "run_minutes", ""));
    if isnan(minutes)
        minutes = nominalMinutes;
        basis = "filled";
    elseif source == "measured"
        basis = "measured";
    elseif source == "nominal"
        basis = "nominal";
    elseif source == "calculated"
        basis = "calculated";
    else
        basis = "unknown";
    end
end

function f = localChart(rows, instruments, year, month)
    seriesMinutes = zeros(numel(instruments), 4);
    for k = 1:numel(instruments)
        selected = rows.instrument == instruments(k);
        seriesMinutes(k, 1) = sum(rows.run_minutes(selected & ...
            rows.duration_basis == "measured"));
        seriesMinutes(k, 2) = sum(rows.run_minutes(selected & ismember( ...
            rows.duration_basis, ["nominal", "filled"])));
        seriesMinutes(k, 3) = sum(rows.run_minutes(selected & ...
            rows.duration_basis == "unknown"));
        seriesMinutes(k, 4) = sum(rows.run_minutes(selected & ...
            rows.duration_basis == "calculated"));
    end

    totalMinutes = sum(seriesMinutes, 2);
    if max(totalMinutes) < 120
        chartValues = seriesMinutes;
        unit = "min";
    else
        chartValues = seriesMinutes / 60;
        unit = "h";
    end
    maximum = max(sum(chartValues, 2));
    if maximum == 0
        upperLimit = 1;
    else
        upperLimit = 1.15 * maximum;
    end

    f = elab.visualization.lightFigure([100 100 900 460]);
    ax = axes(f);
    displayInstruments = localInstrumentDisplayNames(instruments);
    categories = categorical(instruments, instruments, displayInstruments);
    bars = bar(ax, categories, chartValues, "stacked");
    colors = [0.20 0.55 0.78; 0.95 0.62 0.20; 0.55 0.55 0.55; 0.45 0.35 0.75];
    for k = 1:numel(bars)
        bars(k).FaceColor = colors(k, :);
    end
    ylabel(ax, "Recorded time (" + unit + ")");
    title(ax, sprintf("Recorded instrument time %04d-%02d", year, month));
    labels = ["Measured", "Nominal or filled", "Basis unknown", "Calculated"];
    for k = 1:numel(bars)
        bars(k).DisplayName = labels(k);
    end
    legend(ax, bars, labels, ...
        "Location", "northoutside", ...
        "Orientation", "horizontal");
    grid(ax, "on");
    ax.TickLabelInterpreter = "none";
    ylim(ax, [0 upperLimit]);
end

function [summary, tables, notes] = localHtmlParts( ...
        rows, byInstr, byProj, byOp, nominalMinutes, rangeStart, rangeEnd, ...
        listTruncated, reportListLimit)
    totalMinutes = sum(rows.run_minutes);
    summary = sprintf([ ...
        '<p><strong>Period</strong>: %s to %s (by acquisition date)<br>' ...
        '<strong>Sessions</strong>: %d<br>' ...
        '<strong>Recorded time</strong>: %s min (%.2f h)</p>'], ...
        string(rangeStart, "yyyy-MM-dd"), ...
        string(rangeEnd - caldays(1), "yyyy-MM-dd"), height(rows), ...
        localMinutesText(totalMinutes), totalMinutes / 60);

    totalNominal = sum(byInstr.nominal_session_count);
    totalCalculated = sum(byInstr.calculated_session_count);
    totalInstrument = [height(rows), totalMinutes / 60, totalNominal, ...
        round(100 * totalNominal / height(rows)), ...
        totalCalculated, ...
        sum(byInstr.unknown_source_count), ...
        sum(byInstr.date_estimated_count), sum(byInstr.date_unknown_count)];
    instrumentRows = strings(height(byInstr), 1);
    for r = 1:height(byInstr)
        values = [byInstr.GroupCount(r), byInstr.sum_run_minutes(r) / 60, ...
            byInstr.nominal_session_count(r), ...
            round(byInstr.nominal_session_share_pct(r)), ...
            byInstr.calculated_session_count(r), ...
            byInstr.unknown_source_count(r), byInstr.date_estimated_count(r), ...
            byInstr.date_unknown_count(r)];
        instrumentRows(r) = localInstrumentRow(byInstr.instrument(r), values);
    end
    instrumentTable = localTable(["Instrument", "Sessions", "Time (h)", ...
        "Nominal", "Nominal (%)", "Calculated", "Basis unknown", "Date estimated", ...
        "Date unknown"], instrumentRows, localInstrumentRow("Total", totalInstrument));

    projectTable = localSimpleSummaryTable(byProj, "project", "Project", ...
        height(rows), totalMinutes);
    operatorTable = localSimpleSummaryTable(byOp, "operator", "Operator", ...
        height(rows), totalMinutes);
    tables = "<h3>By instrument</h3>" + instrumentTable + ...
        "<h3>By project</h3>" + projectTable + ...
        "<h3>By operator</h3>" + operatorTable;
    notes = sprintf([ ...
        '<h3>Notes</h3><ul>' ...
        '<li><strong>Nominal</strong>: The duration was absent from the file, ' ...
        'so the configured nominal value (%s min) was used.</li>' ...
        '<li><strong>Calculated</strong>: The duration was calculated from parameters, ' ...
        'so it can be slightly shorter than a measured duration.</li>' ...
        '<li><strong>Basis unknown</strong>: The basis of the recorded duration ' ...
        'is unknown (for example, a record created before M2).</li>' ...
        '<li><strong>Date estimated / Date unknown</strong>: The acquisition ' ...
        'date was estimated from the file modification time / was unavailable, ' ...
        'so registration date determined the month.</li></ul>'], ...
        localMinutesText(nominalMinutes));
    if listTruncated
        truncationNote = sprintf([ ...
            '<li><strong>List limit reached</strong>: The query returned %d ' ...
            'sessions, so this report may be incomplete. Increase ' ...
            '<code>elab.report_list_limit</code> and create the report again.</li>'], ...
            reportListLimit);
        notes = string(extractBefore(notes, "</ul>")) + ...
            string(truncationNote) + "</ul>";
    end
end

function value = localPositiveInteger(value, key)
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
            value > 0 && value == floor(value))
        error("elab:pipeline:monthlyUsageReport:invalidListLimit", ...
            "%s must be a positive integer.", key);
    end
end

function tableHtml = localSimpleSummaryTable( ...
        grouped, nameVariable, nameHeader, totalSessions, totalMinutes)
    rows = strings(height(grouped), 1);
    for r = 1:height(grouped)
        rows(r) = "<tr><td>" + localHtmlEscape(grouped.(nameVariable)(r)) + ...
            "</td>" + localNumericCell(sprintf("%d", grouped.GroupCount(r))) + ...
            localNumericCell(sprintf("%.2f", grouped.sum_run_minutes(r) / 60)) + ...
            "</tr>";
    end
    totalRow = "<tr><td>Total</td>" + ...
        localNumericCell(sprintf("%d", totalSessions)) + ...
        localNumericCell(sprintf("%.2f", totalMinutes / 60)) + "</tr>";
    tableHtml = localTable([nameHeader, "Sessions", "Time (h)"], rows, totalRow);
end

function row = localInstrumentRow(name, values)
    displayName = localInstrumentDisplayNames(name);
    row = "<tr><td>" + localHtmlEscape(displayName) + "</td>" + ...
        localNumericCell(sprintf("%d", values(1))) + ...
        localNumericCell(sprintf("%.2f", values(2))) + ...
        localNumericCell(sprintf("%d", values(3))) + ...
        localNumericCell(sprintf("%d", values(4))) + ...
        localNumericCell(sprintf("%d", values(5))) + ...
        localNumericCell(sprintf("%d", values(6))) + ...
        localNumericCell(sprintf("%d", values(7))) + ...
        localNumericCell(sprintf("%d", values(8))) + "</tr>";
end

function names = localInstrumentDisplayNames(names)
    names = string(names);
    names(strlength(names) == 0) = "(blank)";
end

function html = localTable(headers, rows, totalRow)
    html = "<table border='1' cellpadding='4' cellspacing='0'><tr>";
    for header = headers
        html = html + "<th>" + header + "</th>";
    end
    html = html + "</tr>" + join(rows, "") + totalRow + "</table>";
end

function cellHtml = localNumericCell(value)
    cellHtml = "<td style=""text-align:right"">" + string(value) + "</td>";
end

function text = localMinutesText(minutes)
    if abs(minutes - round(minutes)) < 1e-9
        text = sprintf("%.0f", minutes);
    else
        text = sprintf("%.1f", minutes);
    end
end

function escaped = localHtmlEscape(value)
    escaped = replace(string(value), ...
        ["&", "<", ">", '"'], ["&amp;", "&lt;", "&gt;", "&quot;"]);
end
