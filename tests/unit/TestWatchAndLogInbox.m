classdef TestWatchAndLogInbox < matlab.unittest.TestCase
    % TestWatchAndLogInbox  Regression tests for inbox file selection.

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
        function testNonInputFilesRemainInInbox(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            dataName = "xrd_SMP-2026-001.xy";
            ignoredNames = [".gitkeep", ".DS_Store", "Thumbs.db", "desktop.ini"];
            tc.writeSpectrum(fullfile(inbox, dataName));
            tc.touchFiles(inbox, ignoredNames);
            fake = tc.watchClient();

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyNumElements(results, 1);
            tc.verifyEqual(string({results.file}), dataName);
            tc.verifyEqual(string({results.status}), "logged");
            tc.verifyTrue(all(isfile(fullfile(inbox, ignoredNames))));
            tc.verifyFalse(any(isfile(fullfile(cfg.watch.failed_dir, ignoredNames))));
            tc.verifyFalse(any(isfile(fullfile(cfg.watch.processed_dir, ignoredNames))));
        end

        function testExplorerNamesAreCaseInsensitive(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            ignoredNames = ["thumbs.db", "Desktop.ini"];
            tc.touchFiles(inbox, ignoredNames);
            fake = tc.watchClient();

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyEmpty(results);
            tc.verifyTrue(all(isfile(fullfile(inbox, ignoredNames))));
            tc.verifyEqual(tc.createEntryCount(fake), 0);
        end

        function testDotfileOnlyInboxDoesNotCreateEntry(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            dotfile = ".gitkeep";
            tc.touchFiles(inbox, dotfile);
            fake = tc.watchClient();

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyEmpty(results);
            tc.verifyTrue(isfile(fullfile(inbox, dotfile)));
            tc.verifyEqual(tc.createEntryCount(fake), 0);
        end

        function testNamesContainingDotOrExplorerNameAreInputs(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            dataNames = ["xrd_SMP.2026.001.xy", "thumbs.db.xy"];
            tc.writeSpectrum(fullfile(inbox, dataNames(1)));
            tc.writeSpectrum(fullfile(inbox, dataNames(2)));
            fake = tc.watchClient();

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyEqual(sort(string({results.file})), sort(dataNames));
            tc.verifyEqual(string({results.status}), ["logged", "logged"]);
            tc.verifyEqual(tc.createEntryCount(fake), 2);
        end

        function testQcHashStillCreatesSessionExperiment(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            filePath = fullfile(inbox, "xrd_qc_hash.xy");
            tc.writeSpectrum(filePath);
            fileHash = elab.util.fileHash(filePath);
            fake = tc.watchClient();
            fake.setGetResponse("/experiments", ...
                tc.experiment(81, fileHash, 8));

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyEqual(results.status, "logged");
            tc.verifyEqual(tc.createEntryCount(fake), 1);
        end

        function testSessionHashSkipsSessionExperiment(tc)
            [cfg, inbox] = tc.prepareWatchCase();
            filePath = fullfile(inbox, "xrd_session_hash.xy");
            tc.writeSpectrum(filePath);
            fileHash = elab.util.fileHash(filePath);
            fake = tc.watchClient();
            fake.setGetResponse("/experiments", ...
                tc.experiment(82, fileHash, 7));

            results = elab.pipeline.watchAndLog(fake, cfg);

            tc.verifyEqual(results.status, "skipped");
            tc.verifyEqual(results.experimentId, 82);
            tc.verifyEqual(tc.createEntryCount(fake), 0);
        end
    end

    methods (Access = private)
        function [cfg, inbox] = prepareWatchCase(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));

            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            sampleMap = table("does-not-match", "SMP-TEST", "PRJ-A", ...
                "operator-a", "Instrument", "XRD-01", ...
                'VariableNames', {'match_substring', 'sample_id', 'project', ...
                    'operator', 'instrument_type', 'instrument_title'});
            mapPath = fullfile(mapDir, "sample_map.csv");
            writetable(sampleMap, mapPath);

            cfg = struct();
            cfg.elab = struct( ...
                "base_url", "https://example.test", ...
                "session_category", "Session", ...
                "draft_status", "Draft", ...
                "instrument_category", "Instrument", ...
                "sample_category", "Sample", ...
                "consumable_category", "Consumable", ...
                "sop_category", "SOP");
            cfg.watch = struct( ...
                "inbox_dir", inbox, ...
                "processed_dir", fullfile(folder, "processed"), ...
                "failed_dir", fullfile(folder, "failed"), ...
                "sample_map", mapPath, ...
                "nominal_run_minutes", 17);
        end

        function fake = watchClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function writeSpectrum(~, filePath)
            writematrix([10, 100; 20, 200; 30, 150], filePath, ...
                "FileType", "text");
        end

        function touchFiles(~, folder, names)
            for name = names
                fid = fopen(fullfile(folder, name), "w");
                fclose(fid);
            end
        end

        function count = createEntryCount(~, fake)
            count = sum(cellfun( ...
                @(call) call.Method == "createEntry", fake.Calls));
        end
        function item = experiment(~, id, hash, category)
            extraFields.data_file_hash = struct( ...
                "type", "text", "value", hash);
            item = struct("id", id, "category", category, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end
    end
end
