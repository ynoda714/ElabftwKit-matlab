classdef TestUsageAggregationKeys < matlab.unittest.TestCase
    % TestUsageAggregationKeys  Offline regression tests for usage-aggregation metadata.

    properties (TestParameter)
        technique = {"xrd", "raman", "ftir", "nmr", "lcms", "sem"}
    end

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
        function testMatchedChromatogramSendsInstrumentAndMeasuredDuration(tc)
            [cfg, fileName] = tc.prepareWatchCase("lcms", true, 23);
            fake = tc.watchClient(true);

            result = elab.pipeline.watchAndLog(fake, cfg);
            [metadata, rawMetadata] = tc.sessionMetadata(fake);

            tc.verifyEqual(result.status, "logged");
            tc.verifyEqual(metadata.extra_fields.instrument_title.value, ...
                'LCMS-01 Q-Exactive');
            tc.verifyEqual(metadata.extra_fields.instrument_title.type, 'text');
            tc.verifyEqual(metadata.extra_fields.run_minutes_source.value, 'measured');
            tc.verifyEqual(str2double(metadata.extra_fields.run_minutes.value), 12, ...
                AbsTol=1e-12);
            tc.verifyEqual(count(string(rawMetadata), '"run_minutes":'), 1);
            tc.verifyEqual(result.file, fileName);
        end

        function testUnmatchedSpectrumOmitsInstrumentTitle(tc)
            [cfg, ~] = tc.prepareWatchCase("xrd", false, 23);
            fake = tc.watchClient(false);

            result = elab.pipeline.watchAndLog(fake, cfg);
            [metadata, ~] = tc.sessionMetadata(fake);

            tc.verifyEqual(result.status, "logged");
            tc.verifyFalse(isfield(metadata.extra_fields, "instrument_title"));
            tc.verifyEqual(metadata.extra_fields.run_minutes_source.value, 'nominal');
            tc.verifyEqual(str2double(string(metadata.extra_fields.run_minutes.value)), ...
                23, AbsTol=1e-12);
        end

        function testEveryTechniqueSendsOneTypedDurationWithItsSource(tc, technique)
            % Only chromatograms carry a time axis; every other technique must
            % fall back to the configured nominal value and say so.
            [cfg, fileName, stagedPath] = tc.prepareWatchCase(technique, false, 23);
            fake = tc.watchClient(false);

            result = elab.pipeline.watchAndLog(fake, cfg);
            tc.assertEqual(result.status, "logged", result.message);
            [metadata, rawMetadata] = tc.sessionMetadata(fake);
            ef = metadata.extra_fields;

            if technique == "lcms"
                parsed = elab.io.parseAny(stagedPath);
                expectedSource = 'measured';
                expectedMinutes = max(parsed.t);
                tc.assertNotEqual(expectedMinutes, cfg.watch.nominal_run_minutes);
            else
                expectedSource = 'nominal';
                expectedMinutes = cfg.watch.nominal_run_minutes;
            end

            tc.verifyEqual(result.file, fileName);
            tc.verifyEqual(count(string(rawMetadata), '"run_minutes":'), 1);
            tc.verifyEqual(count(string(rawMetadata), '"run_minutes_source":'), 1);
            tc.verifyEqual(ef.run_minutes.type, 'number');
            tc.verifyEqual(ef.run_minutes_source.type, 'text');
            tc.verifyEqual(ef.run_minutes_source.value, expectedSource);
            tc.verifyEqual(str2double(string(ef.run_minutes.value)), ...
                expectedMinutes, AbsTol=1e-12);
        end

        function testEveryTechniqueOmitsDecoratedSeparatorField(tc, technique)
            tc.applyExtraFieldCapture();
            [cfg, ~] = tc.prepareWatchCase(technique, false, 23);
            fake = tc.watchClient(false);

            result = elab.pipeline.watchAndLog(fake, cfg);
            tc.assertEqual(result.status, "logged", result.message);
            fields = tc.rawExtraFields(fake, "experiments");
            names = string({fields.name});

            tc.verifyFalse(any(names == "--- data"));
        end

        function testMatchedSpectrumUsesConfiguredNominalDuration(tc)
            [cfg, ~] = tc.prepareWatchCase("xrd", true, 23);
            fake = tc.watchClient(true);

            result = elab.pipeline.watchAndLog(fake, cfg);
            [metadata, rawMetadata] = tc.sessionMetadata(fake);

            tc.verifyEqual(result.status, "logged");
            tc.verifyEqual(metadata.extra_fields.run_minutes_source.value, 'nominal');
            tc.verifyEqual(str2double(metadata.extra_fields.run_minutes.value), 23, ...
                AbsTol=1e-12);
            tc.verifyEqual(count(string(rawMetadata), '"run_minutes":'), 1);
        end

        function testChromatogramPassesOneCanonicalRunMinutesToEncoder(tc)
            tc.applyExtraFieldCapture();
            [cfg, ~] = tc.prepareWatchCase("lcms", false, 23);
            fake = tc.watchClient(false);

            result = elab.pipeline.watchAndLog(fake, cfg);
            fields = tc.rawExtraFields(fake, "experiments");
            names = string({fields.name});
            runMinutes = fields(names == "run_minutes");

            tc.verifyEqual(result.status, "logged");
            tc.verifyEqual(sum(names == "run_minutes"), 1);
            tc.verifyEqual(double(runMinutes(end).value), 12, AbsTol=1e-12);
        end

        function testMonthlyReportCsvAndAggregatesRetainDurationSource(tc)
            tc.useTemporaryWorkingFolder();
            cfg = tc.pinnedConfig();
            % A non-default nominal value, so a fallback that ignores the
            % configuration cannot pass by coinciding with the default of 10.
            cfg.watch.nominal_run_minutes = 17;
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                [struct("id", 7, "title", "Session"), ...
                 struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", { ...
                tc.experiment(101, "XRD-01", "PRJ-A", "operator-a", 8, "measured", "2026-08-15"), ...
                tc.experiment(102, "XRD-01", "PRJ-A", "operator-a", 10, "nominal", "2026-08-15"), ...
                tc.legacyExperiment(103, "XRD-02", 99, "2026-08-15")});

            reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);
            csvPath = tc.uploadedPath(fake, "raw session rows");
            rows = readtable(csvPath, "TextType", "string");
            [reportBody, reportPatch] = tc.reportBody(fake);
            chartInfo = dir(tc.uploadedPath(fake, "usage by instrument"));

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(reportPatch.category, 8);
            tc.verifyEqual(reportPatch.status, 5);
            tc.verifyEqual(string(reportPatch.title), "Usage report 2026-08");
            tc.verifyEqual(string(rows.Properties.VariableNames), ...
                ["instrument" "project" "operator" "run_minutes" ...
                 "run_minutes_source" "duration_basis" "acquired_at_source"]);
            tc.verifyEqual(rows.run_minutes_source, ...
                ["measured"; "nominal"; "unspecified"]);
            tc.verifyEqual(rows.duration_basis, ...
                ["measured"; "nominal"; "filled"]);
            tc.verifyEqual(rows.run_minutes, [8; 10; 17], AbsTol=1e-12);
            tc.verifyNotEmpty(chartInfo);
            tc.verifyGreaterThan(chartInfo.bytes, 0);

            byInstrument = extractBetween(reportBody, "<h3>By instrument</h3>", "<h3>By project</h3>");
            byProject = extractBetween(reportBody, "<h3>By project</h3>", "<h3>By operator</h3>");
            byOperator = extractAfter(reportBody, "<h3>By operator</h3>");
            tc.assertNotEmpty(byInstrument);
            tc.assertNotEmpty(byProject);

            tc.verifySubstring(byInstrument, "Nominal");
            tc.verifySubstring(byInstrument, "Nominal (%)");
            tc.verifySubstring(byInstrument, "Basis unknown");
            tc.verifyEqual(count(byInstrument, "<td>XRD-01</td>"), 1);
            tc.verifySubstring(byInstrument, ...
                "<tr><td>XRD-01</td><td style=""text-align:right"">2</td><td style=""text-align:right"">0.30</td><td style=""text-align:right"">1</td><td style=""text-align:right"">50</td><td style=""text-align:right"">0</td><td style=""text-align:right"">0</td><td style=""text-align:right"">0</td><td style=""text-align:right"">2</td></tr>");
            tc.verifySubstring(byInstrument, ...
                "<tr><td>XRD-02</td><td style=""text-align:right"">1</td><td style=""text-align:right"">0.28</td><td style=""text-align:right"">1</td><td style=""text-align:right"">100</td><td style=""text-align:right"">0</td><td style=""text-align:right"">0</td><td style=""text-align:right"">0</td><td style=""text-align:right"">1</td></tr>");
            tc.verifyEqual(count(byProject, "<tr><td>"), 3);
            tc.verifySubstring(byProject, "<tr><td>PRJ-A</td><td style=""text-align:right"">2</td><td style=""text-align:right"">0.30</td></tr>");
            tc.verifySubstring(byProject, "<tr><td>(none)</td><td style=""text-align:right"">1</td><td style=""text-align:right"">0.28</td></tr>");
            tc.verifyEqual(count(byOperator, "<tr><td>"), 3);
            tc.verifySubstring(byOperator, "<tr><td>operator-a</td><td style=""text-align:right"">2</td><td style=""text-align:right"">0.30</td></tr>");
            tc.verifySubstring(byOperator, "<tr><td>(none)</td><td style=""text-align:right"">1</td><td style=""text-align:right"">0.28</td></tr>");
            tc.verifyFalse(contains(reportBody, "run_minutes_source"));
        end

        function testMonthlyReportClassifiesEveryDurationBasis(tc)
            tc.useTemporaryWorkingFolder();
            cfg = tc.pinnedConfig();
            cfg.watch.nominal_run_minutes = 17;
            fake = tc.reportClient({ ...
                tc.experiment(201, "XRD-01", "PRJ-A", "operator-a", 5, "measured", "2026-08-15"), ...
                tc.experiment(202, "XRD-01", "PRJ-A", "operator-a", 6, "nominal", "2026-08-15"), ...
                tc.experiment(203, "XRD-01", "PRJ-A", "operator-a", "abc", "measured", "2026-08-15"), ...
                tc.experimentWithoutMinutes(204, "XRD-01", "2026-08-15"), ...
                tc.experimentWithoutSource(205, "XRD-01", 7, "2026-08-15"), ...
                tc.experiment(206, "XRD-01", "PRJ-A", "operator-a", 8, "Measured", "2026-08-15")});

            elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);
            rows = readtable(tc.uploadedPath(fake, "raw session rows"), ...
                "TextType", "string");
            [reportBody, ~] = tc.reportBody(fake);
            byInstrument = extractBetween( ...
                reportBody, "<h3>By instrument</h3>", "<h3>By project</h3>");

            tc.verifyEqual(rows.run_minutes, [5; 6; 17; 17; 7; 8], AbsTol=1e-12);
            tc.verifyEqual(rows.run_minutes_source, ...
                ["measured"; "nominal"; "measured"; "unspecified"; ...
                 "unspecified"; "Measured"]);
            tc.verifyEqual(rows.duration_basis, ...
                ["measured"; "nominal"; "filled"; "filled"; "unknown"; "unknown"]);
            tc.verifySubstring(byInstrument, ...
                "<tr><td>XRD-01</td><td style=""text-align:right"">6</td><td style=""text-align:right"">1.00</td><td style=""text-align:right"">3</td><td style=""text-align:right"">50</td><td style=""text-align:right"">0</td><td style=""text-align:right"">2</td><td style=""text-align:right"">0</td><td style=""text-align:right"">6</td></tr>");
        end
    end

    methods (Access = private)
        function [cfg, fileName, stagedPath] = prepareWatchCase(tc, technique, matched, nominalMinutes)
            folder = tc.useTemporaryWorkingFolder();
            staging = fullfile(folder, "staging");
            files = string(elab.io.writeMockRuns(staging));
            selected = files(startsWith(files, fullfile(staging, technique + "_")));

            % Image techniques come with a metadata sidecar that must travel
            % with the image; the sidecar is not itself an input file.
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            for k = 1:numel(selected)
                [~, base, ext] = fileparts(selected(k));
                copyfile(selected(k), fullfile(inbox, base + ext));
            end
            stagedPath = selected(~endsWith(selected, "_meta.txt"));
            tc.assertNumElements(stagedPath, 1);
            [~, base, ext] = fileparts(stagedPath);
            fileName = base + ext;

            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            if matched
                matchSubstring = technique + "_";
            else
                matchSubstring = "does-not-match";
            end
            sampleMap = table(matchSubstring, "SMP-TEST", "PRJ-A", "operator-a", ...
                "Instrument", tc.instrumentTitle(technique), ...
                'VariableNames', {'match_substring', 'sample_id', 'project', ...
                                  'operator', 'instrument_type', 'instrument_title'});
            mapPath = fullfile(mapDir, "sample_map.csv");
            writetable(sampleMap, mapPath);

            cfg = tc.pinnedConfig();
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.watch.nominal_run_minutes = nominalMinutes;
        end

        function fake = watchClient(~, withMappedItems)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            if withMappedItems
                fake.setGetResponse("/teams/current/resources_categories", [ ...
                    struct("id", 3, "title", "Instrument"), ...
                    struct("id", 4, "title", "Sample")]);
                fake.setGetResponse("/items", [ ...
                    struct("id", 201, "title", "LCMS-01 Q-Exactive", "category", 3), ...
                    struct("id", 202, "title", "XRD-01 Rigaku MiniFlex", "category", 3), ...
                    struct("id", 203, "title", "SMP-TEST", "category", 4)]);
                fake.setGetResponse("/items/201", ...
                    struct("id", 201, "title", "LCMS-01 Q-Exactive", ...
                           "category", 3, "metadata", ""));
                fake.setGetResponse("/items/202", ...
                    struct("id", 202, "title", "XRD-01 Rigaku MiniFlex", ...
                           "category", 3, "metadata", ""));
                fake.setGetResponse("/items/203", ...
                    struct("id", 203, "title", "SMP-TEST", ...
                           "category", 4, "metadata", ""));
            end
        end

        function fake = reportClient(~, experiments)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                [struct("id", 7, "title", "Session"), ...
                 struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", experiments);
        end

        function [metadata, rawMetadata] = sessionMetadata(tc, fake)
            rawMetadata = tc.metadataPayload(fake, "experiments");
            metadata = jsondecode(rawMetadata);
        end

        function applyExtraFieldCapture(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            fixtureRoot = fullfile(projectRoot, "tests", "fixtures", ...
                "capture_extra_fields");
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fixtureRoot));
            clear("elab.client.setExtraFields");
            tc.addTeardown(@() clear("elab.client.setExtraFields"));
            tc.assertSubstring(string(which("elab.client.setExtraFields")), ...
                "capture_extra_fields");
        end

        function fields = rawExtraFields(~, fake, kind)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "setExtraFieldsInput" && call.Arguments{1} == kind
                    fields = call.Arguments{3};
                    return
                end
            end
            error("TestUsageAggregationKeys:rawExtraFieldsNotFound", ...
                "No raw extra-fields call was recorded for %s.", kind);
        end

        function rawMetadata = metadataPayload(~, fake, kind)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && call.Arguments{1} == kind
                    payload = call.Arguments{3};
                    if isfield(payload, "metadata")
                        rawMetadata = payload.metadata;
                        return
                    end
                end
            end
            error("TestUsageAggregationKeys:metadataNotFound", ...
                "No metadata PATCH was recorded for %s.", kind);
        end

        function path = uploadedPath(~, fake, comment)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "uploadFile" && call.Arguments{4} == comment
                    path = string(call.Arguments{3});
                    return
                end
            end
            error("TestUsageAggregationKeys:uploadNotFound", ...
                "No upload was recorded with comment '%s'.", comment);
        end

        function cfg = pinnedConfig(~)
            % pinnedConfig  Defaults with the values these tests depend on fixed.
            %   The temporary working folder keeps config/settings.json out, but
            %   ELAB_* environment variables still apply inside loadConfig.
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.report_category = "Report";
            cfg.elab.draft_status = "Draft";
            cfg.watch.nominal_run_minutes = 10;
        end

        function [body, payload] = reportBody(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && call.Arguments{1} == "experiments"
                    payload = call.Arguments{3};
                    if isfield(payload, "body")
                        body = string(payload.body);
                        return
                    end
                end
            end
            error("TestUsageAggregationKeys:bodyNotFound", ...
                "No report body PATCH was recorded.");
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
        function title = instrumentTitle(technique)
            titles = struct( ...
                "lcms", "LCMS-01 Q-Exactive", ...
                "xrd", "XRD-01 Rigaku MiniFlex", ...
                "raman", "RAMAN-01", ...
                "ftir", "FTIR-01", ...
                "nmr", "NMR-01", ...
                "sem", "SEM-01");
            title = titles.(technique);
        end

        function entry = experiment(id, instrument, project, operator, minutes, source, date)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument), ...
                "project", struct("type", "text", "value", project), ...
                "operator", struct("type", "text", "value", operator), ...
                "run_minutes", struct("type", "number", "value", string(minutes)), ...
                "run_minutes_source", struct("type", "text", "value", source));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function entry = legacyExperiment(id, instrument, durationMinutes, date)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument), ...
                "duration_min", struct("type", "number", ...
                    "value", string(durationMinutes)));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end


        function entry = experimentWithoutMinutes(id, instrument, date)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function entry = experimentWithoutSource(id, instrument, minutes, date)
            extraFields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument), ...
                "run_minutes", struct("type", "number", "value", string(minutes)));
            entry = struct("id", id, "date", date, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end
    end
end
