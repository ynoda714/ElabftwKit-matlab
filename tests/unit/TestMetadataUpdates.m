classdef TestMetadataUpdates < matlab.unittest.TestCase
    % TestMetadataUpdates  Contract tests for field-level metadata updates.

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
        function test_updateExtraFields_oneField_preservesOtherValuesAndTypes(tc)
            fake = FakeElabClient();
            fields = TestMetadataUpdates.instrumentFields(4);
            fake.setGetResponse("/items/17", TestMetadataUpdates.entry(17, fields));

            elab.client.updateExtraFields(fake, "items", 17, ...
                elab.util.fieldStruct("usage_hours_total", 5.5, "number"));

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/17");
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '5.5');
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.type, 'number');
            tc.verifyEqual(metadata.extra_fields.model.value, 'MiniFlex');
            tc.verifyEqual(metadata.extra_fields.model.type, 'text');
            tc.verifyEqual(metadata.extra_fields.location.value, 'Room 203');
            tc.verifyEqual(metadata.extra_fields.location.type, 'text');
        end

        function test_updateExtraFields_twoFields_sendsOnePatchWithStringValues(tc)
            fake = FakeElabClient();
            fields = TestMetadataUpdates.instrumentFields(4);
            fake.setGetResponse("/items/18", TestMetadataUpdates.entry(18, fields));
            updates = [ ...
                elab.util.fieldStruct("usage_hours_total", 7.25, "number"), ...
                elab.util.fieldStruct("status", "Check", "text")];

            elab.client.updateExtraFields(fake, "items", 18, updates);

            patches = TestMetadataUpdates.callsOf(fake, "patchJson");
            payload = patches{1}.Arguments{3};
            tc.verifyNumElements(patches, 1);
            tc.verifyEqual(string(payload.action), "updatemetadatafield");
            tc.verifyTrue(ischar(payload.usage_hours_total));
            tc.verifyTrue(ischar(payload.status));
            tc.verifyEqual(payload.usage_hours_total, '7.25');
            tc.verifyEqual(payload.status, 'Check');
        end

        function test_updateExtraFields_missingDefault_errorsBeforePatch(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/19", TestMetadataUpdates.entry(19, ...
                elab.util.fieldStruct("usage_hours_total", 4, "number")));
            updates = [ ...
                elab.util.fieldStruct("usage_hours_total", 8, "number"), ...
                elab.util.fieldStruct("last_used", "2026-09-14T10:00", "datetime-local")];

            call = @() elab.client.updateExtraFields(fake, "items", 19, updates);

            tc.verifyError(call, "elab:client:updateExtraFields:fieldMissing");
            tc.verifyEmpty(TestMetadataUpdates.callsOf(fake, "patchJson"));
        end

        function test_updateExtraFields_missingWarn_updatesPresentAndWarns(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/20", TestMetadataUpdates.entry(20, ...
                elab.util.fieldStruct("usage_hours_total", 4, "number")));
            updates = [ ...
                elab.util.fieldStruct("usage_hours_total", 8, "number"), ...
                elab.util.fieldStruct("last_used", "2026-09-14T10:00", "datetime-local")];
            call = @() elab.client.updateExtraFields( ...
                fake, "items", 20, updates, missing="warn"); %#ok<NASGU>

            output = evalc("call();");

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/20");
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '8');
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "items/20");
            tc.verifySubstring(output, "last_used");
        end

        function test_updateExtraFields_noMetadata_initializesWholeMetadata(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/21", struct("id", 21));
            fields = elab.util.fieldStruct("quantity", 10, "number");

            elab.client.updateExtraFields(fake, "items", 21, fields);

            patches = TestMetadataUpdates.callsOf(fake, "patchJson");
            payload = patches{1}.Arguments{3};
            metadata = jsondecode(payload.metadata);
            tc.verifyNumElements(patches, 1);
            tc.verifyFalse(isfield(payload, "action"));
            tc.verifyEqual(metadata.extra_fields.quantity.value, '10');
        end

        function test_updateExtraFields_serverIgnoresUpdate_throwsNotApplied(tc)
            fake = FakeElabClient();
            fake.IgnoreMetadataFieldUpdates = true;
            fake.setGetResponse("/items/22", TestMetadataUpdates.entry(22, ...
                elab.util.fieldStruct("quantity", 10, "number")));

            call = @() elab.client.updateExtraFields(fake, "items", 22, ...
                elab.util.fieldStruct("quantity", 9, "number"));

            tc.verifyError(call, "elab:client:updateExtraFields:notApplied");
        end

        function test_updateExtraFields_allMissingWarn_sendsNoPatchAndPreservesMetadata(tc)
            fake = FakeElabClient();
            original = TestMetadataUpdates.entry(23, ...
                elab.util.fieldStruct("location", "Room 203", "text"));
            fake.setGetResponse("/items/23", original);
            updates = [ ...
                elab.util.fieldStruct("quantity", 9, "number"), ...
                elab.util.fieldStruct("status", "Reorder", "text")]; %#ok<NASGU>

            output = evalc("elab.client.updateExtraFields(fake, 'items', 23, " + ...
                "updates, missing='warn');");

            current = fake.getJson("/items/23");
            tc.verifyEmpty(TestMetadataUpdates.callsOf(fake, "patchJson"));
            tc.verifyEqual(current.metadata, original.metadata);
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "quantity");
            tc.verifySubstring(output, "status");
        end

        function test_updateExtraFields_secondUpdateIgnored_throwsNotApplied(tc)
            fake = FakeElabClient();
            fake.IgnoredMetadataFieldNames = "status";
            fake.setGetResponse("/items/24", TestMetadataUpdates.entry(24, [ ...
                elab.util.fieldStruct("quantity", 10, "number"), ...
                elab.util.fieldStruct("status", "InStock", "text")]));
            updates = [ ...
                elab.util.fieldStruct("quantity", 9, "number"), ...
                elab.util.fieldStruct("status", "Reorder", "text")];

            call = @() elab.client.updateExtraFields(fake, "items", 24, updates);

            tc.verifyError(call, "elab:client:updateExtraFields:notApplied");
        end

        function test_updateExtraFields_invalidIdentifier_throwsBeforeRequest(tc)
            fake = FakeElabClient();
            fields = elab.util.fieldStruct("not a name", 1, "number");

            call = @() elab.client.updateExtraFields(fake, "items", 23, fields);

            tc.verifyError(call, "elab:client:updateExtraFields:invalidFieldName");
            tc.verifyEmpty(fake.Calls);
        end

        function test_updateInstrumentLedger_preservesBootstrapFields(tc)
            fake = FakeElabClient();
            fields = TestMetadataUpdates.instrumentFields(4);
            fake.setGetResponse("/items/31", TestMetadataUpdates.entry(31, fields));

            elab.pipeline.updateInstrumentLedger(fake, ...
                TestMetadataUpdates.config(), 31, 90);

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/31");
            tc.verifyEqual(metadata.extra_fields.usage_minutes_total.value, '330');
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '5.5');
            tc.verifyEqual(metadata.extra_fields.model.value, 'MiniFlex');
            tc.verifyEqual(metadata.extra_fields.location.value, 'Room 203');
            tc.verifyEqual(metadata.extra_fields.calibration_due.value, '2099-12-31');
        end

        function test_consumeInventory_preservesThresholdAndUnit(tc)
            fake = FakeElabClient();
            fields = TestMetadataUpdates.consumableFields(5);
            item = TestMetadataUpdates.entry(32, fields, "Buffer", 3);
            TestMetadataUpdates.configureConsumable(fake, item);

            elab.pipeline.consumeInventory(fake, ...
                TestMetadataUpdates.config(), "Buffer", 2);

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/32");
            tc.verifyEqual(metadata.extra_fields.quantity.value, '3');
            tc.verifyEqual(metadata.extra_fields.reorder_threshold.value, '2');
            tc.verifyEqual(metadata.extra_fields.unit.value, 'bottle');
        end

        function test_consumeInventory_existingInStockAtThreshold_assignsReorder(tc)
            fake = FakeElabClient();
            fields = [ ...
                elab.util.fieldStruct("quantity", 5, "number"), ...
                elab.util.fieldStruct("reorder_threshold", 5, "number"), ...
                elab.util.fieldStruct("unit", "bottle", "text")];
            item = TestMetadataUpdates.entry(35, fields, "Buffer", 3);
            item.status = 14;
            item.status_title = "InStock";
            TestMetadataUpdates.configureConsumable(fake, item);
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.consumeInventory(fake, ...
                TestMetadataUpdates.config(), "Buffer", 2);

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/35");
            updated = fake.getJson("/items/35");
            tc.verifyEqual(metadata.extra_fields.quantity.value, '3');
            tc.verifyFalse(isfield(metadata.extra_fields, "status"));
            tc.verifyEqual(string(updated.status_title), "Reorder");
            tc.verifyNumElements(TestMetadataUpdates.nativeStatusPatches(fake), 1);
        end

        function test_updateInstrumentLedger_existingOkOverdue_assignsNativeStatus(tc)
            fake = FakeElabClient();
            fields = TestMetadataUpdates.instrumentFields(4);
            fields(strcmp(string({fields.name}), "calibration_due")).value = "2000-01-01";
            item = TestMetadataUpdates.entry(36, fields);
            item.status = 11;
            item.status_title = "OK";
            fake.setGetResponse("/items/36", item);
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.updateInstrumentLedger(fake, ...
                TestMetadataUpdates.config(), 36, 15);

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/36");
            updated = fake.getJson("/items/36");
            tc.verifyEqual(string(metadata.extra_fields.status.value), "OK");
            tc.verifyEqual(string(updated.status_title), "CalibrationOverdue");
            tc.verifyNumElements(TestMetadataUpdates.nativeStatusPatches(fake), 1);
        end

        function test_updateInstrumentLedger_emptyStatusWithinDueDate_assignsOk(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/items/37", TestMetadataUpdates.entry(37, ...
                TestMetadataUpdates.instrumentFields(4)));
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.updateInstrumentLedger(fake, ...
                TestMetadataUpdates.config(), 37, 15);

            updated = fake.getJson("/items/37");
            tc.verifyEqual(string(updated.status_title), "OK");
            tc.verifyNumElements(TestMetadataUpdates.nativeStatusPatches(fake), 1);
        end

        function test_updateInstrumentLedger_existingCheckWithinDueDate_doesNotPatchStatus(tc)
            fake = FakeElabClient();
            item = TestMetadataUpdates.entry(42, ...
                TestMetadataUpdates.instrumentFields(4));
            item.status = 12;
            item.status_title = "Check";
            fake.setGetResponse("/items/42", item);
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.updateInstrumentLedger(fake, ...
                TestMetadataUpdates.config(), 42, 15);

            tc.verifyEmpty(TestMetadataUpdates.nativeStatusPatches(fake));
            updated = fake.getJson("/items/42");
            tc.verifyEqual(string(updated.status_title), "Check");
        end

        function test_consumeInventory_emptyStatusAboveThreshold_assignsInStock(tc)
            fake = FakeElabClient();
            item = TestMetadataUpdates.entry(38, ...
                TestMetadataUpdates.consumableFields(5), "Buffer", 3);
            TestMetadataUpdates.configureConsumable(fake, item);
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.consumeInventory(fake, ...
                TestMetadataUpdates.config(), "Buffer", 2);

            updated = fake.getJson("/items/38");
            tc.verifyEqual(string(updated.status_title), "InStock");
            tc.verifyNumElements(TestMetadataUpdates.nativeStatusPatches(fake), 1);
        end

        function test_consumeInventory_existingStatusAboveThreshold_doesNotPatchStatus(tc)
            fake = FakeElabClient();
            item = TestMetadataUpdates.entry(43, ...
                TestMetadataUpdates.consumableFields(5), "Buffer", 3);
            item.status = 15;
            item.status_title = "Reorder";
            TestMetadataUpdates.configureConsumable(fake, item);
            TestMetadataUpdates.configureStatuses(fake);

            elab.pipeline.consumeInventory(fake, ...
                TestMetadataUpdates.config(), "Buffer", 2);

            tc.verifyEmpty(TestMetadataUpdates.nativeStatusPatches(fake));
            updated = fake.getJson("/items/43");
            tc.verifyEqual(string(updated.status_title), "Reorder");
        end

        function test_statusCreationFailureWarnsAndKeepsLedgerAndInventory(tc)
            ledgerFake = FakeElabClient();
            ledgerFields = TestMetadataUpdates.instrumentFields(1);
            ledgerFields(strcmp(string({ledgerFields.name}), ...
                "calibration_due")).value = "2000-01-01";
            ledgerFake.setGetResponse("/items/39", ...
                TestMetadataUpdates.entry(39, ledgerFields));
            ledgerFake.setGetResponse("/teams/current/items_status", {});
            ledgerFake.FailCreateKinds = "teams/current/items_status";
            inventoryFake = FakeElabClient();
            inventoryItem = TestMetadataUpdates.entry(40, ...
                TestMetadataUpdates.consumableFields(2), "Buffer", 3);
            TestMetadataUpdates.configureConsumable(inventoryFake, inventoryItem);
            inventoryFake.setGetResponse("/teams/current/items_status", {});
            inventoryFake.FailCreateKinds = "teams/current/items_status";

            ledgerOutput = evalc("elab.pipeline.updateInstrumentLedger(" + ...
                "ledgerFake, TestMetadataUpdates.config(), 39, 15);");
            inventoryOutput = evalc("elab.pipeline.consumeInventory(" + ...
                "inventoryFake, TestMetadataUpdates.config(), 'Buffer', 1);");

            ledger = TestMetadataUpdates.readMetadata(ledgerFake, "/items/39");
            inventory = TestMetadataUpdates.readMetadata(inventoryFake, "/items/40");
            tc.verifyEqual(string(ledger.extra_fields.usage_minutes_total.value), "75");
            tc.verifyEqual(string(inventory.extra_fields.quantity.value), "1");
            tc.verifySubstring(ledgerOutput, "[WARN]");
            tc.verifySubstring(inventoryOutput, "[WARN]");
        end

        function test_updateInstrumentLedger_missingLastUsed_updatesHoursAndWarns(tc)
            fake = FakeElabClient();
            fields = [ ...
                elab.util.fieldStruct("usage_minutes_total", 120, "number"), ...
                elab.util.fieldStruct("usage_hours_total", 2, "number"), ...
                elab.util.fieldStruct("model", "MiniFlex", "text")];
            fake.setGetResponse("/items/33", TestMetadataUpdates.entry(33, fields));

            output = evalc("elab.pipeline.updateInstrumentLedger(fake, " + ...
                "TestMetadataUpdates.config(), 33, 60);");

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/33");
            tc.verifyEqual(metadata.extra_fields.usage_minutes_total.value, '180');
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '3');
            tc.verifySubstring(output, "[WARN]");
            tc.verifySubstring(output, "last_used");
        end

        function test_updateInstrumentLedger_notApplied_propagates(tc)
            fake = FakeElabClient();
            fake.IgnoreMetadataFieldUpdates = true;
            fields = TestMetadataUpdates.instrumentFields(2);
            fake.setGetResponse("/items/34", TestMetadataUpdates.entry(34, fields));

            call = @() elab.pipeline.updateInstrumentLedger(fake, ...
                TestMetadataUpdates.config(), 34, 60);

            tc.verifyError(call, "elab:client:updateExtraFields:notApplied");
        end

        function test_ensureItem_existingWithFields_doesNotPatch(tc)
            fake = FakeElabClient();
            item = TestMetadataUpdates.entry(41, ...
                elab.util.fieldStruct("usage_hours_total", 12, "number"), ...
                "XRD-01", 1);
            TestMetadataUpdates.configureInstrument(fake, item);

            output = evalc("id = elab.client.ensureItem(fake, 'Instrument', " + ...
                "'XRD-01', elab.util.fieldStruct('usage_hours_total', 0, 'number'));");

            tc.verifyEqual(id, 41);
            tc.verifyEmpty(TestMetadataUpdates.callsOf(fake, "patchJson"));
            tc.verifySubstring(output, "[INFO]");
            tc.verifySubstring(output, "were not written");
        end

        function test_ensureItem_newWithFields_writesMetadata(tc)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 1, "title", "Instrument"));
            fake.setGetResponse("/items", {});
            fake.setGetResponse("/items/501", ...
                struct("id", 501, "title", "XRD-01", "category", 1));

            id = elab.client.ensureItem(fake, "Instrument", "XRD-01", ...
                elab.util.fieldStruct("usage_hours_total", 0, "number"));

            patches = TestMetadataUpdates.callsOf(fake, "patchJson");
            metadata = jsondecode(patches{2}.Arguments{3}.metadata);
            tc.verifyEqual(id, 501);
            tc.verifyNumElements(patches, 2);
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '0');
        end

        function test_bootstrapItems_newInstrument_createsLedgerFields(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            [instrumentCsv, consumableCsv] = TestMetadataUpdates.writeSeedCsvs();
            fake = TestMetadataUpdates.bootstrapFake(false);

            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);

            patch = TestMetadataUpdates.firstMetadataPatch(fake, "items");
            metadata = jsondecode(patch.Arguments{3}.metadata);
            tc.verifyEqual(metadata.extra_fields.usage_minutes_total.type, 'number');
            tc.verifyEqual(metadata.extra_fields.usage_minutes_total.value, '0');
            tc.verifyEqual(metadata.extra_fields.last_used.type, 'datetime-local');
            tc.verifyEqual(metadata.extra_fields.last_used.value, '');
            tc.verifyEqual(metadata.extra_fields.days_to_calibration.type, 'number');
            tc.verifyEqual(metadata.extra_fields.days_to_calibration.value, '');
            tc.verifyFalse(isfield(metadata.extra_fields, "status"));
        end

        function test_bootstrapItems_createsFiveStatusesAndAssignsNewItems(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            [instrumentCsv, consumableCsv] = TestMetadataUpdates.writeSeedCsvs();
            fake = TestMetadataUpdates.bootstrapFake(false);

            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);

            statusCreates = TestMetadataUpdates.createCallsOf( ...
                fake, "teams/current/items_status");
            statusPatches = TestMetadataUpdates.nativeStatusPatches(fake);
            instrument = fake.getJson("/items/501");
            consumable = fake.getJson("/items/502");
            instrumentMetadata = jsondecode(instrument.metadata);
            consumableMetadata = jsondecode(consumable.metadata);
            listGetCount = TestMetadataUpdates.callCountForRoute( ...
                fake, "/teams/current/items_status");
            statuses = elab.util.toItems(fake.getJson( ...
                "/teams/current/items_status"));
            titles = sort(string(cellfun(@(item) item.title, statuses, ...
                "UniformOutput", false)));
            colors = sort(string(cellfun(@(item) item.color, statuses, ...
                "UniformOutput", false)));
            tc.verifyNumElements(statusCreates, 5);
            tc.verifyNumElements(statusPatches, 2);
            tc.verifyEqual(string(instrument.status_title), "OK");
            tc.verifyEqual(string(consumable.status_title), "InStock");
            tc.verifyFalse(isfield(instrumentMetadata.extra_fields, "status"));
            tc.verifyFalse(isfield(consumableMetadata.extra_fields, "status"));
            tc.verifyEqual(string(consumableMetadata.extra_fields.quantity.value), "10");
            tc.verifyEqual(titles, sort(["CalibrationOverdue", "Check", ...
                "InStock", "OK", "Reorder"]));
            tc.verifyEqual(colors, sort(["28a745", "ffc107", "dc3545", ...
                "28a745", "fd7e14"]));
            tc.verifyEqual(listGetCount, 1);
        end

        function test_bootstrapItems_secondRunDoesNotRecreateStatuses(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            [instrumentCsv, consumableCsv] = TestMetadataUpdates.writeSeedCsvs();
            fake = TestMetadataUpdates.bootstrapFake(false);

            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);
            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);

            tc.verifyNumElements(TestMetadataUpdates.createCallsOf( ...
                fake, "teams/current/items_status"), 5);
        end

        function test_bootstrapItems_twice_doesNotResetUsageHours(tc)
            tc.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            [instrumentCsv, consumableCsv] = TestMetadataUpdates.writeSeedCsvs();
            fake = TestMetadataUpdates.bootstrapFake(true);

            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);
            elab.pipeline.bootstrapItems(fake, TestMetadataUpdates.config(), ...
                instrumentsCsv=instrumentCsv, consumablesCsv=consumableCsv);

            metadata = TestMetadataUpdates.readMetadata(fake, "/items/41");
            tc.verifyEqual(metadata.extra_fields.usage_minutes_total.value, '720');
            tc.verifyEqual(metadata.extra_fields.usage_hours_total.value, '12');
            instrumentPatches = TestMetadataUpdates.itemPatches(fake, 41);
            tc.verifyEmpty(instrumentPatches);
        end
    end

    methods (Static, Access = private)
        function fields = instrumentFields(hours)
            fields = [ ...
                elab.util.fieldStruct("usage_minutes_total", hours * 60, "number"), ...
                elab.util.fieldStruct("usage_hours_total", hours, "number"), ...
                elab.util.fieldStruct("last_used", "", "datetime-local"), ...
                elab.util.fieldStruct("days_to_calibration", "", "number"), ...
                elab.util.fieldStruct("model", "MiniFlex", "text"), ...
                elab.util.fieldStruct("location", "Room 203", "text"), ...
                elab.util.fieldStruct("calibration_due", "2099-12-31", "date"), ...
                elab.util.fieldStruct("status", "OK", "text")];
        end

        function fields = consumableFields(quantity)
            fields = [ ...
                elab.util.fieldStruct("quantity", quantity, "number"), ...
                elab.util.fieldStruct("reorder_threshold", 2, "number"), ...
                elab.util.fieldStruct("unit", "bottle", "text"), ...
                elab.util.fieldStruct("status", "InStock", "text")];
        end

        function item = entry(id, fields, title, category)
            arguments
                id
                fields
                title = ""
                category = []
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

        function metadata = readMetadata(fake, route)
            entry = fake.getJson(route);
            metadata = jsondecode(entry.metadata);
        end

        function calls = callsOf(fake, method)
            selected = cellfun(@(call) string(call.Method) == method, fake.Calls);
            calls = fake.Calls(selected);
        end

        function calls = createCallsOf(fake, kind)
            selected = cellfun(@(call) string(call.Method) == "createEntry" && ...
                string(call.Arguments{1}) == kind, fake.Calls);
            calls = fake.Calls(selected);
        end

        function calls = nativeStatusPatches(fake)
            selected = cellfun(@TestMetadataUpdates.isNativeStatusPatch, fake.Calls);
            calls = fake.Calls(selected);
        end

        function calls = itemPatches(fake, itemId)
            selected = cellfun(@(call) string(call.Method) == "patchJson" && ...
                string(call.Arguments{1}) == "items" && ...
                double(call.Arguments{2}) == itemId, fake.Calls);
            calls = fake.Calls(selected);
        end

        function tf = isNativeStatusPatch(call)
            tf = string(call.Method) == "patchJson" && ...
                string(call.Arguments{1}) == "items" && ...
                isfield(call.Arguments{3}, "status");
        end

        function call = firstMetadataPatch(fake, kind)
            patches = TestMetadataUpdates.callsOf(fake, "patchJson");
            selected = cellfun(@(candidate) ...
                string(candidate.Arguments{1}) == kind && ...
                isfield(candidate.Arguments{3}, "metadata"), patches);
            matches = patches(selected);
            call = matches{1};
        end

        function count = callCountForRoute(fake, route)
            count = sum(cellfun(@(call) string(call.Method) == "getJson" && ...
                string(call.Arguments{1}) == route, fake.Calls));
        end

        function cfg = config()
            cfg = struct();
            cfg.elab = struct( ...
                "session_category", "Session", ...
                "qc_category", "QC", ...
                "report_category", "Report", ...
                "instrument_category", "Instrument", ...
                "sample_category", "Sample", ...
                "consumable_category", "Consumable", ...
                "sop_category", "SOP", ...
                "labels", struct( ...
                    "instrument_status_ok", "OK", ...
                    "instrument_status_check", "Check", ...
                    "instrument_status_calibration_overdue", "CalibrationOverdue", ...
                    "consumable_status_ok", "InStock", ...
                    "consumable_status_reorder", "Reorder"));
        end

        function configureInstrument(fake, item)
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 1, "title", "Instrument"));
            fake.setGetResponse("/items", item);
            fake.setGetResponse("/items/" + item.id, item);
        end

        function configureConsumable(fake, item)
            fake.setGetResponse("/teams/current/resources_categories", ...
                struct("id", 3, "title", "Consumable"));
            fake.setGetResponse("/items", item);
            fake.setGetResponse("/items/" + item.id, item);
        end

        function [instrumentCsv, consumableCsv] = writeSeedCsvs()
            instrumentCsv = string(fullfile(pwd, "instruments.csv"));
            consumableCsv = string(fullfile(pwd, "consumables.csv"));
            instruments = table("XRD-01", "Instrument", "MiniFlex", ...
                "Room 203", "2099-12-31", VariableNames=[ ...
                "title", "item_type", "model", "location", "calibration_due"]);
            consumables = table("Buffer", 10, 2, "bottle", VariableNames=[ ...
                "title", "quantity", "reorder_threshold", "unit"]);
            writetable(instruments, instrumentCsv);
            writetable(consumables, consumableCsv);
        end

        function fake = bootstrapFake(existing)
            fake = FakeElabClient();
            fake.setGetResponse("/teams/current/experiments_categories", [ ...
                struct("id", 1, "title", "Session"), ...
                struct("id", 2, "title", "QC"), ...
                struct("id", 3, "title", "Report")]);
            fake.setGetResponse("/teams/current/resources_categories", [ ...
                struct("id", 1, "title", "Instrument"), ...
                struct("id", 2, "title", "Sample"), ...
                struct("id", 3, "title", "Consumable"), ...
                struct("id", 4, "title", "SOP")]);
            fake.setGetResponse("/teams/current/items_status", {});
            if existing
                TestMetadataUpdates.configureStatuses(fake);
                item = TestMetadataUpdates.entry(41, ...
                    TestMetadataUpdates.instrumentFields(12), "XRD-01", 1);
                fake.setGetResponse("/items", item);
                fake.setGetResponse("/items/41", item);
            else
                fake.setGetResponse("/items", {});
            end
        end


        function configureStatuses(fake)
            statuses = { ...
                struct("id", 11, "title", "OK", "color", "28a745"), ...
                struct("id", 12, "title", "Check", "color", "ffc107"), ...
                struct("id", 13, "title", "CalibrationOverdue", "color", "dc3545"), ...
                struct("id", 14, "title", "InStock", "color", "28a745"), ...
                struct("id", 15, "title", "Reorder", "color", "fd7e14")};
            fake.setGetResponse("/teams/current/items_status", statuses);
        end
    end
end
