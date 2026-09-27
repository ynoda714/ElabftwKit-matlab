classdef TestElabClient < matlab.unittest.TestCase
    % TestElabClient  Offline contract tests for elab.client helpers.

    properties (TestParameter)
        teamEndpoint = struct( ...
            "experimentCategories", "experiments_categories", ...
            "experimentStatuses", "experiments_status", ...
            "resourceCategories", "resources_categories", ...
            "itemStatuses", "items_status")
    end

    methods (TestClassSetup)
        function addSrcToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(fullfile(projectRoot, "src"), ...
                    "IncludingSubfolders", true));
            tc.applyFixture( ...
                matlab.unittest.fixtures.CurrentFolderFixture(projectRoot));
        end
    end

    methods (Test)
        function test_recording_whenCalled_capturesArguments(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/actual", struct("id", 1));

            fake.getJson("/actual", {"limit", 10});

            tc.verifyEqual(fake.Calls{1}.Method, "getJson");
            tc.verifyEqual(fake.Calls{1}.Arguments, ...
                {"/actual", {"limit", 10}});
        end

        function test_resolveId_teamEndpoint_usesCurrentTeamRoute(tc, teamEndpoint)
            fake = FakeElabClient();
            route = "/teams/current/" + teamEndpoint;
            fake.setGetResponse(route, struct("id", 17, "title", "Target"));

            id = elab.client.resolveId(fake, teamEndpoint, "Target");

            tc.verifyEqual(id, 17);
            tc.verifyEqual(fake.Calls{1}.Method, "getJson");
            tc.verifyEqual(fake.Calls{1}.Arguments, {route});
        end

        function test_resolveId_itemsTypes_usesTopLevelRoute(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items_types", struct("id", 19, "title", "Template"));

            id = elab.client.resolveId(fake, "items_types", "Template");

            tc.verifyEqual(id, 19);
            tc.verifyEqual(fake.Calls{1}.Arguments, {"/items_types"});
        end

        function test_resolveId_numericName_returnsWithoutRequest(tc)
            fake = FakeElabClient();

            id = elab.client.resolveId(fake, "experiments_categories", "42");

            tc.verifyEqual(id, 42);
            tc.verifyEmpty(fake.Calls);
        end

        function test_resolveId_missingName_throwsNotFound(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 17, "title", "Other"));

            call = @() elab.client.resolveId( ...
                fake, "experiments_categories", "Missing");

            tc.verifyError(call, "elab:client:resolveId:notFound");
        end

        function test_ensureItemStatus_matchingTitle_returnsWithoutCreate(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/items_status", ...
                struct("id", 23, "title", "OK", "color", "28a745"));

            id = elab.client.ensureItemStatus(fake, "OK", "28a745");

            tc.verifyEqual(id, 23);
            tc.verifyEqual(TestElabClient.callMethods(fake), {"getJson"});
        end

        function test_ensureItemStatus_missing_createsPatchesAndVerifies(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/items_status", {});

            id = elab.client.ensureItemStatus(fake, "Check", "ffc107");

            tc.verifyEqual(id, 601);
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "createEntry", "patchJson", "getJson"});
            tc.verifyEqual(fake.Calls{2}.Arguments, ...
                {"teams/current/items_status", struct()});
            tc.verifyEqual(fake.Calls{3}.Arguments{3}, ...
                struct("title", "Check", "color", "ffc107"));
        end

        function test_ensureItemStatus_missingTitleAfterPatch_throwsNotApplied(tc)
            fake = FakeElabClient();
            fake.IgnoreStatusTitlePatches = true;
            fake.setGetResponse("/teams/current/items_status", {});

            call = @() elab.client.ensureItemStatus(fake, "Check", "ffc107");

            tc.verifyError(call, "elab:client:ensureItemStatus:notApplied");
        end

        function test_createExperiment_namedCategory_sendsCategoryField(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));

            id = elab.client.createExperiment( ...
                fake, "Session", "Run 001", date="2026-09-11", status="Draft");

            patchCall = fake.Calls{4};
            payload = patchCall.Arguments{3};
            tc.verifyEqual(id, fake.CreatedId);
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "createEntry", "getJson", "patchJson"});
            tc.verifyEqual(patchCall.Arguments(1:2), {"experiments", fake.CreatedId});
            tc.verifyEqual(payload.category, 7);
            tc.verifyFalse(isfield(payload, "category_id"));
        end

        function test_createExperiment_omittedStatus_leavesServerDefault(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));

            elab.client.createExperiment( ...
                fake, "Session", "Run 002", date="2026-09-11");

            payload = fake.Calls{3}.Arguments{3};
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "createEntry", "patchJson"});
            tc.verifyFalse(isfield(payload, "status"));
        end

        function test_setExtraFields_suppliedFields_sendsEncodedMetadata(tc)
            fake = FakeElabClient();
            fields = struct("name", "temperature", "type", "number", "value", 25.5);

            elab.client.setExtraFields(fake, "experiments", 91, fields);

            patchCall = fake.Calls{1};
            payload = patchCall.Arguments{3};
            metadata = jsondecode(payload.metadata);
            tc.verifyEqual(patchCall.Method, "patchJson");
            tc.verifyEqual(patchCall.Arguments(1:2), {"experiments", 91});
            tc.verifyTrue(ischar(payload.metadata));
            tc.verifyEqual(metadata.extra_fields.temperature.type, 'number');
            tc.verifyEqual(metadata.extra_fields.temperature.value, '25.5');
        end

        function test_ensureItem_missingTitle_createsThenSetsCategory(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", {});
            fake.setGetResponse("/items/501", ...
                struct("id", 501, "title", "XRD-01", "category", 3));

            id = elab.client.ensureItem(fake, "Instrument", "XRD-01");

            patchCall = fake.Calls{4};
            tc.verifyEqual(id, 501);
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "getJson", "createEntry", "patchJson", "getJson"});
            tc.verifyEqual(fake.Calls{2}.Arguments, ...
                {"/items", {"cat", 3, "q", "XRD-01", "limit", 50}});
            tc.verifyEqual(fake.Calls{3}.Arguments, {"items", struct()});
            tc.verifyEqual(patchCall.Arguments(1:2), {"items", 501});
            tc.verifyEqual(patchCall.Arguments{3}, ...
                struct("title", "XRD-01", "category", 3));
        end

        function test_ensureItem_matchingTitle_returnsExistingWithoutCreate(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                struct("id", 202, "title", "XRD-01", "category", 3));
            fake.setGetResponse("/items/202", ...
                struct("id", 202, "title", "XRD-01", "category", 3));

            id = elab.client.ensureItem(fake, "Instrument", "XRD-01");

            tc.verifyEqual(id, 202);
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "getJson", "getJson"});
            tc.verifyEqual(fake.Calls{3}.Arguments, {"/items/202"});
        end

        function test_findExperiment_queryIgnored_returnsEmptyForDifferentValue(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", { ...
                TestElabClient.experiment(101, "AAAA"), ...
                TestElabClient.experiment(102, "BBBB"), ...
                TestElabClient.experiment(103, "CCCC")});

            id = elab.client.findExperimentByExtraField( ...
                fake, "experiments", "data_file_hash", "ZZZZ");

            tc.verifyEmpty(id);
            tc.verifyEqual(fake.Calls{1}.Arguments{1}, "/experiments");
            tc.verifyEqual(fake.Calls{1}.Arguments{2}(1:2), ...
                {"q", "extrafield:data_file_hash:ZZZZ"});
        end

        function test_findExperiment_duplicateMatches_warnsAndReturnsLowestId(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", { ...
                TestElabClient.experiment(205, "SAME"), ...
                TestElabClient.experiment(104, "SAME")});

            output = evalc("id = elab.client.findExperimentByExtraField(" + ...
                "fake, 'experiments', 'data_file_hash', 'SAME');");

            tc.verifyEqual(id, 104);
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "found 2 entries");
            tc.verifySubstring(output, "returning the lowest id");
        end

        function test_findExperiment_limitReached_warnsAndReturnsMatch(tc)
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_ELAB_EXTRA_FIELD_SEARCH_LIMIT", "3"));
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", { ...
                TestElabClient.experiment(301, "NO"), ...
                TestElabClient.experiment(302, "MATCH"), ...
                TestElabClient.experiment(303, "NO")});

            output = evalc("id = elab.client.findExperimentByExtraField(" + ...
                "fake, 'experiments', 'data_file_hash', 'MATCH');");

            tc.verifyEqual(id, 302);
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "configured limit of 3 entries");
            tc.verifyEqual(fake.Calls{1}.Arguments{2}, ...
                {"q", "extrafield:data_file_hash:MATCH", "limit", 3});
        end

        function test_findExperiment_category_addsCatToQuery(tc)
            tc.applyFixture( ...
                matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                    "ELAB_ELAB_EXTRA_FIELD_SEARCH_LIMIT", "3"));
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/experiments", ...
                TestElabClient.categorizedExperiment(401, "MATCH", 7));

            id = elab.client.findExperimentByExtraField(fake, ...
                "experiments", "data_file_hash", "MATCH", category="Session");

            tc.verifyEqual(id, 401);
            tc.verifyEqual(fake.Calls{2}.Arguments, ...
                {"/experiments", {"q", "extrafield:data_file_hash:MATCH", ...
                "cat", 7, "limit", 3}});
        end

        function test_findExperiment_itemCategory_usesResourceCategories(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 9, "title", "Instrument"));
            fake.setGetResponse("/items", ...
                TestElabClient.categorizedExperiment(407, "MATCH", 9));

            id = elab.client.findExperimentByExtraField(fake, ...
                "items", "data_file_hash", "MATCH", category="Instrument");

            tc.verifyEqual(id, 407);
            tc.verifyEqual(fake.Calls{1}.Arguments, ...
                {"/teams/current/resources_categories"});
            tc.verifyEqual(fake.Calls{2}.Arguments{1}, "/items");
        end

        function test_findExperiment_serverIgnoresCat_rejectsOtherCategory(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/experiments", { ...
                TestElabClient.categorizedExperiment(402, "MATCH", 8), ...
                TestElabClient.categorizedExperiment(403, "MATCH", 7)});

            id = elab.client.findExperimentByExtraField(fake, ...
                "experiments", "data_file_hash", "MATCH", category="Session");

            tc.verifyEqual(id, 403);
        end

        function test_findExperiment_categoryTitleOnly_matchesIgnoringCase(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            item = TestElabClient.experiment(404, "MATCH");
            item.category_title = "sEsSiOn";
            fake.setGetResponse("/experiments", item);

            id = elab.client.findExperimentByExtraField(fake, ...
                "experiments", "data_file_hash", "MATCH", category="Session");

            tc.verifyEqual(id, 404);
            tc.verifyEqual(TestElabClient.callMethods(fake), ...
                {"getJson", "getJson"});
        end

        function test_findExperiment_missingCategory_refetchesCandidate(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/experiments", ...
                TestElabClient.experiment(405, "MATCH"));
            fake.setGetResponse("/experiments/405", ...
                TestElabClient.categorizedExperiment(405, "MATCH", 7));

            output = evalc("id = elab.client.findExperimentByExtraField(" + ...
                "fake, 'experiments', 'data_file_hash', 'MATCH', " + ...
                "category='Session');");

            tc.verifyEqual(id, 405);
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "refetched 1 candidate");
            tc.verifyEqual(fake.Calls{3}.Arguments, {"/experiments/405"});
        end

        function test_findExperiment_unknownCategoryAfterRefetch_excludesAndWarns(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            item = TestElabClient.experiment(406, "MATCH");
            fake.setGetResponse("/experiments", item);
            fake.setGetResponse("/experiments/406", item);

            output = evalc("id = elab.client.findExperimentByExtraField(" + ...
                "fake, 'experiments', 'data_file_hash', 'MATCH', " + ...
                "category='Session');");

            tc.verifyEmpty(id);
            tc.verifySubstring(output, "category is unknown");
            tc.verifySubstring(output, "id 406");
            tc.verifySubstring(output, "refetched 1 candidate");
        end

        function test_findExperiment_categoryWithUnsupportedKind_errors(tc)
            fake = FakeElabClient();

            call = @() elab.client.findExperimentByExtraField(fake, ...
                "reports", "data_file_hash", "MATCH", category="Session");

            tc.verifyError(call, ...
                "elab:client:findExperimentByExtraField:unsupportedKind");
            tc.verifyEmpty(fake.Calls);
        end
    end

    methods (Static, Access = private)
        function item = experiment(id, hash)
            extraFields = struct( ...
                "data_file_hash", struct("type", "text", "value", hash));
            item = struct("id", id, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
        end

        function item = categorizedExperiment(id, hash, category)
            item = TestElabClient.experiment(id, hash);
            item.category = category;
        end

        function methods = callMethods(fake)
            methods = cellfun(@(call) call.Method, fake.Calls, ...
                "UniformOutput", false);
        end
    end
end
