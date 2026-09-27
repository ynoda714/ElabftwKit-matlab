classdef TestNmrFolderIngest < matlab.unittest.TestCase
    % TestNmrFolderIngest  Folder-specific contracts for Session ingestion.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true));
        end
    end

    methods (Test)
        function test_unitName_folder_returnsRelativeAndArchiveNames(tc)
            root = tc.folder();
            inbox = fullfile(root, "inbox");
            run = elab.io.writeMockNmrRun(fullfile(inbox, "dataset"), name="1");

            [name, archiveName] = elab.io.unitName(run, inbox);

            tc.verifyEqual(name, "dataset/1");
            tc.verifyEqual(archiveName, "dataset_1");
        end

        function test_unitName_file_returnsTheFileName(tc)
            root = tc.folder();
            inbox = fullfile(root, "inbox");
            mkdir(inbox);
            path = fullfile(inbox, "xrd_test.xy");
            writelines("1 2", path);

            [name, archiveName] = elab.io.unitName(path, inbox);

            tc.verifyEqual(name, "xrd_test.xy");
            tc.verifyEqual(archiveName, "xrd_test.xy");
        end

        function test_sourceLocation_folder_usesFidMtime(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(root, name="sample");
            fid = fullfile(run, "fid");
            java.io.File(char(fid)).setLastModified(1577841600000);
            expected = dir(fid);

            source = elab.io.sourceLocation(run, computerName="test-host");

            tc.verifyEqual(source.source_path, string(java.io.File(char(run)).getAbsolutePath()));
            tc.verifyEqual(source.source_mtime, string( ...
                datetime(expected.datenum, ConvertFrom="datenum"), "yyyy-MM-dd'T'HH:mm"));
        end

        function test_sourceLocation_folder_usesSerMtimeWhenFidIsAbsent(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(root, name="sample", variant="twoDimensional");
            ser = fullfile(run, "ser");
            java.io.File(char(ser)).setLastModified(1577841600000);
            expected = dir(ser);
            source = elab.io.sourceLocation(run, computerName="test-host");
            expectedMtime = string(datetime(expected.datenum, ConvertFrom="datenum"), "yyyy-MM-dd'T'HH:mm");
            tc.verifyEqual(source.source_mtime, expectedMtime);
        end

        function test_sourceLocation_folder_withoutAcquisitionFileErrors(tc)
            root = tc.folder();
            run = fullfile(root, "empty");
            mkdir(run);
            tc.verifyError(@() elab.io.sourceLocation(run), "elab:io:sourceLocation:notFound");
        end

        function test_shouldAttachRaw_folder_neverAttaches(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(root, name="sample");
            cfg.ingest = struct("attach_raw", "auto", "attach_raw_max_mb", 0);

            [attach, reason] = elab.io.shouldAttachRaw(run, cfg, pipeline="test");

            tc.verifyFalse(attach);
            tc.verifyEqual(reason, "folder");
        end

        function test_shouldAttachRaw_folder_warnsOnlyForAlways(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(root, name="sample");
            cfg.ingest = struct("attach_raw", "auto", "attach_raw_max_mb", 0);
            autoOutput = evalc("elab.io.shouldAttachRaw(run, cfg, pipeline='test');");
            cfg.ingest.attach_raw = "never";
            neverOutput = evalc("elab.io.shouldAttachRaw(run, cfg, pipeline='test');");
            cfg.ingest.attach_raw = "always";
            alwaysOutput = evalc("elab.io.shouldAttachRaw(run, cfg, pipeline='test');");
            tc.verifyEqual(count(autoOutput, "is a folder"), 0);
            tc.verifyEqual(count(neverOutput, "is a folder"), 0);
            tc.verifyEqual(count(alwaysOutput, "is a folder"), 1);
        end

        function test_shouldAttachRaw_folder_rejectsInvalidPolicy(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(root, name="sample");
            cfg.ingest = struct("attach_raw", "bad", "attach_raw_max_mb", 0);
            tc.verifyError(@() elab.io.shouldAttachRaw(run, cfg), "elab:io:shouldAttachRaw:invalidPolicy");
        end

        function test_archiveFile_folder_preservesManifestOnMove(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(fullfile(root, "inbox"), name="sample");
            before = elab.io.experimentManifest(run);

            archived = elab.io.archiveFile(run, fullfile(root, "processed"), "move", name="dataset_1");

            after = elab.io.experimentManifest(archived);
            tc.verifyEqual(after.fullHash, before.fullHash);
        end

        function test_archiveFile_folder_collisionAddsTimestamp(tc)
            root = tc.folder();
            destination = fullfile(root, "processed");
            first = elab.io.writeMockNmrRun(fullfile(root, "first"), name="sample");
            second = elab.io.writeMockNmrRun(fullfile(root, "second"), name="sample");
            elab.io.archiveFile(first, destination, "move", name="dataset_1");

            archived = elab.io.archiveFile(second, destination, "move", ...
                name="dataset_1", timestamp="20260925T120000");

            tc.verifyEqual(archived, fullfile(destination, "dataset_1__20260925T120000"));
        end

        function test_archiveFile_folder_moveKeepsParentFolder(tc)
            root = tc.folder();
            parent = fullfile(root, "inbox", "dataset");
            run = elab.io.writeMockNmrRun(parent, name="1");
            elab.io.archiveFile(run, fullfile(root, "processed"), "move", name="dataset_1");
            tc.verifyTrue(isfolder(parent));
        end

        function test_archiveFile_folder_copyRetainsSourceAndManifest(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(fullfile(root, "inbox"), name="sample");
            before = elab.io.experimentManifest(run);
            archived = elab.io.archiveFile(run, fullfile(root, "processed"), "copy", name="dataset_1");
            tc.verifyTrue(isfolder(run));
            tc.verifyEqual(elab.io.experimentManifest(archived).fullHash, before.fullHash);
        end

        function test_archiveFile_folder_leaveDoesNotCreateDestination(tc)
            root = tc.folder();
            run = elab.io.writeMockNmrRun(fullfile(root, "inbox"), name="sample");
            archived = elab.io.archiveFile(run, fullfile(root, "processed"), "leave", name="dataset_1");
            tc.verifyEqual(archived, "");
            tc.verifyTrue(isfolder(run));
        end

        function test_archiveFile_folder_collisionAddsNumericSuffix(tc)
            root = tc.folder();
            destination = fullfile(root, "processed");
            first = elab.io.writeMockNmrRun(fullfile(root, "first"), name="sample");
            second = elab.io.writeMockNmrRun(fullfile(root, "second"), name="sample");
            third = elab.io.writeMockNmrRun(fullfile(root, "third"), name="sample");
            elab.io.archiveFile(first, destination, "move", name="dataset_1");
            elab.io.archiveFile(second, destination, "move", name="dataset_1", timestamp="20260925T120000");
            archived = elab.io.archiveFile(third, destination, "move", name="dataset_1", timestamp="20260925T120000");
            tc.verifyEqual(archived, fullfile(destination, "dataset_1__20260925T120000_2"));
        end

        function test_archiveIngested_folderUsesArchiveNameForEveryMoveOutcome(tc)
            root = tc.folder();
            cfg = tc.archiveConfig(root, "move");
            logged = elab.io.writeMockNmrRun(fullfile(cfg.watch.inbox_dir, "dataset"), name="1");
            skipped = elab.io.writeMockNmrRun(fullfile(cfg.watch.inbox_dir, "dataset"), name="2");
            failed = elab.io.writeMockNmrRun(fullfile(cfg.watch.inbox_dir, "dataset"), name="3");
            loggedPath = elab.pipeline.archiveIngested(logged, "logged", cfg);
            skippedPath = elab.pipeline.archiveIngested(skipped, "skipped", cfg);
            failedPath = elab.pipeline.archiveIngested(failed, "failed", cfg);
            tc.verifyEqual(string(java.io.File(char(loggedPath)).getName()), "dataset_1");
            tc.verifyEqual(string(java.io.File(char(skippedPath)).getName()), "dataset_2");
            tc.verifyEqual(string(java.io.File(char(failedPath)).getName()), "dataset_3");
        end

        function test_archiveIngested_folderCopyAndLeaveKeepSkippedAndFailedInInbox(tc)
            root = tc.folder();
            copyCfg = tc.archiveConfig(root, "copy");
            copied = elab.io.writeMockNmrRun(fullfile(copyCfg.watch.inbox_dir, "dataset"), name="1");
            skipped = elab.io.writeMockNmrRun(fullfile(copyCfg.watch.inbox_dir, "dataset"), name="2");
            failed = elab.io.writeMockNmrRun(fullfile(copyCfg.watch.inbox_dir, "dataset"), name="3");
            copiedPath = elab.pipeline.archiveIngested(copied, "logged", copyCfg);
            skippedPath = elab.pipeline.archiveIngested(skipped, "skipped", copyCfg);
            failedPath = elab.pipeline.archiveIngested(failed, "failed", copyCfg);
            leaveCfg = tc.archiveConfig(fullfile(root, "leave"), "leave");
            left = elab.io.writeMockNmrRun(fullfile(leaveCfg.watch.inbox_dir, "dataset"), name="1");
            leftPath = elab.pipeline.archiveIngested(left, "logged", leaveCfg);
            tc.verifyEqual(string(java.io.File(char(copiedPath)).getName()), "dataset_1");
            tc.verifyEqual(skippedPath, "");
            tc.verifyEqual(failedPath, "");
            tc.verifyEqual(leftPath, "");
            tc.verifyTrue(isfolder(skipped));
            tc.verifyTrue(isfolder(failed));
            tc.verifyTrue(isfolder(left));
        end

        function test_provenanceFields_sessionAddsFolderUnitAfterHash(tc)
            session = tc.session("folder");
            fields = elab.util.provenanceFields(session, tc.kit(), "none", tc.group(), ...
                includeSessionContext=true);
            names = string({fields.name});

            tc.verifyEqual(names(1:3), ["data_file_name", "data_file_hash", "data_unit"]);
        end

        function test_provenanceFields_qcOmitsSessionSchema(tc)
            session = tc.session("file");
            fields = elab.util.provenanceFields(session, tc.kit(), "none", tc.group());
            names = string({fields.name});

            tc.verifyFalse(any(names == "data_unit"));
        end

        function test_schemaVersion_returnsCurrentValue(tc)
            tc.verifyEqual(elab.util.schemaVersion(), "1.2");
        end

        function test_writeElabSidecar_folderKeepsDotInName(tc)
            root = tc.folder();
            dataPath = fullfile(root, "sample_1.5");
            mkdir(dataPath);
            payload = struct("data_unit", "folder", "data_file_hash", "hash");

            sidecar = elab.io.writeElabSidecar(dataPath, payload);

            tc.verifyEqual(sidecar, fullfile(root, "sample_1.5.elab.json"));
        end

        function test_writeSessionSidecar_folderStoresCompleteManifest(tc)
            root = tc.folder();
            cfg = tc.archiveConfig(root, "leave");
            run = elab.io.writeMockNmrRun(fullfile(cfg.watch.inbox_dir, "dataset"), name="1");
            session = tc.folderSession(run, cfg);
            runDir = fullfile(root, "runs");
            mkdir(runDir);
            elab.pipeline.writeSessionSidecar(session, 501, cfg, tc.kit(), "", runDir);
            path = fullfile(runDir, "dataset_1.elab.json");
            payload = jsondecode(fileread(path));
            tc.verifyEqual(string(payload.data_unit), "folder");
            tc.verifyEqual(string(payload.data_file_manifest_hash), session.manifest.fullHash);
            tc.verifyEqual(string(payload.manifest), session.manifest.fullText);
            tc.verifyEqual(string(payload.schema_version), "1.2");
        end

        function test_writeSessionSidecar_fileOmitsManifest(tc)
            root = tc.folder();
            cfg = tc.archiveConfig(root, "leave");
            path = fullfile(cfg.watch.inbox_dir, "xrd.xy");
            writematrix([1, 2; 2, 3], path, FileType="text");
            session = tc.fileSession(path, cfg);
            runDir = fullfile(root, "runs");
            mkdir(runDir);
            elab.pipeline.writeSessionSidecar(session, 501, cfg, tc.kit(), "", runDir);
            payload = jsondecode(fileread(fullfile(runDir, "xrd.elab.json")));
            tc.verifyEqual(string(payload.data_unit), "file");
            tc.verifyFalse(isfield(payload, "manifest"));
        end

        function test_findElabSidecar_skipsInvalidJson(tc)
            root = tc.folder();
            writelines("{", fullfile(root, "broken.elab.json"));
            elab.io.writeElabSidecar(fullfile(root, "dataset"), ...
                struct("data_unit", "folder", "data_file_hash", "core"));

            sidecar = elab.io.findElabSidecar(root, "core");

            tc.verifyEqual(sidecar, fullfile(root, "dataset.elab.json"));
        end

        function test_findElabSidecar_usesNewestMatchingHash(tc)
            root = tc.folder();
            old = elab.io.writeElabSidecar(fullfile(root, "old"), struct("data_file_hash", "core"));
            new = elab.io.writeElabSidecar(fullfile(root, "new"), struct("data_file_hash", "core"));
            java.io.File(char(old)).setLastModified(1577841600000);
            java.io.File(char(new)).setLastModified(1577845200000);
            tc.verifyEqual(elab.io.findElabSidecar(root, "core"), new);
        end

        function test_findElabSidecar_skipsDifferentHashesAndMissingFolder(tc)
            root = tc.folder();
            elab.io.writeElabSidecar(fullfile(root, "other"), struct("data_file_hash", "other"));
            tc.verifyEqual(elab.io.findElabSidecar(root, "core"), "");
            tc.verifyEqual(elab.io.findElabSidecar(fullfile(root, "missing"), "core"), "");
        end

        function test_warnManifestChange_warnsForDifferentFullHash(tc)
            root = tc.folder();
            processed = fullfile(root, "processed");
            mkdir(processed);
            session = tc.session("folder");
            session.hash = "core";
            session.manifest = struct("fullHash", "new", "fullText", "");
            elab.io.writeElabSidecar(fullfile(processed, "dataset"), ...
                struct("data_unit", "folder", "data_file_hash", "core", ...
                "data_file_manifest_hash", "old"));
            cfg.watch.processed_dir = processed;

            output = evalc("elab.pipeline.warnManifestChange(session, cfg);");

            tc.verifySubstring(output, "changed outside the acquisition hash core");
        end

        function test_warnManifestChange_isSilentForMatchingManifest(tc)
            root = tc.folder();
            [session, cfg] = tc.manifestCase(root, "same");
            output = evalc("elab.pipeline.warnManifestChange(session, cfg);");
            tc.verifyEqual(count(output, "changed outside the acquisition hash core"), 0);
        end

        function test_warnManifestChange_isSilentWithoutSidecar(tc)
            root = tc.folder();
            session = tc.session("folder");
            session.manifest = struct("fullHash", "new", "fullText", "");
            cfg.watch.processed_dir = fullfile(root, "processed");
            mkdir(cfg.watch.processed_dir);
            output = evalc("elab.pipeline.warnManifestChange(session, cfg);");
            tc.verifyEqual(count(output, "changed outside the acquisition hash core"), 0);
        end

        function test_warnManifestChange_isSilentForFileSession(tc)
            root = tc.folder();
            session = tc.session("file");
            session.manifest = struct("fullHash", "new", "fullText", "");
            cfg.watch.processed_dir = root;
            payload = struct("data_file_hash", "hash", "data_file_manifest_hash", "old");
            elab.io.writeElabSidecar(fullfile(root, "dataset"), payload);
            output = evalc("elab.pipeline.warnManifestChange(session, cfg);");
            tc.verifyEqual(count(output, "changed outside the acquisition hash core"), 0);
        end

        function test_createSessionExperiment_folderAddsPreviewAndProvenance(tc)
            root = tc.folder();
            cfg = tc.archiveConfig(root, "move");
            run = elab.io.writeMockNmrRun(fullfile(cfg.watch.inbox_dir, "dataset"), name="1");
            session = tc.folderSession(run, cfg);
            sourceLocator = @(x) tc.source(x);
            session = elab.pipeline.addSessionContext(session, cfg, sourceLocator=sourceLocator, ...
                timezoneResolver=@(~) "Asia/Tokyo");
            fake = tc.client();
            runDir = fullfile(root, "runs");
            mkdir(runDir);
            [~, png] = elab.pipeline.createSessionExperiment(fake, cfg, session, [], runDir, tc.kit());
            tc.verifyTrue(isfile(png));
            tc.verifyEqual(tc.callCount(fake, "uploadFile"), 2);
            tc.verifyEqual(tc.bodyPatchCount(fake), 1);
            tc.verifyEqual(tc.createdTitle(fake), "NMR  dataset/1");
        end

        function test_schemaVersion_sourceHasNoLegacyLiteral(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            paths = dir(fullfile(root, "src", "**", "*.m"));
            contents = arrayfun(@(x) fileread(fullfile(x.folder, x.name)), paths, UniformOutput=false);
            text = join(string(contents), newline);
            tc.verifyFalse(contains(text, '"1.0"'));
        end
    end

    methods (Access = private)
        function root = folder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
        end

        function cfg = archiveConfig(~, root, mode)
            cfg = loadConfig();
            cfg.elab.base_url = "https://example.test";
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.watch.inbox_dir = fullfile(root, "inbox");
            cfg.watch.processed_dir = fullfile(root, "processed");
            cfg.watch.failed_dir = fullfile(root, "failed");
            cfg.watch.sample_map = fullfile(root, "sample_map.csv");
            cfg.watch.nominal_run_minutes = 10;
            cfg.ingest.archive_mode = mode;
            mkdir(cfg.watch.inbox_dir);
            writetable(table("never", 'VariableNames', "match_substring"), cfg.watch.sample_map);
        end

        function session = folderSession(~, run, cfg)
            session = elab.pipeline.readSessionFile(run, cfg);
            session.source = struct("source_path", "path", "source_host", "host", "source_mtime", "2026-09-25T12:00");
            session.timezone = "Asia/Tokyo";
        end

        function session = fileSession(~, path, cfg)
            session = elab.pipeline.readSessionFile(path, cfg);
            session.source = struct("source_path", "path", "source_host", "host", "source_mtime", "2026-09-25T12:00");
            session.timezone = "Asia/Tokyo";
        end

        function [session, cfg] = manifestCase(tc, root, fullHash)
            cfg = tc.archiveConfig(root, "move");
            mkdir(cfg.watch.processed_dir);
            session = tc.session("folder");
            session.hash = "core";
            session.manifest = struct("fullHash", fullHash, "fullText", "");
            payload = struct("data_unit", "folder", "data_file_hash", "core", ...
                "data_file_manifest_hash", fullHash);
            elab.io.writeElabSidecar(fullfile(cfg.watch.processed_dir, "dataset"), payload);
        end

        function source = source(~, path)
            source = struct("source_path", path, "source_host", "host", "source_mtime", "2026-09-25T12:00");
        end

        function fake = client(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", struct("id", 5, "title", "Draft"));
        end

        function count = callCount(~, fake, name)
            count = sum(cellfun(@(value) value.Method == name, fake.Calls));
        end

        function count = bodyPatchCount(~, fake)
            isBodyPatch = @(value) value.Method == "patchJson" && isfield(value.Arguments{3}, "body");
            count = sum(cellfun(isBodyPatch, fake.Calls));
        end

        function title = createdTitle(~, fake)
            isTitlePatch = @(value) value.Method == "patchJson" && isfield(value.Arguments{3}, "title");
            call = fake.Calls{find(cellfun(isTitlePatch, fake.Calls), 1)};
            title = string(call.Arguments{3}.title);
        end
    end

    methods (Static, Access = private)
        function session = session(unit)
            session = struct("fileName", "dataset/1", "hash", "hash", ...
                "unit", unit, "source", struct("source_path", "path", ...
                "source_host", "host", "source_mtime", "2026-09-25T12:00"), ...
                "info", struct("parser", "parser"));
        end

        function group = group()
            group = struct("id", 3, "name", "Provenance");
        end

        function info = kit()
            info = struct("version", "test", "commit", "test");
        end
    end
end
