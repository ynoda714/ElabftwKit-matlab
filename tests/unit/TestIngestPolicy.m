classdef TestIngestPolicy < matlab.unittest.TestCase
    % TestIngestPolicy  ADR-007 retention and raw attachment contracts.

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestIngestPolicy.projectRoot(), "src"), ...
                IncludingSubfolders=true));
        end
    end

    methods (Test)
        function test01AutoAttachesFileWithinLimit(testCase)
            [cfg, fake] = testCase.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyEqual(testCase.uploadCount(fake, "raw instrument file"), 1);
        end

        function test02AutoOverLimitKeepsRecordPreviewAndHash(testCase)
            [cfg, fake] = testCase.watchCase();
            cfg.ingest.attach_raw_max_mb = 0.000001;

            output = evalc("result = elab.pipeline.watchAndLog(fake, cfg);");
            fields = testCase.sentMetadata(fake).extra_fields;

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyEqual(testCase.uploadCount(fake, "raw instrument file"), 0);
            testCase.verifyEqual(testCase.uploadCount(fake, "quick look"), 1);
            testCase.verifyTrue(isfield(fields, "data_file_hash"));
            testCase.verifySubstring(output, "over the 1e-06 MB limit");
        end

        function test03NeverSkipsWithoutWarning(testCase)
            folder = testCase.temporaryWorkingFolder();
            filePath = fullfile(folder, "raw.dat");
            writelines("raw", filePath);
            cfg.ingest = struct("attach_raw", "never", ... %#ok<STRNU>
                "attach_raw_max_mb", 0);

            output = evalc("[attach, reason] = " + ...
                "elab.io.shouldAttachRaw(filePath, cfg, pipeline='test');");

            testCase.verifyFalse(attach);
            testCase.verifyEqual(reason, "disabled");
            testCase.verifyFalse(contains(output, "[WARN]"));
        end

        function test04AlwaysAttachesOverLimit(testCase)
            folder = testCase.temporaryWorkingFolder();
            filePath = fullfile(folder, "raw.dat");
            writelines("raw", filePath);
            cfg.ingest = struct("attach_raw", "always", ...
                "attach_raw_max_mb", 0);

            [attach, reason] = elab.io.shouldAttachRaw(filePath, cfg);

            testCase.verifyTrue(attach);
            testCase.verifyEqual(reason, "always");
        end

        function test05MoveCollisionDoesNotOverwrite(testCase)
            [source, destination] = testCase.archiveCase("original", "existing");

            archived = elab.io.archiveFile(source, destination, "move", ...
                timestamp="20260921T130000");

            testCase.verifyEqual(strtrim(string(fileread( ...
                fullfile(destination, "sample.dat")))), "existing");
            testCase.verifyEqual(string(archived), ...
                fullfile(destination, "sample__20260921T130000.dat"));
            testCase.verifyEqual(strtrim(string(fileread(archived))), "original");
        end

        function test06SecondCollisionGetsNumericSuffix(testCase)
            [source, destination] = testCase.archiveCase("original", "existing");
            writelines("first collision", ...
                fullfile(destination, "sample__20260921T130000.dat"));

            archived = elab.io.archiveFile(source, destination, "move", ...
                timestamp="20260921T130000");

            testCase.verifyEqual(string(archived), ...
                fullfile(destination, "sample__20260921T130000_2.dat"));
        end

        function test07ImageMetadataSidecarUsesCollisionName(testCase)
            [source, destination] = testCase.archiveCase("image", "existing", ".png");
            [folder, base] = fileparts(source);
            writelines("metadata", fullfile(folder, base + "_meta.txt"));

            archived = elab.io.archiveFile(source, destination, "move", ...
                timestamp="20260921T130000");

            testCase.verifyEqual(string(archived), ...
                fullfile(destination, "sample__20260921T130000.png"));
            testCase.verifyTrue(isfile(fullfile(destination, ...
                "sample__20260921T130000_meta.txt")));
            testCase.verifyFalse(isfile(fullfile(destination, "sample_meta.txt")));
        end

        function test08CopyRetainsSourceAndCreatesArchive(testCase)
            [source, destination] = testCase.archiveCase("original", "");

            archived = elab.io.archiveFile(source, destination, "copy");

            testCase.verifyTrue(isfile(source));
            testCase.verifyTrue(isfile(archived));
        end

        function test09CopyDuplicateDoesNotCreateAnotherArchive(testCase)
            [cfg, fake, filePath] = testCase.watchCase();
            cfg.ingest.archive_mode = "copy";
            fileHash = elab.util.fileHash(filePath);
            fake.setGetResponse("/experiments", ...
                TestIngestPolicy.experiment(77, fileHash, 7));

            result = elab.pipeline.watchAndLog(fake, cfg);

            testCase.verifyEqual(result.status, "skipped");
            testCase.verifyTrue(isfile(filePath));
            testCase.verifyEmpty(dir(fullfile(cfg.watch.processed_dir, "*.xy")));
        end

        function test10LeaveChangesNoInputAndWritesSidecarInRun(testCase)
            [cfg, fake, filePath] = testCase.watchCase();
            cfg.ingest.archive_mode = "leave";

            result = elab.pipeline.watchAndLog(fake, cfg);

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyTrue(isfile(filePath));
            testCase.verifyEmpty(dir(fullfile(cfg.watch.processed_dir, "*.xy")));
            testCase.verifyNumElements(dir(fullfile(cfg.run.root_dir, ...
                "**", "xrd_test.elab.json")), 1);
            testCase.verifyFalse(isfile(fullfile(cfg.watch.inbox_dir, ...
                "xrd_test.elab.json")));
        end

        function test11CopyAndLeaveFailuresStayInInbox(testCase)
            [copyCfg, copyFake, copyFile] = testCase.failedWatchCase("copy");
            copyResult = elab.pipeline.watchAndLog(copyFake, copyCfg);
            [leaveCfg, leaveFake, leaveFile] = testCase.failedWatchCase("leave");
            leaveResult = elab.pipeline.watchAndLog(leaveFake, leaveCfg);

            testCase.verifyEqual(copyResult.status, "failed");
            testCase.verifyEqual(leaveResult.status, "failed");
            testCase.verifyTrue(isfile(copyFile));
            testCase.verifyTrue(isfile(leaveFile));
            testCase.verifyEmpty(dir(fullfile(copyCfg.watch.failed_dir, "*.xy")));
            testCase.verifyEmpty(dir(fullfile(leaveCfg.watch.failed_dir, "*.xy")));
            testCase.verifyNumElements(dir(fullfile(copyCfg.run.root_dir, ...
                "**", "watch_summary.csv")), 1);
            testCase.verifyNumElements(dir(fullfile(leaveCfg.run.root_dir, ...
                "**", "watch_summary.csv")), 1);
        end

        function test12InvalidChoicesError(testCase)
            folder = testCase.temporaryWorkingFolder();
            testCase.writeSettings(folder, ...
                '{"ingest":{"attach_raw":"sometimes"}}');
            attachCall = @() loadConfig();

            testCase.verifyError(attachCall, ...
                "elab:config:loadConfig:invalidChoice");

            folder = testCase.temporaryWorkingFolder();
            testCase.writeSettings(folder, ...
                '{"ingest":{"archive_mode":"delete"}}');
            archiveCall = @() loadConfig();

            testCase.verifyError(archiveCall, ...
                "elab:config:loadConfig:invalidChoice");
        end

        function test13SessionFieldsHaveRequiredValuesAndOrder(testCase)
            [cfg, fake] = testCase.watchCase();
            cfg.elab.timezone = "Configured/Zone";

            result = elab.pipeline.watchAndLog(fake, cfg, ...
                sourceLocator=@TestIngestPolicy.fixedSource);
            fields = testCase.sentMetadata(fake).extra_fields;
            measurementNames = ["acquired_at_source", "timezone", ...
                "run_minutes", "run_minutes_source"];
            provenanceNames = ["data_file_name", "data_file_hash", "data_unit", ...
                "source_path", "source_host", "source_mtime", "logged_at", ...
                "schema_version", "kit_version", "kit_commit", ...
                "matlab_version", "parser", "quicklook_profile"];

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyEqual(string(fields.timezone.value), "Configured/Zone");
            testCase.verifyEqual(string(fields.source_path.value), "X:\share\raw.xy");
            testCase.verifyEqual(string(fields.source_host.value), "fixed-host");
            testCase.verifyEqual(string(fields.source_mtime.value), "2026-09-21T13:00");
            testCase.verifyEqual(string(fields.source_mtime.type), "datetime-local");
            testCase.verifyEqual(string(fields.schema_version.value), "1.2");
            testCase.verifyEqual(testCase.positions(fields, measurementNames), 2:5);
            testCase.verifyEqual(testCase.positions(fields, provenanceNames), 1:13);
        end

        function test14SourceHostUsesUncServerOrComputerName(testCase)
            info = struct("folder", "\\server\share", "name", "raw.dat", ...
                "datenum", datenum(2026, 9, 21, 13, 0, 0)); %#ok<DATNM>
            unc = elab.io.sourceLocation("ignored", fileInfo=info);
            folder = testCase.temporaryWorkingFolder();
            localPath = fullfile(folder, "raw.dat");
            writelines("raw", localPath);

            local = elab.io.sourceLocation(localPath, computerName="test-host");

            testCase.verifyEqual(unc.source_host, "server");
            testCase.verifyEqual(local.source_host, "test-host");
        end

        function test15TimezoneUsesInjectedLocalOrConfiguredValue(testCase)
            cfg.elab.timezone = "";
            local = elab.util.resolveTimezone(cfg, localTimezone="Test/Local");
            cfg.elab.timezone = "Configured/Zone";

            configured = elab.util.resolveTimezone(cfg, ...
                localTimezone="Ignored/Local");

            testCase.verifyEqual(local, "Test/Local");
            testCase.verifyEqual(configured, "Configured/Zone");
        end

        function test16SidecarContainsContractAndFailureDoesNotFailRecord(testCase)
            [cfg, fake] = testCase.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg, ...
                sourceLocator=@TestIngestPolicy.fixedSource, ...
                timezoneResolver=@TestIngestPolicy.fixedTimezone);
            sidecar = dir(fullfile(cfg.watch.processed_dir, "*.elab.json"));
            payload = jsondecode(fileread(fullfile(sidecar(1).folder, sidecar(1).name)));

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyTrue(all(isfield(payload, ["schema_version", ...
                "source_path", "source_host", "source_mtime", ...
                "data_file_hash", "metadata", "acquired_at", ...
                "acquired_at_source", "timezone", "experiment_id", ...
                "experiment_url", "kit_version", "kit_commit"])));
            testCase.verifyEqual(string(payload.timezone), "Test/Zone");

            [failureCfg, failureFake] = testCase.watchCase(); %#ok<ASGLU>
            output = evalc("failureResult = elab.pipeline.watchAndLog(" + ...
                "failureFake, failureCfg, sidecarWriter=@TestIngestPolicy.failWrite);");

            testCase.verifyEqual(failureResult.status, "logged");
            testCase.verifySubstring(output, "could not write the eLab sidecar");
        end

        function test17QcUsesPolicyAndArchiveWithoutSessionSchema(testCase)
            [cfg, fake, filePath] = testCase.qcInboxCase();
            cfg.ingest.attach_raw = "never";
            writelines("existing", fullfile(cfg.watch.processed_dir, "xrd_test.xy"));

            result = elab.pipeline.qcInbox(fake, cfg);
            fields = testCase.sentMetadata(fake).extra_fields;

            testCase.verifyEqual(result.status, "logged");
            testCase.verifyEqual(testCase.uploadCount(fake, "QC standard file"), 0);
            testCase.verifyFalse(isfile(filePath));
            testCase.verifyNumElements(dir(fullfile(cfg.watch.processed_dir, ...
                "xrd_test__*.xy")), 1);
            testCase.verifyFalse(any(isfield(fields, ["timezone", "source_path", ...
                "source_host", "source_mtime", "schema_version"])));
            testCase.verifyEmpty(dir(fullfile(cfg.watch.processed_dir, "*.elab.json")));
        end
    end

    methods (Access = private)
        function [cfg, fake, filePath] = watchCase(testCase)
            folder = testCase.temporaryWorkingFolder();
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            filePath = fullfile(inbox, "xrd_test.xy");
            writematrix([1, 0; 2, 10; 3, 0], filePath, "FileType", "text");
            mapFolder = fullfile(folder, "data", "list");
            mkdir(mapFolder);
            mapPath = fullfile(mapFolder, "sample_map.csv");
            writetable(table("no-match", "sample", "project", "operator", ...
                "Instrument", "XRD", 'VariableNames', {'match_substring', ...
                'sample_id', 'project', 'operator', 'instrument_type', ...
                'instrument_title'}), mapPath);
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.elab.timezone = "Test/Zone";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.run.root_dir = fullfile(folder, "runs");
            fake = TestIngestPolicy.baseClient("Session");
        end

        function [cfg, fake, filePath] = failedWatchCase(testCase, mode)
            [cfg, fake, filePath] = testCase.watchCase();
            writelines("", filePath);
            cfg.ingest.archive_mode = mode;
        end

        function [source, destination] = archiveCase(testCase, sourceText, ...
                destinationText, extension)
            arguments
                testCase
                sourceText (1,1) string
                destinationText (1,1) string
                extension (1,1) string = ".dat"
            end
            folder = testCase.temporaryWorkingFolder();
            sourceFolder = fullfile(folder, "inbox");
            destination = fullfile(folder, "processed");
            mkdir(sourceFolder);
            mkdir(destination);
            source = fullfile(sourceFolder, "sample" + extension);
            writelines(sourceText, source);
            if destinationText ~= ""
                writelines(destinationText, ...
                    fullfile(destination, "sample" + extension));
            end
        end

        function [cfg, fake, filePath] = qcInboxCase(testCase)
            folder = testCase.temporaryWorkingFolder();
            inbox = fullfile(folder, "qc_inbox");
            processed = fullfile(folder, "processed");
            mkdir(inbox);
            mkdir(processed);
            filePath = fullfile(inbox, "xrd_test.xy");
            writematrix([1, 0; 2, 10; 3, 0], filePath, "FileType", "text");
            specs = fullfile(folder, "qc_specs.csv");
            writelines([ ...
                "match_substring,instrument_title,instrument_type,metric,target,tolerance"; ...
                "xrd_,XRD-01,Instrument,peak_x,2,0.1"], specs);
            cfg = loadConfig();
            cfg.elab.qc_category = "QC";
            cfg.elab.draft_status = "Draft";
            cfg.qc.inbox_dir = inbox;
            cfg.qc.spec_list = specs;
            cfg.watch.processed_dir = processed;
            cfg.watch.failed_dir = fullfile(folder, "failed");
            fake = TestIngestPolicy.baseClient("QC");
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                struct("id", 41, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/41", struct("id", 41, ...
                "title", "XRD-01", "category", 3, "status_title", "OK"));
            fake.setGetResponse("/teams/current/items_status", { ...
                struct("id", 11, "title", "OK", "color", "28a745"), ...
                struct("id", 12, "title", "Check", "color", "ffc107")});
        end

        function folder = temporaryWorkingFolder(testCase)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            testCase.applyFixture(fixture);
            folder = string(fixture.Folder);
            testCase.applyFixture( ...
                matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end

        function count = uploadCount(~, fake, comment)
            count = sum(cellfun(@(call) call.Method == "uploadFile" && ...
                string(call.Arguments{4}) == comment, fake.Calls));
        end

        function metadata = sentMetadata(~, fake)
            matches = fake.Calls(cellfun(@(call) call.Method == "patchJson" && ...
                isfield(call.Arguments{3}, "metadata"), fake.Calls));
            metadata = jsondecode(matches{1}.Arguments{3}.metadata);
        end

        function values = positions(~, fields, names)
            values = arrayfun(@(name) fields.(name).position, names);
        end

        function writeSettings(~, folder, contents)
            mkdir(fullfile(folder, "config"));
            writelines(contents, fullfile(folder, "config", "settings.json"));
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end

        function fake = baseClient(category)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", category));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function entry = experiment(id, hash, category)
            fields.data_file_hash = struct("type", "text", "value", hash);
            entry = struct("id", id, "category", category, "metadata", ...
                jsonencode(struct("extra_fields", fields)));
        end

        function source = fixedSource(~)
            source = struct("source_path", "X:\share\raw.xy", ...
                "source_host", "fixed-host", ...
                "source_mtime", "2026-09-21T13:00");
        end

        function timezone = fixedTimezone(~)
            timezone = "Test/Zone";
        end

        function failWrite(~, ~)
            error("TestIngestPolicy:sidecarFailure", "Injected write failure.");
        end
    end
end
