classdef TestLoadConfig < matlab.unittest.TestCase
    % TestLoadConfig  Unit tests for the project configuration layer.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(fullfile(projectRoot, "src"), ...
                    "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function test_load_withoutSettings_returnsElabDefaults(tc)
            tc.useTemporaryWorkingFolder();
            tc.clearElabEnvironment();

            cfg = loadConfig();

            tc.verifyTrue(isfield(cfg, "elab"));
            tc.verifyEqual(cfg.elab.draft_status, "Draft");
            tc.verifyFalse(cfg.elab.allow_self_signed);
            tc.verifyEqual(cfg.elab.session_category, "Session");
            tc.verifyEqual(cfg.elab.qc_category, "QC");
            tc.verifyEqual(cfg.elab.report_category, "Report");
            tc.verifyEqual(cfg.elab.extra_field_search_limit, 400);
            tc.verifyClass(cfg.elab.extra_field_search_limit, "double");
        end

        function test_load_withSettings_returnsJsonOverride(tc)
            folder = tc.useTemporaryWorkingFolder();
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_ELAB_DRAFT_STATUS", ""));
            tc.writeSettings(folder, ...
                '{"elab":{"draft_status":"ReviewPending"}}');

            cfg = loadConfig();

            tc.verifyEqual(cfg.elab.draft_status, "ReviewPending");
        end

        function test_load_withoutSettings_returnsLabelsStruct(tc)
            tc.useTemporaryWorkingFolder();

            cfg = loadConfig();

            tc.verifyTrue(isstruct(cfg.elab.labels));
            tc.verifyTrue(isfield(cfg.elab.labels, "consumable_status_reorder"));
            tc.verifyEqual(cfg.elab.labels.field_group_measurement, "Measurement");
            tc.verifyEqual(cfg.elab.labels.field_group_instrument_params, ...
                "Instrument parameters");
            tc.verifyEqual(cfg.elab.labels.field_group_provenance, "Provenance");
        end

        function test_load_withoutSettings_returnsWatchDefaults(tc)
            tc.useTemporaryWorkingFolder();
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_WATCH_INBOX_DIR", ""));
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_WATCH_SAMPLE_MAP", ""));
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_WATCH_INSTRUMENT_MAP", ""));
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_WATCH_NOMINAL_RUN_MINUTES", ""));
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_QC_INBOX_DIR", ""));
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_QC_SPEC_LIST", ""));

            cfg = loadConfig();

            tc.verifyTrue(isfield(cfg, "watch"));
            tc.verifyTrue(contains(cfg.watch.inbox_dir, "inbox"));
            tc.verifyTrue(endsWith(cfg.watch.sample_map, ".csv"));
            tc.verifyEqual(cfg.watch.instrument_map, "data/list/instrument_map.csv");
            tc.verifyEqual(cfg.watch.nominal_run_minutes, 10);
            tc.verifyEqual(cfg.qc.inbox_dir, "data/qc_inbox");
            tc.verifyEqual(cfg.qc.spec_list, "data/list/qc_specs.csv");
        end

        function test_load_withSettingsAndEnvironment_returnsEnvironmentOverride(tc)
            folder = tc.useTemporaryWorkingFolder();
            tc.writeSettings(folder, ...
                '{"elab":{"base_url":"http://json.example.test"}}');
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_ELAB_BASE_URL", "http://example.test:9999"));

            cfg = loadConfig();

            tc.verifyEqual(cfg.elab.base_url, "http://example.test:9999");
        end

        function test_load_withInstrumentMapEnvironment_returnsMapOverride(tc)
            tc.useTemporaryWorkingFolder();
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_WATCH_INSTRUMENT_MAP", "custom-map.csv"));

            cfg = loadConfig();

            tc.verifyEqual(cfg.watch.instrument_map, "custom-map.csv");
        end

        function test_load_withInvalidSettings_warnsAndReturnsDefaults(tc)
            folder = tc.useTemporaryWorkingFolder();
            tc.clearElabEnvironment();
            tc.writeSettings(folder, '{"elab": invalid json}');

            output = evalc("cfg = loadConfig();");

            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, ...
                "loadConfig: failed to parse settings.json");
            tc.verifyEqual(cfg.elab.draft_status, "Draft");
            tc.verifyFalse(cfg.elab.allow_self_signed);
            tc.verifyEqual(cfg.elab.extra_field_search_limit, 400);
        end
    end

    methods (Access = private)
        function folder = useTemporaryWorkingFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture( ...
                matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end

        function clearElabEnvironment(tc)
            names = [ ...
                "ELAB_ELAB_DRAFT_STATUS", ...
                "ELAB_ELAB_ALLOW_SELF_SIGNED", ...
                "ELAB_ELAB_SESSION_CATEGORY", ...
                "ELAB_ELAB_QC_CATEGORY", ...
                "ELAB_ELAB_REPORT_CATEGORY", ...
                "ELAB_ELAB_EXTRA_FIELD_SEARCH_LIMIT"];
            for name = names
                tc.applyFixture( ...
                    matlab.unittest.fixtures.EnvironmentVariableFixture(name, ""));
            end
        end

        function writeSettings(~, folder, contents)
            configDir = fullfile(folder, "config");
            mkdir(configDir);
            writelines(contents, fullfile(configDir, "settings.json"));
        end
    end
end
