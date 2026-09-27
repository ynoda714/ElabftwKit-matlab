classdef TestWatchAndLogBody < matlab.unittest.TestCase
    % TestWatchAndLogBody  Quick-look body embedding and title tests.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testRewritesBodyOnceWithUploadedImage(tc)
            [cfg, quickLookName] = tc.watchCase(false);
            fake = tc.baseClient();
            upload = struct("id", 19, "real_name", quickLookName, ...
                "long_name", "stored quicklook.png", "storage", 1);
            fake.setGetResponse("/experiments/501", struct("uploads", upload));

            result = elab.pipeline.watchAndLog(fake, cfg);
            [payloads, createPayload] = tc.bodyPayloads(fake);
            imageHtml = elab.client.uploadImageHtml( ...
                fake, "experiments", 501, quickLookName, alt="quick look");
            expectedBody = string(createPayload.body) + ...
                "<p>" + imageHtml + "</p>";

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyNumElements(payloads, 1);
            tc.verifyEqual(string(payloads{1}.body), expectedBody);
            tc.verifySubstring(string(payloads{1}.body), "<img");
            tc.verifySubstring(string(payloads{1}.body), "download.php");
            tc.verifySubstring(string(payloads{1}.body), "_quicklook.png");
            tc.verifySubstring(string(payloads{1}.body), "Auto-logged from");
            tc.verifyFalse(contains(string(createPayload.body), "<img"));
        end

        function testCreationBodyUsesLocaleIndependentTimestamp(tc)
            [cfg, ~] = tc.watchCase(false);
            fake = tc.baseClient();

            evalc("result = elab.pipeline.watchAndLog(fake, cfg);");
            [~, createPayload] = tc.bodyPayloads(fake);
            body = string(createPayload.body);

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyNotEmpty(regexp(body, ...
                "^Auto-logged from .+ by watchAndLog \(\d{4}-\d{2}-\d{2} " + ...
                "\d{2}:\d{2}:\d{2}\)\.$", "once"));
            tc.verifyFalse(contains(body, "<img"));
            tc.verifyFalse(contains(body, "/"));
        end

        function testImageBodyFailureWarnsAndContinuesUpdates(tc)
            [cfg, ~] = tc.watchCase(true);
            fake = tc.clientWithMappedItems();

            output = evalc("result = elab.pipeline.watchAndLog(fake, cfg);");

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifySubstring(output, "could not show the quick look");
            tc.verifyTrue(tc.hasItemFieldPatch(fake, "usage_hours_total"));
            tc.verifyTrue(tc.hasItemFieldPatch(fake, "quantity"));
            tc.verifyTrue(isfile(fullfile(cfg.watch.processed_dir, "xrd_sample.xy")));
            tc.verifyFalse(isfile(fullfile(cfg.watch.failed_dir, "xrd_sample.xy")));
        end

        function testQuickLookTitleContainsTechniqueSampleAndAcquisitionTime(tc)
            [cfg, ~] = tc.watchCase(true);
            fake = tc.clientWithMappedItems();
            key = "M3_8QuickLookTitle";
            oldCallback = get(groot, "DefaultFigureCloseRequestFcn");
            set(groot, "DefaultFigureCloseRequestFcn", ...
                @TestWatchAndLogBody.captureFigureTitle);
            tc.addTeardown(@() TestWatchAndLogBody.restoreCloseCallback( ...
                oldCallback, key));

            evalc("result = elab.pipeline.watchAndLog(fake, cfg);");
            capturedTitle = string(getappdata(groot, key));

            tc.assertEqual(result.status, "logged", result.message);
            tc.verifyEqual(capturedTitle, "XRD  SMP-TEST  2026-08-31 14:25");
        end
    end

    methods (Access = private)
        function [cfg, quickLookName] = watchCase(tc, matched)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(folder));

            inbox = fullfile(folder, "inbox");
            mkdir(inbox);
            filePath = fullfile(inbox, "xrd_sample.xy");
            writelines(["# acquired_at: 2026-08-31 14:25:00"; ...
                "10 100"; "20 200"; "30 150"], filePath);
            quickLookName = "xrd_sample_quicklook.png";

            mapDir = fullfile(folder, "data", "list");
            mkdir(mapDir);
            matchSubstring = "does-not-match";
            if matched
                matchSubstring = "xrd_";
            end
            sampleMap = table(matchSubstring, "SMP-TEST", "PRJ-A", ...
                "operator-a", "Instrument", "XRD-01", "Vial", 2, ...
                'VariableNames', {'match_substring', 'sample_id', 'project', ...
                'operator', 'instrument_type', 'instrument_title', ...
                'consumable_title', 'consumable_qty'});
            mapPath = fullfile(mapDir, "sample_map.csv");
            writetable(sampleMap, mapPath);

            cfg = loadConfig();
            cfg.elab.base_url = "https://example.test";
            cfg.elab.session_category = "Session";
            cfg.elab.draft_status = "Draft";
            cfg.watch.inbox_dir = inbox;
            cfg.watch.processed_dir = fullfile(folder, "processed");
            cfg.watch.failed_dir = fullfile(folder, "failed");
            cfg.watch.sample_map = mapPath;
            cfg.watch.nominal_run_minutes = 17;
        end

        function fake = baseClient(~)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments", {});
            fake.setGetResponse("/teams/current/experiments_categories", ...
                struct("id", 7, "title", "Session"));
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
        end

        function fake = clientWithMappedItems(tc)
            fake = tc.baseClient();
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 3, "title", "Instrument"), ...
                struct("id", 4, "title", "Sample"), ...
                struct("id", 5, "title", "Consumable")]);
            fake.setGetResponse("/items", [ ...
                struct("id", 201, "title", "XRD-01", "category", 3), ...
                struct("id", 202, "title", "SMP-TEST", "category", 4), ...
                struct("id", 203, "title", "Vial", "category", 5)]);

            instrumentFields = struct( ...
                "usage_hours_total", struct("type", "number", "value", "1"), ...
                "last_used", struct("type", "datetime-local", "value", ""));
            consumableFields = struct( ...
                "quantity", struct("type", "number", "value", "5"), ...
                "reorder_threshold", struct("type", "number", "value", "2"), ...
                "status", struct("type", "text", "value", "InStock"));
            fake.setGetResponse("/items/201", struct("id", 201, ...
                "title", "XRD-01", "category", 3, ...
                "metadata", jsonencode(struct("extra_fields", instrumentFields))));
            fake.setGetResponse("/items/202", struct("id", 202, ...
                "title", "SMP-TEST", "category", 4, "metadata", ""));
            fake.setGetResponse("/items/203", struct("id", 203, ...
                "title", "Vial", "category", 5, ...
                "metadata", jsonencode(struct("extra_fields", consumableFields))));
        end

        function [rewrites, createPayload] = bodyPayloads(~, fake)
            rewrites = {};
            createPayload = [];
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method ~= "patchJson" || call.Arguments{1} ~= "experiments"
                    continue
                end
                payload = call.Arguments{3};
                if ~isfield(payload, "body")
                    continue
                end
                if isfield(payload, "title")
                    createPayload = payload;
                else
                    rewrites{end + 1} = payload; %#ok<AGROW>
                end
            end
        end

        function tf = hasItemFieldPatch(~, fake, fieldName)
            tf = false;
            for k = 1:numel(fake.Calls)
                call = fake.Calls{k};
                if call.Method == "patchJson" && call.Arguments{1} == "items" && ...
                        isfield(call.Arguments{3}, "action") && ...
                        isfield(call.Arguments{3}, fieldName)
                    tf = true;
                    return
                end
            end
        end
    end

    methods (Static, Access = private)
        function captureFigureTitle(f, ~)
            ax = findobj(f, "Type", "axes");
            setappdata(groot, "M3_8QuickLookTitle", ax(1).Title.String);
            delete(f);
        end

        function restoreCloseCallback(callback, key)
            set(groot, "DefaultFigureCloseRequestFcn", callback);
            if isappdata(groot, key)
                rmappdata(groot, key);
            end
        end
    end
end
