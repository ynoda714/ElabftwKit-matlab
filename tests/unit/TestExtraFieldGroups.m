classdef TestExtraFieldGroups < matlab.unittest.TestCase
    % TestExtraFieldGroups  Group and position contract for extra fields.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testGroupedFieldsWriteThreeDefinitionsAndMembership(tc)
            fake = tc.entryClient("/experiments/91");
            groups = tc.groups();
            fields = [ ...
                elab.util.fieldStruct("sample_id", "S-1", "text", groups.measurement), ...
                elab.util.fieldStruct("anode", "Cu", "text", groups.instrumentParams), ...
                elab.util.fieldStruct("logged_at", "2026-09-21T12:00", ...
                "datetime-local", groups.provenance)];

            elab.client.setExtraFields(fake, "experiments", 91, fields);
            metadata = tc.sentMetadata(fake);

            tc.verifyEqual([metadata.elabftw.extra_fields_groups.id], [1 2 3]);
            tc.verifyEqual(string({metadata.elabftw.extra_fields_groups.name}), ...
                ["Measurement" "Instrument parameters" "Provenance"]);
            tc.verifyEqual(metadata.extra_fields.sample_id.group_id, 1);
            tc.verifyEqual(metadata.extra_fields.anode.group_id, 2);
            tc.verifyEqual(metadata.extra_fields.logged_at.group_id, 3);
        end

        function testUngroupedFieldsRetainLegacyMetadataShape(tc)
            fake = tc.entryClient("/experiments/92");
            fields = elab.util.fieldStruct("temperature", 25.5, "number");

            elab.client.setExtraFields(fake, "experiments", 92, fields);
            metadata = tc.sentMetadata(fake);

            tc.verifyFalse(isfield(metadata, "elabftw"));
            tc.verifyEqual(metadata.extra_fields.temperature.type, 'number');
            tc.verifyEqual(metadata.extra_fields.temperature.value, '25.5');
            tc.verifyFalse(isfield(metadata.extra_fields.temperature, "group_id"));
            tc.verifyFalse(isfield(metadata.extra_fields.temperature, "position"));
        end

        function testPositionsRestartForEachGroupAndFollowInputOrder(tc)
            fake = tc.entryClient("/experiments/93");
            groups = tc.groups();
            fields = [ ...
                elab.util.fieldStruct("sample_id", "S-1", "text", groups.measurement), ...
                elab.util.fieldStruct("anode", "Cu", "text", groups.instrumentParams), ...
                elab.util.fieldStruct("operator", "alice", "text", groups.measurement), ...
                elab.util.fieldStruct("x_max", 80, "number", groups.instrumentParams)];

            elab.client.setExtraFields(fake, "experiments", 93, fields);
            ef = tc.sentMetadata(fake).extra_fields;

            tc.verifyEqual([ef.sample_id.position ef.operator.position], [1 2]);
            tc.verifyEqual([ef.anode.position ef.x_max.position], [1 2]);
        end

        function testWatchMeasurementFieldsUseCanonicalOrder(tc)
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            ef = tc.sentMetadata(fake).extra_fields;
            names = ["sample_id" "instrument_title" "operator" "project" ...
                "acquired_at" "acquired_at_source" "timezone" "run_minutes" ...
                "run_minutes_source"];
            positions = arrayfun(@(name) ef.(name).position, names);

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(positions, 1:9);
            tc.verifyEqual(arrayfun(@(name) ef.(name).group_id, names), ...
                ones(1, 9));
        end

        function testWatchParserFieldsUseInstrumentParameterGroup(tc)
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            ef = tc.sentMetadata(fake).extra_fields;
            parserNames = ["anode" "instrument" "x_min" "x_max" "n_points"];
            groupIds = arrayfun(@(name) ef.(name).group_id, parserNames);

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(groupIds, 2 * ones(size(parserNames)));
        end

        function testWatchInstrumentTitleUsesMeasurementGroup(tc)
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            field = tc.sentMetadata(fake).extra_fields.instrument_title;

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(field.group_id, 1);
            tc.verifyEqual(string(field.value), "XRD-01 Rigaku MiniFlex");
        end

        function testWatchExistingProvenanceFieldsUseProvenanceGroup(tc)
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            ef = tc.sentMetadata(fake).extra_fields;
            names = ["data_file_name" "data_file_hash" "data_unit" "logged_at"];

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(arrayfun(@(name) ef.(name).group_id, names), ...
                3 * ones(1, 4));
            tc.verifyEqual(arrayfun(@(name) ef.(name).position, names), [1 2 3 7]);
        end

        function testQcUsesMeasurementAndInstrumentParameterGroups(tc)
            [cfg, fake, filePath, spec] = tc.qcCase();

            [passed, experimentId] = elab.pipeline.qcCheck(fake, cfg, filePath, spec);
            ef = tc.sentMetadata(fake).extra_fields;
            decisionNames = ["metric" "measured" "target" "deviation" ...
                "tolerance" "qc_result" "qc_pass"];
            parserNames = ["anode" "instrument" "x_min" "x_max" "n_points"];

            tc.verifyTrue(passed);
            tc.verifyEqual(experimentId, fake.CreatedId);
            tc.verifyEqual(arrayfun(@(name) ef.(name).group_id, decisionNames), ...
                ones(size(decisionNames)));
            tc.verifyEqual(arrayfun(@(name) ef.(name).group_id, parserNames), ...
                2 * ones(size(parserNames)));
        end

        function testConfiguredGroupNamesAreWrittenVerbatim(tc)
            fake = tc.entryClient("/experiments/94");
            cfg = struct("elab", struct("labels", struct( ...
                "field_group_measurement", "Measured facts", ...
                "field_group_instrument_params", "Header facts", ...
                "field_group_provenance", "Audit facts")));
            groups = elab.util.fieldGroups(cfg);
            fields = [ ...
                elab.util.fieldStruct("sample_id", "S-1", "text", groups.measurement), ...
                elab.util.fieldStruct("anode", "Cu", "text", groups.instrumentParams), ...
                elab.util.fieldStruct("logged_at", "now", "text", groups.provenance)];

            elab.client.setExtraFields(fake, "experiments", 94, fields);
            definitions = tc.sentMetadata(fake).elabftw.extra_fields_groups;

            tc.verifyEqual(string({definitions.name}), ...
                ["Measured facts" "Header facts" "Audit facts"]);
        end

        function testFieldUpdatePreservesGroupsAndPositions(tc)
            fake = tc.entryClient("/items/95");
            groups = tc.groups();
            fields = [ ...
                elab.util.fieldStruct("sample_id", "S-1", "text", groups.measurement), ...
                elab.util.fieldStruct("logged_at", "old", "text", groups.provenance)];
            elab.client.setExtraFields(fake, "items", 95, fields);

            elab.client.updateExtraFields(fake, "items", 95, ...
                elab.util.fieldStruct("logged_at", "new", "text"));
            stored = fake.getJson("/items/95");
            metadata = jsondecode(stored.metadata);

            tc.verifyEqual(metadata.extra_fields.logged_at.value, 'new');
            tc.verifyEqual(metadata.extra_fields.logged_at.group_id, 3);
            tc.verifyEqual(metadata.extra_fields.logged_at.position, 1);
            tc.verifyEqual([metadata.elabftw.extra_fields_groups.id], [1 3]);
        end
    end

    methods (Access = private)
        function [cfg, fake] = watchCase(tc)
            folder = tc.temporaryWorkingFolder();
            sourceFolder = fullfile(folder, "source");
            files = string(elab.io.writeMockRuns(sourceFolder, ...
                acquiredAt=datetime(2026, 9, 21, 10, 30, 0)));
            source = files(startsWith(files, fullfile(sourceFolder, "xrd_")));
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            copyfile(source, inbox);
            mapFolder = fullfile(folder, "data", "list");
            mkdir(mapFolder);
            sampleMap = table("xrd_", "SMP-1", "PRJ-A", "alice", ...
                "Instrument", "XRD-01 Rigaku MiniFlex", 'VariableNames', ...
                {'match_substring', 'sample_id', 'project', 'operator', ...
                 'instrument_type', 'instrument_title'});
            mapPath = fullfile(mapFolder, "sample_map.csv");
            writetable(sampleMap, mapPath);

            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;

            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 3, "title", "Instrument"), ...
                struct("id", 4, "title", "Sample")]);
            fake.setGetResponse("/items", [ ...
                struct("id", 201, "title", "XRD-01 Rigaku MiniFlex", "category", 3), ...
                struct("id", 202, "title", "SMP-1", "category", 4)]);
            fake.setGetResponse("/items/201", struct("id", 201, ...
                "title", "XRD-01 Rigaku MiniFlex", "category", 3, "metadata", ""));
            fake.setGetResponse("/items/202", struct("id", 202, ...
                "title", "SMP-1", "category", 4, "metadata", ""));
        end

        function [cfg, fake, filePath, spec] = qcCase(tc)
            folder = tc.temporaryWorkingFolder();
            files = string(elab.io.writeMockRuns(fullfile(folder, "source"), ...
                acquiredAt=datetime(2026, 9, 21, 9, 0, 0)));
            filePath = files(startsWith(files, fullfile(folder, "source", "xrd_")));
            cfg = loadConfig();
            cfg.elab.qc_category = "QC";
            cfg.elab.draft_status = "Draft";
            spec = struct("instrumentTitle", "XRD-01", ...
                "instrumentType", "Instrument", "metric", "max_intensity", ...
                "target", 1000, "tolerance", 1000);

            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                struct("id", 41, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/41", struct("id", 41, "title", "XRD-01", ...
                "category", 3, "status_title", "OK", "metadata", ""));
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "QC"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function fake = entryClient(~, route)
            fake = FakeElabClient();
            parts = split(string(route), "/");
            fake.setGetResponse(route, struct("id", str2double(parts(end)), ...
                "metadata", ""));
        end

        function metadata = sentMetadata(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && isfield(call.Arguments{3}, "metadata")
                    metadata = jsondecode(call.Arguments{3}.metadata);
                    return
                end
            end
            error("TestExtraFieldGroups:metadataNotFound", ...
                "No metadata PATCH was recorded.");
        end

        function folder = temporaryWorkingFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end

        function groups = groups(~)
            groups = elab.util.fieldGroups(struct());
        end
    end
end
