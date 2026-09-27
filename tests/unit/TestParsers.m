classdef TestParsers < matlab.unittest.TestCase
    % TestParsers  Unit tests for elab.io.* format detection and parsing,
    % driven by the synthetic files from elab.io.writeMockRuns.

    properties
        MockDir (1,1) string
        Files   (1,:) string
    end

    methods (TestClassSetup)
        function setup(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(fullfile(projectRoot, "src"), ...
                    "IncludingSubfolders", true));
            tc.MockDir = string(tempname);
            tc.Files = elab.io.writeMockRuns(tc.MockDir);
        end
    end

    methods (TestClassTeardown)
        function teardown(tc)
            if isfolder(tc.MockDir)
                rmdir(tc.MockDir, "s");
            end
        end
    end

    methods (Access = private)
        function p = fileFor(tc, prefix)
            hit = tc.Files(startsWith(lower(tc.Files), lower(prefix), ...
                "IgnoreCase", true) | contains(tc.Files, prefix));
            tc.assertNotEmpty(hit);
            p = hit(1);
        end

        function value = paramValue(tc, parsed, name)
            names = string({parsed.params.name});
            hit = find(names == name);
            tc.assertNumElements(hit, 1);
            value = parsed.params(hit).value;
        end
    end

    methods (Test)
        function test_detect_supportedFiles_returnsExpectedFormats(tc)
            tc.verifyEqual(elab.io.detectFormat(tc.fileFor("xrd_")).format, "spectrum");
            tc.verifyEqual(elab.io.detectFormat(tc.fileFor("lcms_")).format, "chromatogram");
            tc.verifyEqual(elab.io.detectFormat(tc.fileFor("sem_")).format, "image");
            tc.verifyEqual(elab.io.detectFormat(tc.fileFor("nmr_")).technique, "nmr");
        end

        function test_parseSpectrum_xrd_returnsHeaderAndComputedValues(tc)
            s = elab.io.parseSpectrum(tc.fileFor("xrd_"), "xrd");

            anode = tc.paramValue(s, "anode");
            nPoints = tc.paramValue(s, "n_points");

            tc.verifyEqual(anode, "Cu");
            tc.verifyClass(nPoints, "double");
            tc.verifyEqual(nPoints, numel(s.x));
        end

        function test_parseSpectrum_raman_returnsHeaderAndComputedValues(tc)
            s = elab.io.parseSpectrum(tc.fileFor("raman_"), "raman");

            instrument = tc.paramValue(s, "instrument");
            nPoints = tc.paramValue(s, "n_points");

            tc.verifyEqual(instrument, "Raman-01 inVia");
            tc.verifyClass(nPoints, "double");
            tc.verifyEqual(nPoints, numel(s.x));
        end

        function test_parseSpectrum_ftir_returnsHeaderAndComputedValues(tc)
            s = elab.io.parseSpectrum(tc.fileFor("ftir_"), "ftir");

            mode = tc.paramValue(s, "mode");
            nPoints = tc.paramValue(s, "n_points");

            tc.verifyEqual(mode, "ATR");
            tc.verifyClass(nPoints, "double");
            tc.verifyEqual(nPoints, numel(s.x));
        end

        function test_parseSpectrum_nmr_returnsHeaderAndComputedValues(tc)
            s = elab.io.parseSpectrum(tc.fileFor("nmr_"), "nmr");

            solvent = tc.paramValue(s, "solvent");
            nPoints = tc.paramValue(s, "n_points");

            tc.verifyEqual(solvent, "CDCl3");
            tc.verifyClass(nPoints, "double");
            tc.verifyEqual(nPoints, numel(s.x));
        end

        function test_parseChromatogram_lcms_returnsHeaderAndComputedValues(tc)
            s = elab.io.parseChromatogram(tc.fileFor("lcms_"), "lcms");

            method = tc.paramValue(s, "method");
            nPeaks = tc.paramValue(s, "n_peaks");
            runMinutes = tc.paramValue(s, "run_minutes");

            tc.verifyEqual(method, "gradient_5-95_ACN_12min");
            tc.verifyClass(nPeaks, "double");
            tc.verifyEqual(nPeaks, height(s.peaks));
            tc.verifyClass(runMinutes, "double");
            tc.verifyEqual(runMinutes, max(s.t));
        end

        function test_parseImageMeta_sem_returnsHeaderAndComputedValues(tc)
            [parsed, info] = elab.io.parseAny(tc.fileFor("sem_"));

            magnification = tc.paramValue(parsed, "magnification");
            imageWidth = tc.paramValue(parsed, "image_width_px");
            imageInfo = imfinfo(parsed.imagePath);

            tc.verifyEqual(info.format, "image");
            tc.verifyEqual(magnification, "5000");
            tc.verifyClass(imageWidth, "double");
            tc.verifyEqual(imageWidth, imageInfo(1).Width);
        end

        function test_kvline_withSupportedSeparators_returnsKeyAndValue(tc)
            [colonName, colonValue] = elab.io.kvline("a: 1");
            [equalsName, equalsValue] = elab.io.kvline("a = 1");

            tc.verifyEqual(colonName, "a");
            tc.verifyEqual(colonValue, "1");
            tc.verifyEqual(equalsName, "a");
            tc.verifyEqual(equalsValue, "1");
        end

        function test_kvline_withHashPrefixes_returnsKeyWithoutPrefix(tc)
            [singleName, singleValue] = elab.io.kvline("# a: 1");
            [doubleName, doubleValue] = elab.io.kvline("## a= 1");

            tc.verifyEqual(singleName, "a");
            tc.verifyEqual(singleValue, "1");
            tc.verifyEqual(doubleName, "a");
            tc.verifyEqual(doubleValue, "1");
        end

        function test_kvline_withDecoratedSeparatorNames_returnsEmptyPair(tc)
            [dashName, dashValue] = elab.io.kvline("# --- data: x y ---");
            [starName, starValue] = elab.io.kvline("# *** Data: x y ***");
            [equalsName, equalsValue] = elab.io.kvline("# === Data: x y ===");
            [shortDashName, shortDashValue] = elab.io.kvline("## -- data= x --");
            [tildeName, tildeValue] = elab.io.kvline("# ~~ note: x");

            tc.verifyEqual([dashName, dashValue], ["", ""]);
            tc.verifyEqual([starName, starValue], ["", ""]);
            tc.verifyEqual([equalsName, equalsValue], ["", ""]);
            tc.verifyEqual([shortDashName, shortDashValue], ["", ""]);
            tc.verifyEqual([tildeName, tildeValue], ["", ""]);
        end

        function test_kvline_withJcampLabelPrefixes_returnsKeyAndValue(tc)
            [dotName, dotValue] = elab.io.kvline("##.OBSERVE FREQUENCY= 399.78");
            [dollarName, dollarValue] = elab.io.kvline("##$RELAX= 1");

            tc.verifyEqual([dotName, dotValue], ...
                [".OBSERVE FREQUENCY", "399.78"]);
            tc.verifyEqual([dollarName, dollarValue], ["$RELAX", "1"]);
        end

        function test_kvline_withSingleUnderscorePrefix_returnsKeyAndValue(tc)
            [name, value] = elab.io.kvline("# _private: 1");

            tc.verifyEqual([name, value], ["_private", "1"]);
        end

        function test_kvline_withDecoratorsInsideName_returnsKeyAndValue(tc)
            [dashName, dashValue] = elab.io.kvline("# scan--rate: 5");
            [underscoreName, underscoreValue] = ...
                elab.io.kvline("# sample__id: A1");

            tc.verifyEqual([dashName, dashValue], ["scan--rate", "5"]);
            tc.verifyEqual([underscoreName, underscoreValue], ...
                ["sample__id", "A1"]);
        end

        function test_kvline_withJcampMarkers_returnsEmptyPair(tc)
            [rangeName, rangeValue] = elab.io.kvline("##FIRSTX= 1..10");
            [xyDataName, xyDataValue] = elab.io.kvline("##XYDATA= values");
            [xyPointsName, xyPointsValue] = elab.io.kvline("##XYPOINTS= values");
            [peakTableName, peakTableValue] = elab.io.kvline("##PEAKTABLE= values");
            [endName, endValue] = elab.io.kvline("##END= done");

            tc.verifyEqual([rangeName, rangeValue], ["", ""]);
            tc.verifyEqual([xyDataName, xyDataValue], ["", ""]);
            tc.verifyEqual([xyPointsName, xyPointsValue], ["", ""]);
            tc.verifyEqual([peakTableName, peakTableValue], ["", ""]);
            tc.verifyEqual([endName, endValue], ["", ""]);
        end

        function test_kvline_withoutKeyValue_returnsEmptyPair(tc)
            [name, value] = elab.io.kvline("measurement data only");

            tc.verifyEqual([name, value], ["", ""]);
        end

        function test_parseSpectrum_withDecoratedSeparator_omitsSeparatorAndKeepsHeaders(tc)
            xrd = elab.io.parseSpectrum(tc.fileFor("xrd_"), "xrd");
            raman = elab.io.parseSpectrum(tc.fileFor("raman_"), "raman");
            xrdNames = string({xrd.params.name});
            ramanNames = string({raman.params.name});

            tc.verifyFalse(any(startsWith(xrdNames, "-")));
            tc.verifyFalse(any(startsWith(ramanNames, "-")));
            tc.verifyEqual(tc.paramValue(xrd, "anode"), "Cu");
            tc.verifyEqual(tc.paramValue(raman, "laser_nm"), "532");
        end
    end
end
