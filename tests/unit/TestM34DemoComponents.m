classdef TestM34DemoComponents < matlab.unittest.TestCase
    % TestM34DemoComponents  Offline checks for the demonstration helpers.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = TestM34DemoComponents.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true));
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(root));
        end
    end

    methods (Test)
        function test_ensureCategory_createsEachSupportedEndpoint(tc)
            for endpoint = ["experiments_categories", "resources_categories", "experiments_status"]
                fake = FakeElabClient();
                route = "/teams/current/" + endpoint;
                fake.setGetResponse(route, {});

                id = elab.client.ensureCategory(fake, endpoint, "Demo", color="A1b2C3");

                tc.verifyEqual(id, 701);
                tc.verifyEqual(fake.Calls{2}.Arguments, {"teams/current/" + endpoint, struct()});
                tc.verifyEqual(fake.Calls{3}.Arguments{3}, ...
                    struct("title", "Demo", "color", "a1b2c3"));
            end
        end

        function test_ensureCategory_reusesExactTitleAndValidatesInput(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 17, "title", "Session", "color", "29aeb9"));

            id = elab.client.ensureCategory(fake, "experiments_categories", "Session");

            tc.verifyEqual(id, 17);
            tc.verifyEqual(cellfun(@(call) call.Method, fake.Calls, UniformOutput=false), {"getJson"});
            tc.verifyError(@() elab.client.ensureCategory(fake, "other", "Session"), ...
                "elab:client:ensureCategory:invalidEndpoint");
            tc.verifyError(@() elab.client.ensureCategory(fake, "experiments_categories", ...
                "Session", color="blue"), "elab:client:ensureCategory:invalidColor");
        end

        function test_ensureCategory_throwsWhenTitleIsNotApplied(tc)
            fake = FakeElabClient();
            fake.IgnoreCategoryTitlePatches = true;
            fake.setGetResponse("/teams/current/experiments_categories", {});

            tc.verifyError(@() elab.client.ensureCategory(fake, ...
                "experiments_categories", "Session"), ...
                "elab:client:ensureCategory:notApplied");
        end

        function test_bootstrapStructure_createsConfiguredDefinitionsOnlyOnce(tc)
            fake = TestM34DemoComponents.emptyStructureClient();
            cfg = TestM34DemoComponents.config();
            cfg.elab.session_category = "Sessions for demo";

            ids = elab.pipeline.bootstrapStructure(fake, cfg);
            createCount = TestM34DemoComponents.callCount(fake, "createEntry");
            elab.pipeline.bootstrapStructure(fake, cfg);

            tc.verifyEqual(createCount, 8);
            tc.verifyEqual(TestM34DemoComponents.callCount(fake, "createEntry"), 8);
            tc.verifyEqual(string(fieldnames(ids)).', ["session", "qc", "report", "instrument", ...
                "sample", "consumable", "sop", "draft"]);
            tc.verifyEqual(ids.session, 701);
            tc.verifyEqual(fake.Calls{3}.Arguments{3}.title, "Sessions for demo");
        end

        function test_loadConfig_readsSelectedFileAndRetainsEnvironmentPriority(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            settings = fullfile(folder, "demo.json");
            writelines('{"elab":{"draft_status":"ReviewPending"}}', settings);
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "ELAB_ELAB_DRAFT_STATUS", "FromEnvironment"));

            cfg = loadConfig(SettingsFile=settings);

            tc.verifyEqual(cfg.elab.draft_status, "FromEnvironment");
            tc.verifyError(@() loadConfig(SettingsFile=fullfile(folder, "missing.json")), ...
                "elab:config:loadConfig:settingsNotFound");
        end

        function test_assertDemoTarget_stopsBeforeWrites(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            cfg = TestM34DemoComponents.config();
            cfg.elab.base_url = "https://wrong.example";
            cfg.elab.api_key = "not-in-message";

            caught = "";
            try
                elab.util.assertDemoTarget(fake, cfg, allowedBaseUrl="https://allowed.example");
            catch exception
                caught = string(exception.message);
                tc.verifyEqual(string(exception.identifier), "elab:demo:wrongServer");
            end
            tc.verifySubstring(caught, "https://wrong.example");
            tc.verifySubstring(caught, "https://allowed.example");
            tc.verifyFalse(contains(caught, cfg.elab.api_key));
            tc.verifyEqual(TestM34DemoComponents.callCount(fake, "createEntry"), 0);

            fake = FakeElabClient();
            fake.setGetResponse("/experiments", struct("id", 1));
            cfg.elab.base_url = "https://allowed.example";
            tc.verifyError(@() elab.util.assertDemoTarget(fake, cfg, ...
                allowedBaseUrl="https://allowed.example"), "elab:demo:serverNotEmpty");
            elab.util.assertDemoTarget(fake, cfg, allowedBaseUrl="https://allowed.example", ...
                allowNonEmpty=true);
        end

        function test_writeDemoRuns_hasBoundDeterministicDiverseInputs(tc)
            firstFixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            secondFixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(firstFixture);
            tc.applyFixture(secondFixture);
            first = string(firstFixture.Folder);
            second = string(secondFixture.Folder);
            monthValue = datetime(2026, 8, 1);
            files = elab.io.writeDemoRuns(first, month=monthValue);
            again = elab.io.writeDemoRuns(second, month=monthValue);
            cfg = TestM34DemoComponents.config();
            root = TestM34DemoComponents.projectRoot();
            cfg.watch.instrument_map = fullfile(root, "data", "list", "instrument_map.example.csv");
            cfg.watch.sample_map = fullfile(root, "data", "list", "sample_map.example.csv");
            maps = elab.pipeline.readBindingMaps(cfg);

            tc.verifyEqual(numel(files), 12);
            tc.verifyEqual(numel(files), numel(again));
            hashes = strings(numel(files), 1);
            instruments = strings(numel(files), 1);
            samples = strings(numel(files), 1);
            operators = strings(numel(files), 1);
            projects = strings(numel(files), 1);
            sources = strings(numel(files), 1);
            acquiredDays = NaT(numel(files), 1);
            for k = 1:numel(files)
                [parsed, ~] = elab.io.parseAny(files(k));
                [at, ~] = elab.io.readAcquiredAt(files(k), parsed);
                [~, sources(k)] = elab.io.readRunMinutes(parsed, cfg.watch.nominal_run_minutes);
                [name, ~] = elab.io.unitName(files(k), first);
                binding = elab.pipeline.matchBinding(maps, name);
                hashes(k) = TestM34DemoComponents.unitHash(files(k));
                acquiredDays(k) = dateshift(at, "start", "day");
                instruments(k) = binding.instrument_title;
                samples(k) = binding.sample_id;
                operators(k) = binding.operator;
                projects(k) = binding.project;
                tc.verifyEqual(hashes(k), TestM34DemoComponents.unitHash(again(k)));
            end
            tc.verifyEqual(sort(unique(instruments)).', ["FTIR-01", "LCMS-01", "NMR-01", "NMR-02", "Raman-01", "SEM-01", "XRD-01"]);
            tc.verifyEqual(sort(unique(samples)).', "SMP-2026-00" + string(1:7));
            tc.verifyEqual(sort(unique(operators)).', ["operator-a", "operator-b", "operator-c", "operator-d"]);
            tc.verifyEqual(sort(unique(projects)).', ["PRJ-A", "PRJ-B", "PRJ-C"]);
            tc.verifyGreaterThanOrEqual(numel(unique(acquiredDays)), 8);
            tc.verifyTrue(all(year(acquiredDays) == 2026 & month(acquiredDays) == 8));
            tc.verifyEqual(numel(unique(hashes)), numel(hashes));
            tc.verifyGreaterThanOrEqual(numel(unique(sources)), 2);
            tc.verifyEqual(sources(end), "calculated");
            tc.verifyTrue(any(samples == "SMP-2026-004") && any(samples == "SMP-2026-005"));
            tc.verifyFalse(TestM34DemoComponents.containsEnvironmentText(files));
        end

        function test_watchAndLog_reportsEachInputBeforeProcessing(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
            inbox = fullfile(root, "inbox");
            mkdir(inbox);
            writematrix([1, 0; 2, 2], fullfile(inbox, "xrd_demo_a.xy"), FileType="text");
            writematrix([1, 0; 2, 3], fullfile(inbox, "xrd_demo_b.xy"), FileType="text");
            cfg = TestM34DemoComponents.progressConfig(root, inbox);
            fake = TestM34DemoComponents.progressClient();

            output = evalc("elab.pipeline.watchAndLog(fake, cfg);");

            tc.verifyTrue(contains(output, "watchAndLog: [1/2] xrd_demo_a.xy"));
            tc.verifyTrue(contains(output, "watchAndLog: [2/2] xrd_demo_b.xy"));
        end
    end

    methods (Static, Access = private)
        function fake = emptyStructureClient()
            fake = FakeElabClient();
            for endpoint = ["experiments_categories", "resources_categories", "experiments_status"]
                fake.setGetResponse("/teams/current/" + endpoint, {});
            end
        end

        function cfg = config()
            cfg = struct();
            cfg.elab = struct("session_category", "Session", "qc_category", "QC", ...
                "report_category", "Report", "instrument_category", "Instrument", ...
                "sample_category", "Sample", "consumable_category", "Consumable", ...
                "sop_category", "SOP", "draft_status", "Draft", "base_url", "");
            cfg.elab.labels = struct("instrument_status_ok", "OK", ...
                "instrument_status_calibration_overdue", "CalibrationOverdue", ...
                "consumable_status_ok", "InStock", ...
                "consumable_status_reorder", "Reorder", ...
                "field_group_measurement", "Measurement", ...
                "field_group_instrument_params", "Instrument parameters", ...
                "field_group_provenance", "Provenance");
            cfg.watch = struct("nominal_run_minutes", 10, "sample_map", "", "instrument_map", "");
        end

        function cfg = progressConfig(root, inbox)
            mapPath = fullfile(root, "sample_map.csv");
            writelines(["match_substring,sample_id"; "not-a-demo-match,SMP-1"], mapPath);
            cfg = TestM34DemoComponents.config();
            cfg.elab.base_url = "https://example.test";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(root, "processed");
            cfg.watch.failed_dir = fullfile(root, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.run = struct("root_dir", fullfile(root, "runs"));
            cfg.ingest = struct("archive_mode", "leave", "attach_raw", "never", ...
                "attach_raw_max_mb", 25);
        end

        function fake = progressClient()
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/teams/current/items_status", {});
        end

        function count = callCount(fake, name)
            count = sum(cellfun(@(call) call.Method == name, fake.Calls));
        end

        function hash = unitHash(path)
            if isfolder(path)
                hash = string(elab.io.experimentManifest(path).coreHash);
            else
                hash = string(elab.util.fileHash(path));
            end
        end

        function found = containsEnvironmentText(files)
            needles = string([getenv("USERNAME"), getenv("COMPUTERNAME")]);
            needles = needles(strlength(needles) > 0);
            found = false;
            for path = files.'
                if isfolder(path)
                    entries = dir(fullfile(path, "**", "*"));
                    entries = entries(~[entries.isdir]);
                    paths = fullfile(string({entries.folder}), string({entries.name}));
                else
                    paths = path;
                end
                for file = paths
                    if isempty(needles) || ~TestM34DemoComponents.isTextFile(file)
                        continue
                    end
                    found = found || any(contains(string(fileread(file)), needles));
                end
            end
        end

        function tf = isTextFile(path)
            [~, ~, extension] = fileparts(path);
            tf = ismember(lower(string(extension)), ["", ".txt", ".dx", ".xy", ".csv", ".par"]);
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
