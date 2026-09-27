classdef TestQcIo < matlab.unittest.TestCase
    % TestQcIo  Tests for QC inbox selection and specification loading.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            projectRoot = TestQcIo.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testReadExampleSpecs(tc)
            csvPath = fullfile(TestQcIo.projectRoot(), ...
                "data", "list", "qc_specs.example.csv");

            specs = elab.io.readQcSpecs(csvPath);

            tc.verifySize(specs, [2, 1]);
            tc.verifyClass(specs(1).matchSubstring, "string");
            tc.verifyClass(specs(1).instrumentTitle, "string");
            tc.verifyClass(specs(1).instrumentType, "string");
            tc.verifyClass(specs(1).metric, "string");
            tc.verifyClass(specs(1).target, "double");
            tc.verifyClass(specs(1).tolerance, "double");
            tc.verifyEqual(specs(1).metric, "peak_x");
            tc.verifyEqual(specs(1).target, 28.44, AbsTol=1e-12);
        end

        function testInvalidMetricIncludesRowAndColumn(tc)
            csvPath = tc.writeSpecs("xrd_,XRD-01,Instrument,bogus,1,0.1");

            exception = TestQcIo.captureError(@() elab.io.readQcSpecs(csvPath));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:readQcSpecs:invalidSpec");
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "metric");
        end

        function testNegativeToleranceIncludesRowAndColumn(tc)
            csvPath = tc.writeSpecs("xrd_,XRD-01,Instrument,peak_x,1,-0.1");

            exception = TestQcIo.captureError(@() elab.io.readQcSpecs(csvPath));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:readQcSpecs:invalidSpec");
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "tolerance");
        end

        function testNonnumericTargetIncludesRowAndColumn(tc)
            csvPath = tc.writeSpecs("xrd_,XRD-01,Instrument,peak_x,nope,0.1");

            exception = TestQcIo.captureError(@() elab.io.readQcSpecs(csvPath));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:readQcSpecs:invalidSpec");
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "target");
        end

        function testEmptyMatchSubstringIncludesRowAndColumn(tc)
            csvPath = tc.writeSpecs(",XRD-01,Instrument,peak_x,1,0.1");

            exception = TestQcIo.captureError(@() elab.io.readQcSpecs(csvPath));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:readQcSpecs:invalidSpec");
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "match_substring");
        end

        function testEmptyInstrumentTitleIncludesRowAndColumn(tc)
            csvPath = tc.writeSpecs("xrd_,,Instrument,peak_x,1,0.1");

            exception = TestQcIo.captureError(@() elab.io.readQcSpecs(csvPath));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:io:readQcSpecs:invalidSpec");
            tc.verifySubstring(exception.message, "row 2");
            tc.verifySubstring(exception.message, "instrument_title");
        end

        function testEmptyInstrumentTypeUsesConfiguredValue(tc)
            csvPath = tc.writeSpecs("xrd_,XRD-01,,peak_x,1,0.1");
            cfg = loadConfig();
            cfg.elab.instrument_category = "Equipment";

            specs = elab.io.readQcSpecs(csvPath, cfg);

            tc.verifyEqual(specs.instrumentType, "Equipment");
        end

        function testMissingColumn(tc)
            folder = tc.tempFolder();
            csvPath = fullfile(folder, "specs.csv");
            writelines(["match_substring,instrument_title,instrument_type,metric,target"; ...
                "xrd_,XRD-01,Instrument,peak_x,1"], csvPath);

            call = @() elab.io.readQcSpecs(csvPath);

            tc.verifyError(call, "elab:io:readQcSpecs:missingColumn");
        end

        function testMissingFile(tc)
            csvPath = fullfile(tc.tempFolder(), "absent.csv");

            call = @() elab.io.readQcSpecs(csvPath);

            tc.verifyError(call, "elab:io:readQcSpecs:notFound");
        end

        function testListInboxExclusions(tc)
            folder = tc.tempFolder();
            inputPath = fullfile(folder, "xrd_run.xy");
            TestQcIo.touch(inputPath);
            TestQcIo.touch(fullfile(folder, ".gitkeep"));
            TestQcIo.touch(fullfile(folder, "Thumbs.db"));
            TestQcIo.touch(fullfile(folder, "desktop.INI"));
            TestQcIo.touch(fullfile(folder, "sem_run_meta.txt"));

            files = elab.io.listInbox(folder);

            tc.verifyEqual(files, string(inputPath));
            tc.verifySize(files, [1, 1]);
        end

        function testListInboxExclusionsWithVerboseLoggingReportsIgnoredCount(tc)
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "APP_LOG_VERBOSE", "1"));
            folder = tc.tempFolder();
            TestQcIo.touch(fullfile(folder, ".gitkeep"));
            TestQcIo.touch(fullfile(folder, "Thumbs.db"));
            TestQcIo.touch(fullfile(folder, "desktop.ini"));
            call = @() elab.io.listInbox(folder); %#ok<NASGU>

            output = evalc("call();");

            tc.verifySubstring(output, "[DEBUG]");
            tc.verifySubstring(output, "ignored 3 non-input file(s)");
        end
    end

    methods (Access = private)
        function csvPath = writeSpecs(tc, dataLine)
            folder = tc.tempFolder();
            csvPath = fullfile(folder, "specs.csv");
            header = "match_substring,instrument_title,instrument_type," + ...
                "metric,target,tolerance";
            writelines([header; dataLine], csvPath);
        end

        function folder = tempFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            thisDir = fileparts(mfilename("fullpath"));
            root = string(fileparts(fileparts(thisDir)));
        end

        function exception = captureError(call)
            try
                call();
                exception = MException("TestQcIo:noError", "Expected an error.");
            catch exception
            end
        end

        function touch(path)
            fid = fopen(path, "w");
            fclose(fid);
        end
    end
end
