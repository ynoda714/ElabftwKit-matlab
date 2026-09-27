function tests = test_binding_layers_smoke()
% test_binding_layers_smoke  Offline split-binding watch-and-log smoke checks.

    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    tc.TestData.root = root;
    addpath(genpath(fullfile(root, "src")));
    addpath(fullfile(root, "tests", "unit"));
end

function test_exampleMaps_logDistinctBoundSessions(tc)
    state = localExampleState(tc);
    elab.io.writeMockRuns(state.cfg.watch.inbox_dir);
    elab.io.writeMockNmrRun(state.cfg.watch.inbox_dir);

    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    values = localExperimentValues(state.fake);

    verifyEqual(tc, string({results.status}), repmat("logged", 1, 7));
    verifyEqual(tc, sort(values.instrument_title), ...
        sort(["XRD-01", "Raman-01", "FTIR-01", "NMR-01", "LCMS-01", "SEM-01", "NMR-02"]));
    verifyEqual(tc, sort(values.sample_id), sort("SMP-2026-00" + string(1:7)));
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 14);
end

function test_twoInstruments_updateSeparateLedgers(tc)
    state = localState(tc, ["sem1_,SEM-01"; "sem2_,SEM-02"], ...
        ["SMP-A,SMP-A"; "SMP-B,SMP-B"]);
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "sem1_SMP-A.xy"));
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "sem2_SMP-B.xy"));

    results = elab.pipeline.watchAndLog(state.fake, state.cfg);

    verifyEqual(tc, string({results.status}), ["logged", "logged"]);
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 4);
    verifyEqual(tc, localMetadataCallCount(state.fake, "items"), 2);
end

function test_instrumentOnly_linksAndUpdatesLedger(tc)
    state = localState(tc, "xrd_,XRD-01", "SMP-A,SMP-A");
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "xrd_unlisted.xy"));

    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    values = localExperimentValues(state.fake);

    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 1);
    verifyEqual(tc, localMetadataCallCount(state.fake, "items"), 1);
    verifyEqual(tc, values.sample_id, "");
end

function test_sampleOnly_linksWithoutLedger(tc)
    state = localState(tc, "xrd_,XRD-01", "SMP-A,SMP-A");
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "other_SMP-A.xy"));

    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    values = localExperimentValues(state.fake);

    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 1);
    verifyEqual(tc, localMetadataCallCount(state.fake, "items"), 0);
    verifyEqual(tc, values.instrument_title, "");
end

function test_ambiguousInstrument_warnsWithoutLedger(tc)
    state = localState(tc, ["xrd_,XRD-01"; "xrd_,XRD-02"], "SMP-A,SMP-A");
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "xrd_SMP-A.xy"));

    output = evalc("results = elab.pipeline.watchAndLog(state.fake, state.cfg);");

    verifyEqual(tc, results.status, "logged");
    verifySubstring(tc, output, "ambiguous instrument binding");
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 1);
    verifyEqual(tc, localMetadataCallCount(state.fake, "items"), 0);
end

function test_legacyMap_warnsOnceAndUpdatesLedger(tc)
    state = localState(tc, "xrd_,XRD-01", "SMP-A,SMP-A");
    delete(state.cfg.watch.instrument_map);
    writelines([ ...
        "match_substring,sample_id,instrument_title,instrument_type,operator,project"; ...
        "xrd_,SMP-A,XRD-01,Instrument,operator-a,PRJ-A"], state.cfg.watch.sample_map);
    localSpectrum(fullfile(state.cfg.watch.inbox_dir, "xrd_SMP-A.xy"));

    output = evalc("results = elab.pipeline.watchAndLog(state.fake, state.cfg);");

    verifyEqual(tc, results.status, "logged");
    verifyEqual(tc, count(output, "legacy sample_map.csv is deprecated"), 1);
    verifyEqual(tc, localCallCount(state.fake, "linkTo"), 2);
    verifyEqual(tc, localMetadataCallCount(state.fake, "items"), 1);
end

