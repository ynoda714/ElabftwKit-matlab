function tests = test_nmr_preview_smoke()
% test_nmr_preview_smoke  Exercise each offline NMR preview ingestion stage.
    tests = functiontests(localfunctions);
end

function test_stage01_logsNmrPreviewFieldsAndAttachments(tc)
    state = localState(tc);
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    fields = localNmrFields(state.fake);
    uploads = localUploads(state.fake);
    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, [string(fields.quicklook_profile.value), string(fields.anynmr_version.value), ...
        string(fields.provenance_file.value), string(fields.schema_version.value), string(fields.data_unit.value)], ...
        ["light;900x460;120dpi;interp=none", "v1.0.0", "dataset_1_provenance.json", "1.2", "folder"]);
    verifyEqual(tc, string(cellfun(@(call) call.Arguments{4}, uploads, UniformOutput=false)), ["quick look", "provenance"]);
end

function test_stage02_uploadedProvenanceMatchesPinnedVendor(tc)
    state = localState(tc);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    uploads = localUploads(state.fake);
    provenance = jsondecode(fileread(uploads{2}.Arguments{3}));
    info = elab.util.anynmrInfo();
    verifyEqual(tc, string(provenance.anynmr.commit), string(info.commit));
    verifyTrue(tc, provenance.anynmr.files_verified);
end

function test_stage03_writesProvenanceAndPreservesFullHash(tc)
    state = localState(tc);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    archives = dir(fullfile(state.cfg.run.root_dir, "*"));
    archives = archives([archives.isdir] & ~ismember(string({archives.name}), [".", ".."]));
    path = fullfile(archives(1).folder, archives(1).name, "dataset_1_provenance.json");
    archived = fullfile(state.cfg.watch.processed_dir, "dataset_1");
    verifyTrue(tc, isfile(path));
    verifyEqual(tc, elab.io.experimentManifest(archived).fullHash, state.before.fullHash);
end

function test_stage04_writesNmrProvenanceSidecarFields(tc)
    state = localState(tc);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    sidecar = jsondecode(fileread(fullfile(state.cfg.watch.processed_dir, "dataset_1.elab.json")));
    verifyEqual(tc, [string(sidecar.anynmr_version), string(sidecar.provenance_file)], ...
        ["v1.0.0", "dataset_1_provenance.json"]);
end

function test_stage05_previewFailureLogsWithoutNmrAttachments(tc)
    state = localState(tc);
    output = evalc("results = elab.pipeline.watchAndLog(state.fake, state.cfg, spectrumReader=@localFailSpectrum);");
    fields = localNmrFields(state.fake);
    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, count(output, "NMR preview was skipped"), 1);
    verifyEqual(tc, string(fields.quicklook_profile.value), "none");
    verifyFalse(tc, isfield(fields, "anynmr_version") || isfield(fields, "provenance_file"));
    verifyEmpty(tc, localUploads(state.fake));
end

function test_stage06_keepsSingleFileBehavior(tc)
    state = localState(tc, includeXrd=true);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    path = fullfile(state.cfg.watch.processed_dir, "xrd_test.elab.json");
    uploads = localUploads(state.fake);
    verifyTrue(tc, isfile(path));
    content = string(fileread(path));
    verifyNotEmpty(tc, strtrim(content));
    sidecar = jsondecode(content);
    verifyEqual(tc, string(sidecar.data_unit), "file");
    verifyFalse(tc, isfield(sidecar, "anynmr_version") || isfield(sidecar, "provenance_file"));
    comments = string(cellfun(@(call) call.Arguments{4}, uploads, UniformOutput=false));
    verifyTrue(tc, any(comments == "raw instrument file"));
end

function test_stage07_reingestedFolderSkips(tc)
    state = localState(tc);
    elab.pipeline.watchAndLog(state.fake, state.cfg);
    archived = fullfile(state.cfg.watch.processed_dir, "dataset_1");
    copyfile(archived, fullfile(state.cfg.watch.inbox_dir, "dataset", "1"));
    payload = struct("data_file_hash", state.before.coreHash);
    state.fake.setGetResponse("/experiments", {localExisting(payload)});
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    verifyEqual(tc, results.status, "skipped");
    verifyEqual(tc, localCreateCount(state.fake), 1);
end

function state = localState(tc, opts)
    arguments
        tc
        opts.variant (1,1) string = "normal"
        opts.includeXrd (1,1) logical = false
    end
    fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
    tc.applyFixture(fixture);
    root = string(fixture.Folder);
    tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(root));
    state.cfg = loadConfig();
    state.cfg.elab.base_url = "https://example.test";
    state.cfg.elab.session_category = "Session";
    state.cfg.elab.report_category = "Report";
    state.cfg.elab.draft_status = "Draft";
    state.cfg.watch.inbox_dir = fullfile(root, "inbox");
    state.cfg.watch.processed_dir = fullfile(root, "processed");
    state.cfg.watch.failed_dir = fullfile(root, "failed");
    state.cfg.watch.sample_map = localMap(root);
    state.cfg.run.root_dir = fullfile(root, "runs");
    state.run = elab.io.writeMockNmrRun(fullfile(state.cfg.watch.inbox_dir, "dataset"), name="1", variant=opts.variant);
    state.before = elab.io.experimentManifest(state.run);
    if opts.includeXrd
        writematrix([1, 0; 2, 10; 3, 0], fullfile(state.cfg.watch.inbox_dir, "xrd_test.xy"), FileType="text");
    end
    state.fake = localClient();
end

function path = localMap(root)
    path = fullfile(root, "sample_map.csv");
    names = {'match_substring', 'sample_id', 'project', 'operator', 'instrument_type', ...
        'instrument_title', 'consumable_title', 'consumable_qty'};
    map = table("dataset", "SMP-1", "P-1", "operator", "Instrument", "NMR-01", "", 1, VariableNames=names);
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

function fields = localNmrFields(fake)
    fields = localFields(fake, "folder");
end

function fields = localFileFields(fake)
    fields = localFields(fake, "file");
end

function fields = localFields(fake, unit)
    calls = fake.Calls(cellfun(@(call) call.Method == "patchJson" && ...
        isfield(call.Arguments{3}, "metadata"), fake.Calls));
    for index = 1:numel(calls)
        metadata = jsondecode(calls{index}.Arguments{3}.metadata);
        candidate = metadata.extra_fields;
        if string(candidate.data_unit.value) == unit
            fields = candidate;
            return
        end
    end
    error("test:nmrPreview:missingMetadata", "No metadata was recorded for the requested unit.");
end

function uploads = localUploads(fake)
    uploads = fake.Calls(cellfun(@(call) call.Method == "uploadFile", fake.Calls));
end

function count = localCreateCount(fake)
    count = sum(cellfun(@(call) call.Method == "createEntry" && string(call.Arguments{1}) == "experiments", fake.Calls));
end

function entry = localExisting(payload)
    fields.data_file_hash = struct("type", "text", "value", payload.data_file_hash);
    entry = struct("id", 72, "category", 7, "metadata", jsonencode(struct("extra_fields", fields)));
end

function spectrum = localFailSpectrum(~)
    error("test:nmrPreview:readerFailed", "Injected preview failure.");
    spectrum = struct();
end
