classdef TestAssemblyGuide < matlab.unittest.TestCase
    % TestAssemblyGuide  Static checks for the public assembly guide and example.

    methods (Test)
        function test_publicGuidesExcludePrivateDocumentNames(tc)
            guides = tc.readFile(fullfile("docs", "assembly_guide.md")) + newline + ...
                tc.readFile(fullfile("docs", "ja", "assembly_guide.ja.md"));
            privateNames = "AGENTS\.md|CLAUDE\.md|PLAN\.md|adr\.md|" + ...
                "dev_history|docs/tasks|docs/archive|vision\.md";

            tc.verifyEmpty(regexpi(guides, privateNames, "match"));
        end

        function test_guideLinksResolve(tc)
            guidePaths = [fullfile("docs", "assembly_guide.md"), ...
                fullfile("docs", "ja", "assembly_guide.ja.md")];

            for guidePath = guidePaths
                tc.verifyLinksInFile(guidePath);
            end
        end

        function test_translationTracksEnglishCommit(tc)
            japanese = tc.readFile(fullfile("docs", "ja", "assembly_guide.ja.md"));
            commit = regexp(japanese, ...
                "(?m)^tracks_english_commit:\s*""?([^""\r\n]+)""?\s*$", ...
                "tokens", "once");

            tc.verifyNotEmpty(commit);
            tc.verifyNotEmpty(strtrim(string(commit{1})));
        end

        function test_exampleCallsExistingElabParts(tc)
            script = tc.exampleScript();
            calls = unique(string(regexp(script, ...
                "elab\.[A-Za-z]\w*\.[A-Za-z]\w*", "match")));

            tc.verifyNotEmpty(calls);
            for k = 1:numel(calls)
                call = calls(k);
                parts = split(call, ".");
                partPath = fullfile(tc.projectRoot(), "src", ...
                    "+" + parts(1), "+" + parts(2), parts(3) + ".m");
                tc.verifyEqual(exist(partPath, "file"), 2, ...
                    "Missing eLab part: " + call);
            end
        end

        function test_exampleDoesNotUpdateLedgers(tc)
            script = tc.exampleScript();

            tc.verifyFalse(contains(script, "updateInstrumentLedger"));
            tc.verifyFalse(contains(script, "consumeInventory"));
        end

        function test_exampleChecksDuplicatesAndArchives(tc)
            script = tc.exampleScript();

            tc.verifyTrue(contains(script, "findLoggedSession"));
            tc.verifyTrue(contains(script, "archiveIngested"));
        end

        function test_exampleCustomFigureUsesLightThemeAndLiteralTitle(tc)
            script = tc.exampleScript();

            tc.verifyTrue(contains(script, "elab.visualization.lightFigure("));
            tc.verifyEmpty(regexp(script, "(?<!light)figure\(", "match"));
            tc.verifyNotEmpty(regexp(script, ...
                "Interpreter""\s*,\s*""none""", "once"));
        end

        function test_exampleIsAsciiOnly(tc)
            script = tc.exampleScript();

            tc.verifyTrue(all(double(char(script)) <= 127));
        end
    end

    methods (Access = private)
        function text = exampleScript(tc)
            text = tc.readFile(fullfile("scripts", "example_custom_ingest.m"));
        end

        function text = readFile(tc, relativePath)
            text = string(fileread(fullfile(tc.projectRoot(), relativePath)));
        end

        function verifyLinksInFile(tc, relativePath)
            text = tc.readFile(relativePath);
            baseDir = fileparts(fullfile(tc.projectRoot(), relativePath));
            lines = splitlines(text);
            for line = lines'
                starts = strfind(line, "](");
                for k = 1:numel(starts)
                    suffix = extractAfter(line, starts(k) + 1);
                    closing = strfind(suffix, ")");
                    if isempty(closing)
                        continue
                    end
                    target = extractBefore(suffix, closing(1));
                    if startsWith(target, ["#", "http://", "https://"])
                        continue
                    end
                    target = extractBefore(target + "#", "#");
                    tc.verifyTrue(isfile(fullfile(baseDir, target)), ...
                        "Missing linked file: " + target);
                end
            end
        end

        function root = projectRoot(~)
            testFile = mfilename("fullpath");
            root = fileparts(fileparts(fileparts(testFile)));
        end
    end
end
