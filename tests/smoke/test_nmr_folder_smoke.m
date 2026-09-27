function tests = test_nmr_folder_smoke()
% test_nmr_folder_smoke  Run each offline folder ingestion stage independently.
    tests = functiontests(localfunctions);
end

function test_stage01_inboxLogsFolderAndFile(tc)
    state = localCase(tc, true);
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    verifyEqual(tc, string({results.file}), ["xrd_test.xy", "dataset/1"]);
    verifyEqual(tc, string({results.status}), ["logged", "logged"]);
end

function test_stage02_folderMetadataHasExpectedValuesAndGroups(tc)
    state = localCase(tc, false);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    fields = localNmrFields(state.fake);
    verifyEqual(tc, string(fields.data_unit.value), "folder");
    verifyEqual(tc, string(fields.schema_version.value), "1.2");
    verifyEqual(tc, string(fields.data_file_hash.value), state.before.coreHash);
    verifyEqual(tc, string(fields.acquired_at.value), "2026-09-24T09:00");
    verifyEqual(tc, string(fields.acquired_at_source.value), "file");
    verifyEqual(tc, double(string(fields.run_minutes.value)), 38 / 60, AbsTol=1e-9);
    verifyEqual(tc, string(fields.run_minutes_source.value), "measured");
    verifyEqual(tc, string(fields.parser.value), "elab.io.parseBrukerExperiment");
    verifyEqual(tc, [fields.nucleus.group_id, fields.sw_hz.group_id], [2, 2]);
end

function test_stage03_folderSkipsUploadAndFileUploadsRaw(tc)
    state = localCase(tc, true);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    raw = localUploads(state.fake, "raw instrument file");
    verifyNumElements(tc, raw, 1);
    verifyTrue(tc, endsWith(string(raw{1}.Arguments{3}), "xrd_test.xy"));
end

function test_stage04_archivePreservesManifestAndSidecar(tc)
    state = localCase(tc, false);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    archived = fullfile(state.cfg.watch.processed_dir, "dataset_1");
    verifyEqual(tc, elab.io.experimentManifest(archived).fullHash, state.before.fullHash);
    verifyTrue(tc, isfolder(fullfile(state.cfg.watch.inbox_dir, "dataset")));
    verifyTrue(tc, isfile(fullfile(state.cfg.watch.processed_dir, "dataset_1.elab.json")));
end

function test_stage05_duplicateSkipsArchivesAndDoesNotUpdateResources(tc)
    state = localCase(tc, false);
    state.fake.setGetResponse("/experiments", {localExisting(state.before.coreHash)});
    mkdir(state.cfg.watch.processed_dir);
    copyfile(state.run, fullfile(state.cfg.watch.processed_dir, "dataset_1"));
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    archived = dir(fullfile(state.cfg.watch.processed_dir, "dataset_1__*"));
    verifyEqual(tc, results.status, "skipped");
    verifyEqual(tc, localCreateCount(state.fake, "experiments"), 0);
    verifyNumElements(tc, archived, 1);
    verifyEqual(tc, localResourceMutationCount(state.fake), 0);
end

function test_stage06_auxiliaryChangeSkipsAndWarns(tc)
    state = localCase(tc, false);
    old = state.before;
    writelines("##$AUX= 2", fullfile(state.run, "uxnmr.par"));
    mkdir(state.cfg.watch.processed_dir);
    payload = struct("data_unit", "folder", "data_file_hash", old.coreHash, "data_file_manifest_hash", old.fullHash);
    elab.io.writeElabSidecar(fullfile(state.cfg.watch.processed_dir, "dataset_1"), payload);
    state.fake.setGetResponse("/experiments", {localExisting(old.coreHash)});
    output = evalc("results = elab.pipeline.watchAndLog(state.fake, state.cfg);");
    verifyEqual(tc, results.status, "skipped");
    verifySubstring(tc, output, "changed outside the acquisition hash core");
end

function test_stage07_coreChangeCreatesNewExperiment(tc)
    state = localCase(tc, false);
    lines = readlines(fullfile(state.run, "acqus"));
    writelines(replace(lines, "##$NS= 16", "##$NS= 17"), fullfile(state.run, "acqus"));
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, localCreateCount(state.fake, "experiments"), 1);
end