function test_monthlyReport_groupsExampleSessionsByInstrumentId(tc)
    state = localExampleState(tc);
    tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture( ...
        fileparts(state.cfg.watch.inbox_dir)));
    elab.io.writeMockRuns(state.cfg.watch.inbox_dir);
    elab.io.writeMockNmrRun(state.cfg.watch.inbox_dir);
    results = elab.pipeline.watchAndLog(state.fake, state.cfg);
    state.fake.setGetResponse("/experiments", localReportEntries(state.fake));

    reportId = elab.pipeline.monthlyUsageReport(state.fake, state.cfg, year(datetime("today")), month(datetime("today")));
    rows = readtable(localUploadedPath(state.fake, "raw session rows"), "TextType", "string");

    verifyTrue(tc, all(string({results.status}) == "logged"));
    verifyEqual(tc, reportId, state.fake.CreatedId);
    verifyEqual(tc, sort(rows.instrument).', sort(["XRD-01", "Raman-01", "FTIR-01", "NMR-01", "NMR-02", "LCMS-01", "SEM-01"]));
end

function state = localExampleState(tc)
    root = string(tc.TestData.root);
    state = localState(tc, strings(0, 1), strings(0, 1));
    copyfile(fullfile(root, "data", "list", "instrument_map.example.csv"), state.cfg.watch.instrument_map);
    copyfile(fullfile(root, "data", "list", "sample_map.example.csv"), state.cfg.watch.sample_map);
end

function state = localState(tc, instrumentRows, sampleRows)
    fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
    tc.applyFixture(fixture);
    root = string(fixture.Folder);
    listDir = fullfile(root, "data", "list");
    mkdir(listDir);
    inbox = fullfile(root, "inbox");
    mkdir(inbox);
    cfg = loadConfig();
    cfg.elab.base_url = "https://example.test";
    cfg.watch.inbox_dir = inbox;
    cfg.watch.processed_dir = fullfile(root, "processed");
    cfg.watch.failed_dir = fullfile(root, "failed");
    cfg.watch.instrument_map = fullfile(listDir, "instrument_map.csv");
    cfg.watch.sample_map = fullfile(listDir, "sample_map.csv");
    cfg.run.root_dir = fullfile(root, "runs");
    cfg.ingest.archive_mode = "leave";
    writelines(["match_substring,instrument_id"; instrumentRows], cfg.watch.instrument_map);
    writelines(["match_substring,sample_id"; sampleRows], cfg.watch.sample_map);
    state = struct("cfg", cfg, "fake", localClient());
end

function fake = localClient()
    fake = FakeElabClient();
    fake.setGetResponse("/experiments", {});
    fake.setGetResponse("/teams/current/experiments_categories", [ ...
        struct("id", 7, "title", "Session"), struct("id", 8, "title", "Report")]);
    fake.setGetResponse("/teams/current/experiments_status", struct("id", 5, "title", "Draft"));
    fake.setGetResponse("/teams/current/resources_categories", { ...
        struct("id", 3, "title", "Instrument"), struct("id", 4, "title", "Sample"), ...
        struct("id", 5, "title", "Consumable")});
    fake.setGetResponse("/teams/current/items_status", {});
    fake.setGetResponse("/items", {});
end

function values = localExperimentValues(fake)
    values = struct("instrument_title", strings(1, 0), "sample_id", strings(1, 0));
    for k = 1:numel(fake.Calls)
        call = fake.Calls{k};
        if call.Method ~= "patchJson" || call.Arguments{1} ~= "experiments"
            continue
        end
        payload = call.Arguments{3};
        if ~isfield(payload, "metadata")
            continue
        end
        metadata = jsondecode(payload.metadata);
        fields = metadata.extra_fields;
        values.instrument_title(end + 1) = localMetadataValue(fields, "instrument_title"); %#ok<AGROW>
        values.sample_id(end + 1) = localMetadataValue(fields, "sample_id"); %#ok<AGROW>
    end
end

function value = localMetadataValue(fields, name)
    value = "";
    if isfield(fields, name)
        value = string(fields.(name).value);
    end
end

function count = localCallCount(fake, method)
    count = sum(cellfun(@(call) call.Method == method, fake.Calls));
end

function count = localMetadataCallCount(fake, kind)
    count = 0;
    for k = 1:numel(fake.Calls)
        call = fake.Calls{k};
        if call.Method == "patchJson" && call.Arguments{1} == kind && isfield(call.Arguments{3}, "metadata")
            count = count + 1;
        end
    end
end

function entries = localReportEntries(fake)
    entries = {};
    for k = 1:numel(fake.Calls)
        call = fake.Calls{k};
        if call.Method ~= "patchJson" || call.Arguments{1} ~= "experiments"
            continue
        end
        payload = call.Arguments{3};
        if ~isfield(payload, "metadata")
            continue
        end
        entries{end + 1} = struct("id", numel(entries) + 1, ...
            "date", string(datetime("today"), "yyyy-MM-dd"), "metadata", payload.metadata); %#ok<AGROW>
    end
end

function path = localUploadedPath(fake, comment)
    for k = 1:numel(fake.Calls)
        call = fake.Calls{k};
        if call.Method == "uploadFile" && call.Arguments{4} == comment
            path = string(call.Arguments{3});
            return
        end
    end
    error("test:bindingLayers:missingUpload", "No upload was recorded with comment %s.", comment);
end

function localSpectrum(path)
    writematrix([1, 0; 2, 10; 3, 0], path, FileType="text");
end
