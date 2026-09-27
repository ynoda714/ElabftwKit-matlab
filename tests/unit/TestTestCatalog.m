classdef TestTestCatalog < matlab.unittest.TestCase
    % TestTestCatalog  docs/test_catalog.md matches the tests it describes.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(TestTestCatalog.projectRoot(), "src"), ...
                "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function test_compare_committedCatalog_equalsGenerated(tc)
            root = TestTestCatalog.projectRoot();
            committed = string(fileread(fullfile(root, "docs", "test_catalog.md")));
            committed = replace(committed, sprintf("\r\n"), newline);

            generated = buildTestCatalog(root) + newline;

            tc.verifyEqual(committed, generated, ...
                "docs/test_catalog.md is stale: run scripts/build_test_catalog.m");
        end

        function test_count_catalogTotal_equalsSuiteSize(tc)
            root = TestTestCatalog.projectRoot();
            suite = [testsuite(char(fullfile(root, "tests", "unit"))), ...
                testsuite(char(fullfile(root, "tests", "smoke")))];

            md = buildTestCatalog(root);
            total = regexp(md, "Total test points: (\d+)", "tokens", "once");

            tc.verifyEqual(str2double(total{1}), numel(suite));
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