function test_stage08_twoDimensionalRunFailsAndArchives(tc)
    state = localCase(tc, false, variant="twoDimensional");
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    verifyEqual(tc, results.status, "failed");
    verifySubstring(tc, results.message, "unsupported experiment dimension");
    verifyTrue(tc, isfolder(fullfile(state.cfg.watch.failed_dir, "dataset_1")));
    verifyEqual(tc, localCreateCount(state.fake, "experiments"), 0);
end

function test_stage09_inboxArchiveDirectoriesAreNotReingested(tc)
    state = localCase(tc, false);
    state.cfg.watch.processed_dir = fullfile(state.cfg.watch.inbox_dir, "processed");
    state.cfg.watch.failed_dir = fullfile(state.cfg.watch.inbox_dir, "failed");
    mkdir(state.cfg.watch.processed_dir);
    movefile(state.run, fullfile(state.cfg.watch.processed_dir, "dataset_1"));
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    verifyEmpty(tc, results);
end

function test_stage10_monthlyReportCountsMeasuredAndCalculatedNmr(tc)
    state = localCase(tc, false);
    measured = localEntry(101, localMetadataForRun(state.run, state.cfg), "2026-09-24");
    noAuditAt = datetime(2026, 9, 24, 10, 0, 0);
    noAudit = elab.io.writeMockNmrRun(fullfile(state.root, "second"), name="2", ...
        acquiredAt=noAuditAt, variant="noAudit");
    calculated = localEntry(102, localMetadataForRun(noAudit, state.cfg), "2026-09-24");
    xrd = localEntry(103, localXrdMetadata(), "2026-09-24");
    fake = localReportClient({measured, calculated, xrd});
    reportId = elab.pipeline.monthlyUsageReport(fake, state.cfg, 2026, 9);
    verifyEqual(tc, reportId, fake.CreatedId);
    verifySubstring(tc, localReportBody(fake), "<td style=""text-align:right"">1</td>");
end

function test_stage11_emptyAuxiliaryLogsAndEmptyFidFails(tc)
    logged = localCase(tc, false);
    localWriteEmptyFile(fullfile(logged.run, "prosol_History"));
    session = elab.pipeline.readSessionFile(logged.run, logged.cfg);
    results = elab.pipeline.watchAndLog(logged.fake, logged.cfg);
    verifyEqual(tc, session.unit, "folder");
    verifyEqual(tc, results.status, "logged");
    failed = localCase(tc, false, variant="emptyFid");
    failedResults = elab.pipeline.watchAndLog(failed.fake, failed.cfg);
    verifyEqual(tc, failedResults.status, "failed");
    verifySubstring(tc, failedResults.message, "empty fid");
end

function state = localCase(tc, includeXrd, opts)
    arguments
        tc
        includeXrd (1,1) logical
        opts.variant (1,1) string = "normal"
    end
    projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    addpath(genpath(fullfile(projectRoot, "src")));
    addpath(fullfile(projectRoot, "tests", "unit"));
    fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
    tc.applyFixture(fixture);
    state.root = string(fixture.Folder);
    tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(state.root));
    state.cfg = loadConfig();
    state.cfg.elab.base_url = "https://example.test";
    state.cfg.elab.session_category = "Session";
    state.cfg.elab.report_category = "Report";
    state.cfg.elab.draft_status = "Draft";
    state.cfg.watch.inbox_dir = fullfile(state.root, "inbox");
    state.cfg.watch.processed_dir = fullfile(state.root, "processed");
    state.cfg.watch.failed_dir = fullfile(state.root, "failed");
    state.cfg.watch.sample_map = localMap(state.root);
    state.cfg.run.root_dir = fullfile(state.root, "runs");
    acquiredAt = datetime(2026, 9, 24, 9, 0, 0);
    state.run = elab.io.writeMockNmrRun(fullfile(state.cfg.watch.inbox_dir, "dataset"), ...
        name="1", acquiredAt=acquiredAt, variant=opts.variant);
    state.before = elab.io.experimentManifest(state.run);
    if includeXrd
        writematrix([1, 0; 2, 10; 3, 0], fullfile(state.cfg.watch.inbox_dir, "xrd_test.xy"), FileType="text");
    end
    state.fake = localClient();
end

