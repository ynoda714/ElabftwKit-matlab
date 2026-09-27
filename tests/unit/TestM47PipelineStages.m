classdef TestM47PipelineStages < matlab.unittest.TestCase
    % TestM47PipelineStages  Public contracts for the session-ingest pipeline stages.

    properties (TestParameter)
        archiveCase = struct( ...
            "loggedMove", struct("mode", "move", "outcome", "logged"), ...
            "skippedMove", struct("mode", "move", "outcome", "skipped"), ...
            "failedMove", struct("mode", "move", "outcome", "failed"), ...
            "loggedCopy", struct("mode", "copy", "outcome", "logged"), ...
            "skippedCopy", struct("mode", "copy", "outcome", "skipped"), ...
            "failedCopy", struct("mode", "copy", "outcome", "failed"), ...
            "loggedLeave", struct("mode", "leave", "outcome", "logged"), ...
            "skippedLeave", struct("mode", "leave", "outcome", "skipped"), ...
            "failedLeave", struct("mode", "leave", "outcome", "failed"));
    end

    methods (TestClassSetup)
        function addSourceToPath(tc)
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestM47PipelineStages.projectRoot(), "src"), ...
                IncludingSubfolders=true));
        end
    end

    methods (Test)
        function testReadSessionFileReturnsParsedSessionWithoutClient(tc)
            [cfg, paths] = tc.sessionCase();

            session = elab.pipeline.readSessionFile(paths.matched, cfg);

            tc.verifyEqual(session.filePath, paths.matched);
            tc.verifyEqual(session.fileName, "xrd_matched.xy");
            tc.verifyEqual(session.baseName, "xrd_matched");
            tc.verifyTrue(isfield(session, "parsed"));
            tc.verifyTrue(isfield(session, "info"));
            tc.verifyEqual(session.hash, string(elab.util.fileHash(paths.matched)));
            tc.verifyEqual(session.runMinutes, 10);
            tc.verifyEqual(session.runMinutesSource, "nominal");
        end

        function testMatchSampleReturnsCaseInsensitiveBindingAndEmpty(tc)
            [cfg, ~] = tc.sessionCase();
            map = elab.pipeline.readSampleMap(cfg);

            binding = elab.pipeline.matchSample(map, "XRD_MATCHED.xy");
            noBinding = elab.pipeline.matchSample(map, "raman_unknown.txt");

            tc.verifyEqual(binding, table2struct(map(1, :)));
            tc.verifyEmpty(noBinding);
        end

        function testSessionFieldsMatchPreRefactorGoldenForBinding(tc)
            [cfg, paths] = tc.sessionCase();
            map = elab.pipeline.readSampleMap(cfg);
            session = tc.contextualSession(paths.matched, cfg);
            binding = elab.pipeline.matchSample(map, paths.matched);
            loggedAt = datetime("2026-09-21 12:00:00");

            fields = elab.pipeline.sessionFields(session, binding, cfg, ...
                tc.kitInfo(), tc.profile(), loggedAt=loggedAt);
            actual = tc.normalizedMetadataFromFields(fields);
            expected = tc.goldenMetadata("xrd_matched.xy");

            tc.verifyEqual(actual, expected);
            tc.verifyEqual(fields(tc.fieldIndex(fields, "logged_at")).value, loggedAt);
        end

        function testSessionFieldsUseParsedCanonicalFieldsWithoutBinding(tc)
            [cfg, paths] = tc.sessionCase();
            session = tc.contextualSession(paths.matched, cfg);
            session.parsed.params = [ ...
                elab.util.fieldStruct("sample_id", "SMP-PARSED", "text"), ...
                elab.util.fieldStruct("instrument_title", "XRD-PARSED", "text"), ...
                elab.util.fieldStruct("operator", "operator-parsed", "text"), ...
                elab.util.fieldStruct("project", "PRJ-PARSED", "text")];

            fields = elab.pipeline.sessionFields(session, [], cfg, ...
                tc.kitInfo(), tc.profile(), loggedAt=datetime("2026-09-21"));

            tc.verifyEqual(string({fields(1:4).name}), ...
                ["sample_id", "instrument_title", "operator", "project"]);
            tc.verifyEqual(string({fields(1:4).value}), ...
                ["SMP-PARSED", "XRD-PARSED", "operator-parsed", "PRJ-PARSED"]);
        end

        function testFindLoggedSessionUsesConfiguredCategory(tc)
            [cfg, paths] = tc.sessionCase();
            session = elab.pipeline.readSessionFile(paths.matched, cfg);
            fake = tc.sessionClient();
            fake.setGetResponse("/experiments", {tc.experiment(72, session.hash, 7)});

            id = elab.pipeline.findLoggedSession(fake, cfg, session);

            tc.verifyEqual(id, 72);
            tc.verifyTrue(tc.hasGetQuery(fake, "cat", 7));
        end

        function testCreateSessionExperimentOnlyCreatesFieldsAndAttachments(tc)
            [cfg, paths] = tc.sessionCase();
            map = elab.pipeline.readSampleMap(cfg);
            session = tc.contextualSession(paths.matched, cfg);
            binding = elab.pipeline.matchSample(map, paths.matched);
            fake = tc.sessionClient();
            runDir = fullfile(fileparts(paths.matched), "runs");
            mkdir(runDir);

            [experimentId, png] = elab.pipeline.createSessionExperiment( ...
                fake, cfg, session, binding, runDir, tc.kitInfo());

            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyTrue(endsWith(png, "xrd_matched_quicklook.png"));
            tc.verifyEqual(tc.callCount(fake, "linkTo"), 0);
            tc.verifyEqual(tc.itemPatchCount(fake), 0);
            tc.verifyTrue(isfile(paths.matched));
        end

        function testLinkSessionItemsWithEmptyBindingDoesNothing(tc)
            [cfg, ~] = tc.sessionCase();
            fake = tc.sessionClient();

            [instrumentId, sampleId] = elab.pipeline.linkSessionItems(fake, cfg, 501, []);

            tc.verifyEmpty(instrumentId);
            tc.verifyEmpty(sampleId);
            tc.verifyEmpty(fake.Calls);
        end

        function testArchiveIngestedAppliesOutcomePolicy(tc, archiveCase)
            tc.verifyArchiveCase(archiveCase);
        end

        function testReassembledStagesSkipLedgerInventoryAndAppendExtraField(tc)
            [cfg, paths] = tc.sessionCase();
            map = elab.pipeline.readSampleMap(cfg);
            session = tc.contextualSession(paths.matched, cfg);
            binding = elab.pipeline.matchSample(map, paths.matched);
            fake = tc.sessionClient();
            runDir = fullfile(fileparts(paths.matched), "runs");
            mkdir(runDir);
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestM47PipelineStages.projectRoot(), "tests", ...
                "fixtures", "capture_extra_fields"), IncludingSubfolders=true));
            extra = elab.util.fieldStruct("operator_note", "manual note", "text");

            [experimentId, ~] = elab.pipeline.createSessionExperiment( ...
                fake, cfg, session, binding, runDir, tc.kitInfo(), extraFields=extra);
            elab.pipeline.linkSessionItems(fake, cfg, experimentId, binding);
            archivedPath = elab.pipeline.archiveIngested(paths.matched, "logged", cfg);
            elab.pipeline.writeSessionSidecar(session, experimentId, cfg, tc.kitInfo(), ...
                archivedPath, runDir);

            captured = tc.capturedFields(fake);
            tc.verifyEqual(captured(end).name, "operator_note");
            tc.verifyEqual(captured(end).value, "manual note");
            tc.verifyEqual(tc.itemPatchCount(fake), 2);
            tc.verifyFalse(tc.hasItemMetadataPatch(fake));
            tc.verifyTrue(isfile(fullfile(cfg.watch.processed_dir, "xrd_matched.xy")));
        end

        function testQcInboxGetsKitVersionOnceForTwoFiles(tc)
            [cfg, ~] = tc.qcInboxCase();
            fake = tc.qcClient();
            global M47KitVersionCalls
            M47KitVersionCalls = 0;
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestM47PipelineStages.projectRoot(), "tests", ...
                "fixtures", "m4_7_kit_counter"), IncludingSubfolders=true));

            results = elab.pipeline.qcInbox(fake, cfg);

            tc.verifyEqual(numel(results), 2);
            tc.verifyEqual(M47KitVersionCalls, 1);
        end

        function testQcProvenanceRetainsFieldOrder(tc)
            [cfg, filePath, spec] = tc.qcCheckCase();
            fake = tc.qcClient();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestM47PipelineStages.projectRoot(), "tests", ...
                "fixtures", "capture_extra_fields"), IncludingSubfolders=true));

            elab.pipeline.qcCheck(fake, cfg, filePath, spec, kitInfo=tc.kitInfo());

            fields = tc.capturedFields(fake);
            names = string({fields.name});
            tc.verifyEqual(names(endsWith(names, ["data_file_name", "data_file_hash", ...
                "kit_version", "kit_commit", "matlab_version", "parser", ...
                "quicklook_profile"])), [ ...
                "data_file_name", "data_file_hash", "kit_version", "kit_commit", ...
                "matlab_version", "parser", "quicklook_profile"]);
        end

        function testQcCheckWithoutKitInfoStillReadsKitVersion(tc)
            [cfg, filePath, spec] = tc.qcCheckCase();
            fake = tc.qcClient();
            global M47KitVersionCalls
            M47KitVersionCalls = 0;
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestM47PipelineStages.projectRoot(), "tests", ...
                "fixtures", "m4_7_kit_counter"), IncludingSubfolders=true));

            [passed, experimentId] = elab.pipeline.qcCheck(fake, cfg, filePath, spec);

            tc.verifyTrue(passed);
            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyEqual(M47KitVersionCalls, 1);
        end
    end

    methods (Access = private)
        function [cfg, paths] = sessionCase(tc)
            folder = tc.temporaryFolder();
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            mapPath = fullfile(mapDir, "sample_map.csv");
            map = table("matched", "SMP-1", "P-1", "operator", ...
                "Instrument", "XRD-01", "", 1, 'VariableNames', ...
                {'match_substring', 'sample_id', 'project', 'operator', ...
                'instrument_type', 'instrument_title', 'consumable_title', ...
                'consumable_qty'});
            writetable(map, mapPath);
            paths.matched = fullfile(inbox, "xrd_matched.xy");
            writematrix([1, 0; 2, 11; 3, 0], paths.matched, FileType="text");
            cfg = loadConfig();
            cfg.elab.base_url = "https://example.test";
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.elab.instrument_category = "Instrument";
            cfg.elab.sample_category = "Sample";
            cfg.elab.consumable_category = "Consumable";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.watch.nominal_run_minutes = 10;
            cfg.ingest.archive_mode = "move";
        end

        function session = contextualSession(~, filePath, cfg)
            session = elab.pipeline.readSessionFile(filePath, cfg);
            session = elab.pipeline.addSessionContext(session, cfg, ...
                sourceLocator=@TestM47PipelineStages.fixedSource, ...
                timezoneResolver=@TestM47PipelineStages.fixedTimezone);
        end

        function fake = sessionClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/teams/current/resources_categories", { ...
                struct("id", 3, "title", "Instrument"), ...
                struct("id", 4, "title", "Sample")});
            fake.setGetResponse("/items", {});
        end

        function [cfg, paths] = qcInboxCase(tc)
            folder = tc.temporaryFolder();
            cfg = tc.qcConfig(folder);
            mkdir(cfg.qc.inbox_dir);
            tc.writeSpectrum(fullfile(cfg.qc.inbox_dir, "xrd_one.xy"));
            tc.writeSpectrum(fullfile(cfg.qc.inbox_dir, "xrd_two.xy"));
            writelines([ ...
                "match_substring,instrument_title,instrument_type,metric,target,tolerance"; ...
                "xrd_,XRD-01,Instrument,peak_x,2,0.1"], cfg.qc.spec_list);
            paths = string({dir(fullfile(cfg.qc.inbox_dir, "*.xy")).name});
        end

        function [cfg, filePath, spec] = qcCheckCase(tc)
            folder = tc.temporaryFolder();
            cfg = tc.qcConfig(folder);
            filePath = fullfile(folder, "xrd_test.xy");
            tc.writeSpectrum(filePath);
            spec = struct("matchSubstring", "xrd_", "instrumentTitle", "XRD-01", ...
                "instrumentType", "Instrument", "metric", "peak_x", ...
                "target", 2, "tolerance", 0.1);
        end

        function cfg = qcConfig(~, folder)
            cfg = loadConfig();
            cfg.elab.base_url = "https://example.test";
            cfg.elab.qc_category = "QC";
            cfg.elab.draft_status = "Draft";
            cfg.elab.instrument_category = "Instrument";
            cfg.qc.inbox_dir = fullfile(folder, "qc_inbox");
            cfg.qc.spec_list = fullfile(folder, "qc_specs.csv");
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.ingest.archive_mode = "move";
        end

        function fake = qcClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "QC"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", struct("id", 41, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/41", struct("id", 41, "title", "XRD-01", ...
                "category", 3, "status_title", "OK", "metadata", ""));
            fake.setGetResponse("/teams/current/items_status", { ...
                struct("id", 11, "title", "OK", "color", "28a745"), ...
                struct("id", 12, "title", "Check", "color", "ffc107")});
        end

        function verifyArchiveCase(tc, archiveCase)
            folder = tc.temporaryFolder();
            filePath = fullfile(folder, "input.xy");
            tc.writeSpectrum(filePath);
            cfg = tc.qcConfig(folder);
            cfg.ingest.archive_mode = archiveCase.mode;

            archivedPath = elab.pipeline.archiveIngested(filePath, archiveCase.outcome, cfg);

            shouldArchive = (archiveCase.outcome == "logged" && ...
                archiveCase.mode ~= "leave") || archiveCase.mode == "move";
            tc.verifyEqual(archivedPath ~= "", shouldArchive);
            tc.verifyEqual(isfile(filePath), archiveCase.mode ~= "move");
            if shouldArchive
                tc.verifyTrue(isfile(archivedPath));
            end
        end

        function metadata = normalizedMetadataFromFields(~, fields)
            fake = FakeElabClient();
            elab.client.setExtraFields(fake, "experiments", 1, fields);
            payload = fake.Calls{1}.Arguments{3};
            metadata = TestM47PipelineStages.normalizeMetadata(jsondecode(payload.metadata));
        end

        function metadata = goldenMetadata(~, fileName)
            root = TestM47PipelineStages.projectRoot();
            calls = jsondecode(fileread(fullfile(root, "tests", "fixtures", ...
                "watch_and_log_sequence_calls.json")));
            metadata = struct();
            for k = 1:numel(calls)
                call = calls(k);
                if call.Method ~= "patchJson" || string(call.Arguments{1}) ~= "experiments"
                    continue
                end
                payload = call.Arguments{3};
                if isfield(payload, "metadata")
                    decoded = jsondecode(payload.metadata);
                    if string(decoded.extra_fields.data_file_name.value) == fileName
                        metadata = TestM47PipelineStages.normalizeMetadata(decoded);
                        return
                    end
                end
            end
        end

        function tf = hasGetQuery(~, fake, name, value)
            tf = false;
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method ~= "getJson" || numel(call.Arguments) < 2
                    continue
                end
                query = call.Arguments{2};
                nameIndex = find(string(query(1:2:end)) == name, 1);
                if ~isempty(nameIndex) && query{2 * nameIndex} == value
                    tf = true;
                    return
                end
            end
        end

        function count = callCount(~, fake, method)
            count = sum(cellfun(@(call) call.Method == method, fake.Calls));
        end

        function count = itemPatchCount(~, fake)
            count = sum(cellfun(@(call) call.Method == "patchJson" && ...
                call.Arguments{1} == "items", fake.Calls));
        end

        function tf = hasItemMetadataPatch(~, fake)
            tf = false;
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && call.Arguments{1} == "items" && ...
                        isfield(call.Arguments{3}, "metadata")
                    tf = true;
                    return
                end
            end
        end

        function fields = capturedFields(~, fake)
            calls = fake.Calls(cellfun(@(call) call.Method == "setExtraFieldsInput", fake.Calls));
            fields = calls{1}.Arguments{3};
        end

        function index = fieldIndex(~, fields, name)
            index = find(string({fields.name}) == name, 1);
        end

        function folder = temporaryFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end

        function writeSpectrum(~, filePath)
            writematrix([1, 0; 2, 10; 3, 0], filePath, FileType="text");
        end

        function info = kitInfo(~)
            info = struct("version", "0.1.0-dev", "commit", "7105b6d");
        end

        function profile = profile(~)
            profile = "light;900x460;120dpi;interp=none";
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end

        function item = experiment(id, hash, category)
            fields.data_file_hash = struct("type", "text", "value", hash);
            item = struct("id", id, "category", category, "metadata", ...
                jsonencode(struct("extra_fields", fields)));
        end

        function source = fixedSource(~)
            source = struct("source_path", "X:\\raw\\fixed.xy", ...
                "source_host", "fixed-host", "source_mtime", "2026-09-21T13:00");
        end

        function timezone = fixedTimezone(~)
            timezone = "Test/Zone";
        end

        function metadata = normalizeMetadata(metadata)
            names = ["acquired_at", "logged_at", "last_used"];
            for name = names
                if isfield(metadata.extra_fields, name)
                    metadata.extra_fields.(name).value = "<TIME>";
                end
            end
        end
    end
end
