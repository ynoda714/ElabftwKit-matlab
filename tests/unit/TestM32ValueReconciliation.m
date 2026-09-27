classdef TestM32ValueReconciliation < matlab.unittest.TestCase
    % TestM32ValueReconciliation  Ledger and report value-reconciliation regressions.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testLedgerTenMinutesThreeTimesUsesMinuteTotal(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/61", tc.instrument(61, 0, 0));

            elab.pipeline.updateInstrumentLedger(fake, tc.config(), 61, 10);
            elab.pipeline.updateInstrumentLedger(fake, tc.config(), 61, 10);
            elab.pipeline.updateInstrumentLedger(fake, tc.config(), 61, 10);

            fields = tc.extraFields(fake, "/items/61");
            tc.verifyEqual(str2double(fields.usage_minutes_total.value), 30);
            tc.verifyEqual(str2double(fields.usage_hours_total.value), 0.50, ...
                AbsTol=1e-12);
            tc.verifyNotEqual(str2double(fields.usage_hours_total.value), 0.51);
        end

        function testLedgerMinuteTotalsAreNeverRounded(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/62", tc.instrument(62, 0, 0));
            fake.setGetResponse("/items/63", tc.instrument(63, 0, 0));
            fake.setGetResponse("/items/64", tc.instrument(64, 0, 0));

            tc.updateThreeTimes(fake, 62, 7);
            tc.updateThreeTimes(fake, 63, 5);
            tc.updateThreeTimes(fake, 64, 2.5);

            seven = tc.extraFields(fake, "/items/62");
            five = tc.extraFields(fake, "/items/63");
            fractional = tc.extraFields(fake, "/items/64");
            tc.verifyEqual(str2double(seven.usage_minutes_total.value), 21);
            tc.verifyEqual(str2double(seven.usage_hours_total.value), 0.35, AbsTol=1e-12);
            tc.verifyEqual(str2double(five.usage_minutes_total.value), 15);
            tc.verifyEqual(str2double(five.usage_hours_total.value), 0.25, AbsTol=1e-12);
            tc.verifyEqual(str2double(fractional.usage_minutes_total.value), 7.5, ...
                AbsTol=1e-12);
        end

        function testLedgerMigratesMissingMinutesFromZero(tc)
            fake = FakeElabClient();
            fields = [ ...
                elab.util.fieldStruct("usage_hours_total", 0.34, "number"), ...
                elab.util.fieldStruct("last_used", "", "datetime-local"), ...
                elab.util.fieldStruct("calibration_due", "2099-12-31", "date")];
            fake.setGetResponse("/items/65", tc.entry(65, fields));

            output = evalc("elab.pipeline.updateInstrumentLedger(fake, tc.config(), 65, 10);");

            updated = tc.extraFields(fake, "/items/65");
            tc.verifyEqual(str2double(updated.usage_minutes_total.value), 10);
            tc.verifyEqual(str2double(updated.usage_hours_total.value), 0.17, AbsTol=1e-12);
            tc.verifyEqual(updated.calibration_due.value, '2099-12-31');
            tc.verifySubstring(output, "had no usage_minutes_total");
            tc.verifySubstring(output, "0.34 was not carried over");
        end

        function testLedgerTreatsNullMinutesAsZero(tc)
            fake = FakeElabClient();
            text = ['{"extra_fields":{"usage_minutes_total":{"type":"number","value":null},' ...
                '"usage_hours_total":{"type":"number","value":"9"},' ...
                '"last_used":{"type":"datetime-local","value":""}}}'];
            fake.setGetResponse("/items/66", struct("id", 66, "metadata", text));

            output = evalc("elab.pipeline.updateInstrumentLedger(fake, tc.config(), 66, 10);");

            fields = tc.extraFields(fake, "/items/66");
            tc.verifyEqual(str2double(fields.usage_minutes_total.value), 10);
            tc.verifyEqual(str2double(fields.usage_hours_total.value), 0.17, AbsTol=1e-12);
            tc.verifySubstring(output, "had no usage_minutes_total");
        end

        function testLedgerRejectsNonnumericMinutesWithoutPatch(tc)
            fake = FakeElabClient();
            fields = [ ...
                elab.util.fieldStruct("usage_minutes_total", "abc", "number"), ...
                elab.util.fieldStruct("usage_hours_total", 4, "number")];
            fake.setGetResponse("/items/67", tc.entry(67, fields));

            call = @() elab.pipeline.updateInstrumentLedger(fake, tc.config(), 67, 10);

            tc.verifyError(call, "elab:pipeline:updateInstrumentLedger:invalidMinutes");
            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
        end

        function testAddExtraFieldPreservesRawMetadata(tc)
            fake = FakeElabClient();
            japaneseName = char([35013 32622 32 12513 12514]);
            original = ['{"elabftw":{"display_main_text":true},"extra_fields":{' ...
                '"ids":{"type":"number","value":"1"},"' japaneseName ...
                '":{"type":"select","value":"a","options":["a","b"]},' ...
                '"usage_hours_total":{"type":"number","value":"0.34"}}}'];
            fake.setGetResponse("/items/68", struct("id", 68, "metadata", original));
            openPosition = regexp(original, '"extra_fields"\s*:\s*\{', 'once', 'end');

            elab.client.addExtraField(fake, "items", 68, ...
                "usage_minutes_total", 0, "number");

            payload = tc.callsOf(fake, "patchJson");
            sent = payload{1}.Arguments{3}.metadata;
            suffix = original(openPosition + 1:end);
            tc.verifyEqual(sent(1:openPosition), original(1:openPosition));
            tc.verifyTrue(endsWith(sent, suffix));
            tc.verifySubstring(sent, ['"' japaneseName '":']);
            tc.verifySubstring(sent, '"options":["a","b"]');
            tc.verifySubstring(sent, '"elabftw":{"display_main_text":true}');
            tc.verifySubstring(sent(openPosition + 1:end), ...
                '"usage_minutes_total":{"type":"number","value":"0"}, ');
        end

        function testAddExtraFieldHandlesEmptyObject(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/69", ...
                struct("id", 69, "metadata", '{"extra_fields": {}}'));

            elab.client.addExtraField(fake, "items", 69, "new_value", 5, "number");

            payloads = tc.callsOf(fake, "patchJson");
            sent = payloads{1}.Arguments{3}.metadata;
            decoded = jsondecode(sent);
            tc.verifyEqual(string(decoded.extra_fields.new_value.value), "5");
            tc.verifyFalse(contains(sent, ", }"));
        end

        function testAddExtraFieldExistingNameDoesNotPatch(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/70", tc.instrument(70, 1, 0.02));

            elab.client.addExtraField(fake, "items", 70, ...
                "usage_minutes_total", 9, "number");

            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
            fields = tc.extraFields(fake, "/items/70");
            tc.verifyEqual(string(fields.usage_minutes_total.value), "1");
        end

        function testAddExtraFieldRejectsArrayExtraFields(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/71", ...
                struct("id", 71, "metadata", '{"extra_fields":[]}'));

            call = @() elab.client.addExtraField(fake, "items", 71, "new_value", 1, "number");

            tc.verifyError(call, "elab:client:addExtraField:unsupportedMetadata");
            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
        end

        function testAddExtraFieldRejectsMissingExtraFields(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/72", struct("id", 72, "metadata", '{"elabftw":{}}'));

            call = @() elab.client.addExtraField(fake, "items", 72, "new_value", 1, "number");

            tc.verifyError(call, "elab:client:addExtraField:unsupportedMetadata");
            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
        end

        function testAddExtraFieldRejectsBrokenMetadata(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/73", struct("id", 73, "metadata", '{broken'));

            call = @() elab.client.addExtraField(fake, "items", 73, "new_value", 1, "number");

            tc.verifyError(call, "elab:client:addExtraField:invalidMetadata");
            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
        end

        function testAddExtraFieldReadbackDetectsIgnoredPatch(tc)
            fake = FakeElabClient();
            fake.IgnoreMetadataPatches = true;
            fake.setGetResponse("/items/74", ...
                struct("id", 74, "metadata", '{"extra_fields":{}}'));

            call = @() elab.client.addExtraField(fake, "items", 74, "new_value", 1, "number");

            tc.verifyError(call, "elab:client:addExtraField:notApplied");
        end

        function testNegativeInventoryIsRecordedAndWarned(tc)
            fake = FakeElabClient();
            fields = [ ...
                elab.util.fieldStruct("quantity", 1, "number"), ...
                elab.util.fieldStruct("reorder_threshold", 2, "number"), ...
                elab.util.fieldStruct("status", "InStock", "text")];
            item = tc.entry(75, fields, "Buffer", 3);
            tc.configureConsumable(fake, item);
            fake.setGetResponse("/teams/current/items_status", ...
                struct("id", 15, "title", "Reorder", "color", "fd7e14"));

            output = evalc("elab.pipeline.consumeInventory(fake, tc.config(), 'Buffer', 3);");

            updated = tc.extraFields(fake, "/items/75");
            native = fake.getJson("/items/75");
            tc.verifyEqual(str2double(updated.quantity.value), -2);
            tc.verifyEqual(string(updated.status.value), "InStock");
            tc.verifyEqual(string(native.status_title), "Reorder");
            tc.verifySubstring(output, "is below zero (-2)");
        end

        function testNullInventoryIsSkipped(tc)
            fake = FakeElabClient();
            metadata = ['{"extra_fields":{"quantity":{"type":"number","value":null},' ...
                '"reorder_threshold":{"type":"number","value":"2"},' ...
                '"status":{"type":"text","value":"InStock"}}}'];
            item = struct("id", 76, "title", "Buffer", "category", 3, "metadata", metadata);
            tc.configureConsumable(fake, item);

            output = evalc("elab.pipeline.consumeInventory(fake, tc.config(), 'Buffer', 1);");

            tc.verifySubstring(output, "has no numeric 'quantity'");
            tc.verifyEmpty(tc.callsOf(fake, "patchJson"));
        end

        function testReportUsesDefaultsForNullValues(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            nullMetadata = ['{"extra_fields":{' ...
                '"instrument_title":{"type":"text","value":null},' ...
                '"project":{"type":"text","value":"P"},' ...
                '"operator":{"type":"text","value":"O"},' ...
                '"run_minutes":{"type":"number","value":null},' ...
                '"run_minutes_source":{"type":"text","value":null},' ...
                '"acquired_at_source":{"type":"text","value":null}}}'];
            entries = {struct("id", 77, "date", "2026-08-10", "metadata", nullMetadata), ...
                tc.experiment(78, "A", 5, "measured")};
            [fake, cfg] = tc.reportClient(entries);

            elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);

            rows = tc.uploadedRows(fake);
            tc.verifyEqual(rows.instrument(1), "(unknown)");
            tc.verifyEqual(rows.run_minutes(1), 10, AbsTol=1e-12);
            tc.verifyEqual(rows.run_minutes_source(1), "unspecified");
            tc.verifyEqual(rows.duration_basis(1), "filled");
            tc.verifyEqual(height(rows), 2);
        end

        function testReportExcludesUnreadableMetadata(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            entries = {struct("id", 79, "date", "2026-08-10", "metadata", '{broken'), ...
                tc.experiment(80, "A", 5, "measured")};
            [fake, cfg] = tc.reportClient(entries); %#ok<ASGLU>

            output = evalc("elab.pipeline.monthlyUsageReport(fake, cfg, 2026, 8);");

            rows = tc.uploadedRows(fake);
            body = tc.creationBody(fake);
            tc.verifyEqual(height(rows), 1);
            tc.verifyEqual(rows.run_minutes, 5, AbsTol=1e-12);
            tc.verifySubstring(body, "<strong>Sessions</strong>: 1");
            tc.verifySubstring(output, "excluded 1 sessions with unreadable metadata");
        end

        function testLedgerAndMonthlyReportTotalsAgree(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            fake = FakeElabClient();
            fake.setGetResponse("/items/81", tc.instrument(81, 0, 0));
            fake.setGetResponse("/items/82", tc.instrument(82, 0, 0));
            tc.updateThreeTimes(fake, 81, 10);
            tc.updateThreeTimes(fake, 82, 10);
            entries = {tc.experiment(811, "A", 10, "measured"), ...
                tc.experiment(812, "A", 10, "measured"), ...
                tc.experiment(813, "A", 10, "measured"), ...
                tc.experiment(821, "B", 10, "measured"), ...
                tc.experiment(822, "B", 10, "measured"), ...
                tc.experiment(823, "B", 10, "measured")};
            tc.configureReport(fake, entries);

            elab.pipeline.monthlyUsageReport(fake, tc.config(), 2026, 8);

            a = tc.extraFields(fake, "/items/81");
            b = tc.extraFields(fake, "/items/82");
            rows = tc.uploadedRows(fake);
            body = tc.creationBody(fake);
            ledgerMinutes = str2double(a.usage_minutes_total.value) + ...
                str2double(b.usage_minutes_total.value);
            tc.verifyEqual(ledgerMinutes, sum(rows.run_minutes), AbsTol=1e-12);
            tc.verifyEqual(ledgerMinutes, 60, AbsTol=1e-12);
            tc.verifyEqual(str2double(a.usage_hours_total.value), 0.50, AbsTol=1e-12);
            tc.verifyEqual(str2double(b.usage_hours_total.value), 0.50, AbsTol=1e-12);
            tc.verifySubstring(body, "<strong>Recorded time</strong>: 60 min (1.00 h)");
        end
    end

    methods (Access = private)
        function updateThreeTimes(tc, fake, id, minutes)
            cfg = tc.config();
            elab.pipeline.updateInstrumentLedger(fake, cfg, id, minutes);
            elab.pipeline.updateInstrumentLedger(fake, cfg, id, minutes);
            elab.pipeline.updateInstrumentLedger(fake, cfg, id, minutes);
        end

        function item = instrument(tc, id, minutes, hours)
            fields = [ ...
                elab.util.fieldStruct("usage_minutes_total", minutes, "number"), ...
                elab.util.fieldStruct("usage_hours_total", hours, "number"), ...
                elab.util.fieldStruct("last_used", "", "datetime-local"), ...
                elab.util.fieldStruct("calibration_due", "2099-12-31", "date")];
            item = tc.entry(id, fields);
        end

        function item = entry(~, id, fields, title, category)
            if nargin < 4
                title = "";
            end
            if nargin < 5
                category = [];
            end
            extraFields = struct();
            for k = 1:numel(fields)
                extraFields.(fields(k).name) = struct( ...
                    "type", fields(k).type, ...
                    "value", elab.util.toElabValue(fields(k).value));
            end
            item = struct("id", id, "metadata", ...
                jsonencode(struct("extra_fields", extraFields)));
            if title ~= ""
                item.title = title;
            end
            if ~isempty(category)
                item.category = category;
            end
        end

        function fields = extraFields(~, fake, route)
            item = fake.getJson(route);
            metadata = jsondecode(item.metadata);
            fields = metadata.extra_fields;
        end

        function calls = callsOf(~, fake, method)
            selected = cellfun(@(call) string(call.Method) == method, fake.Calls);
            calls = fake.Calls(selected);
        end

        function cfg = config(~)
            cfg = struct();
            cfg.elab = struct( ...
                "session_category", "Session", ...
                "qc_category", "QC", ...
                "report_category", "Report", ...
                "instrument_category", "Instrument", ...
                "sample_category", "Sample", ...
                "consumable_category", "Consumable", ...
                "sop_category", "SOP", ...
                "draft_status", "Draft", ...
                "report_list_limit", 500, ...
                "labels", struct( ...
                    "instrument_status_ok", "OK", ...
                    "instrument_status_calibration_overdue", "CalibrationOverdue", ...
                    "consumable_status_ok", "InStock", ...
                    "consumable_status_reorder", "Reorder"));
            cfg.watch = struct("nominal_run_minutes", 10);
        end

        function configureConsumable(~, fake, item)
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Consumable"));
            fake.setGetResponse("/items", item);
            fake.setGetResponse("/items/" + item.id, item);
        end

        function entry = experiment(~, id, instrument, minutes, source)
            fields = struct( ...
                "instrument_title", struct("type", "text", "value", instrument), ...
                "project", struct("type", "text", "value", "P"), ...
                "operator", struct("type", "text", "value", "O"), ...
                "run_minutes", struct("type", "number", "value", string(minutes)), ...
                "run_minutes_source", struct("type", "text", "value", source), ...
                "acquired_at_source", struct("type", "text", "value", "measured"));
            entry = struct("id", id, "date", "2026-08-10", ...
                "metadata", jsonencode(struct("extra_fields", fields)));
        end

        function [fake, cfg] = reportClient(tc, entries)
            fake = FakeElabClient();
            cfg = tc.config();
            tc.configureReport(fake, entries);
        end

        function configureReport(~, fake, entries)
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 7, "title", "Session"), ...
                struct("id", 8, "title", "Report")]);
            fake.setGetResponse("/teams/current/experiments_status", ...
                struct("id", 5, "title", "Draft"));
            fake.setGetResponse("/experiments", entries);
        end

        function rows = uploadedRows(tc, fake)
            calls = tc.callsOf(fake, "uploadFile");
            comments = cellfun(@(call) string(call.Arguments{4}), calls);
            selected = calls{find(comments == "raw session rows", 1)};
            rows = readtable(selected.Arguments{3}, "TextType", "string");
        end

        function body = creationBody(tc, fake)
            calls = tc.callsOf(fake, "patchJson");
            for k = 1:numel(calls)
                payload = calls{k}.Arguments{3};
                if calls{k}.Arguments{1} == "experiments" && ...
                        isfield(payload, "title") && isfield(payload, "body")
                    body = string(payload.body);
                    return
                end
            end
            error("TestM32ValueReconciliation:bodyNotFound", ...
                "No report creation body was recorded.");
        end
    end
end
