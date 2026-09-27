classdef TestNmrExperimentFolder < matlab.unittest.TestCase
    % TestNmrExperimentFolder  Value contracts for Bruker experiment folders.

    methods (TestClassSetup)
        function test_addSourcePath_enablesPackage(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            fixture = matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), IncludingSubfolders=true);
            tc.applyFixture(fixture);
        end
    end

    methods (Test)
        function test_write_defaultRun_createsSupplementalFiles(tc)
            run = tc.write(tc.root(), "normal");
            tc.verifyTrue(isfile(fullfile(run, "audita.txt")));
            tc.verifyTrue(isfile(fullfile(run, "uxnmr.par")));
            tc.verifyTrue(isfile(fullfile(run, "pdata", "1", "procs")));
        end

        function test_write_defaultRun_writesExpectedDate(tc)
            run = tc.write(tc.root(), "normal");
            contents = string(fileread(fullfile(run, "acqus")));
            tc.verifySubstring(contents, "##$DATE= 1790208000");
        end

        function test_write_variants_changeExpectedFiles(tc)
            root = tc.root();
            zero = tc.write(root, "dateZero", "zero");
            absent = tc.write(root, "dateAbsent", "absent");
            noAudit = tc.write(root, "noAudit", "no-audit");
            multi = tc.write(root, "multiAudit", "multi");
            twoD = tc.write(root, "twoDimensional", "two-d");
            empty = tc.write(root, "emptyFid", "empty");
            tc.verifySubstring(string(fileread(fullfile(zero, "acqus"))), "##$DATE= 0");
            tc.verifyFalse(contains(string(fileread(fullfile(absent, "acqus"))), "##$DATE="));
            tc.verifyFalse(isfile(fullfile(noAudit, "audita.txt")));
            tc.verifyEqual(count(string(fileread(fullfile(multi, "audita.txt"))), "started at"), 2);
            tc.verifyTrue(isfile(fullfile(twoD, "ser")));
            tc.verifyTrue(isfile(fullfile(twoD, "acqu2s")));
            tc.verifyFalse(isfile(fullfile(twoD, "fid")));
            tc.verifyEqual(dir(fullfile(empty, "fid")).bytes, 0);
        end

        function test_write_newYorkSummerTime_writesDateAndOffset(tc)
            root = tc.root();
            at = datetime(2026, 7, 1, 9, 0, 0);
            run = elab.io.writeMockNmrRun(root, acquiredAt=at, ...
                name="new-york", timezone="America/New_York");
            contents = string(fileread(fullfile(run, "acqus")));
            tc.verifySubstring(contents, "##$DATE= 1782910800");
            tc.verifySubstring(contents, "-0400 mock-user@mock-host");
        end

        function test_write_sameArguments_writesEveryFileByteIdentically(tc)
            root = tc.root();
            first = tc.write(root, "normal", "one");
            second = tc.write(root, "normal", "two");
            tc.verifyEqual(tc.fileBytes(first), tc.fileBytes(second));
        end

        function test_listExperimentFolders_nestedRuns_returnsSortedPaths(tc)
            root = tc.root();
            first = tc.write(fullfile(root, "dataset"), "normal", "1");
            second = tc.write(fullfile(root, "dataset"), "normal", "2");
            third = tc.write(fullfile(root, "a", "b", "c"), "normal", "3");
            actual = elab.io.listExperimentFolders(root);
            tc.verifyEqual(actual, sort([string(first); string(second); string(third)]));
        end

        function test_listExperimentFolders_incompleteFolder_omitsFolder(tc)
            root = tc.root();
            incomplete = fullfile(root, "incomplete");
            mkdir(incomplete);
            writelines("x", fullfile(incomplete, "acqus"));
            tc.verifyEmpty(elab.io.listExperimentFolders(root));
        end

        function test_listExperimentFolders_inboxFiles_omitsFiles(tc)
            root = tc.root();
            writelines("x", fullfile(root, "acqus"));
            tc.writeBytes(fullfile(root, "fid"), uint8([1 2]));
            tc.verifyEmpty(elab.io.listExperimentFolders(root));
        end

        function test_listExperimentFolders_processedFolder_omitsNestedAcqus(tc)
            root = tc.root();
            outer = tc.write(root, "normal", "outer");
            processed = fullfile(outer, "pdata", "1");
            writelines("x", fullfile(processed, "acqus"));
            tc.writeBytes(fullfile(processed, "fid"), uint8([1 2]));
            tc.verifyEqual(elab.io.listExperimentFolders(root), string(outer));
        end

        function test_listExperimentFolders_nestedExperiment_stopsAtOuterFolder(tc)
            root = tc.root();
            outer = tc.write(root, "normal", "outer");
            nested = fullfile(outer, "nested");
            mkdir(nested);
            writelines("x", fullfile(nested, "acqus"));
            tc.writeBytes(fullfile(nested, "fid"), uint8([1 2]));
            tc.verifyEqual(elab.io.listExperimentFolders(root), string(outer));
        end

        function test_listExperimentFolders_missingInbox_returnsEmptyColumn(tc)
            paths = elab.io.listExperimentFolders(fullfile(tc.root(), "missing"));
            tc.verifySize(paths, [0 1]);
        end

        function test_manifest_literalCoreText_matchesIndependentContract(tc)
            run = tc.smallRun(tc.root());
            manifest = elab.io.experimentManifest(run);
            expected = "elab-manifest 1" + newline + ...
                "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb  1  acqus" + newline + ...
                "3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d  1  audita.txt" + newline + ...
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  3  fid" + newline;
            tc.verifyEqual(manifest.coreText, expected);
        end

        function test_manifest_auxiliaryChange_leavesCoreHash(tc)
            run = tc.write(tc.root(), "normal");
            before = elab.io.experimentManifest(run);
            writelines("changed", fullfile(run, "uxnmr.par"));
            after = elab.io.experimentManifest(run);
            tc.verifyEqual(after.coreHash, before.coreHash);
            tc.verifyNotEqual(after.fullHash, before.fullHash);
        end

        function test_manifest_emptyAuxiliaryFile_isIncludedOutsideCore(tc)
            run = tc.write(tc.root(), "normal");
            emptyPath = fullfile(run, "prosol_History");
            tc.writeBytes(emptyPath, uint8.empty);
            withEmpty = elab.io.experimentManifest(run);
            index = find(string({withEmpty.entries.path}) == "prosol_History", 1);
            tc.verifyNotEmpty(index);
            tc.verifyEqual(withEmpty.entries(index).bytes, 0);
            tc.verifyEqual(withEmpty.entries(index).sha256, ...
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
            delete(emptyPath);
            withoutEmpty = elab.io.experimentManifest(run);
            tc.verifyEqual(withEmpty.coreHash, withoutEmpty.coreHash);
            tc.verifyNotEqual(withEmpty.fullHash, withoutEmpty.fullHash);
        end

        function test_manifest_processedChange_leavesHashes(tc)
            run = tc.write(tc.root(), "normal");
            before = elab.io.experimentManifest(run);
            writelines("changed", fullfile(run, "pdata", "1", "procs"));
            after = elab.io.experimentManifest(run);
            tc.verifyEqual(after.coreHash, before.coreHash);
            tc.verifyEqual(after.fullHash, before.fullHash);
        end

        function test_manifest_coreFileChanges_changeBothHashes(tc)
            run = tc.write(tc.root(), "normal");
            tc.verifyCoreChange(run, "acqus");
            tc.verifyCoreChange(run, "fid");
            tc.verifyCoreChange(run, "audita.txt");
        end

        function test_manifest_excludedNames_omitsEntries(tc)
            run = tc.write(tc.root(), "normal");
            tc.writeBytes(fullfile(run, ".hidden"), uint8([1]));
            tc.writeBytes(fullfile(run, "Thumbs.db"), uint8([1]));
            paths = string({elab.io.experimentManifest(run).entries.path});
            tc.verifyFalse(any(paths == ".hidden"));
            tc.verifyFalse(any(paths == "Thumbs.db"));
        end

        function test_manifest_subfolderFile_usesRelativePathAndIsNotCore(tc)
            run = tc.write(tc.root(), "normal");
            sub = fullfile(run, "sub");
            mkdir(sub);
            tc.writeBytes(fullfile(sub, "fid"), uint8([1 2]));
            manifest = elab.io.experimentManifest(run);
            index = find(string({manifest.entries.path}) == "sub/fid", 1);
            tc.verifyNotEmpty(index);
            tc.verifyFalse(manifest.entries(index).isCore);
        end

        function test_manifest_caseSensitiveNames_sortsCodePoints(tc)
            run = tc.write(tc.root(), "normal");
            writelines("z", fullfile(run, "Zeta"));
            writelines("a", fullfile(run, "alpha"));
            paths = string({elab.io.experimentManifest(run).entries.path});
            tc.verifyLessThan(find(paths == "Zeta", 1), find(paths == "alpha", 1));
        end

        function test_manifest_missingComponents_raisesNotExperiment(tc)
            run = string(fullfile(tc.root(), "incomplete"));
            mkdir(run);
            writelines("x", fullfile(run, "acqus"));
            tc.verifyError(@() elab.io.experimentManifest(run), ...
                "elab:io:experimentManifest:notExperiment");
        end

        function test_manifest_missingFolder_raisesNotFolder(tc)
            tc.verifyError(@() elab.io.experimentManifest(fullfile(tc.root(), "missing")), ...
                "elab:io:experimentManifest:notFolder");
        end

        function test_parse_defaultRun_returnsAllTypedOrderedValues(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "normal"));
            names = string({parsed.params.name});
            expected = ["vendor" "nucleus" "bf1_mhz" "sw_hz" "td" "ns" "ds" ...
                "d1_s" "solvent" "temperature_k" "pulse_program" "instrument" ...
                "acquisition_software"];
            tc.verifyEqual(names, expected);
            tc.verifyEqual([parsed.params(3:8).value], [400.13 8012.820513 16384 16 2 1], AbsTol=1e-9);
            tc.verifyEqual(string(parsed.params(1).value), "Bruker");
            tc.verifyEqual(string(parsed.params(13).value), "TopSpin 4.1.4");
        end

        function test_parse_privateHeaderValues_omitsPrivateAndPulseWidth(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "normal"));
            values = string(cellfun(@string, {parsed.params.value}, UniformOutput=false));
            names = string({parsed.params.name});
            tc.verifyFalse(any(contains(values, ["mock-owner" "mock-user" "mock-host"])));
            tc.verifyFalse(any(contains(lower(names), "pw")));
        end

        function test_parse_noneSolvent_omitsSolvent(tc)
            run = tc.write(tc.root(), "normal");
            tc.replaceAcqus(run, "##$SOLVENT= <CDCl3>", "##$SOLVENT= <None>");
            names = string({elab.io.parseBrukerExperiment(run).params.name});
            tc.verifyFalse(any(names == "solvent"));
        end

        function test_parse_missingNs_omitsOnlyNs(tc)
            run = tc.write(tc.root(), "normal");
            tc.removeAcqusLine(run, "##$NS=");
            names = string({elab.io.parseBrukerExperiment(run).params.name});
            tc.verifyFalse(any(names == "ns"));
            tc.verifyTrue(all(ismember(["vendor" "ds" "td"], names)));
        end

        function test_parse_missingFid_raisesNoFid(tc)
            run = tc.write(tc.root(), "normal");
            delete(fullfile(run, "fid"));
            tc.verifyError(@() elab.io.parseBrukerExperiment(run), ...
                "elab:io:parseBrukerExperiment:noFid");
        end

        function test_parse_twoDimensionalRun_raisesUnsupportedDimension(tc)
            run = tc.write(tc.root(), "twoDimensional");
            tc.verifyError(@() elab.io.parseBrukerExperiment(run), ...
                "elab:io:parseBrukerExperiment:unsupportedDimension");
        end

        function test_readAcquiredAt_fixedEpoch_convertsTimezones(tc)
            parsed = tc.parsedWithEpoch(tc.root(), 1750000000);
            [tokyo, ~] = elab.io.readAcquiredAt("", parsed, timezone="Asia/Tokyo");
            [newYork, ~] = elab.io.readAcquiredAt("", parsed, timezone="America/New_York");
            [utc, ~] = elab.io.readAcquiredAt("", parsed, timezone="UTC");
            tc.verifyEqual(tokyo, datetime(2025, 6, 16, 0, 6, 40));
            tc.verifyEqual(newYork, datetime(2025, 6, 15, 11, 6, 40));
            tc.verifyEqual(utc, datetime(2025, 6, 15, 15, 6, 40));
        end

        function test_readAcquiredAt_winterEpoch_convertsNewYork(tc)
            parsed = tc.parsedWithEpoch(tc.root(), 1735000000);
            [actual, ~] = elab.io.readAcquiredAt("", parsed, timezone="America/New_York");
            tc.verifyEqual(actual, datetime(2024, 12, 23, 19, 26, 40));
        end

        function test_readAcquiredAt_invalidDate_fallsBackToFidMtime(tc)
            run = tc.write(tc.root(), "dateZero");
            parsed = elab.io.parseBrukerExperiment(run);
            [actual, source] = elab.io.readAcquiredAt("", parsed, timezone="UTC");
            tc.verifyEqual(source, "file_mtime");
            tc.verifyLessThan(abs(seconds(actual - tc.fileMtime(fullfile(run, "fid")))), 5);
        end

        function test_readAcquiredAt_absentDate_fallsBackToFidMtime(tc)
            run = tc.write(tc.root(), "dateAbsent");
            parsed = elab.io.parseBrukerExperiment(run);
            [actual, source] = elab.io.readAcquiredAt("", parsed, timezone="UTC");
            tc.verifyEqual(source, "file_mtime");
            tc.verifyLessThan(abs(seconds(actual - tc.fileMtime(fullfile(run, "fid")))), 5);
        end

        function test_readAcquiredAt_matchingOffset_writesNoWarning(tc)
            run = tc.write(tc.root(), "normal");
            parsed = elab.io.parseBrukerExperiment(run);
            output = evalc("elab.io.readAcquiredAt(run, parsed, timezone='Asia/Tokyo');");
            tc.verifyFalse(contains(string(output), "header timezone offset differs"));
        end

        function test_readAcquiredAt_differentOffset_warnsWithoutPrivateData(tc)
            run = tc.write(tc.root(), "normal");
            parsed = elab.io.parseBrukerExperiment(run);
            output = evalc("elab.io.readAcquiredAt(run, parsed, timezone='America/New_York');");
            tc.verifySubstring(string(output), "header timezone offset differs");
            tc.verifyFalse(contains(string(output), "mock-user"));
            tc.verifyFalse(contains(string(output), "mock-host"));
        end

        function test_readAcquiredAt_emptyTimezone_fallsBackToFidMtime(tc)
            run = tc.write(tc.root(), "normal");
            parsed = elab.io.parseBrukerExperiment(run);
            resolver = @(~) "";
            output = evalc("[actual, source] = elab.io.readAcquiredAt(run, parsed, timezoneResolver=resolver);");
            tc.verifyEqual(source, "file_mtime");
            tc.verifyLessThan(abs(seconds(actual - tc.fileMtime(fullfile(run, "fid")))), 5);
            tc.verifySubstring(string(output), "configured timezone is empty");
        end

        function test_readAcquiredAt_missingDataFile_returnsUnknown(tc)
            parsed = tc.parsedWithEpoch(tc.root(), NaN);
            parsed.acquisition.data_file = "";
            [actual, source] = elab.io.readAcquiredAt("", parsed, timezone="UTC");
            tc.verifyTrue(isnat(actual));
            tc.verifyEqual(source, "unknown");
        end

        function test_readRunMinutes_defaultAudit_returnsMeasured(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "normal"));
            [value, source] = elab.io.readRunMinutes(parsed, 10);
            tc.verifyEqual(value, 38 / 60, AbsTol=1e-9);
            tc.verifyEqual(source, "measured");
        end

        function test_readRunMinutes_noAudit_returnsCalculated(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "noAudit"));
            [value, source] = elab.io.readRunMinutes(parsed, 10);
            expected = (16 + 2) * (1 + 8192 / 8012.820513) / 60;
            tc.verifyEqual(value, expected, AbsTol=1e-9);
            tc.verifyEqual(source, "calculated");
        end

        function test_readRunMinutes_multipleAudit_returnsCalculated(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "multiAudit"));
            [~, source] = elab.io.readRunMinutes(parsed, 10);
            tc.verifyEqual(source, "calculated");
        end

        function test_readRunMinutes_missingNs_returnsNominal(tc)
            run = tc.write(tc.root(), "noAudit");
            tc.removeAcqusLine(run, "##$NS=");
            parsed = elab.io.parseBrukerExperiment(run);
            [value, source] = elab.io.readRunMinutes(parsed, 10);
            tc.verifyEqual(value, 10);
            tc.verifyEqual(source, "nominal");
        end

        function test_readRunMinutes_nonpositiveAudit_warnsAndCalculates(tc)
            run = tc.write(tc.root(), "normal");
            tc.replaceAudit(run, "completed at 2026-09-24 09:00:00.000 +0900", ...
                "completed at 2026-09-24 08:59:00.000 +0900");
            parsed = elab.io.parseBrukerExperiment(run);
            output = evalc("[~, source] = elab.io.readRunMinutes(parsed, 10);");
            tc.verifyEqual(source, "calculated");
            tc.verifySubstring(string(output), "audit completion is not after audit start");
        end

        function test_readRunMinutes_zeroSweep_returnsNominal(tc)
            parsed = elab.io.parseBrukerExperiment(tc.write(tc.root(), "noAudit"));
            parsed.acquisition.sw_hz = 0;
            [value, source] = elab.io.readRunMinutes(parsed, 10);
            tc.verifyEqual(value, 10);
            tc.verifyEqual(source, "nominal");
        end

        function test_readRunMinutes_chromatogram_returnsMeasuredMaximum(tc)
            parsed = struct("t", [1 4 2]);
            [value, source] = elab.io.readRunMinutes(parsed, 10);
            tc.verifyEqual(value, 4);
            tc.verifyEqual(source, "measured");
        end

        function test_parseAny_unhandledFolder_raisesExpectedId(tc)
            folder = string(fullfile(tc.root(), "unknown"));
            mkdir(folder);
            tc.verifyError(@() elab.io.parseAny(folder), "elab:io:parseAny:unhandled");
        end

        function test_readSessionFile_dotFolder_preservesNames(tc)
            root = tc.root();
            run = tc.write(fullfile(root, "ds"), "normal", "sample_1.5");
            session = elab.pipeline.readSessionFile(run, tc.config(root));
            tc.verifyEqual(session.fileName, "ds/sample_1.5");
            tc.verifyEqual(session.baseName, "sample_1.5");
        end

        function test_readSessionFile_trailingInboxSeparator_preservesRelativePath(tc)
            root = tc.root();
            run = tc.write(fullfile(root, "ds"), "normal", "sample_1.5");
            cfg = tc.config(root + filesep);
            session = elab.pipeline.readSessionFile(run, cfg);
            tc.verifyEqual(session.fileName, "ds/sample_1.5");
        end

        function test_readSessionFile_outsideInbox_usesFullFolderName(tc)
            root = tc.root();
            run = tc.write(fullfile(root, "outside"), "normal", "sample_1.5");
            session = elab.pipeline.readSessionFile(run, tc.config(fullfile(root, "inbox")));
            tc.verifyEqual(session.fileName, "sample_1.5");
            tc.verifyEqual(session.baseName, "sample_1.5");
        end

        function test_readSessionFile_folder_returnsManifestAndAcquisitionValues(tc)
            root = tc.root();
            run = tc.write(fullfile(root, "dataset"), "normal", "1");
            session = elab.pipeline.readSessionFile(run, tc.config(root));
            manifest = elab.io.experimentManifest(run);
            tc.verifyEqual(elab.io.detectFormat(run).format, "nmr_folder");
            tc.verifyEqual(elab.io.detectFormat(run).technique, "nmr");
            tc.verifyEqual(session.info.parser, "elab.io.parseBrukerExperiment");
            tc.verifyEqual(session.hash, manifest.coreHash);
            tc.verifyEqual(session.unit, "folder");
            tc.verifyTrue(isfield(session.manifest, "fullText"));
            tc.verifyEqual(session.acquiredAt, datetime(2026, 9, 24, 9, 0, 0));
            tc.verifyEqual(session.acquiredAtSource, "file");
            tc.verifyEqual(session.runMinutes, 38 / 60, AbsTol=1e-9);
            tc.verifyEqual(session.runMinutesSource, "measured");
        end

        function test_readSessionFile_jcampNmr_remainsSingleFile(tc)
            root = tc.root();
            files = string(elab.io.writeMockRuns(root));
            path = files(startsWith(files, fullfile(root, "nmr_")));
            info = elab.io.detectFormat(path);
            session = elab.pipeline.readSessionFile(path, tc.config(root));
            tc.verifyEqual(info.format, "spectrum");
            tc.verifyEqual(info.technique, "nmr");
            tc.verifyEqual(session.unit, "file");
        end
    end

    methods (Access = private)
        function root = root(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
        end

        function run = write(~, parent, variant, name)
            arguments
                ~
                parent (1,1) string
                variant (1,1) string
                name (1,1) string = "nmr"
            end
            if ~isfolder(parent)
                mkdir(parent);
            end
            run = elab.io.writeMockNmrRun(parent, ...
                acquiredAt=datetime(2026, 9, 24, 9, 0, 0), ...
                name=name, variant=variant);
        end

        function cfg = config(~, inbox)
            cfg = loadConfig();
            cfg.watch.inbox_dir = inbox;
            cfg.watch.nominal_run_minutes = 10;
            cfg.elab.timezone = "Asia/Tokyo";
        end

        function run = smallRun(tc, root)
            run = string(fullfile(root, "small"));
            mkdir(run);
            tc.writeBytes(fullfile(run, "acqus"), unicode2native("a", "UTF-8"));
            tc.writeBytes(fullfile(run, "audita.txt"), unicode2native("b", "UTF-8"));
            tc.writeBytes(fullfile(run, "fid"), unicode2native("abc", "UTF-8"));
        end

        function parsed = parsedWithEpoch(tc, root, epoch)
            run = tc.write(root, "normal");
            parsed = elab.io.parseBrukerExperiment(run);
            parsed.acquisition.date_epoch = epoch;
        end

        function verifyCoreChange(tc, run, name)
            before = elab.io.experimentManifest(run);
            tc.writeBytes(fullfile(run, name), uint8([11 12 13]));
            after = elab.io.experimentManifest(run);
            tc.verifyNotEqual(after.coreHash, before.coreHash);
            tc.verifyNotEqual(after.fullHash, before.fullHash);
        end

        function replaceAcqus(~, run, old, new)
            path = fullfile(run, "acqus");
            contents = replace(string(fileread(path)), old, new);
            writelines(splitlines(contents), path);
        end

        function removeAcqusLine(~, run, prefix)
            path = fullfile(run, "acqus");
            lines = string(readlines(path));
            writelines(lines(~startsWith(lines, prefix)), path);
        end

        function replaceAudit(~, run, old, new)
            path = fullfile(run, "audita.txt");
            contents = replace(string(fileread(path)), old, new);
            writelines(splitlines(contents), path);
        end

        function value = fileMtime(~, path)
            info = dir(path);
            value = datetime(info.datenum, ConvertFrom="datenum");
        end

        function files = fileBytes(~, folder)
            listing = dir(fullfile(folder, "**", "*"));
            listing = listing(~[listing.isdir]);
            files = strings(numel(listing), 1);
            for k = 1:numel(listing)
                fid = fopen(fullfile(listing(k).folder, listing(k).name), "r");
                closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
                bytes = fread(fid, Inf, "*uint8");
                relative = erase(string(fullfile(listing(k).folder, listing(k).name)), folder + filesep);
                files(k) = replace(relative, "\", "/") + ":" + join(string(bytes), ",");
            end
            files = sort(files);
        end

        function writeBytes(~, path, bytes)
            fid = fopen(path, "w");
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, bytes, "uint8");
        end
    end
end
