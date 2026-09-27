classdef TestMonthlyUsageReport < matlab.unittest.TestCase
    % TestMonthlyUsageReport  Month filtering regressions for scenario R1.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(fullfile(projectRoot, "src"), ...
                    "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testAugustBoundariesAndExtendedQuery(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.experiment(101, "2026-07-31", 7), ...
                tc.experiment(102, "2026-08-01", 8), ...
                tc.experiment(103, "2026-08-31", 31), ...
                tc.experiment(104, "2026-09-01", 9)});

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            rows = tc.uploadedRows(fake);
            query = tc.experimentQuery(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(rows.run_minutes, [8; 31], AbsTol=1e-12);
            tc.verifyEqual(query, {"cat", 7, "extended", ...
                "date:>=2026-08-01 AND date:<2026-09-01", "limit", 1000});
            tc.verifyFalse(any(string(query) == "since"));
            tc.verifyFalse(any(string(query) == "before"));
            % Out-of-month dates are valid dates: they are filtered, not warned.
            tc.verifyFalse(contains(output, "invalid dates"));
            tc.verifyFalse(contains(output, "refetched metadata"));
        end

        function testDecemberBoundaryUsesNextYear(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.experiment(201, "2026-12-31", 31), ...
                tc.experiment(202, "2027-01-01", 1)});

            reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 12);
            rows = tc.uploadedRows(fake);
            query = tc.experimentQuery(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(rows.run_minutes, 31, AbsTol=1e-12);
            tc.verifyEqual(query, {"cat", 7, "extended", ...
                "date:>=2026-12-01 AND date:<2027-01-01", "limit", 1000});
        end

        function testMonthWithoutSessionsCreatesNoReport(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.experiment(401, "2026-07-31", 7), ...
                tc.experiment(402, "2026-09-01", 9)});

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            called = cellfun(@(c) string(c.Method), fake.Calls);

            tc.verifyTrue(isnan(reportId));
            tc.verifySubstring(output, "no sessions found for 2026-08");
            tc.verifyFalse(contains(output, "invalid dates"));
            tc.verifyFalse(any(called == "createEntry"));
            tc.verifyFalse(any(called == "uploadFile"));
            tc.verifyFalse(any(called == "patchJson"));
        end

        function testMissingAndInvalidDatesAreWarnedAndExcluded(tc)
            tc.useTemporaryWorkingFolder();
            missing = rmfield(tc.experiment(301, "2026-08-10", 10), "date");
            [fake, cfg] = tc.reportClient({ ...
                missing, ...
                tc.experiment(302, "not-a-date", 20), ...
                tc.experiment(303, "2026-08-20", 30)});

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            rows = tc.uploadedRows(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(rows.run_minutes, 30, AbsTol=1e-12);
            tc.verifySubstring(output, ...
                "excluded 2 sessions with missing or invalid dates");
        end


        function testMissingListingMetadataIsRefetched(tc)
            tc.useTemporaryWorkingFolder();
            listed = tc.experiment(501, "2026-08-10", 23);
            listed.metadata = "";
            [fake, cfg] = tc.reportClient({listed});
            fake.CreatedId = 901;
            fake.setGetResponse("/experiments/501", ...
                tc.experiment(501, "2026-08-10", 23));

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            rows = tc.uploadedRows(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(rows.run_minutes, 23, AbsTol=1e-12);
            tc.verifyEqual(rows.duration_basis, "measured");
            tc.verifySubstring(output, "refetched metadata for 1 sessions");
            tc.verifyEqual(tc.getCallCount(fake, "/experiments/501"), 1);
        end

        function testRefetchedEntryWithoutMetadataIsFilled(tc)
            tc.useTemporaryWorkingFolder();
            listed = rmfield(tc.experiment(502, "2026-08-10", 23), "metadata");
            [fake, cfg] = tc.reportClient({listed});
            fake.setGetResponse("/experiments/502", ...
                struct("id", 502, "date", "2026-08-10"));

            elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);
            rows = tc.uploadedRows(fake);

            tc.verifyEqual(rows.instrument, "(unknown)");
            tc.verifyEqual(rows.run_minutes, 10, AbsTol=1e-12);
            tc.verifyEqual(rows.run_minutes_source, "unspecified");
            tc.verifyEqual(rows.duration_basis, "filled");
        end

        function testOutOfMonthEntryIsNotRefetched(tc)
            tc.useTemporaryWorkingFolder();
            outside = rmfield(tc.experiment(503, "2026-07-31", 7), "metadata");
            [fake, cfg] = tc.reportClient({ ...
                outside, tc.experiment(504, "2026-08-10", 8)});

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(tc.getCallCount(fake, "/experiments/503"), 0);
            tc.verifyFalse(contains(output, "refetched metadata"));
        end

        function testMetadataRefetchFailureStopsReport(tc)
            tc.useTemporaryWorkingFolder();
            listed = rmfield(tc.experiment(505, "2026-08-10", 23), "metadata");
            [fake, cfg] = tc.reportClient({listed});

            tc.verifyError( ...
                @() elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8), ...
                "elab:pipeline:monthlyUsageReport:metadataRefetchFailed");
        end

        function testReadableBodyUsesPublicHeadersOnly(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(601, ...
                "2026-08-10", "XRD-01", "PRJ-A", "operator-a", 10, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            body = tc.creationBody(fake);
            oldHeaders = ["GroupCount", "sum_run_minutes", ...
                "nominal_session_count", "nominal_session_share_pct", ...
                "unknown_source_count", "date_estimated_count", ...
                "date_unknown_count"];
            newHeaders = ["Instrument", "Sessions", "Time (h)", "Nominal", ...
                "Nominal (%)", "Calculated", "Basis unknown", "Date estimated", ...
                "Date unknown", "Project", "Operator"];

            tc.verifyFalse(any(contains(body, oldHeaders)));
            tc.verifyTrue(all(contains(body, newHeaders)));
        end

        function testHoursRoundRowsAfterAggregation(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(611, "2026-08-10", "A", "P1", "O1", 10, "measured"), ...
                tc.namedExperiment(612, "2026-08-10", "B", "P2", "O2", 10, "measured"), ...
                tc.namedExperiment(613, "2026-08-10", "C", "P3", "O3", 10, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            instrumentTable = extractBetween(tc.creationBody(fake), ...
                "<h3>By instrument</h3>", "<h3>By project</h3>");

            tc.verifyEqual(count(instrumentTable, ...
                "<td style=""text-align:right"">0.17</td>"), 3);
            tc.verifySubstring(instrumentTable, ...
                "<tr><td>Total</td><td style=""text-align:right"">3</td><td style=""text-align:right"">0.50</td>");
            tc.verifyFalse(contains(instrumentTable, ...
                "<tr><td>Total</td><td style=""text-align:right"">3</td><td style=""text-align:right"">0.51</td>"));
        end

        function testLeapYearPeriodAndSummary(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(621, "2028-02-01", "A", "P", "O", 12, "measured"), ...
                tc.namedExperiment(622, "2028-02-29", "B", "P", "O", 60, "measured")});

            tc.runReportWithOutput(fake, cfg, 2028, 2);
            body = tc.creationBody(fake);

            tc.verifySubstring(body, ...
                "<strong>Period</strong>: 2028-02-01 to 2028-02-29 (by acquisition date)");
            tc.verifySubstring(body, "<strong>Sessions</strong>: 2");
            tc.verifySubstring(body, ...
                "<strong>Recorded time</strong>: 72 min (1.20 h)");
            tc.verifyEqual(count(body, ...
                "<tr><td>Total</td><td style=""text-align:right"">2</td><td style=""text-align:right"">1.20</td>"), 3);
        end

        function testNamesAreHtmlEscaped(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(631, ...
                "2026-08-10", "A&B <X>", "P&<Q>", "O&<R>", 10, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            body = tc.creationBody(fake);

            tc.verifySubstring(body, "A&amp;B &lt;X&gt;");
            tc.verifySubstring(body, "P&amp;&lt;Q&gt;");
            tc.verifySubstring(body, "O&amp;&lt;R&gt;");
            tc.verifyFalse(contains(body, "<X>"));
        end

        function testBlankInstrumentUsesDisplayNameWithoutChangingCsv(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(635, "2026-08-10", "", "P", "O", 10, "measured"), ...
                tc.namedExperiment(636, "2026-08-10", "XRD-01", "P", "O", 20, "measured")});

            reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);
            body = tc.creationBody(fake);
            rows = tc.uploadedRows(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifySubstring(body, "<td>(blank)</td>");
            tc.verifyTrue(ismissing(rows.instrument(1)));
            tc.verifyEqual(rows.instrument(2), "XRD-01");
        end

        function testNotesExplainColumnsAndNominalMinutes(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(641, ...
                "2026-08-10", "A", "P", "O", 10, "measured")});
            cfg.watch.nominal_run_minutes = 17;

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            notes = extractAfter(tc.creationBody(fake), "<h3>Notes</h3>");

            tc.verifySubstring(notes, "<strong>Nominal</strong>");
            tc.verifySubstring(notes, "17 min");
            tc.verifySubstring(notes, "<strong>Calculated</strong>");
            tc.verifySubstring(notes, "<strong>Basis unknown</strong>");
            tc.verifySubstring(notes, ...
                "<strong>Date estimated / Date unknown</strong>");
        end

        function testTotalNominalPercentUsesAllSessions(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(651, "2026-08-10", "A", "P", "O", 10, "nominal"), ...
                tc.namedExperiment(652, "2026-08-10", "A", "P", "O", 10, "measured"), ...
                tc.namedExperiment(653, "2026-08-10", "B", "P", "O", 10, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            instrumentTable = extractBetween(tc.creationBody(fake), ...
                "<h3>By instrument</h3>", "<h3>By project</h3>");

            tc.verifySubstring(instrumentTable, ...
                "<tr><td>Total</td><td style=""text-align:right"">3</td><td style=""text-align:right"">0.50</td><td style=""text-align:right"">1</td><td style=""text-align:right"">33</td>");
        end

        function testCalculatedDurationIsSeparateAndAggregated(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(654, "2026-08-10", "A", "P", "O", 9, "calculated"), ...
                tc.namedExperiment(655, "2026-08-10", "A", "P", "O", 10, "nominal")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            rows = tc.uploadedRows(fake);
            instrumentTable = extractBetween(tc.creationBody(fake), ...
                "<h3>By instrument</h3>", "<h3>By project</h3>");

            tc.verifyEqual(rows.duration_basis, ["calculated"; "nominal"]);
            tc.verifySubstring(instrumentTable, "<td style=""text-align:right"">1</td>");
            tc.verifySubstring(instrumentTable, "<td style=""text-align:right"">50</td>");
            tc.verifyEqual(sum(rows.run_minutes), 19, AbsTol=1e-12);
        end

        function testUploadedChartIsInsertedOnceAfterSummary(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(661, ...
                "2026-08-10", "A", "P", "O", 10, "measured")});
            upload = struct("id", 19, "real_name", "by_instrument.png", ...
                "long_name", "stored chart.png", "storage", 1);
            fake.setGetResponse("/experiments/501", struct("uploads", upload));

            reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);
            [rewrites, creation] = tc.bodyPayloads(fake);
            rewritten = string(rewrites{1}.body);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyNumElements(rewrites, 1);
            tc.verifyFalse(contains(string(creation.body), "<img"));
            tc.verifySubstring(rewritten, "<img");
            tc.verifySubstring(rewritten, "download.php");
            tc.verifyLessThan(strfind(rewritten, "<img"), ...
                strfind(rewritten, "<h3>By instrument</h3>"));
            tc.verifySubstring(rewritten, "<h3>By project</h3>");
            tc.verifySubstring(rewritten, "<h3>By operator</h3>");
            tc.verifySubstring(rewritten, "<h3>Notes</h3>");
        end

        function testMissingUploadedChartWarnsButKeepsReport(tc)
            tc.useTemporaryWorkingFolder();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(671, ...
                "2026-08-10", "A", "P", "O", 10, "measured")});

            [output, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            [rewrites, ~] = tc.bodyPayloads(fake);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifySubstring(output, "could not show the chart");
            tc.verifyEqual(tc.uploadCount(fake), 2);
            tc.verifyEmpty(rewrites);
        end

        function testChartPngIsLightUnderDarkDefault(tc)
            tc.useTemporaryWorkingFolder();
            tc.useDarkFigureTheme();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(681, ...
                "2026-08-10", "A", "P", "O", 10, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            imageData = imread(tc.uploadedPath(fake, "usage by instrument"));

            tc.verifyGreaterThanOrEqual(mean(double(imageData), "all"), 200);
        end

        function testMinuteChartHasStackedBasisSeriesAndLiteralTicks(tc)
            tc.useTemporaryWorkingFolder();
            key = tc.captureNextChart();
            [fake, cfg] = tc.reportClient({ ...
                tc.namedExperiment(691, "2026-08-10", "XRD_01", "P", "O", 5, "measured"), ...
                tc.namedExperiment(692, "2026-08-10", "XRD_01", "P", "O", 6, "nominal"), ...
                tc.namedExperiment(693, "2026-08-10", "XRD_01", "P", "O", 7, "other")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            captured = getappdata(groot, key);

            tc.verifyEqual(string(captured.YLabel), "Recorded time (min)");
            tc.verifyEqual(captured.YLim, [0 20.7], AbsTol=1e-12);
            tc.verifyEqual(string(captured.TickLabelInterpreter), "none");
            tc.verifyEqual(captured.SeriesTotals( ...
                captured.SeriesNames == "Measured"), 5, AbsTol=1e-12);
            tc.verifyEqual(captured.SeriesTotals( ...
                captured.SeriesNames == "Nominal or filled"), 6, AbsTol=1e-12);
            tc.verifyEqual(captured.SeriesTotals( ...
                captured.SeriesNames == "Basis unknown"), 7, AbsTol=1e-12);
            tc.verifyEqual(string(captured.LegendLocation), "northoutside");
            tc.verifyEqual(string(captured.LegendOrientation), "horizontal");
        end

        function testHourChartUsesScaledHeadroom(tc)
            tc.useTemporaryWorkingFolder();
            key = tc.captureNextChart();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(701, ...
                "2026-08-10", "A", "P", "O", 120, "measured")});

            tc.runReportWithOutput(fake, cfg, 2026, 8);
            captured = getappdata(groot, key);

            tc.verifyEqual(string(captured.YLabel), "Recorded time (h)");
            tc.verifyEqual(captured.YLim, [0 2.3], AbsTol=1e-12);
        end

        function testZeroDurationChartUsesOneAsUpperLimit(tc)
            tc.useTemporaryWorkingFolder();
            key = tc.captureNextChart();
            [fake, cfg] = tc.reportClient({tc.namedExperiment(711, ...
                "2026-08-10", "A", "P", "O", 0, "measured")});

            [~, reportId] = tc.runReportWithOutput(fake, cfg, 2026, 8);
            captured = getappdata(groot, key);

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(captured.YLim, [0 1], AbsTol=1e-12);
        end
    end

    methods (Access = private)
        function [fake, cfg] = reportClient(~, experiments)
            % The temporary working folder keeps config/settings.json out, but
            % ELAB_* environment variables still apply inside loadConfig, so
            % pin the values these tests depend on.
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.report_category = "Report";
            cfg.elab.draft_status = "Draft";
            cfg.watch.nominal_run_minutes = 10;
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                [struct("id", 7, "title", "Session"), ...
                 struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", experiments);
        end

        function rows = uploadedRows(tc, fake)
            csvPath = tc.uploadedPath(fake, "raw session rows");
            rows = readtable(csvPath, "TextType", "string");
        end

        function [output, reportId] = runReportWithOutput(~, fake, cfg, year, month) %#ok<STOUT,INUSD>
            % The evaluated statement uses the named inputs and assigns reportId.
            output = evalc( ...
                "reportId = elab.pipeline.monthlyUsageReport(fake, cfg, year, month);");
        end

        function query = experimentQuery(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "getJson" && call.Arguments{1} == "/experiments"
                    query = call.Arguments{2};
                    return
                end
            end
            error("TestMonthlyUsageReport:queryNotFound", ...
                "No experiments query was recorded.");
        end

        function count = getCallCount(~, fake, route)
            count = 0;
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "getJson" && call.Arguments{1} == route
                    count = count + 1;
                end
            end
        end

        function path = uploadedPath(~, fake, comment)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "uploadFile" && call.Arguments{4} == comment
                    path = string(call.Arguments{3});
                    return
                end
            end
            error("TestMonthlyUsageReport:uploadNotFound", ...
                "No upload was recorded with comment '%s'.", comment);
        end

        function body = creationBody(tc, fake)
            [~, creation] = tc.bodyPayloads(fake);
            body = string(creation.body);
        end

        function [rewrites, creation] = bodyPayloads(~, fake)
            rewrites = {};
            creation = [];
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method ~= "patchJson" || call.Arguments{1} ~= "experiments"
                    continue
                end
                payload = call.Arguments{3};
                if ~isfield(payload, "body")
                    continue
                end
                if isfield(payload, "title")
                    creation = payload;
                else
                    rewrites{end + 1} = payload; %#ok<AGROW>
                end
            end
        end

        function count = uploadCount(~, fake)
            methods = cellfun(@(call) string(call.Method), fake.Calls);
            count = sum(methods == "uploadFile");
        end

        function useDarkFigureTheme(tc)
            probe = figure("Visible", "off");
            tc.addTeardown(@() TestMonthlyUsageReport.closeIfValid(probe));
            tc.assumeTrue(isprop(probe, "Theme"), ...
                "This MATLAB release has no figure Theme property.");
            close(probe);
            s = settings;
            graphicsTheme = s.matlab.appearance.figure.GraphicsTheme;
            graphicsTheme.TemporaryValue = "dark";
            tc.addTeardown(@() clearTemporaryValue(graphicsTheme));
        end

        function key = captureNextChart(tc)
            key = "M3_7MonthlyChart" + string(randi(1e9));
            oldCallback = get(groot, "DefaultFigureCloseRequestFcn");
            setappdata(groot, "M3_7CaptureKey", key);
            set(groot, "DefaultFigureCloseRequestFcn", ...
                @TestMonthlyUsageReport.captureChart);
            tc.addTeardown(@() TestMonthlyUsageReport.restoreCloseCallback( ...
                oldCallback, key));
        end

        function folder = useTemporaryWorkingFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture( ...
                matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end
    end

    methods (Static, Access = private)
        function entry = experiment(id, date, minutes)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", "XRD-01"), ...
                "project", struct("type", "text", "value", "PRJ-A"), ...
                "operator", struct("type", "text", "value", "operator-a"), ...
                "run_minutes", struct("type", "number", "value", string(minutes)), ...
                "run_minutes_source", struct("type", "text", "value", "measured"));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function entry = namedExperiment( ...
                id, date, instrument, project, operator, minutes, source)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument), ...
                "project", struct("type", "text", "value", project), ...
                "operator", struct("type", "text", "value", operator), ...
                "run_minutes", struct("type", "number", "value", string(minutes)), ...
                "run_minutes_source", struct("type", "text", "value", source), ...
                "acquired_at_source", struct("type", "text", "value", "file"));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function captureChart(f, ~)
            key = string(getappdata(groot, "M3_7CaptureKey"));
            ax = findobj(f, "Type", "axes");
            bars = findobj(ax(1), "Type", "bar");
            names = strings(1, numel(bars));
            totals = zeros(1, numel(bars));
            for k = 1:numel(bars)
                names(k) = string(bars(k).DisplayName);
                totals(k) = sum(bars(k).YData);
            end
            chartLegend = findobj(f, "Type", "legend");
            captured = struct( ...
                "YLabel", ax(1).YLabel.String, ...
                "YLim", ax(1).YLim, ...
                "TickLabelInterpreter", ax(1).TickLabelInterpreter, ...
                "SeriesNames", names, ...
                "SeriesTotals", totals, ...
                "LegendLocation", chartLegend(1).Location, ...
                "LegendOrientation", chartLegend(1).Orientation);
            setappdata(groot, key, captured);
            delete(f);
        end

        function restoreCloseCallback(callback, key)
            set(groot, "DefaultFigureCloseRequestFcn", callback);
            if isappdata(groot, key)
                rmappdata(groot, key);
            end
            if isappdata(groot, "M3_7CaptureKey")
                rmappdata(groot, "M3_7CaptureKey");
            end
        end

        function closeIfValid(f)
            if isgraphics(f)
                close(f);
            end
        end
    end
end