function path = localMap(root)
    path = fullfile(root, "sample_map.csv");
    names = {'match_substring', 'sample_id', 'project', 'operator', 'instrument_type', ...
        'instrument_title', 'consumable_title', 'consumable_qty'};
    map = table("dataset", "SMP-1", "P-1", "operator", "Instrument", "NMR-01", "", 1, 'VariableNames', names);
    writetable(map, path);
end

function fake = localClient()
    fake = FakeElabClient();
    fake.setGetResponse("/experiments", {});
    categories = {struct("id", 7, "title", "Session"), struct("id", 8, "title", "Report")};
    fake.setGetResponse("/teams/current/experiments_categories", categories);
    fake.setGetResponse("/teams/current/experiments_status", struct("id", 5, "title", "Draft"));
    resources = {struct("id", 3, "title", "Instrument"), struct("id", 4, "title", "Sample"), ...
        struct("id", 5, "title", "Consumable")};
    fake.setGetResponse("/teams/current/resources_categories", resources);
    statuses = {struct("id", 11, "title", "OK", "color", "28a745"), ...
        struct("id", 12, "title", "CalibrationOverdue", "color", "dc3545"), ...
        struct("id", 13, "title", "InStock", "color", "28a745"), ...
        struct("id", 14, "title", "Reorder", "color", "fd7e14")};
    fake.setGetResponse("/teams/current/items_status", statuses);
    fake.setGetResponse("/items", {});
end

function item = localExisting(hash)
    fields.data_file_hash = struct("type", "text", "value", hash);
    item = struct("id", 72, "category", 7, "metadata", jsonencode(struct("extra_fields", fields)));
end

function fields = localNmrFields(fake)
    keep = cellfun(@(call) call.Method == "patchJson" && isfield(call.Arguments{3}, "metadata"), fake.Calls);
    calls = fake.Calls(keep);
    metadata = jsondecode(calls{1}.Arguments{3}.metadata);
    fields = metadata.extra_fields;
end

function uploads = localUploads(fake, comment)
    keep = cellfun(@(call) call.Method == "uploadFile" && string(call.Arguments{4}) == comment, fake.Calls);
    uploads = fake.Calls(keep);
end

function count = localCreateCount(fake, kind)
    count = sum(cellfun(@(call) call.Method == "createEntry" && string(call.Arguments{1}) == kind, fake.Calls));
end

function count = localResourceMutationCount(fake)
    isResourceCall = @(call) any(call.Method == ["createEntry", "patchJson", "linkTo"]);
    isItemCall = @(call) isResourceCall(call) && string(call.Arguments{1}) == "items";
    count = sum(cellfun(isItemCall, fake.Calls));
end

function metadata = localMetadataForRun(path, cfg)
    session = elab.pipeline.readSessionFile(path, cfg);
    session = elab.pipeline.addSessionContext(session, cfg, sourceLocator=@localSource, ...
        timezoneResolver=@(~) "Asia/Tokyo");
    fields = elab.pipeline.sessionFields(session, [], cfg, struct("version", "test", "commit", "test"), "none");
    metadata = jsonencode(struct("extra_fields", localFieldsMap(fields)));
end

function map = localFieldsMap(fields)
    map = struct();
    for k = 1:numel(fields)
        map.(fields(k).name) = struct("value", string(fields(k).value));
    end
end

function source = localSource(path)
    source = struct("source_path", path, "source_host", "host", "source_mtime", "2026-09-24T09:00");
end

function metadata = localXrdMetadata()
    fields = struct("instrument_title", struct("value", "XRD-01"), ...
        "project", struct("value", "P-1"), "operator", struct("value", "operator"), ...
        "run_minutes", struct("value", "10"), "run_minutes_source", struct("value", "nominal"), ...
        "acquired_at_source", struct("value", "file"));
    metadata = jsonencode(struct("extra_fields", fields));
end

function entry = localEntry(id, metadata, date)
    entry = struct("id", id, "date", date, "metadata", metadata);
end

function fake = localReportClient(entries)
    fake = localClient();
    fake.setGetResponse("/experiments", entries);
    fake.setGetResponse("/experiments/501", struct("uploads", struct([])));
end

function body = localReportBody(fake)
    keep = cellfun(@(value) value.Method == "patchJson" && isfield(value.Arguments{3}, "body"), fake.Calls);
    call = fake.Calls{find(keep, 1)};
    body = string(call.Arguments{3}.body);
end

function localWriteEmptyFile(path)
    fid = fopen(path, "w");
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
end
