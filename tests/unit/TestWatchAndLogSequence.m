classdef TestWatchAndLogSequence < matlab.unittest.TestCase
    % TestWatchAndLogSequence  Pre-refactor behavior contract for A1.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true));
        end
    end

    methods (TestMethodSetup)
        function fixKitVersion(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "tests", "fixtures", "watch_and_log_sequence"), ...
                IncludingSubfolders=true));
        end
    end

    methods (Test)
        function testCallOrderAndOutcomes(tc)
            [cfg, paths] = tc.caseFiles();
            fake = tc.client();
            duplicateHash = elab.util.fileHash(paths.duplicate);
            fake.setGetResponse("/experiments", ...
                {tc.experiment(72, duplicateHash, 7)});

            results = elab.pipeline.watchAndLog(fake, cfg, ...
                sourceLocator=@TestWatchAndLogSequence.fixedSource, ...
                timezoneResolver=@TestWatchAndLogSequence.fixedTimezone);

            tc.verifyEqual(string({results.file}), [ ...
                "xrd_duplicate.xy", "xrd_failure.xy", "xrd_matched.xy", ...
                "xrd_unmatched.xy"]);
            tc.verifyEqual(string({results.status}), [ ...
                "skipped", "failed", "logged", "logged"]);
            tc.verifyEqual(tc.normalizedCalls(fake, cfg), tc.expectedCalls());
            tc.verifyEqual(tc.createExperimentCount(fake), 2);
        end

        function testDuplicateDoesNotResolveSourceOrTimezone(tc)
            [cfg, paths] = tc.caseFiles();
            delete(paths.failure);
            delete(paths.matched);
            delete(paths.unmatched);
            fake = tc.client();
            duplicateHash = elab.util.fileHash(paths.duplicate);
            fake.setGetResponse("/experiments", ...
                {tc.experiment(72, duplicateHash, 7)});

            result = elab.pipeline.watchAndLog(fake, cfg, ...
                sourceLocator=@TestWatchAndLogSequence.failSourceLookup, ...
                timezoneResolver=@TestWatchAndLogSequence.failTimezoneLookup);

            tc.verifyEqual(result.status, "skipped");
        end
    end

    methods (Access = private)
        function [cfg, paths] = caseFiles(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));
            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            mapPath = fullfile(mapDir, "sample_map.csv");
            map = table("matched", "SMP-1", "P-1", "operator", ...
                "Instrument", "XRD-01", "Acid", 2, 'VariableNames', ...
                {'match_substring', 'sample_id', 'project', 'operator', ...
                'instrument_type', 'instrument_title', 'consumable_title', ...
                'consumable_qty'});
            writetable(map, mapPath);
            paths = struct( ...
                "duplicate", fullfile(inbox, "xrd_duplicate.xy"), ...
                "failure", fullfile(inbox, "xrd_failure.xy"), ...
                "matched", fullfile(inbox, "xrd_matched.xy"), ...
                "unmatched", fullfile(inbox, "xrd_unmatched.xy"));
            writematrix([1, 0; 2, 10; 3, 0], paths.duplicate, FileType="text");
            writelines("", paths.failure);
            writematrix([1, 0; 2, 11; 3, 0], paths.matched, FileType="text");
            writematrix([1, 0; 2, 12; 3, 0], paths.unmatched, FileType="text");
            cfg = loadConfig();
            cfg.elab.base_url = "https://example.test";
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.elab.instrument_category = "Instrument";
            cfg.elab.sample_category = "Sample";
            cfg.elab.consumable_category = "Consumable";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.run.root_dir = fullfile(folder, "runs");
        end

        function fake = client(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/teams/current/resources_categories", { ...
                struct("id", 3, "title", "Instrument"), ...
                struct("id", 4, "title", "Sample"), ...
                struct("id", 5, "title", "Consumable")});
            fake.setGetResponse("/items", {});
            fake.setGetResponse("/teams/current/items_status", { ...
                struct("id", 11, "title", "OK", "color", "28a745"), ...
                struct("id", 12, "title", "CalibrationOverdue", "color", "ffc107"), ...
                struct("id", 13, "title", "Reorder", "color", "dc3545")});
        end

        function calls = normalizedCalls(~, fake, cfg)
            temporaryRoot = string(fileparts(cfg.watch.inbox_dir));
            calls = localNormalizeCalls(fake.Calls, temporaryRoot);
            calls = jsonencode(calls);
        end

        function calls = expectedCalls(~)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            path = fullfile(root, "tests", "fixtures", ...
                "watch_and_log_sequence_calls.json");
            calls = jsondecode(fileread(path));
            calls = jsonencode(calls);
        end

        function count = createExperimentCount(~, fake)
            count = sum(cellfun(@(call) call.Method == "createEntry" && ...
                string(call.Arguments{1}) == "experiments", fake.Calls));
        end
    end

    methods (Static, Access = private)
        function item = experiment(id, hash, category)
            fields.data_file_hash = struct("type", "text", "value", hash);
            item = struct("id", id, "category", category, "metadata", ...
                jsonencode(struct("extra_fields", fields)));
        end

        function source = fixedSource(~)
            source = struct("source_path", "X:\\raw\\fixed.xy", ...
                "source_host", "fixed-host", "source_mtime", "2026-09-21T13:00");
        end

        function timezone = fixedTimezone(~)
            timezone = "Test/Zone";
        end

        function failSourceLookup(~)
            error("TestWatchAndLogSequence:sourceCalled", ...
                "Source lookup must not run for a duplicate.");
        end

        function failTimezoneLookup(~)
            error("TestWatchAndLogSequence:timezoneCalled", ...
                "Timezone lookup must not run for a duplicate.");
        end
    end
end

function calls = localNormalizeCalls(calls, temporaryRoot)
for k = 1:numel(calls)
    calls{k}.Arguments = localNormalizeValue(calls{k}.Arguments, temporaryRoot, "");
end
end

function value = localNormalizeValue(value, temporaryRoot, fieldName)
if iscell(value)
    for k = 1:numel(value)
        value{k} = localNormalizeValue(value{k}, temporaryRoot, "");
    end
elseif isstruct(value)
    names = string(fieldnames(value));
    for k = 1:numel(value)
        for n = 1:numel(names)
            name = names(n);
            childName = name;
            if name == "value" && ismember(fieldName, ...
                    ["logged_at", "last_used", "acquired_at"])
                childName = fieldName;
            end
            value(k).(name) = localNormalizeValue(value(k).(name), temporaryRoot, childName);
        end
    end
elseif ischar(value) || isstring(value)
    value = replace(string(value), temporaryRoot, "<TEMP_ROOT>");
    value = regexprep(value, "<TEMP_ROOT>\\runs\\\d{8}_\d{6}", "<RUN_DIR>");
    if fieldName == "metadata"
        value = jsonencode(localNormalizeValue(jsondecode(value), temporaryRoot, ""));
    elseif fieldName == "logged_at" || fieldName == "last_used" || ...
            fieldName == "acquired_at"
        value = "<LOGGED_AT>";
    elseif fieldName == "date"
        value = "<ACQUIRED_DATE>";
    elseif fieldName == "body"
        value = regexprep(value, ...
            "watchAndLog \(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\)", ...
            "watchAndLog (<BODY_TIMESTAMP>)");
    end
end
end
