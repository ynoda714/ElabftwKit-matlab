classdef TestAcquisitionDatePipeline < matlab.unittest.TestCase
    % TestAcquisitionDatePipeline  Acquisition dates through A1, A3, and R1.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testWatchWritesMeasuredDateAndFields(tc)
            [cfg, ~] = tc.watchCase(datetime(2026, 8, 31, 23, 50, 0), true);
            fake = tc.watchClient();

            result = elab.pipeline.watchAndLog(fake, cfg);
            fields = tc.metadata(fake).extra_fields;
            createPayload = tc.createPayload(fake);

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(string(createPayload.date), "2026-08-31");
            tc.verifyEqual(string(fields.acquired_at.value), "2026-08-31T23:50");
            tc.verifyEqual(string(fields.acquired_at.type), "datetime-local");
            tc.verifyEqual(string(fields.acquired_at_source.value), "file");
            tc.verifyNotEqual(string(fields.logged_at.value), ...
                string(fields.acquired_at.value));
        end

        function testWatchPreservesMidnightAsDatetimeLocal(tc)
            [cfg, ~] = tc.watchCase(datetime(2026, 9, 1, 0, 0, 0), true);
            fake = tc.watchClient();

            result = elab.pipeline.watchAndLog(fake, cfg);
            fields = tc.metadata(fake).extra_fields;

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(string(fields.acquired_at.value), "2026-09-01T00:00");
        end

        function testWatchReadsMtimeBeforeArchiving(tc)
            [cfg, filePath] = tc.watchCase(datetime(2026, 9, 1, 0, 0, 0), false);
            expected = datetime(2026, 7, 15, 8, 30, 0, "TimeZone", "local");
            java.io.File(char(filePath)).setLastModified(posixtime(expected) * 1000);
            fake = tc.watchClient();

            result = elab.pipeline.watchAndLog(fake, cfg);
            fields = tc.metadata(fake).extra_fields;
            createPayload = tc.createPayload(fake);

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(string(createPayload.date), "2026-07-15");
            tc.verifyEqual(string(fields.acquired_at.value), "2026-07-15T08:30");
            tc.verifyEqual(string(fields.acquired_at_source.value), "file_mtime");
        end

        function testWatchSendsOneCanonicalAcquiredAt(tc)
            tc.applyExtraFieldCapture();
            [cfg, ~] = tc.watchCase(datetime(2026, 8, 31, 23, 50, 0), true);
            fake = tc.watchClient();

            result = elab.pipeline.watchAndLog(fake, cfg);
            fields = tc.rawExtraFields(fake);
            names = string({fields.name});
            acquired = fields(names == "acquired_at");

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(sum(names == "acquired_at"), 1);
            tc.verifyEqual(string(acquired.type), "datetime-local");
            tc.verifyEqual(string(acquired.value), "2026-08-31T23:50");
        end

        function testQcUsesAcquisitionDateInTitleDateAndFields(tc)
            folder = tc.tempWorkingFolder();
            files = elab.io.writeMockRuns(folder, ...
                acquiredAt=datetime(2026, 8, 31, 14, 25, 0));
            filePath = files(startsWith(files, fullfile(folder, "xrd_")));
            cfg = tc.qcConfig();
            fake = tc.qcClient();
            spec = struct("instrumentTitle", "XRD-01", ...
                "instrumentType", "Instrument", "metric", "peak_x", ...
                "target", 21.3, "tolerance", 100);

            [passed, experimentId] = elab.pipeline.qcCheck( ...
                fake, cfg, filePath, spec);
            fields = tc.metadata(fake).extra_fields;
            createPayload = tc.createPayload(fake);

            tc.verifyTrue(passed);
            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyEqual(string(createPayload.date), "2026-08-31");
            tc.verifySubstring(string(createPayload.title), "2026-08-31");
            tc.verifyEqual(string(fields.acquired_at.value), "2026-08-31T14:25");
            tc.verifyEqual(string(fields.acquired_at_source.value), "file");
        end

        function testMonthlyReportCountsDateQualityAndWarns(tc)
            tc.tempWorkingFolder();
            cfg = tc.reportConfig();
            fake = tc.reportClient({ ...
                tc.reportEntry(1, "file"), ...
                tc.reportEntry(2, "file_mtime"), ...
                tc.reportEntry(5, "file_mtime"), ...
                tc.reportEntry(3, "unknown"), ...
                tc.reportEntry(4, "")});

            output = evalc( ...
                "reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);"); %#ok<NASGU>
            rows = readtable(tc.uploadedPath(fake), "TextType", "string");
            body = string(tc.createPayload(fake).body);
            byInstrument = extractBetween( ...
                body, "<h3>By instrument</h3>", "<h3>By project</h3>");

            tc.verifyEqual(rows.acquired_at_source, ...
                ["file"; "file_mtime"; "file_mtime"; "unknown"; "unspecified"]);
            tc.verifySubstring(byInstrument, "Date estimated");
            tc.verifySubstring(byInstrument, "Date unknown");
            tc.verifySubstring(byInstrument, ...
                "<td style=""text-align:right"">2</td><td style=""text-align:right"">2</td></tr>");
            tc.verifySubstring(output, "2 sessions have unknown acquisition dates");
        end
    end

    methods (Access = private)
        function [cfg, filePath] = watchCase(tc, acquiredAt, withHeader)
            folder = tc.tempWorkingFolder();
            staging = fullfile(folder, "staging");
            files = elab.io.writeMockRuns(staging, acquiredAt=acquiredAt);
            source = files(startsWith(files, fullfile(staging, "xrd_")));
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            [~, name, ext] = fileparts(source);
            filePath = fullfile(inbox, name + ext);
            if withHeader
                copyfile(source, filePath);
            else
                lines = readlines(source);
                writelines(lines(~contains(lines, "acquired_at:")), filePath);
            end

            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            sampleMap = table("no-match", "SMP", "PRJ", "operator", ...
                "Instrument", "XRD-01", 'VariableNames', ...
                {'match_substring', 'sample_id', 'project', 'operator', ...
                 'instrument_type', 'instrument_title'});
            mapPath = fullfile(mapDir, "sample_map.csv");
            writetable(sampleMap, mapPath);
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.watch.nominal_run_minutes = 10;
        end

        function fake = watchClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function cfg = qcConfig(~)
            cfg.elab = struct("qc_category", "QC", "draft_status", "Draft", ...
                "labels", struct("qc_tag", "QC", ...
                    "instrument_status_ok", "OK", ...
                    "instrument_status_check", "Check"));
        end

        function fake = qcClient(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                struct("id", 41, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/41", tc.instrument());
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "QC"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function cfg = reportConfig(~)
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.report_category = "Report";
            cfg.elab.draft_status = "Draft";
            cfg.watch.nominal_run_minutes = 10;
        end

        function fake = reportClient(~, entries)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 7, "title", "Session"), ...
                struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", entries);
        end

        function metadata = metadata(tc, fake)
            payload = tc.metadataPayload(fake);
            metadata = jsondecode(payload.metadata);
        end

        function payload = metadataPayload(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && ...
                        call.Arguments{1} == "experiments" && ...
                        isfield(call.Arguments{3}, "metadata")
                    payload = call.Arguments{3};
                    return
                end
            end
            error("TestAcquisitionDatePipeline:metadataNotFound", ...
                "No experiment metadata payload was recorded.");
        end

        function payload = createPayload(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && ...
                        call.Arguments{1} == "experiments" && ...
                        isfield(call.Arguments{3}, "title")
                    payload = call.Arguments{3};
                    return
                end
            end
            error("TestAcquisitionDatePipeline:createNotFound", ...
                "No experiment creation payload was recorded.");
        end

        function applyExtraFieldCapture(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            fixtureRoot = fullfile(root, "tests", "fixtures", ...
                "capture_extra_fields");
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fixtureRoot));
            clear("elab.client.setExtraFields");
            tc.addTeardown(@() clear("elab.client.setExtraFields"));
        end

        function fields = rawExtraFields(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "setExtraFieldsInput"
                    fields = call.Arguments{3};
                    return
                end
            end
            error("TestAcquisitionDatePipeline:fieldsNotFound", ...
                "No raw extra fields were recorded.");
        end

        function path = uploadedPath(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "uploadFile" && ...
                        call.Arguments{4} == "raw session rows"
                    path = string(call.Arguments{3});
                    return
                end
            end
            error("TestAcquisitionDatePipeline:csvNotFound", ...
                "No monthly CSV upload was recorded.");
        end

        function folder = tempWorkingFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end
    end

    methods (Static, Access = private)
        function item = instrument()
            fields.status = struct("type", "text", "value", "OK");
            item = struct("id", 41, "title", "XRD-01", "category", 3, ...
                "metadata", jsonencode(struct("extra_fields", fields)));
        end

        function entry = reportEntry(id, source)
            fields = struct( ...
                "instrument_title", struct("type", "text", "value", "XRD-01"), ...
                "project", struct("type", "text", "value", "PRJ-A"), ...
                "operator", struct("type", "text", "value", "operator-a"), ...
                "run_minutes", struct("type", "number", "value", "10"), ...
                "run_minutes_source", struct("type", "text", "value", "measured"));
            if source ~= ""
                fields.acquired_at_source = ...
                    struct("type", "text", "value", source);
            end
            entry = struct("id", id, "date", "2026-08-15", ...
                "metadata", jsonencode(struct("extra_fields", fields)));
        end
    end
end
