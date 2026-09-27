classdef TestM414ResourceTypeConfiguration < matlab.unittest.TestCase
    % TestM414ResourceTypeConfiguration  Configured resource category coverage.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = TestM414ResourceTypeConfiguration.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testDefaultResourceCategories(tc)
            cfg = tc.defaultConfig();

            tc.verifyEqual(cfg.elab.instrument_category, "Instrument");
            tc.verifyEqual(cfg.elab.sample_category, "Sample");
            tc.verifyEqual(cfg.elab.consumable_category, "Consumable");
            tc.verifyEqual(cfg.elab.sop_category, "SOP");
        end

        function testResolverUsesConfiguredValueForMissingEmptyAndMatching(tc)
            csvPath = tc.tempCsvPath("types.csv");

            fromMissing = elab.io.resolveConfiguredItemType( ...
                csvPath, 2, "instrument_type", missing, ...
                "elab.instrument_category", "Equipment");
            fromEmpty = elab.io.resolveConfiguredItemType( ...
                csvPath, 3, "instrument_type", "", ...
                "elab.instrument_category", "Equipment");
            fromMatch = elab.io.resolveConfiguredItemType( ...
                csvPath, 4, "instrument_type", "Equipment", ...
                "elab.instrument_category", "Equipment");

            tc.verifyEqual(fromMissing, "Equipment");
            tc.verifyEqual(fromEmpty, "Equipment");
            tc.verifyEqual(fromMatch, "Equipment");
        end

        function testResolverRejectsMismatchedCompatibilityValue(tc)
            csvPath = tc.tempCsvPath("types.csv");

            exception = TestM414ResourceTypeConfiguration.captureError(@() ...
                elab.io.resolveConfiguredItemType(csvPath, 2, ...
                "instrument_type", "Instrument", "elab.instrument_category", ...
                "Equipment"));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:resolveConfiguredItemType:itemTypeMismatch");
            tc.verifySubstring(exception.message, csvPath);
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "instrument_type");
            tc.verifySubstring(exception.message, "Instrument");
            tc.verifySubstring(exception.message, "elab.instrument_category");
            tc.verifySubstring(exception.message, "Equipment");
        end

        function testBootstrapStopsBeforeCreatingItemsForMismatch(tc)
            [cfg, fake] = tc.configuredBootstrapClient();
            csvPath = tc.writeLines("instruments.csv", [ ...
                "title,item_type,model,location,calibration_due"; ...
                "XRD-01,Instrument,Model,Room,2099-01-01"]);

            call = @() elab.pipeline.bootstrapItems(fake, cfg, ...
                instrumentsCsv=csvPath, consumablesCsv=tc.tempCsvPath("none.csv"));

            tc.verifyError(call, "elab:io:resolveConfiguredItemType:itemTypeMismatch");
            tc.verifyFalse(TestM414ResourceTypeConfiguration.hasCall(fake, "createEntry"));
        end

        function testReadQcSpecsUsesConfiguredTypeWithoutCompatibilityColumn(tc)
            cfg = tc.customConfig();
            csvPath = tc.writeLines("qc_specs.csv", [ ...
                "match_substring,instrument_title,metric,target,tolerance"; ...
                "xrd_,XRD-01,peak_x,1,0.1"]);

            specs = elab.io.readQcSpecs(csvPath, cfg);

            tc.verifyEqual(specs.instrumentType, "Equipment");
        end

        function testQcInboxStopsBeforeProcessingMismatch(tc)
            cfg = tc.customConfig();
            folder = tc.tempFolder();
            cfg.qc.inbox_dir = fullfile(folder, "inbox");
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.qc.spec_list = tc.writeLines("qc_specs.csv", [ ...
                "match_substring,instrument_title,instrument_type,metric,target,tolerance"; ...
                "xrd_,XRD-01,Instrument,peak_x,1,0.1"]);
            fake = FakeElabClient();

            call = @() elab.pipeline.qcInbox(fake, cfg);

            tc.verifyError(call, "elab:io:resolveConfiguredItemType:itemTypeMismatch");
            tc.verifyFalse(TestM414ResourceTypeConfiguration.hasCall(fake, "createEntry"));
        end

        function testWatchAndLogStopsBeforeInboxProcessingForMismatch(tc)
            cfg = tc.customConfig();
            folder = tc.tempFolder();
            cfg.watch.inbox_dir = fullfile(folder, "inbox");
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.run.root_dir = fullfile(folder, "runs");
            mkdir(cfg.watch.inbox_dir);
            inputPath = fullfile(cfg.watch.inbox_dir, "xrd_input.xy");
            writelines(["# X", "1 2"], inputPath);
            cfg.watch.sample_map = tc.writeLines("sample_map.csv", [ ...
                "match_substring,sample_id,instrument_title,instrument_type,operator,project"; ...
                "xrd_,SMP-1,XRD-01,Instrument,operator,project"]);
            fake = FakeElabClient();

            call = @() elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyError(call, "elab:io:resolveConfiguredItemType:itemTypeMismatch");
            tc.verifyTrue(isfile(inputPath));
            tc.verifyFalse(TestM414ResourceTypeConfiguration.hasCall(fake, "createEntry"));
        end

        function testConfiguredResourceTypesAreUsedByBootstrap(tc)
            [cfg, fake] = tc.configuredBootstrapClient();
            instrumentCsv = tc.writeLines("instruments.csv", [ ...
                "title,model,location,calibration_due"; ...
                "XRD-01,Model,Room,2099-01-01"]);
            consumableCsv = tc.writeLines("consumables.csv", [ ...
                "title,quantity,reorder_threshold,unit"; ...
                "Buffer,2,1,bottle"]);

            elab.pipeline.bootstrapItems(fake, cfg, ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);

            categoryPatches = TestM414ResourceTypeConfiguration.categoryPatches(fake);
            tc.verifyEqual(categoryPatches, [31; 33]);
        end

        function testPipelineSourcesDoNotPassLiteralResourceTypes(tc)
            root = TestM414ResourceTypeConfiguration.projectRoot();
            files = dir(fullfile(root, "src", "+elab", "+pipeline", "*.m"));
            sourceFiles = fullfile(string({files.folder}), string({files.name}));
            source = join(string(cellfun(@fileread, cellstr(sourceFiles), ...
                "UniformOutput", false)), newline);

            tc.verifyEmpty(regexp(source, ...
                'ensureItem\(client,\s*(?:\.\.\.\s*)?"(Instrument|Sample|Consumable|SOP)"', "once"));
            tc.verifyEmpty(regexp(source, ...
                'resolveId\(client,\s*"resources_categories",\s*"(Instrument|Sample|Consumable|SOP)"', "once"));
        end
    end

    methods (Access = private)
        function cfg = defaultConfig(tc)
            cfg = loadConfig();
        end

        function cfg = customConfig(tc)
            cfg = tc.defaultConfig();
            cfg.elab.instrument_category = "Equipment";
            cfg.elab.sample_category = "Specimen";
            cfg.elab.consumable_category = "Supply";
            cfg.elab.sop_category = "Procedure";
        end

        function [cfg, fake] = configuredBootstrapClient(tc)
            cfg = tc.customConfig();
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 1, "title", cfg.elab.session_category), ...
                struct("id", 2, "title", cfg.elab.qc_category), ...
                struct("id", 3, "title", cfg.elab.report_category)]);
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 31, "title", "Equipment"), ...
                struct("id", 32, "title", "Specimen"), ...
                struct("id", 33, "title", "Supply"), ...
                struct("id", 34, "title", "Procedure")]);
            fake.setGetResponse("/teams/current/items_status", {});
            fake.setGetResponse("/items", {});
        end

        function path = writeLines(tc, name, lines)
            path = tc.tempCsvPath(name);
            writelines(lines, path);
        end

        function path = tempCsvPath(tc, name)
            path = fullfile(tc.tempFolder(), name);
        end

        function folder = tempFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end

        function exception = captureError(call)
            try
                call();
                exception = MException("TestM414ResourceTypeConfiguration:noError", ...
                    "Expected an error.");
            catch exception
            end
        end

        function tf = hasCall(fake, method)
            tf = any(cellfun(@(call) call.Method == method, fake.Calls));
        end

        function categories = categoryPatches(fake)
            calls = fake.Calls(cellfun(@(call) call.Method == "patchJson", fake.Calls));
            categories = zeros(0, 1);
            for k = 1:numel(calls)
                payload = calls{k}.Arguments{3};
                if isfield(payload, "category")
                    categories(end + 1, 1) = payload.category; %#ok<AGROW>
                end
            end
        end
    end
end
