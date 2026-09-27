classdef TestProvenance < matlab.unittest.TestCase
    % TestProvenance  Minimum producer provenance for records and previews.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestProvenance.projectRoot(), "src"), ...
                "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testKitVersionReadsVersionAndShortCommit(tc)
            folder = tc.versionFolder("2.3.4-test");

            info = elab.util.kitVersion(projectRoot=folder, ...
                commandRunner=@TestProvenance.cleanGit);

            tc.verifyEqual(info.version, "2.3.4-test");
            tc.verifyEqual(info.commit, "abc1234");
        end

        function testKitVersionGitFailureReturnsEmptyCommit(tc)
            folder = tc.versionFolder("2.3.4-test");

            info = elab.util.kitVersion(projectRoot=folder, ...
                commandRunner=@TestProvenance.failedGit);

            tc.verifyEqual(info.version, "2.3.4-test");
            tc.verifyEqual(info.commit, "");
        end

        function testKitVersionDirtyTreeAppendsSuffix(tc)
            folder = tc.versionFolder("2.3.4-test");

            info = elab.util.kitVersion(projectRoot=folder, ...
                commandRunner=@TestProvenance.dirtyGit);

            tc.verifyEqual(info.commit, "abc1234-dirty");
        end

        function testWatchWritesFiveProducerFieldsAndActualParser(tc)
            tc.applyNoGitKitVersion();
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            ef = tc.sentMetadata(fake).extra_fields;

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(string(ef.kit_version.value), "0.1.0-dev");
            tc.verifyEqual(string(ef.kit_commit.value), "");
            tc.verifyEqual(string(ef.matlab_version.value), string(version));
            tc.verifyEqual(string(ef.parser.value), "elab.io.parseSpectrum");
            tc.verifySubstring(string(ef.quicklook_profile.value), "light");
            tc.verifyEqual([ef.kit_version.group_id ef.kit_commit.group_id ...
                ef.matlab_version.group_id ef.parser.group_id ...
                ef.quicklook_profile.group_id], 3 * ones(1, 5));
        end

        function testQuickLookReturnsProfilesBuiltFromRenderConstants(tc)
            folder = tc.temporaryWorkingFolder();
            spectrumPath = fullfile(folder, "spectrum.png");
            spectrum = struct("x", (1:5)', "y", [1; 3; 2; 4; 1], ...
                "xlabel", "x", "ylabel", "y");
            imagePath = fullfile(folder, "source.png");
            copiedPath = fullfile(folder, "copy.png");
            imwrite(uint8(zeros(4, 6, 3)), imagePath);

            [~, spectrumProfile] = elab.visualization.quickLook( ...
                "spectrum", spectrum, spectrumPath);
            [~, imageProfile] = elab.visualization.quickLook( ...
                "image", struct("imagePath", imagePath), copiedPath);

            tc.verifySubstring(spectrumProfile, "light");
            tc.verifySubstring(spectrumProfile, "900x460");
            tc.verifySubstring(spectrumProfile, "120dpi");
            tc.verifyEqual(imageProfile, "copy;maxdim=1200");
        end

        function testMonthlyReportWritesReportProvenance(tc)
            tc.applyNoGitKitVersion();
            tc.temporaryWorkingFolder();
            cfg = loadConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.report_category = "Report";
            cfg.elab.draft_status = "Draft";
            fake = tc.reportClient();

            reportId = elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 9);
            ef = tc.sentMetadata(fake).extra_fields;

            tc.verifyEqual(reportId, fake.CreatedId);
            tc.verifyEqual(string(ef.kit_version.value), "0.1.0-dev");
            tc.verifyEqual(string(ef.matlab_version.value), string(version));
            tc.verifyEqual(string(ef.report_period.value), "2026-09");
            tc.verifyEqual([ef.kit_version.position ef.matlab_version.position ...
                ef.report_period.position], 1:3);
            tc.verifyEqual([ef.kit_version.group_id ef.matlab_version.group_id ...
                ef.report_period.group_id], [3 3 3]);
        end

        function testWatchWithoutGitStillCreatesRecordWithEmptyCommit(tc)
            tc.applyNoGitKitVersion();
            [cfg, fake] = tc.watchCase();

            result = elab.pipeline.watchAndLog(fake, cfg);
            ef = tc.sentMetadata(fake).extra_fields;

            tc.verifyEqual(result.status, "logged");
            tc.verifyEqual(result.experimentId, fake.CreatedId);
            tc.verifyTrue(isfield(ef, "kit_commit"));
            tc.verifyEqual(string(ef.kit_commit.value), "");
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
            mapPath = fullfile(mapFolder, "sample_map.csv");
            sampleMap = table("does-not-match", "SMP", "PRJ", "operator", ...
                "Instrument", "XRD-01", 'VariableNames', ...
                {'match_substring', 'sample_id', 'project', 'operator', ...
                 'instrument_type', 'instrument_title'});
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
        end

        function fake = reportClient(~)
            fields = struct( ...
                "instrument_title", struct("type", "text", "value", "XRD-01"), ...
                "project", struct("type", "text", "value", "PRJ-A"), ...
                "operator", struct("type", "text", "value", "alice"), ...
                "run_minutes", struct("type", "number", "value", "10"), ...
                "run_minutes_source", struct("type", "text", "value", "measured"), ...
                "acquired_at_source", struct("type", "text", "value", "file"));
            entry = struct("id", 21, "date", "2026-09-10", ...
                "metadata", jsonencode(struct("extra_fields", fields)));
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 7, "title", "Session"), ...
                struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", {entry});
        end

        function applyNoGitKitVersion(tc)
            fixtureRoot = fullfile(TestProvenance.projectRoot(), ...
                "tests", "fixtures", "no_git");
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fixtureRoot));
            clear("elab.util.kitVersion");
            tc.addTeardown(@() clear("elab.util.kitVersion"));
            tc.assertSubstring(string(which("elab.util.kitVersion")), "no_git");
        end

        function metadata = sentMetadata(~, fake)
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && isfield(call.Arguments{3}, "metadata")
                    metadata = jsondecode(call.Arguments{3}.metadata);
                    return
                end
            end
            error("TestProvenance:metadataNotFound", ...
                "No metadata PATCH was recorded.");
        end

        function folder = versionFolder(tc, value)
            folder = tc.temporaryWorkingFolder();
            writelines(value, fullfile(folder, "VERSION"));
        end

        function folder = temporaryWorkingFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));
        end
    end

    methods (Static, Access = private)
        function [status, output] = cleanGit(command)
            status = 0;
            output = TestProvenance.gitOutput(command, "");
        end

        function [status, output] = failedGit(~)
            status = 128;
            output = "git unavailable";
        end

        function [status, output] = dirtyGit(command)
            status = 0;
            output = TestProvenance.gitOutput(command, " M changed.m");
        end

        function output = gitOutput(command, statusOutput)
            if contains(string(command), "status --porcelain")
                output = statusOutput;
            else
                output = "abc1234";
            end
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
