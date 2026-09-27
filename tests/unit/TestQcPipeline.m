classdef TestQcPipeline < matlab.unittest.TestCase
    % TestQcPipeline  Contract tests for QC recording and inbox processing.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            projectRoot = TestQcPipeline.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testQcCheckPassWritesSchemaTitleUploadAndId(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 2.0, 0.1);

            [passed, experimentId] = elab.pipeline.qcCheck( ...
                fake, cfg, filePath, spec);

            metadata = TestQcPipeline.experimentMetadata(fake);
            fields = metadata.extra_fields;
            tc.verifyTrue(passed);
            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyEqual(sort(string(fieldnames(fields))), sort([ ...
                "metric"; "measured"; "target"; "deviation"; "tolerance"; ...
                "qc_result"; "qc_pass"; "instrument_title"; ...
                "data_file_name"; "data_file_hash"; ...
                "acquired_at"; "acquired_at_source"; ...
                "x_min"; "x_max"; "n_points"; ...
                "kit_version"; "kit_commit"; "matlab_version"; ...
                "parser"; "quicklook_profile"]));
            tc.verifyEqual(string(fields.qc_result.value), "pass");
            tc.verifyEqual(string(fields.qc_pass.value), "on");
            tc.verifyEqual(string(fields.instrument_title.value), "XRD-01");
            tc.verifyEqual(string(fields.data_file_name.value), "xrd_test.xy");
            tc.verifyEqual(string(fields.data_file_hash.value), ...
                string(elab.util.fileHash(filePath)));
            tc.verifyMatches(TestQcPipeline.experimentTitle(fake), ...
                "^QC XRD  XRD-01  \d{4}-\d{2}-\d{2}$");
            upload = TestQcPipeline.firstCall(fake, "uploadFile");
            tc.verifyEqual(upload.Arguments, ...
                {"experiments", fake.CreatedId, filePath, "QC standard file"});
        end

        function testQcCheckFailWritesExplicitResultAndCheckbox(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 10.0, 0.1);

            passed = elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            fields = TestQcPipeline.experimentMetadata(fake).extra_fields;
            tc.verifyFalse(passed);
            tc.verifyEqual(string(fields.qc_result.value), "fail");
            tc.verifyEqual(string(fields.qc_pass.value), "");
        end

        function testQcCheckFailLinksExperimentToInstrumentOnce(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 10.0, 0.1);

            elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            links = fake.Calls(cellfun( ...
                @(call) call.Method == "linkTo", fake.Calls));
            tc.assertNumElements(links, 1);
            tc.verifyEqual(links{1}.Arguments, ...
                {"experiments", fake.CreatedId, "items", 41});
        end

        function testQcCheckToleranceBoundaryPasses(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 1.0, 1.0);

            passed = elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyTrue(passed);
        end

        function testQcCheckFailSetsCheckStatus(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 10.0, 0.1);

            elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyEqual(TestQcPipeline.instrumentStatus(fake), "Check");
            tc.verifyEqual(TestQcPipeline.statusPatchCount(fake), 1);
        end

        function testQcCheckPassRestoresCheckStatus(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("Check");
            spec = tc.spec("peak_x", 2.0, 0.1);

            elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyEqual(TestQcPipeline.instrumentStatus(fake), "OK");
            tc.verifyEqual(TestQcPipeline.statusPatchCount(fake), 1);
        end

        function testQcCheckPassDoesNotPatchOkStatus(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            spec = tc.spec("peak_x", 2.0, 0.1);

            elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyEqual(TestQcPipeline.instrumentStatus(fake), "OK");
            tc.verifyEqual(TestQcPipeline.statusPatchCount(fake), 0);
        end

        function testQcCheckPassPreservesCalibrationOverdue(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("CalibrationOverdue");
            spec = tc.spec("peak_x", 2.0, 0.1);

            output = evalc("elab.pipeline.qcCheck(fake, cfg, filePath, spec);");

            tc.verifyEqual(TestQcPipeline.instrumentStatus(fake), ...
                "CalibrationOverdue");
            tc.verifyEqual(TestQcPipeline.statusPatchCount(fake), 0);
            tc.verifySubstring(output, "status was not changed");
        end

        function testQcCheckFailCreatesMissingStatusBeforeAssignment(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            fake.setGetResponse("/teams/current/items_status", {});
            spec = tc.spec("peak_x", 10.0, 0.1);

            elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyEqual(TestQcPipeline.instrumentStatus(fake), "Check");
            tc.verifyEqual(TestQcPipeline.callCountForKind( ...
                fake, "createEntry", "teams/current/items_status"), 1);
        end

        function testQcCheckStatusCreationFailureWarnsAndKeepsExperiment(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            fake.setGetResponse("/teams/current/items_status", {});
            fake.FailCreateKinds = "teams/current/items_status";
            spec = tc.spec("peak_x", 10.0, 0.1);

            output = evalc("[passed, experimentId] = " + ...
                "elab.pipeline.qcCheck(fake, cfg, filePath, spec);");

            tc.verifyFalse(passed);
            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyNotEmpty(TestQcPipeline.experimentMetadata(fake));
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "status was not changed");
        end

        function testQcCheckImageRejectedBeforeExperiment(tc)
            folder = tc.tempFolder();
            mockFiles = elab.io.writeMockRuns(folder);
            filePath = mockFiles(endsWith(mockFiles, ".png"));
            cfg = tc.config(folder);
            fake = FakeElabClient();
            spec = tc.spec("peak_x", 1.0, 0.1);

            call = @() elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyError(call, "elab:pipeline:qcCheck:unsupportedFormat");
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 0);
        end

        function testQcCheckUnknownMetricRejectedBeforeExperiment(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = FakeElabClient();
            spec = tc.spec("height", 1.0, 0.1);

            call = @() elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyError(call, "elab:pipeline:qcCheck:unknownMetric");
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 0);
        end

        function testQcCheckCategoryMismatchBeforeExperiment(tc)
            [filePath, cfg] = tc.simpleCase();
            fake = tc.qcClient("OK");
            fake.setGetResponse("/items/41", ...
                struct("id", 41, "title", "XRD-01", "category", 99));
            spec = tc.spec("peak_x", 2.0, 0.1);

            call = @() elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyError(call, "elab:client:ensureItem:categoryMismatch");
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 0);
        end

        function testQcInboxLogsXrdAndRaman(tc)
            [cfg, paths] = tc.mockInboxCase();
            fake = tc.twoInstrumentClient();

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(string({results.status}), ["logged", "logged"]);
            tc.verifyEqual(string({results.qcResult}), ["fail", "pass"]);
            tc.verifyTrue(all(isfile(fullfile(cfg.watch.processed_dir, ...
                [paths.ramanName, paths.xrdName]))));
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 2);
        end

        function testQcInboxUppercaseFileMatchesLowercaseSpecification(tc)
            [cfg, paths] = tc.mockInboxCase("xrd");
            uppercaseName = "XRD_std.xy";
            movefile(fullfile(cfg.qc.inbox_dir, paths.xrdName), ...
                fullfile(cfg.qc.inbox_dir, uppercaseName));
            fake = tc.twoInstrumentClient();

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(results.status, "logged");
            tc.verifyEqual(results.file, uppercaseName);
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 1);
        end

        function testQcInboxDuplicateSkipsAndArchives(tc)
            [cfg, paths] = tc.mockInboxCase("xrd");
            fileHash = elab.util.fileHash(fullfile(cfg.qc.inbox_dir, paths.xrdName));
            fake = tc.twoInstrumentClient();
            fake.setGetResponse("/experiments", ...
                {TestQcPipeline.experiment(77, fileHash, 7)});

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(results.status, "skipped");
            tc.verifyEqual(results.experimentId, 77);
            tc.verifyEqual(results.message, "already recorded as a QC experiment");
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 0);
            tc.verifyTrue(isfile(fullfile(cfg.watch.processed_dir, paths.xrdName)));
        end

        function testQcInboxSessionHashStillCreatesQcExperiment(tc)
            [cfg, paths] = tc.mockInboxCase("xrd");
            fileHash = elab.util.fileHash(fullfile(cfg.qc.inbox_dir, paths.xrdName));
            fake = tc.twoInstrumentClient();
            fake.setGetResponse("/experiments", ...
                {TestQcPipeline.experiment(78, fileHash, 8)});

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(results.status, "logged");
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 1);
        end

        function testQcInboxNoSpecStaysAndWarns(tc)
            [cfg, paths] = tc.mockInboxCase("ftir");
            fake = tc.twoInstrumentClient();

            output = evalc("results = elab.pipeline.qcInbox(fake, cfg);");

            tc.verifyEqual(results.status, "no_spec");
            tc.verifyTrue(isfile(fullfile(cfg.qc.inbox_dir, paths.ftirName)));
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 0);
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, paths.ftirName);
        end

        function testQcInboxFailureContinues(tc)
            folder = tc.tempFolder();
            cfg = tc.config(folder);
            mkdir(cfg.qc.inbox_dir);
            tc.writeSpecs(cfg.qc.spec_list);
            TestQcPipeline.touch(fullfile(cfg.qc.inbox_dir, "xrd_empty.xy"));
            tc.writeSpectrum(fullfile(cfg.qc.inbox_dir, "raman_good.txt"));
            fake = tc.twoInstrumentClient();

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(sort(string({results.status})), ["failed", "logged"]);
            failed = results(string({results.status}) == "failed");
            tc.verifySubstring(failed.message, "no 2-column numeric data found");
            tc.verifyTrue(isfile(fullfile(cfg.watch.failed_dir, "xrd_empty.xy")));
            tc.verifyTrue(isfile(fullfile(cfg.watch.processed_dir, "raman_good.txt")));
            tc.verifyEqual(TestQcPipeline.callCount(fake, "createEntry"), 1);
        end

        function testQcInboxIgnoresMetadataFiles(tc)
            [cfg, paths] = tc.mockInboxCase("xrd");
            TestQcPipeline.touch(fullfile(cfg.qc.inbox_dir, ".gitkeep"));
            TestQcPipeline.touch(fullfile(cfg.qc.inbox_dir, "desktop.ini"));
            fake = tc.twoInstrumentClient();

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyNumElements(results, 1);
            tc.verifyTrue(isfile(fullfile(cfg.qc.inbox_dir, ".gitkeep")));
            tc.verifyTrue(isfile(fullfile(cfg.qc.inbox_dir, "desktop.ini")));
            tc.verifyEqual(results.file, paths.xrdName);
        end

        function testQcInboxDoesNotReadWatchInbox(tc)
            [cfg, paths] = tc.mockInboxCase("xrd");
            mkdir(cfg.watch.inbox_dir);
            watchFile = fullfile(cfg.watch.inbox_dir, "raman_watch.txt");
            tc.writeSpectrum(watchFile);
            fake = tc.twoInstrumentClient();

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyNumElements(results, 1);
            tc.verifyEqual(results.file, paths.xrdName);
            tc.verifyTrue(isfile(watchFile));
        end

        function testQcInboxMissingSpecsMovesNothing(tc)
            folder = tc.tempFolder();
            cfg = tc.config(folder);
            mkdir(cfg.qc.inbox_dir);
            filePath = fullfile(cfg.qc.inbox_dir, "xrd_test.xy");
            tc.writeSpectrum(filePath);
            fake = FakeElabClient();

            call = @() elab.pipeline.qcInbox(fake, cfg);

            tc.verifyError(call, "elab:io:readQcSpecs:notFound");
            tc.verifyTrue(isfile(filePath));
        end
    end

    methods (Access = private)
        function [filePath, cfg] = simpleCase(tc)
            folder = tc.tempFolder();
            filePath = fullfile(folder, "xrd_test.xy");
            tc.writeSpectrum(filePath);
            cfg = tc.config(folder);
        end

        function folder = tempFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
        end

        function cfg = config(~, folder)
            cfg.elab = struct("base_url", "https://example.test", ...
                "qc_category", "QC", "draft_status", "Draft", ...
                "instrument_category", "Instrument", ...
                "sample_category", "Sample", ...
                "consumable_category", "Consumable", ...
                "sop_category", "SOP", ...
                "labels", struct("qc_tag", "QC", ...
                    "instrument_status_ok", "OK", ...
                    "instrument_status_check", "Check", ...
                    "instrument_status_calibration_overdue", ...
                    "CalibrationOverdue"));
            cfg.qc = struct("inbox_dir", fullfile(folder, "qc_inbox"), ...
                "spec_list", fullfile(folder, "qc_specs.csv"));
            cfg.watch = struct("inbox_dir", fullfile(folder, "watch_inbox"), ...
                "processed_dir", fullfile(folder, "processed"), ...
                "failed_dir", fullfile(folder, "failed"));
        end

        function spec = spec(~, metric, target, tolerance)
            spec = struct("matchSubstring", "xrd_", ...
                "instrumentTitle", "XRD-01", ...
                "instrumentType", "Instrument", ...
                "metric", metric, "target", target, ...
                "tolerance", tolerance);
        end

        function fake = qcClient(~, status)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                struct("id", 41, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/41", ...
                TestQcPipeline.instrument(41, "XRD-01", status));
            TestQcPipeline.configureStatuses(fake);
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "QC"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function fake = twoInstrumentClient(tc)
            fake = tc.qcClient("OK");
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/items", { ...
                struct("id", 41, "title", "XRD-01", "category", 3), ...
                struct("id", 42, "title", "Raman-01", "category", 3)});
            fake.setGetResponse("/items/41", ...
                TestQcPipeline.instrument(41, "XRD-01", "OK"));
            fake.setGetResponse("/items/42", ...
                TestQcPipeline.instrument(42, "Raman-01", "OK"));
        end

        function [cfg, paths] = mockInboxCase(tc, selection)
            arguments
                tc
                selection (1,1) string = "both"
            end
            folder = tc.tempFolder();
            cfg = tc.config(folder);
            mkdir(cfg.qc.inbox_dir);
            staging = fullfile(folder, "staging");
            mockFiles = elab.io.writeMockRuns(staging);
            paths.xrdName = "xrd_SMP-2026-001.xy";
            paths.ramanName = "raman_SMP-2026-002.txt";
            paths.ftirName = "ftir_SMP-2026-003.dx";
            if selection == "both" || selection == "xrd"
                movefile(mockFiles(endsWith(mockFiles, paths.xrdName)), ...
                    cfg.qc.inbox_dir);
            end
            if selection == "both"
                movefile(mockFiles(endsWith(mockFiles, paths.ramanName)), ...
                    cfg.qc.inbox_dir);
            end
            if selection == "ftir"
                movefile(mockFiles(endsWith(mockFiles, paths.ftirName)), ...
                    cfg.qc.inbox_dir);
            end
            copyfile(fullfile(TestQcPipeline.projectRoot(), ...
                "data", "list", "qc_specs.example.csv"), cfg.qc.spec_list);
        end

        function writeSpecs(~, csvPath)
            writelines([ ...
                "match_substring,instrument_title,instrument_type,metric,target,tolerance"; ...
                "xrd_,XRD-01,Instrument,peak_x,28.44,0.05"; ...
                "raman_,Raman-01,Instrument,peak_x,2,0.1"], csvPath);
        end

        function writeSpectrum(~, filePath)
            writematrix([1, 0; 2, 10; 3, 0], filePath, "FileType", "text");
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            thisDir = fileparts(mfilename("fullpath"));
            root = string(fileparts(fileparts(thisDir)));
        end

        function item = instrument(id, title, status)
            extraFields.status = struct("type", "text", "value", "LegacyCustomStatus");
            extraFields.location = struct("type", "text", "value", "Room A");
            item = struct("id", id, "title", title, "category", 3, ...
                "status_title", status, ...
                "metadata", jsonencode(struct("extra_fields", extraFields)));
        end

        function item = experiment(id, hash, category)
            extraFields.data_file_hash = struct("type", "text", "value", hash);
            item = struct("id", id, "category", category, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function metadata = experimentMetadata(fake)
            call = TestQcPipeline.metadataPatch(fake, "experiments");
            metadata = jsondecode(call.Arguments{3}.metadata);
        end

        function title = experimentTitle(fake)
            calls = fake.Calls;
            title = "";
            for k = 1:numel(calls)
                call = calls{k};
                if call.Method == "patchJson" && ...
                        string(call.Arguments{1}) == "experiments" && ...
                        isfield(call.Arguments{3}, "title")
                    title = string(call.Arguments{3}.title);
                    return
                end
            end
        end

        function call = metadataPatch(fake, kind)
            calls = fake.Calls;
            call = struct();
            for k = 1:numel(calls)
                candidate = calls{k};
                if candidate.Method == "patchJson" && ...
                        string(candidate.Arguments{1}) == kind && ...
                        isfield(candidate.Arguments{3}, "metadata")
                    call = candidate;
                    return
                end
            end
        end

        function call = firstCall(fake, method)
            calls = fake.Calls;
            call = struct();
            for k = 1:numel(calls)
                if calls{k}.Method == method
                    call = calls{k};
                    return
                end
            end
        end

        function value = instrumentStatus(fake)
            entry = fake.getJson("/items/41");
            value = string(entry.status_title);
        end

        function count = statusPatchCount(fake)
            count = 0;
            calls = fake.Calls;
            for k = 1:numel(calls)
                call = calls{k};
                if call.Method == "patchJson" && ...
                        string(call.Arguments{1}) == "items" && ...
                        isfield(call.Arguments{3}, "status")
                    count = count + 1;
                end
            end
        end

        function count = callCount(fake, method)
            count = sum(cellfun(@(call) call.Method == method, fake.Calls));
        end

        function count = callCountForKind(fake, method, kind)
            count = sum(cellfun(@(call) call.Method == method && ...
                string(call.Arguments{1}) == kind, fake.Calls));
        end

        function configureStatuses(fake)
            fake.setGetResponse("/teams/current/items_status", { ...
                struct("id", 11, "title", "OK", "color", "28a745"), ...
                struct("id", 12, "title", "Check", "color", "ffc107"), ...
                struct("id", 13, "title", "CalibrationOverdue", "color", "dc3545")});
        end

        function touch(path)
            fid = fopen(path, "w");
            fclose(fid);
        end
    end
end
