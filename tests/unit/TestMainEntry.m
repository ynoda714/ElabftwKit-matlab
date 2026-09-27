classdef TestMainEntry < matlab.unittest.TestCase
    % TestMainEntry  Static consistency tests for the front entry and guide.

    methods (Test)
        function test_remove_section0c_leavesSinglePipelineCalls(tc)
            mainText = tc.readProjectFile("main_elabftw.m");

            section0c = regexp(mainText, "(?m)^%%\s+0c\)", "match");

            tc.verifyEmpty(section0c);
            tc.verifyEqual(count(mainText, "elab.pipeline.watchAndLog("), 1);
            tc.verifyEqual(count(mainText, "elab.pipeline.monthlyUsageReport("), 1);
        end

        function test_order_section0b_addsPathBeforeLogging(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            section0b = tc.sectionText(mainText, "0b", "1");

            addPathPosition = strfind(section0b, "addpath(genpath(""src""))");
            logPosition = strfind(section0b, "logSection(");

            tc.verifyNotEmpty(addPathPosition);
            tc.verifyNotEmpty(logPosition);
            tc.verifyLessThan(addPathPosition(1), logPosition(1));
        end

        function test_order_section0b_addsPathBeforeResolvingProjectRoot(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            section0b = tc.sectionText(mainText, "0b", "1");

            addPathPosition = strfind(section0b, "addpath(genpath(""src""))");
            resolvePosition = strfind(section0b, "resolveProjectRoot()");

            tc.verifyNotEmpty(addPathPosition);
            tc.verifyNotEmpty(resolvePosition);
            tc.verifyLessThan(addPathPosition(1), resolvePosition(1));
        end

        function test_place_writeMockRuns_insideGenerateMockCondition(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            section2 = tc.sectionText(mainText, "2", "3");

            guardedCall = regexp(section2, ...
                "if\s+opt\.generateMock[\s\S]*?elab\.io\.writeMockRuns\([^\r\n]+\)[\s\S]*?else", ...
                "match");

            tc.verifyEqual(count(mainText, "elab.io.writeMockRuns("), 1);
            tc.verifyNotEmpty(guardedCall);
        end

        function test_document_section0a_listsAllCurrentOptions(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            quickStart = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            section0a = tc.sectionText(mainText, "0a", "0b");
            optionTokens = regexp(section0a, "opt\.[A-Za-z]\w*", "match");
            optionNames = unique(string(optionTokens));
            requiredOptions = ["opt.generateMock", "opt.doBootstrap", ...
                "opt.reportYear", "opt.reportMonth"];

            documented = arrayfun(@(name) contains(quickStart, name), optionNames);

            tc.verifyNotEmpty(optionNames);
            tc.verifyTrue(all(ismember(requiredOptions, optionNames)));
            tc.verifyTrue(all(documented));
            tc.verifyFalse(contains(quickStart, "GENERATE_MOCK"));
            tc.verifyFalse(contains(quickStart, "DO_BOOTSTRAP"));
            tc.verifyFalse(contains(quickStart, "REPORT_YEAR"));
        end

        function test_document_sections_listsAllCurrentHeadings(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            quickStart = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            sectionsTable = tc.markdownSection(quickStart, "Sections", "What to expect");
            headingTokens = regexp(mainText, "(?m)^%%\s+([0-9]+[a-z]?)\)", "tokens");
            headingIds = string([headingTokens{:}]);
            requiredHeadings = ["0a", "0b", "1", "2", "3", "4", "5"];

            documented = arrayfun( ...
                @(id) contains(sectionsTable, "Section " + id), headingIds);

            tc.verifyNotEmpty(headingIds);
            tc.verifyTrue(all(ismember(requiredHeadings, headingIds)));
            tc.verifyTrue(all(documented));
            tc.verifyFalse(contains(sectionsTable, "Section 0c"));
        end

        function test_construct_clients_inDirectApiExample_passesCaCert(tc)
            quickStart = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            directApi = tc.markdownSection(quickStart, "Call the API directly", "Run the tests");
            clientCalls = regexp(directApi, ...
                "elab\.client\.Client\([\s\S]*?\);", "match");

            tc.verifyNotEmpty(clientCalls);
            tc.verifyTrue(all(contains(string(clientCalls), "cfg.elab.ca_cert")));
        end

        function test_scan_publicGuides_excludesPrivateDocumentNames(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));
            guides = english + newline + japanese;
            privateNames = "AGENTS\.md|CLAUDE\.md|PLAN\.md|adr\.md|dev_history|docs/tasks|docs/archive|vision\.md";

            matches = regexpi(guides, privateNames, "match");

            tc.verifyEmpty(matches);
        end

        function test_read_translationFrontMatter_findsNonemptyEnglishCommit(tc)
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));

            commit = regexp(japanese, ...
                "(?m)^tracks_english_commit:\s*""?([^""\r\n]+)""?\s*$", ...
                "tokens", "once");

            tc.verifyNotEmpty(commit);
            tc.verifyNotEmpty(strtrim(string(commit{1})));
        end

        function test_document_categoryScopedDuplicateBehavior_inBothQuickStarts(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));
            englishExpected = tc.markdownSection( ...
                english, "What to expect", "Call the API directly");
            japaneseExpected = tc.markdownSection( ...
                japanese, string(char([26399 24453 12373 12428 12427 32080 26524])), ...
                string(char([65 80 73 32 12434 30452 25509 21628 12406])));

            tc.verifyFalse(contains(englishExpected, "any experiment"));
            tc.verifyTrue(contains(englishExpected, "within the QC category"));
            tc.verifyFalse(contains(japaneseExpected, ...
                string(char([12393 12398 32 101 120 112 101 114 105 109 101 ...
                110 116 32 12391 12354 12428]))));
            tc.verifyTrue(contains(japaneseExpected, ...
                string(char([81 67 32 99 97 116 101 103 111 114 121 32 20869]))));
        end

        function test_document_reportCreationPerRun_inBothQuickStarts(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));
            englishExpected = tc.markdownSection( ...
                english, "What to expect", "Call the API directly");
            japaneseExpected = tc.japaneseExpectedSection(japanese);

            tc.verifyNotEmpty(regexp(englishExpected, ...
                "every\s+run\s+creates\s+one\s+more\s+Report\s+experiment", ...
                "once"));
            tc.verifyTrue(contains(japaneseExpected, ...
                string(char([26082 23384 12398 12524 12509 12540 12488 12434 ...
                26908 32034 12375 12394 12356 12383 12417 12289 ...
                23455 34892 12377 12427 12383 12403 12395]))));
            tc.verifyNotEmpty(regexp(japaneseExpected, ...
                "Section\s+4[\s\S]*?Report\s+experiment[\s\S]*?F5", "once"));
        end

        function test_document_localhostUrls_useHttpsInBothQuickStarts(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));

            tc.verifyFalse(contains(english, "http://localhost"));
            tc.verifyFalse(contains(japanese, "http://localhost"));
            tc.verifyTrue(contains(english, "https://localhost:3148"));
            tc.verifyTrue(contains(japanese, "https://localhost:3148"));
        end

        function test_document_reintroducedFilesAreSkipped_inBothQuickStarts(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            japanese = tc.readProjectFile(fullfile("docs", "ja", "quickstart.ja.md"));
            englishExpected = tc.markdownSection( ...
                english, "What to expect", "Call the API directly");
            japaneseExpected = tc.japaneseExpectedSection(japanese);

            tc.verifyTrue(contains(englishExpected, ...
                "Reintroducing the same file produces `skipped`"));
            tc.verifyTrue(contains(japaneseExpected, ...
                string(char([12418 12358 19968 24230 20837 12428 12427]))));
            tc.verifyTrue(contains(japaneseExpected, "`data_file_hash`"));
            tc.verifyTrue(contains(japaneseExpected, "`skipped`"));
        end

        function test_document_secondMockRunSkipsAllSix_inEnglishQuickStart(tc)
            english = tc.readProjectFile(fullfile("docs", "quickstart.md"));
            englishExpected = tc.markdownSection( ...
                english, "What to expect", "Call the API directly");

            tc.verifyNotEmpty(regexp(englishExpected, ...
                "running\s+Section\s+2\s+and\s+then\s+Section\s+3\s+" + ...
                "a\s+second\s+time\s+skips[\s\S]*?all\s+six\s+" + ...
                "deterministic\s+mock\s+files", "once"));
        end

        function test_wire_qcInbox_onlyFromSection5_notFromWatchAndLog(tc)
            mainText = tc.readProjectFile("main_elabftw.m");
            watchText = tc.readProjectFile( ...
                fullfile("src", "+elab", "+pipeline", "watchAndLog.m"));
            section5 = string(regexp(mainText, ...
                "(?ms)^%%\s+5\).*", "match", "once"));

            tc.verifyNotEmpty(section5);
            tc.verifyTrue(contains(section5, "elab.pipeline.qcInbox("));
            tc.verifyEqual(count(mainText, "elab.pipeline.qcInbox("), 1);
            tc.verifyEqual(count(watchText, "qcInbox("), 0);
            tc.verifyEqual(count(watchText, "qcCheck("), 0);
        end
    end

    methods (Access = private)
        function text = readProjectFile(tc, relativePath)
            text = string(fileread(fullfile(tc.projectRoot(), relativePath)));
        end

        function root = projectRoot(~)
            testFile = mfilename("fullpath");
            root = fileparts(fileparts(fileparts(testFile)));
        end

        function section = sectionText(~, text, startId, endId)
            expression = "(?ms)^%%\s+" + startId + "\).*?(?=^%%\s+" + endId + "\))";
            section = string(regexp(text, expression, "match", "once"));
        end

        function section = markdownSection(~, text, startTitle, endTitle)
            expression = "(?ms)^##\s+" + regexptranslate("escape", startTitle) + ...
                "\s*$.*?(?=^##\s+" + regexptranslate("escape", endTitle) + "\s*$)";
            section = string(regexp(text, expression, "match", "once"));
        end

        function section = japaneseExpectedSection(tc, text)
            section = tc.markdownSection(text, ...
                string(char([26399 24453 12373 12428 12427 32080 26524])), ...
                string(char([65 80 73 32 12434 30452 25509 21628 12406])));
        end
    end
end
