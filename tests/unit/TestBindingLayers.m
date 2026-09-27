classdef TestBindingLayers < matlab.unittest.TestCase
    % TestBindingLayers  Contracts for independent Instrument and Sample bindings.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true));
        end
    end

    methods (Test)
        function test_readBindingMaps_split_returnsIndependentTables(tc)
            cfg = tc.splitCase();

            maps = elab.pipeline.readBindingMaps(cfg);

            tc.verifyEqual(maps.mode, "split");
            tc.verifyEqual(maps.instruments.instrument_title, "SEM-01");
            tc.verifyEqual(maps.samples.sample_id, "SMP-A");
        end

        function test_readBindingMaps_sampleOnly_returnsEmptyInstrumentTable(tc)
            cfg = tc.sampleOnlyCase();

            maps = elab.pipeline.readBindingMaps(cfg);

            tc.verifyEqual(maps.mode, "split");
            tc.verifyEmpty(maps.instruments);
        end

        function test_readBindingMaps_legacy_warnsOnce(tc)
            cfg = tc.legacyCase();

            output = evalc("maps = elab.pipeline.readBindingMaps(cfg);");

            tc.verifyEqual(count(output, "legacy sample_map.csv is deprecated"), 1);
            tc.verifyEqual(maps.mode, "legacy");
        end

        function test_readBindingMaps_noFiles_throwsNoMap(tc)
            cfg = tc.emptyCase();

            tc.verifyError(@() elab.pipeline.readBindingMaps(cfg), ...
                "elab:pipeline:readBindingMaps:noMap");
        end

        function test_readBindingMaps_mixedFormats_throwsMixedFormats(tc)
            cfg = tc.splitCase("instrument_title");

            tc.verifyError(@() elab.pipeline.readBindingMaps(cfg), ...
                "elab:pipeline:readBindingMaps:mixedFormats");
        end

        function test_readBindingMaps_emptyMatch_throwsEmptyMatch(tc)
            cfg = tc.splitCase();
            writelines(["match_substring,instrument_id"; ",SEM-01"], cfg.watch.instrument_map);

            tc.verifyError(@() elab.pipeline.readBindingMaps(cfg), ...
                "elab:pipeline:readBindingMaps:emptyMatch");
        end

        function test_readBindingMaps_missingColumn_throwsMissingColumn(tc)
            cfg = tc.splitCase();
            writelines("instrument_id", cfg.watch.instrument_map);

            tc.verifyError(@() elab.pipeline.readBindingMaps(cfg), ...
                "elab:pipeline:readBindingMaps:missingColumn");
        end

        function test_matchBinding_separatesTwoSamplesForOneInstrument(tc)
            maps = tc.twoSampleMaps();

            first = elab.pipeline.matchBinding(maps, "sem_SMP-A.png");
            second = elab.pipeline.matchBinding(maps, "sem_SMP-B.png");

            tc.verifyEqual(first.instrument_title, "SEM-01");
            tc.verifyEqual(first.sample_id, "SMP-A");
            tc.verifyEqual(second.sample_id, "SMP-B");
        end

        function test_matchBinding_distinguishesTwoInstruments(tc)
            maps = tc.twoInstrumentMaps();

            first = elab.pipeline.matchBinding(maps, "sem1_x.png");
            second = elab.pipeline.matchBinding(maps, "sem2_x.png");

            tc.verifyEqual(first.instrument_title, "SEM-01");
            tc.verifyEqual(second.instrument_title, "SEM-02");
        end

        function test_matchBinding_ignoresCase(tc)
            maps = tc.twoSampleMaps();

            binding = elab.pipeline.matchBinding(maps, "SEM_smp-a.PNG");

            tc.verifyEqual(binding.sample_id, "SMP-A");
        end

        function test_matchBinding_instrumentOnly_returnsPartialBinding(tc)
            maps = tc.twoSampleMaps();

            binding = elab.pipeline.matchBinding(maps, "sem_unlisted.png");

            tc.verifyEqual(binding.instrument_title, "SEM-01");
            tc.verifyEqual(binding.sample_id, "");
        end

        function test_matchBinding_sampleOnly_returnsPartialBinding(tc)
            maps = tc.twoSampleMaps();

            binding = elab.pipeline.matchBinding(maps, "other_SMP-A.png");

            tc.verifyEqual(binding.instrument_title, "");
            tc.verifyEqual(binding.sample_id, "SMP-A");
        end

        function test_matchBinding_noMatches_returnsEmpty(tc)
            maps = tc.twoSampleMaps();

            binding = elab.pipeline.matchBinding(maps, "other_unknown.png");

            tc.verifyEmpty(binding);
        end

        function test_matchBinding_ambiguousInstrument_doesNotBind(tc)
            maps = tc.twoInstrumentMaps();
            maps.instruments.match_substring = ["sem"; "sem"];
            maps.samples.match_substring = "file";

            output = evalc("binding = elab.pipeline.matchBinding(maps, 'sem_file.png');");

            tc.verifyEqual(binding.instrument_title, "");
            tc.verifySubstring(output, "ambiguous instrument binding");
        end

        function test_matchBinding_duplicateTarget_isNotAmbiguous(tc)
            maps = tc.twoInstrumentMaps();
            maps.instruments.instrument_title(2) = "SEM-01";
            maps.instruments.match_substring = ["sem"; "sem"];

            binding = elab.pipeline.matchBinding(maps, "sem_file.png");

            tc.verifyEqual(binding.instrument_title, "SEM-01");
        end

        function test_matchBinding_legacy_preservesFirstMatch(tc)
            cfg = tc.legacyCase();
            maps = elab.pipeline.readBindingMaps(cfg);

            binding = elab.pipeline.matchBinding(maps, "sem_file.png");

            tc.verifyEqual(binding.instrument_title, "SEM-01");
        end

        function test_readBindingMaps_optionalColumns_normalizesEmptyValues(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id,instrument_type"; "sem_,SEM-01,"], cfg.watch.instrument_map);
            writelines(["match_substring,sample_id,operator,project,consumable_title,consumable_qty"; "SMP-A,SMP-A,,,,"], cfg.watch.sample_map);

            maps = elab.pipeline.readBindingMaps(cfg);

            tc.verifyEqual(maps.instruments.instrument_type, "");
            tc.verifyEqual(maps.samples.operator, "");
            tc.verifyEqual(maps.samples.project, "");
            tc.verifyEqual(maps.samples.consumable_title, "");
            tc.verifyTrue(isnan(maps.samples.consumable_qty));
        end

        function test_readBindingMaps_incompatibleInstrumentType_throwsError(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id,instrument_type"; "sem_,SEM-01,WrongType"], cfg.watch.instrument_map);
            writelines(["match_substring,sample_id"; "SMP-A,SMP-A"], cfg.watch.sample_map);

            tc.verifyError(@() elab.pipeline.readBindingMaps(cfg), ...
                "elab:io:resolveConfiguredItemType:itemTypeMismatch");
        end

        function test_readBindingMaps_environmentOverride_usesInstrumentMap(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            override = fullfile(fileparts(cfg.watch.sample_map), "from_environment.csv");
            writelines(["match_substring,instrument_id"; "sem_,SEM-ENV"], override);
            writelines(["match_substring,sample_id"; "SMP-A,SMP-A"], cfg.watch.sample_map);
            original = getenv("ELAB_WATCH_INSTRUMENT_MAP");
            tc.addTeardown(@() setenv("ELAB_WATCH_INSTRUMENT_MAP", original));
            setenv("ELAB_WATCH_INSTRUMENT_MAP", override);

            maps = elab.pipeline.readBindingMaps(loadConfig());

            tc.verifyEqual(maps.instruments.instrument_title, "SEM-ENV");
        end

        function test_matchBinding_folderPaths_distinguishInstruments(tc)
            maps = tc.folderMaps();

            first = elab.pipeline.matchBinding(maps, "nmr-01/ds/1");
            second = elab.pipeline.matchBinding(maps, "nmr-02/ds/1");

            tc.verifyEqual(first.instrument_title, "NMR-01");
            tc.verifyEqual(second.instrument_title, "NMR-02");
        end

        function test_matchBinding_exampleData_containsNoMissingValues(tc)
            cfg = tc.exampleConfig();
            maps = elab.pipeline.readBindingMaps(cfg);

            binding = elab.pipeline.matchBinding(maps, "xrd_SMP-2026-001.xy");

            values = struct2cell(rmfield(binding, "consumable_qty"));
            tc.verifyFalse(any(cellfun(@(value) any(ismissing(value)), values)));
        end

        function test_linkSessionItems_partialBindings_linkMatchedItemOnly(tc)
            cfg = loadConfig();
            fake = tc.itemClient();
            instrument = tc.binding("SEM-01", "");
            sample = tc.binding("", "SMP-A");

            [instrumentId, sampleId] = elab.pipeline.linkSessionItems(fake, cfg, 501, instrument);
            [sampleOnlyInstrumentId, sampleOnlyId] = elab.pipeline.linkSessionItems(fake, cfg, 502, sample);

            tc.verifyNotEmpty(instrumentId);
            tc.verifyEmpty(sampleId);
            tc.verifyEmpty(sampleOnlyInstrumentId);
            tc.verifyNotEmpty(sampleOnlyId);
            tc.verifyEqual(tc.callCount(fake, "linkTo"), 2);
        end

        function test_linkSessionItems_emptyBinding_returnsEmptyIds(tc)
            fake = tc.itemClient();

            [instrumentId, sampleId] = elab.pipeline.linkSessionItems(fake, loadConfig(), 501, []);

            tc.verifyEmpty(instrumentId);
            tc.verifyEmpty(sampleId);
            tc.verifyEqual(tc.callCount(fake, "linkTo"), 0);
        end

        function test_sessionFields_partialBinding_omitsEmptyCanonicalValues(tc)
            [cfg, session] = tc.sessionCase();
            session.parsed.params = repmat(elab.util.fieldStruct("", "", "text"), 1, 0);

            fields = elab.pipeline.sessionFields(session, tc.binding("SEM-01", ""), cfg, tc.kit(), "none");

            tc.verifyFalse(any(string({fields.name}) == "sample_id"));
            tc.verifyTrue(any(string({fields.name}) == "instrument_title"));
        end

        function test_sessionFields_partialBinding_fallsBackPerCanonicalValue(tc)
            [cfg, session] = tc.sessionCase();
            session.parsed.params = [elab.util.fieldStruct("sample_id", "SMP-HEADER", "text"), ...
                elab.util.fieldStruct("instrument_title", "XRD-HEADER", "text")];

            fields = elab.pipeline.sessionFields(session, tc.binding("SEM-01", ""), cfg, tc.kit(), "none");
            names = string({fields.name});

            tc.verifyEqual(fields(names == "sample_id").value, "SMP-HEADER");
            tc.verifyEqual(fields(names == "instrument_title").value, "SEM-01");
        end

        function test_exampleData_csvRows_matchHeaders(tc)
            root = tc.projectRoot();
            files = ["instruments.example.csv", "instrument_map.example.csv", "sample_map.example.csv", "qc_specs.example.csv"];

            for file = files
                data = readtable(fullfile(root, "data", "list", file), "TextType", "string");
                tc.verifyFalse(any(startsWith(string(data.Properties.VariableNames), "Var")));
            end
        end

        function test_exampleData_instrumentReferences_exist(tc)
            root = tc.projectRoot();
            instruments = readtable(fullfile(root, "data", "list", "instruments.example.csv"), "TextType", "string");
            map = readtable(fullfile(root, "data", "list", "instrument_map.example.csv"), "TextType", "string");
            qc = readtable(fullfile(root, "data", "list", "qc_specs.example.csv"), "TextType", "string");

            tc.verifyTrue(all(ismember(map.instrument_id, instruments.title)));
            tc.verifyTrue(all(ismember(qc.instrument_title, instruments.title)));
        end

        function test_exampleData_calibrationDates_areIsoDates(tc)
            instruments = readtable(fullfile(tc.projectRoot(), "data", "list", "instruments.example.csv"), "TextType", "string");

            tc.verifyFalse(any(isnat(datetime(instruments.calibration_due, "InputFormat", "yyyy-MM-dd"))));
        end

        function test_exampleData_mockUnits_haveOneBindingWithoutMissingValues(tc)
            cfg = tc.exampleConfig();
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            inbox = string(fixture.Folder);
            files = elab.io.writeMockRuns(inbox);
            folder = elab.io.writeMockNmrRun(inbox);
            maps = elab.pipeline.readBindingMaps(cfg);
            units = [files(:); folder];

            for unit = units'
                [name, ~] = elab.io.unitName(unit, inbox);
                binding = elab.pipeline.matchBinding(maps, name);
                tc.verifyNotEmpty(binding);
                tc.verifyNotEqual(binding.instrument_title, "");
                tc.verifyNotEqual(binding.sample_id, "");
            end
        end

        function test_createSessionExperiment_partialBinding_omitsEmptyTags(tc)
            [cfg, session] = tc.sessionCase();
            fake = tc.sessionClient();
            runDir = fullfile(cfg.watch.inbox_dir, "runs");
            mkdir(runDir);

            elab.pipeline.createSessionExperiment(fake, cfg, session, tc.binding("SEM-01", ""), runDir, tc.kit());

            tags = string(cellfun(@(call) call.Arguments{3}, fake.Calls( ...
                cellfun(@(call) call.Method == "tag", fake.Calls)), UniformOutput=false));
            tc.verifyFalse(any(tags == ""));
        end

        function test_bootstrapItems_spaceTitle_warnsAndWritesModelAttribute(tc)
            cfg = tc.emptyCase();
            file = fullfile(fileparts(cfg.watch.sample_map), "instruments.csv");
            mkdir(fileparts(file));
            writelines(["title,model,location,calibration_due"; "SEM 01,Model-A,Room-1,2027-01-01"], file);
            fake = tc.bootstrapClient();

            output = evalc("elab.pipeline.bootstrapItems(fake, cfg, instrumentsCsv=file, consumablesCsv='missing.csv');");

            tc.verifySubstring(output, "instrument title 'SEM 01' contains spaces");
            tc.verifySubstring(tc.firstItemMetadata(fake), '"model"');
        end

        function test_bootstrapItems_missingColumn_throwsError(tc)
            cfg = tc.emptyCase();
            file = fullfile(fileparts(cfg.watch.sample_map), "instruments.csv");
            mkdir(fileparts(file));
            writelines(["title,model"; "SEM-01,Model-A"], file);

            tc.verifyError(@() elab.pipeline.bootstrapItems(tc.bootstrapClient(), cfg, ...
                instrumentsCsv=file, consumablesCsv="missing.csv"), ...
                "elab:pipeline:bootstrapItems:missingColumn");
        end

    end

    methods (Access = private)
        function cfg = splitCase(tc, extraSampleColumn)
            arguments
                tc
                extraSampleColumn (1,1) string = ""
            end
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id"; "sem_,SEM-01"], cfg.watch.instrument_map);
            header = "match_substring,sample_id";
            row = "SMP-A,SMP-A";
            if extraSampleColumn ~= ""
                header = header + "," + extraSampleColumn;
                row = row + ",SEM-01";
            end
            writelines([header; row], cfg.watch.sample_map);
        end

        function cfg = sampleOnlyCase(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,sample_id"; "SMP-A,SMP-A"], cfg.watch.sample_map);
        end

        function cfg = legacyCase(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines([ ...
                "match_substring,sample_id,instrument_title,instrument_type,operator,project"; ...
                "sem_,SMP-A,SEM-01,Instrument,operator-a,PRJ-A"], cfg.watch.sample_map);
        end

        function cfg = emptyCase(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
            cfg = loadConfig();
            cfg.watch.sample_map = fullfile(root, "data", "sample_map.csv");
            cfg.watch.instrument_map = fullfile(root, "data", "instrument_map.csv");
        end

        function maps = twoSampleMaps(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id"; "sem_,SEM-01"], cfg.watch.instrument_map);
            writelines(["match_substring,sample_id"; "SMP-A,SMP-A"; "SMP-B,SMP-B"], cfg.watch.sample_map);
            maps = elab.pipeline.readBindingMaps(cfg);
        end

        function maps = twoInstrumentMaps(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id"; "sem1_,SEM-01"; "sem2_,SEM-02"], cfg.watch.instrument_map);
            writelines(["match_substring,sample_id"; "not_used,SMP-A"], cfg.watch.sample_map);
            maps = elab.pipeline.readBindingMaps(cfg);
        end

        function maps = folderMaps(tc)
            cfg = tc.emptyCase();
            mkdir(fileparts(cfg.watch.sample_map));
            writelines(["match_substring,instrument_id"; "nmr-01/ds/1,NMR-01"; "nmr-02/ds/1,NMR-02"], cfg.watch.instrument_map);
            writelines(["match_substring,sample_id"; "nmr-01/ds/1,SMP-A"; "nmr-02/ds/1,SMP-B"], cfg.watch.sample_map);
            maps = elab.pipeline.readBindingMaps(cfg);
        end

        function cfg = exampleConfig(tc)
            root = tc.projectRoot();
            cfg = loadConfig();
            cfg.watch.instrument_map = fullfile(root, "data", "list", "instrument_map.example.csv");
            cfg.watch.sample_map = fullfile(root, "data", "list", "sample_map.example.csv");
        end

        function fake = itemClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 3, "title", "Instrument"), struct("id", 4, "title", "Sample")]);
            fake.setGetResponse("/items", {});
        end

        function fake = sessionClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 3, "title", "Instrument"), struct("id", 4, "title", "Sample")]);
            fake.setGetResponse("/items", {});
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", struct("id", 5, "title", "Draft"));
        end

        function fake = bootstrapClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", { ...
                struct("id", 7, "title", "Session"), struct("id", 8, "title", "QC"), ...
                struct("id", 9, "title", "Report")});
            fake.setGetResponse("/teams/current/resources_categories", { ...
                struct("id", 3, "title", "Instrument"), struct("id", 4, "title", "Sample"), ...
                struct("id", 5, "title", "Consumable"), struct("id", 6, "title", "SOP")});
            fake.setGetResponse("/teams/current/items_status", {});
            fake.setGetResponse("/items", {});
        end

        function binding = binding(~, instrumentTitle, sampleId)
            binding = struct("instrument_title", instrumentTitle, "instrument_type", "", ...
                "sample_id", sampleId, "operator", "", "project", "", ...
                "consumable_title", "", "consumable_qty", NaN);
        end

        function [cfg, session] = sessionCase(tc)
            cfg = tc.emptyCase();
            cfg.watch.inbox_dir = fullfile(fileparts(cfg.watch.sample_map), "inbox");
            mkdir(cfg.watch.inbox_dir);
            file = fullfile(cfg.watch.inbox_dir, "xrd_session.xy");
            writematrix([1, 0; 2, 10; 3, 0], file, FileType="text");
            session = elab.pipeline.readSessionFile(file, cfg);
            session = elab.pipeline.addSessionContext(session, cfg);
        end

        function info = kit(~)
            info = struct("version", "test", "commit", "test");
        end

        function count = callCount(~, fake, method)
            count = sum(cellfun(@(call) call.Method == method, fake.Calls));
        end

        function metadata = firstItemMetadata(~, fake)
            metadata = "";
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && call.Arguments{1} == "items" && ...
                        isfield(call.Arguments{3}, "metadata")
                    metadata = string(call.Arguments{3}.metadata);
                    return
                end
            end
        end

        function root = projectRoot(~)
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
