classdef TestM34DemoSmoke < matlab.unittest.TestCase
    % TestM34DemoSmoke  Offline end-to-end checks for demonstration data.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = TestM34DemoSmoke.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "tests", "fixtures", "demo_smoke"), ...
                IncludingSubfolders=true));
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(root));
            clear("elab.visualization.quickLook");
        end
    end

    methods (Test)
        function test_demoPipeline_logsAllBoundInputs(tc)
            outcome = TestM34DemoSmoke.runDemo(tc);

            tc.verifyEqual(numel(outcome.results), 12);
            tc.verifyEqual(string({outcome.results.status}), repmat("logged", 1, 12), ...
                "Failed messages: " + strjoin(string({outcome.results.message}), " | "));
            tc.verifyEqual(nnz(string({outcome.results.status}) == "failed"), 0);
            tc.verifyEqual(numel(outcome.sessions), 12);
            for k = 1:numel(outcome.sessions)
                fields = TestM34DemoSmoke.extraFields(outcome.sessions{k});
                tc.verifyTrue(isfield(fields, "instrument_title"));
                tc.verifyTrue(isfield(fields, "sample_id"));
                tc.verifyNotEqual(string(fields.instrument_title.value), "");
                tc.verifyNotEqual(string(fields.sample_id.value), "");
            end
        end

        function test_demoPipeline_updatesInstrumentLedgerAndInventory(tc)
            outcome = TestM34DemoSmoke.runDemo(tc);
            itemPatches = TestM34DemoSmoke.itemPatches(outcome.fake);
            payloads = cellfun(@(call) string(jsonencode(call.Arguments{3})), ...
                itemPatches, UniformOutput=false);

            tc.verifyTrue(any(contains(string(payloads), "usage_minutes_total")));
            tc.verifyTrue(any(contains(string(payloads), '"quantity"')));
        end

        function test_demoPipeline_monthlyReportHasNoUnknownInstrument(tc)
            outcome = TestM34DemoSmoke.runDemo(tc);
            reportId = elab.pipeline.monthlyUsageReport(outcome.fake, outcome.cfg, 2026, 8);
            csvPath = TestM34DemoSmoke.reportCsvPath(outcome.fake, reportId);
            rows = readtable(csvPath, "TextType", "string");

            tc.verifyFalse(any(rows.instrument == "(unknown)"));
        end

        function test_demoPipeline_extraFieldsUseDemoEntryNeutralSource(tc)
            outcome = TestM34DemoSmoke.runDemo(tc);
            userName = string(getenv("USERNAME"));
            computerName = string(getenv("COMPUTERNAME"));
            tc.verifyNotEqual(userName, "");
            tc.verifyNotEqual(computerName, "");
            fields = cellfun(@TestM34DemoSmoke.extraFields, outcome.sessions, ...
                UniformOutput=false);
            sourcePaths = string(cellfun(@(field) field.source_path.value, fields, ...
                UniformOutput=false));
            sourceHosts = string(cellfun(@(field) field.source_host.value, fields, ...
                UniformOutput=false));
            sourceMtimes = string(cellfun(@(field) field.source_mtime.value, fields, ...
                UniformOutput=false));
            metadata = string(cellfun(@jsonencode, fields, UniformOutput=false));

            tc.verifyEqual(sourcePaths, repmat("(demo)", 1, numel(fields)));
            tc.verifyEqual(sourceHosts, repmat("demo-workstation", 1, numel(fields)));
            tc.verifyEqual(sourceMtimes, repmat("", 1, numel(fields)));
            tc.verifyFalse(any(contains(metadata, userName)));
            tc.verifyFalse(any(contains(metadata, computerName)));
        end

        function test_demoEntryUsesSameNeutralSourceLocator(tc)
            root = TestM34DemoSmoke.projectRoot();
            script = string(fileread(fullfile(root, "scripts", "demo_run.m")));
            section = string(regexp(script, "(?ms)^%% 3\).*?(?=^%% 4\))", ...
                "match", "once"));

            tc.verifyNotEmpty(section);
            tc.verifyTrue(contains(section, "sourceLocator=@(~) struct("));
            tc.verifyTrue(contains(section, '"source_path", "(demo)"'));
            tc.verifyTrue(contains(section, '"source_host", "demo-workstation"'));
            tc.verifyTrue(contains(section, '"source_mtime", ""'));
        end

        function test_bootstrapStructure_usesAllConfiguredNamesAndDistinctColors(tc)
            fake = FakeElabClient();
            for endpoint = ["experiments_categories", "resources_categories", "experiments_status"]
                fake.setGetResponse("/teams/current/" + endpoint, {});
            end
            cfg = TestM34DemoSmoke.demoConfig(tc);
            names = ["Session custom", "QC custom", "Report custom", ...
                "Instrument custom", "Sample custom", "Consumable custom", ...
                "SOP custom", "Draft custom"];
            cfg.elab.session_category = names(1);
            cfg.elab.qc_category = names(2);
            cfg.elab.report_category = names(3);
            cfg.elab.instrument_category = names(4);
            cfg.elab.sample_category = names(5);
            cfg.elab.consumable_category = names(6);
            cfg.elab.sop_category = names(7);
            cfg.elab.draft_status = names(8);

            elab.pipeline.bootstrapStructure(fake, cfg);
            patches = fake.Calls(cellfun(@(call) call.Method == "patchJson", fake.Calls));
            titles = string(cellfun(@(call) call.Arguments{3}.title, patches, UniformOutput=false));
            colors = string(cellfun(@(call) call.Arguments{3}.color, patches, UniformOutput=false));

            tc.verifyEqual(titles, names);
            tc.verifyEqual(numel(unique(colors)), 8);
        end

        function test_demoGuideAndReadmeContainRequiredDemoInstructions(tc)
            root = TestM34DemoSmoke.projectRoot();
            readme = string(fileread(fullfile(root, "README.md")));
            guide = string(fileread(fullfile(root, "docs", "demo_guide.md")));
            documents = extractAfter(readme, "## Documents");
            documents = extractBefore(documents, newline + "## ");

            tc.verifyTrue(contains(documents, ...
                "| [Demo Guide](docs/demo_guide.md) | Reproduce a demonstration from an empty server. |"));
            tc.verifyTrue(contains(guide, "127.0.0.1"));
            tc.verifyTrue(contains(guide, "elabftw_setup.md#run-a-separate-demo-server"));
            tc.verifyTrue(contains(guide, "cookie collision"));
        end
    end

    methods (Static, Access = private)
        function outcome = runDemo(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
            cfg = TestM34DemoSmoke.demoConfig(tc);
            cfg.elab.base_url = "https://demo.example";
            cfg.watch.inbox_dir = fullfile(root, "inbox");
            cfg.watch.processed_dir = fullfile(root, "processed");
            cfg.watch.failed_dir = fullfile(root, "failed");
            cfg.run.root_dir = fullfile(root, "runs");
            fake = TestM34DemoSmoke.demoClient(cfg);
            elab.io.writeDemoRuns(cfg.watch.inbox_dir, month=datetime(2026, 8, 1));
            results = elab.pipeline.watchAndLog(fake, cfg, ...
                sourceLocator=@TestM34DemoSmoke.demoSource);
            outcome = struct();
            outcome.cfg = cfg;
            outcome.fake = fake;
            outcome.results = results;
            outcome.sessions = TestM34DemoSmoke.sessionEntries(fake);
        end

        function cfg = demoConfig(tc)
            root = TestM34DemoSmoke.projectRoot();
            cfg = loadConfig(SettingsFile=fullfile(root, "config", "settings.example.json"));
            cfg.watch.instrument_map = fullfile(root, "data", "list", "instrument_map.example.csv");
            cfg.watch.sample_map = fullfile(root, "data", "list", "sample_map.example.csv");
            cfg.ingest.archive_mode = "move";
            cfg.ingest.attach_raw = "never";
        end

        function fake = demoClient(cfg)
            fake = FakeElabClient();
            fake.StatefulExperiments = true;
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 1, "title", cfg.elab.session_category), ...
                struct("id", 2, "title", cfg.elab.qc_category), ...
                struct("id", 3, "title", cfg.elab.report_category)]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 11, "title", cfg.elab.draft_status));
            fake.setGetResponse("/teams/current/items_status", [ ...
                struct("id", 21, "title", cfg.elab.labels.instrument_status_ok), ...
                struct("id", 22, "title", cfg.elab.labels.instrument_status_check), ...
                struct("id", 23, "title", cfg.elab.labels.instrument_status_calibration_overdue), ...
                struct("id", 24, "title", cfg.elab.labels.consumable_status_ok), ...
                struct("id", 25, "title", cfg.elab.labels.consumable_status_reorder)]);
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 3, "title", cfg.elab.instrument_category), ...
                struct("id", 4, "title", cfg.elab.sample_category), ...
                struct("id", 5, "title", cfg.elab.consumable_category), ...
                struct("id", 6, "title", cfg.elab.sop_category)]);

            items = TestM34DemoSmoke.demoItems();
            fake.setGetResponse("/items", items);
            for item = items
                fake.setGetResponse("/items/" + string(item{1}.id), item{1});
            end
        end

        function items = demoItems()
            instruments = ["XRD-01", "Raman-01", "FTIR-01", "NMR-01", ...
                "NMR-02", "LCMS-01", "SEM-01"];
            samples = "SMP-2026-00" + string(1:7);
            consumables = ["NMR tube 5mm", "LC column C18 injections"];
            items = cell(1, 0);
            for k = 1:numel(instruments)
                items{end + 1} = struct("id", k, "title", instruments(k), ...
                    "category", 3, "status", 21, ...
                    "metadata", TestM34DemoSmoke.instrumentMetadata()); %#ok<AGROW>
            end
            for k = 1:numel(samples)
                items{end + 1} = struct("id", 100 + k, "title", samples(k), ...
                    "category", 4); %#ok<AGROW>
            end
            for k = 1:numel(consumables)
                items{end + 1} = struct("id", 200 + k, "title", consumables(k), ...
                    "category", 5, "status", 24, "metadata", ...
                    TestM34DemoSmoke.consumableMetadata(k)); %#ok<AGROW>
            end
        end

        function text = instrumentMetadata()
            fields = struct( ...
                "usage_minutes_total", struct("value", "0"), ...
                "usage_hours_total", struct("value", "0"), ...
                "last_used", struct("value", ""), ...
                "days_to_calibration", struct("value", ""), ...
                "calibration_due", struct("value", "2099-01-01"));
            text = jsonencode(struct("extra_fields", fields));
        end

        function text = consumableMetadata(index)
            quantities = [40, 2000];
            thresholds = [10, 300];
            fields = struct( ...
                "quantity", struct("value", string(quantities(index))), ...
                "reorder_threshold", struct("value", string(thresholds(index))), ...
                "unit", struct("value", "pcs"));
            text = jsonencode(struct("extra_fields", fields));
        end

        function source = demoSource(~)
            source = struct("source_path", "(demo)", ...
                "source_host", "demo-workstation", "source_mtime", "");
        end

        function sessions = sessionEntries(fake)
            entries = elab.util.toItems(fake.getJson("/experiments"));
            sessions = entries(cellfun(@(entry) isfield(entry, "category") && ...
                double(entry.category) == 1, entries));
        end

        function fields = extraFields(entry)
            metadata = jsondecode(entry.metadata);
            fields = metadata.extra_fields;
        end

        function patches = itemPatches(fake)
            patches = fake.Calls(cellfun(@(call) call.Method == "patchJson" && ...
                string(call.Arguments{1}) == "items", fake.Calls));
        end

        function path = reportCsvPath(fake, reportId)
            uploads = fake.Calls(cellfun(@(call) call.Method == "uploadFile" && ...
                string(call.Arguments{1}) == "experiments" && ...
                double(call.Arguments{2}) == reportId && ...
                string(call.Arguments{4}) == "raw session rows", fake.Calls));
            path = string(uploads{1}.Arguments{3});
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
