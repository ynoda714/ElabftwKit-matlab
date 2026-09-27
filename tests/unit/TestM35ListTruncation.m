classdef TestM35ListTruncation < matlab.unittest.TestCase
    % TestM35ListTruncation  List-limit detection and configured limits.

    properties (TestParameter)
        invalidLimit = struct( ...
            "zero", 0, "negative", -1, "fractional", 1.5, "text", "two")
    end

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = TestM35ListTruncation.projectRoot();
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testReportBelowLimitHasNoTruncationNote(tc)
            [fake, cfg] = tc.reportClient( ...
                tc.sessionEntries([101], "XRD-01"), 2);

            output = tc.runMonthlyReport(fake, cfg, 2026, 8);
            body = TestM35ListTruncation.reportBody(fake);

            tc.verifyFalse(contains(output, "list returned the configured limit"));
            tc.verifyFalse(contains(body, "elab.report_list_limit"));
        end

        function testReportAtLimitWarnsAndAddsNote(tc)
            [fake, cfg] = tc.reportClient( ...
                tc.sessionEntries([101, 102], "XRD-01"), 2);

            output = tc.runMonthlyReport(fake, cfg, 2026, 8);
            body = TestM35ListTruncation.reportBody(fake);

            tc.verifySubstring(output, "list returned the configured limit of 2");
            tc.verifySubstring(body, "<code>elab.report_list_limit</code>");
            tc.verifySubstring(body, "2 sessions");
        end

        function testReportUsesConfiguredListLimit(tc)
            [fake, cfg] = tc.reportClient( ...
                tc.sessionEntries([101], "XRD-01"), 7);

            tc.runMonthlyReport(fake, cfg, 2026, 8);
            query = TestM35ListTruncation.queryFor(fake, "/experiments");

            tc.verifyEqual(query{end}, 7);
        end

        function testEnsureItemAtLimitReturnsExactMatchAndWarns(tc)
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "ELAB_ELAB_ITEM_SEARCH_LIMIT", "2"));
            fake = tc.itemClient([ ...
                TestM35ListTruncation.item(41, "Needle"), ...
                TestM35ListTruncation.item(42, "Other")]);

            output = evalc("id = elab.client.ensureItem(fake, 'Instrument', 'Needle');");

            tc.verifyEqual(id, 41);
            tc.verifySubstring(output, "search returned the configured limit of 2");
            tc.verifyFalse(TestM35ListTruncation.hasCall(fake, "createEntry"));
        end

        function testEnsureItemAtLimitWithoutMatchStopsBeforeWriting(tc)
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "ELAB_ELAB_ITEM_SEARCH_LIMIT", "2"));
            fake = tc.itemClient([ ...
                TestM35ListTruncation.item(41, "Other A"), ...
                TestM35ListTruncation.item(42, "Other B")]);

            exception = TestM35ListTruncation.captureError(@() ...
                elab.client.ensureItem(fake, "Instrument", "Needle"));

            tc.verifyEqual(string(exception.identifier), ...
                "elab:client:ensureItem:truncated");
            tc.verifySubstring(exception.message, "2");
            tc.verifySubstring(exception.message, "elab.item_search_limit");
            tc.verifyFalse(TestM35ListTruncation.hasCall(fake, "createEntry"));
            tc.verifyFalse(TestM35ListTruncation.hasCall(fake, "patchJson"));
        end

        function testEnsureItemBelowLimitCreatesItem(tc)
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "ELAB_ELAB_ITEM_SEARCH_LIMIT", "2"));
            fake = tc.itemClient(TestM35ListTruncation.item(41, "Other"));

            id = elab.client.ensureItem(fake, "Instrument", "Needle");

            tc.verifyEqual(id, 501);
            tc.verifyTrue(TestM35ListTruncation.hasCall(fake, "createEntry"));
        end

        function testEnsureItemUsesConfiguredListLimit(tc)
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "ELAB_ELAB_ITEM_SEARCH_LIMIT", "7"));
            fake = tc.itemClient(TestM35ListTruncation.item(41, "Needle"));

            elab.client.ensureItem(fake, "Instrument", "Needle");
            query = TestM35ListTruncation.queryFor(fake, "/items");

            tc.verifyEqual(query{end}, 7);
        end

        function testReconcileBookingsWarnsAtItsFixedLimit(tc)
            cfg = tc.tempConfig();
            fake = FakeElabClient();
            fake.setGetResponse("/events", repmat( ...
                struct("start", "2026-08-01T09:00"), 1, 500));
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", cfg.elab.session_category));
            fake.setGetResponse("/experiments", {});

            output = evalc("elab.pipeline.reconcileBookings(fake, cfg, '2026-08-01', '2026-09-01');");

            tc.verifySubstring(output, "events list reached the limit of 500");
        end

        function testInvalidListLimitsError(tc, invalidLimit)
            folder = tc.tempFolder();
            mkdir(fullfile(folder, "config"));
            jsonPath = fullfile(folder, "config", "settings.json");
            settings = struct("elab", struct( ...
                "item_search_limit", invalidLimit, ...
                "report_list_limit", invalidLimit));
            writelines(string(jsonencode(settings)), jsonPath);
            original = cd(folder);
            cleanup = onCleanup(@() cd(original));

            tc.verifyError(@loadConfig, ...
                "elab:config:loadConfig:invalidPositiveInteger");
            clear cleanup
        end
    end

    methods (Access = private)
        function [fake, cfg] = reportClient(tc, entries, limit)
            cfg = tc.tempConfig();
            cfg.elab.session_category = "Session";
            cfg.elab.report_category = "Report";
            cfg.elab.draft_status = "Draft";
            cfg.elab.report_list_limit = limit;
            cfg.watch.nominal_run_minutes = 10;
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 7, "title", "Session"), ...
                struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/experiments", entries);
            fake.setGetResponse("/experiments/501", struct("uploads", []));
        end

        function fake = itemClient(~, items)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", items);
            for k = 1:numel(items)
                fake.setGetResponse("/items/" + string(items(k).id), items(k));
            end
        end

        function cfg = tempConfig(tc)
            cfg = loadConfig();
        end

        function output = runMonthlyReport(tc, fake, cfg, year, month)
            folder = tc.tempFolder();
            original = cd(folder);
            cleanup = onCleanup(@() cd(original));
            output = evalc("elab.pipeline.monthlyUsageReport(fake, cfg, year, month);");
            clear cleanup
        end

        function folder = tempFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
        end
    end

    methods (Static, Access = private)
        function entries = sessionEntries(ids, instrument)
            entries = repmat(struct("id", NaN, "date", "", "metadata", ""), ...
                1, numel(ids));
            for k = 1:numel(ids)
                metadata = struct("extra_fields", struct( ...
                    "instrument_title", struct("value", instrument), ...
                    "project", struct("value", "PRJ"), ...
                    "operator", struct("value", "operator"), ...
                    "run_minutes", struct("value", "10"), ...
                    "run_minutes_source", struct("value", "measured"), ...
                    "acquired_at_source", struct("value", "file")));
                entries(k) = struct("id", ids(k), "date", "2026-08-15", ...
                    "metadata", jsonencode(metadata));
            end
        end

        function entry = item(id, title)
            entry = struct("id", id, "title", title, "category", 3);
        end

        function body = reportBody(fake)
            calls = fake.Calls(cellfun(@(call) call.Method == "patchJson", fake.Calls));
            body = "";
            for k = 1:numel(calls)
                payload = calls{k}.Arguments{3};
                if isfield(payload, "body")
                    body = string(payload.body);
                    return
                end
            end
        end

        function query = queryFor(fake, route)
            calls = fake.Calls(cellfun(@(call) call.Method == "getJson" && ...
                string(call.Arguments{1}) == route, fake.Calls));
            query = calls{1}.Arguments{2};
        end

        function tf = hasCall(fake, method)
            tf = any(cellfun(@(call) call.Method == method, fake.Calls));
        end

        function exception = captureError(call)
            try
                call();
                exception = MException("TestM35ListTruncation:noError", ...
                    "Expected an error.");
            catch exception
            end
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
