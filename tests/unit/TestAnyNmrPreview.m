classdef TestAnyNmrPreview < matlab.unittest.TestCase
% TestAnyNmrPreview  Verify vendored AnyNMR preview and provenance contracts.

    methods (Test)
        function testUpstreamIdentity(tc)
            info = elab.util.anynmrInfo();
            tc.verifyEqual(string(info.commit), "e9332b5aa154136961189617b16723a8e353ed61");
        end

        function testUpstreamFilesAreOrderedAndUnique(tc)
            info = elab.util.anynmrInfo();
            paths = string({info.files.path});
            tc.verifyEqual(paths, sort(paths));
            tc.verifyEqual(numel(paths), numel(unique(paths)));
        end

        function testUpstreamFilesHashMatches(tc)
            info = elab.util.anynmrInfo(verify=true);
            tc.verifyTrue(info.files_verified);
        end

        function testVendorContainsOnlyNmrMatlabCode(tc)
            root = TestAnyNmrPreview.projectRoot();
            files = dir(fullfile(root, "src", "third_party", "AnyNMR", "**", "*.m"));
            relative = replace(string(fullfile({files.folder}, {files.name})), ...
                fullfile(root, "src", "third_party", "AnyNMR") + filesep, "");
            tc.verifyTrue(all(startsWith(relative, "+nmr" + filesep)));
        end

        function testVendorLicenseExists(tc)
            root = TestAnyNmrPreview.projectRoot();
            tc.verifyTrue(isfile(fullfile(root, "src", "third_party", "AnyNMR", "LICENSE")));
        end

        function testThirdPartyNoticeNamesPinnedRevision(tc)
            root = TestAnyNmrPreview.projectRoot();
            notice = string(fileread(fullfile(root, "THIRD_PARTY_NOTICES.md")));
            tc.verifySubstring(notice, "AnyNMR");
            tc.verifySubstring(notice, "e9332b5aa154136961189617b16723a8e353ed61");
        end

        function testVendoredFunctionsResolveOnPath(tc)
            tc.verifyNotEmpty(which("nmr.io.loadBruker"));
            tc.verifyNotEmpty(which("nmr.processing.doFFT"));
            tc.verifyNotEmpty(which("nmr.processing.autoPhase"));
        end

        function testAnynmrInfoOmitsVerificationWithoutRequest(tc)
            info = elab.util.anynmrInfo();
            tc.verifyFalse(isfield(info, "files_verified"));
        end

        function testAnynmrInfoDetectsChangedVendoredFile(tc)
            root = TestAnyNmrPreview.copyVendorRoot(tc);
            info = elab.util.anynmrInfo(verify=true, root=root);
            path = fullfile(root, "src", "third_party", "AnyNMR", string(info.files(1).path));
            fid = fopen(path, "a");
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, " ", "char");
            changed = elab.util.anynmrInfo(verify=true, root=root);
            tc.verifyFalse(changed.files_verified);
            tc.verifyEqual(changed.mismatches, string(info.files(1).path));
        end

        function testAnynmrInfoErrorsWithoutManifest(tc)
            root = TestAnyNmrPreview.temporaryRoot(tc);
            tc.verifyError(@() elab.util.anynmrInfo(root=root), "elab:util:anynmrInfo:noUpstream");
        end

        function testAnynmrInfoErrorsForInvalidManifest(tc)
            root = TestAnyNmrPreview.copyVendorRoot(tc);
            path = fullfile(root, "src", "third_party", "AnyNMR", "UPSTREAM.json");
            writelines("not json", path);
            tc.verifyError(@() elab.util.anynmrInfo(root=root), "elab:util:anynmrInfo:invalidUpstream");
        end

        function testReadBrukerSpectrumHasExpectedLength(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyNumElements(spectrum.x, 8192);
        end

        function testReadBrukerSpectrumMatchesVendorRealData(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            spectrum = elab.io.readBrukerSpectrum(run);
            vendor = TestAnyNmrPreview.vendorSpectrum(run);
            tc.verifyTrue(any(vendor < 0));
            tc.verifyEqual(spectrum.y, vendor, AbsTol=1e-12);
        end

        function testReadBrukerSpectrumHasFiniteMonotonicAxes(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyTrue(all(isfinite(spectrum.x)) && all(diff(spectrum.x) < 0));
        end

        function testReadBrukerSpectrumHasFiniteRealIntensity(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyTrue(isreal(spectrum.y) && all(isfinite(spectrum.y)));
        end

        function testReadBrukerSpectrumLabels(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyEqual([spectrum.xlabel, spectrum.ylabel], ["Chemical shift (ppm)", "Intensity (a.u.)"]);
        end

        function testReadBrukerSpectrumRecordsProcessingSteps(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyEqual(string({spectrum.steps.operation}), ["FFT", "autoPhase"]);
        end

        function testReadBrukerSpectrumOmitsStepTimestamps(tc)
            spectrum = elab.io.readBrukerSpectrum(TestAnyNmrPreview.mockRun(tc));
            tc.verifyFalse(isfield(spectrum.steps, "timestamp"));
        end

        function testReadBrukerSpectrumSuppressesVendorOutput(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            output = evalc("elab.io.readBrukerSpectrum(run);");
            tc.verifyEqual(strtrim(string(output)), "");
        end

        function testVendorReaderWritesInfoOutput(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            output = TestAnyNmrPreview.vendorLoadOutput(tc, run);
            tc.verifySubstring(output, "[INFO]");
        end

        function testReadBrukerSpectrumErrorsForNonFolder(tc)
            tc.verifyError(@() elab.io.readBrukerSpectrum("missing"), ...
                "elab:io:readBrukerSpectrum:notFolder");
        end

        function testReadBrukerSpectrumOmitsFolderFromProcessingFailure(tc)
            run = TestAnyNmrPreview.missingAcqusFolder(tc);
            vendorMessage = TestAnyNmrPreview.vendorFailureMessage(run);
            wrappedMessage = TestAnyNmrPreview.wrapperFailureMessage(run);
            tc.verifySubstring(vendorMessage, run);
            tc.verifyFalse(contains(wrappedMessage, run));
            tc.verifySubstring(wrappedMessage, "<folder>");
        end

        function testReadSessionFileContinuesAfterPreviewReaderFailure(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            cfg = loadConfig();
            cfg.watch.inbox_dir = fileparts(run);
            output = evalc("session = elab.pipeline.readSessionFile(run, cfg, spectrumReader=@TestAnyNmrPreview.failSpectrum);");
            tc.verifyFalse(isfield(session.parsed, "spectrum"));
            tc.verifyEqual(count(output, "NMR preview was skipped"), 1);
        end

        function testQuickLookNmrErrorsWithoutSpectrum(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            parsed = elab.io.parseBrukerExperiment(run);
            png = fullfile(fileparts(run), "preview.png");
            tc.verifyError(@() elab.visualization.quickLook("nmr_folder", parsed, png), ...
                "elab:visualization:quickLook:noPreview");
        end

        function testQuickLookNmrPpmAxisIsReversed(tc)
            run = TestAnyNmrPreview.mockRun(tc);
            parsed = elab.io.parseBrukerExperiment(run);
            parsed.spectrum = struct("x", linspace(0, 10, 201).', "y", ...
                exp(-((linspace(0, 10, 201).' - 9) / 0.05).^2), ...
                "xlabel", "Chemical shift (ppm)", "ylabel", "Intensity (a.u.)");
            png = fullfile(fileparts(run), "preview.png");
            elab.visualization.quickLook("nmr_folder", parsed, png);
            peakColumn = TestAnyNmrPreview.topBlueColumn(png);
            tc.verifyLessThan(peakColumn, size(imread(png), 2) / 2);
            parsed.spectrum.x = flip(parsed.spectrum.x);
            parsed.spectrum.y = exp(-((parsed.spectrum.x - 1) / 0.05).^2);
            elab.visualization.quickLook("nmr_folder", parsed, png);
            peakColumn = TestAnyNmrPreview.topBlueColumn(png);
            tc.verifyGreaterThan(peakColumn, size(imread(png), 2) / 2);
        end

        function testProvenanceDocumentHasExpectedTopLevelKeys(tc)
            document = TestAnyNmrPreview.provenance(tc, true);
            tc.verifyEqual(sort(string(fieldnames(document))), sort(["provenance_version", "kit", ...
                "matlab_version", "input", "parser", "anynmr", "processing"]).');
        end

        function testProvenanceDocumentPreservesFailedVerification(tc)
            document = TestAnyNmrPreview.provenance(tc, false);
            tc.verifyFalse(document.anynmr.files_verified);
        end

        function testProvenanceDocumentContainsNoPrivateLocationData(tc)
            document = TestAnyNmrPreview.provenance(tc, true);
            encoded = string(jsonencode(document));
            tc.verifyFalse(any(contains(lower(encoded), ["c:\\", "mock-user", "mock-host", "timestamp"])));
        end

        function testWriteProvenanceJsonRoundTrips(tc)
            path = fullfile(TestAnyNmrPreview.temporaryRoot(tc), "provenance.json");
            document = TestAnyNmrPreview.provenance(tc, true);
            elab.io.writeProvenanceJson(path, document);
            tc.verifyEqual(string(jsonencode(jsondecode(fileread(path)))), string(jsonencode(document)));
        end

        function testWriteProvenanceJsonIsDeterministic(tc)
            root = TestAnyNmrPreview.temporaryRoot(tc);
            document = TestAnyNmrPreview.provenance(tc, true);
            first = elab.io.writeProvenanceJson(fullfile(root, "one.json"), document);
            second = elab.io.writeProvenanceJson(fullfile(root, "two.json"), document);
            tc.verifyEqual(TestAnyNmrPreview.bytes(first), TestAnyNmrPreview.bytes(second));
        end

        function testWriteProvenanceJsonIsFormattedAndFinalNewline(tc)
            path = fullfile(TestAnyNmrPreview.temporaryRoot(tc), "provenance.json");
            elab.io.writeProvenanceJson(path, TestAnyNmrPreview.provenance(tc, true));
            bytes = TestAnyNmrPreview.bytes(path);
            tc.verifyTrue(any(bytes == uint8(10)) && bytes(end) == uint8(10));
        end

        function testProvenanceFieldsOmitPartialNmrProvenance(tc)
            [session, kit, group] = TestAnyNmrPreview.fieldInputs();
            fields = elab.util.provenanceFields(session, kit, "none", group, anynmrVersion="v1.0.0");
            tc.verifyFalse(any(string({fields.name}) == "anynmr_version"));
        end

        function testProvenanceFieldsAddCompleteNmrProvenanceAfterProfile(tc)
            [session, kit, group] = TestAnyNmrPreview.fieldInputs();
            fields = elab.util.provenanceFields(session, kit, "none", group, ...
                anynmrVersion="v1.0.0", provenanceFile="run_provenance.json");
            names = string({fields.name});
            tc.verifyEqual(names(end - 2:end), ["quicklook_profile", "anynmr_version", "provenance_file"]);
        end

        function testAddingFormatDocumentNamesExistingFunctions(tc)
            root = TestAnyNmrPreview.projectRoot();
            document = string(fileread(fullfile(root, "docs", "adding_a_format.md")));
            names = string(regexp(document, 'elab(?:\.[A-Za-z][A-Za-z0-9_]*)+', "match"));
            tc.verifyGreaterThanOrEqual(numel(names), 10);
            available = arrayfun(@(name) TestAnyNmrPreview.functionExists(name), names);
            tc.verifyTrue(all(available), "Unknown documented functions: " + strjoin(names(~available), ", "));
        end
    end

    methods (Static, Access = private)
        function output = vendorLoadOutput(tc, run)
            output = string(evalc("nmr.io.loadBruker(run);"));
        end

        function data = vendorSpectrum(run)
            data = nmr.io.loadBruker(run);
            data = nmr.processing.doFFT(data);
            data = nmr.processing.autoPhase(data);
            data = real(data.spec.data(:));
        end

        function message = vendorFailureMessage(run)
            try
                nmr.io.loadBruker(run);
            catch exception
                message = string(exception.message);
                return
            end
            error("test:anyNmrPreview:expectedVendorFailure", "Expected a vendor processing failure.");
        end

        function message = wrapperFailureMessage(run)
            try
                elab.io.readBrukerSpectrum(run);
            catch exception
                if string(exception.identifier) == "elab:io:readBrukerSpectrum:processingFailed"
                    message = string(exception.message);
                    return
                end
                rethrow(exception)
            end
            error("test:anyNmrPreview:expectedWrapperFailure", "Expected a processing failure.");
        end

        function column = topBlueColumn(path)
            image = imread(path);
            blue = image(:, :, 3) > image(:, :, 1) + 40 & image(:, :, 3) > image(:, :, 2) + 20;
            row = find(any(blue, 2), 1, "first");
            column = mean(find(blue(row, :)));
        end

        function spectrum = failSpectrum(~)
            error("test:anyNmrPreview:readerFailed", "Injected preview failure.");
            spectrum = struct();
        end

        function document = provenance(tc, verified)
            run = TestAnyNmrPreview.mockRun(tc);
            cfg = loadConfig();
            cfg.watch.inbox_dir = fileparts(run);
            session = elab.pipeline.readSessionFile(run, cfg);
            kit = struct("version", "test", "commit", "test");
            info = elab.util.anynmrInfo(verify=true);
            info.files_verified = verified;
            document = elab.util.provenanceDocument(session, kit, "light;900x460;120dpi;interp=none", anynmrInfo=info);
        end

        function [session, kit, group] = fieldInputs()
            session = struct("fileName", "run", "hash", "hash", "unit", "folder", ...
                "source", struct("source_path", "source", "source_host", "host", "source_mtime", "2026-01-01T00:00"), ...
                "info", struct("parser", "parser"));
            kit = struct("version", "test", "commit", "test");
            group = struct("id", 3, "name", "Provenance");
        end

        function run = mockRun(tc, opts)
            arguments
                tc
                opts.variant (1,1) string = "normal"
            end
            root = TestAnyNmrPreview.temporaryRoot(tc);
            run = elab.io.writeMockNmrRun(root, variant=opts.variant);
        end

        function run = missingAcqusFolder(tc)
            run = fullfile(TestAnyNmrPreview.temporaryRoot(tc), "missing_acqus");
            mkdir(run);
        end

        function root = temporaryRoot(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            root = string(fixture.Folder);
        end

        function root = copyVendorRoot(tc)
            root = TestAnyNmrPreview.temporaryRoot(tc);
            source = fullfile(TestAnyNmrPreview.projectRoot(), "src", "third_party", "AnyNMR");
            target = fullfile(root, "src", "third_party", "AnyNMR");
            mkdir(fileparts(target));
            copyfile(source, target);
        end

        function value = bytes(path)
            fid = fopen(path, "r");
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            value = fread(fid, Inf, "*uint8").';
        end

        function exists = functionExists(name)
            parts = split(name, ".");
            root = TestAnyNmrPreview.projectRoot();
            packages = cellstr("+" + parts(1:end - 1));
            path = fullfile(root, "src", packages{:}, parts(end) + ".m");
            exists = isfile(path);
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
