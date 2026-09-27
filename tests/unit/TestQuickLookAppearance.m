classdef TestQuickLookAppearance < matlab.unittest.TestCase
    % TestQuickLookAppearance  Theme-independent quick-look rendering tests.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testLightFigureOverridesDarkDefault(tc)
            tc.useDarkFigureTheme();

            f = elab.visualization.lightFigure();
            tc.addTeardown(@() close(f));

            tc.verifyEqual(string(f.Theme.BaseColorStyle), "light");
        end

        function testSpectrumPngIsLightUnderDarkDefault(tc)
            tc.useDarkFigureTheme();
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            pngPath = string(fullfile(fixture.Folder, "quicklook.png"));
            parsed = struct("x", (1:5)', "y", [1; 3; 2; 4; 1], ...
                "xlabel", "2 theta", "ylabel", "Intensity");

            elab.visualization.quickLook("spectrum", parsed, pngPath);
            imageData = imread(pngPath);

            tc.verifyGreaterThanOrEqual(mean(double(imageData), "all"), 200);
        end

        function testChromatogramPngIsLightUnderDarkDefault(tc)
            tc.useDarkFigureTheme();
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            pngPath = string(fullfile(fixture.Folder, "quicklook.png"));
            peaks = table([2; 4], 'VariableNames', {'rt_min'});
            parsed = struct("t", (1:5)', "intensity", [1; 3; 2; 4; 1], ...
                "peaks", peaks, "xlabel", "Retention time", ...
                "ylabel", "Intensity");

            elab.visualization.quickLook("chromatogram", parsed, pngPath);
            imageData = imread(pngPath);

            tc.verifyGreaterThanOrEqual(mean(double(imageData), "all"), 200);
        end

        function testTitlePreservesLiteralTextWithoutTexInterpretation(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            pngPath = string(fullfile(fixture.Folder, "quicklook.png"));
            parsed = struct("x", (1:5)', "y", [1; 3; 2; 4; 1], ...
                "xlabel", "2 theta", "ylabel", "Intensity");
            expectedTitle = "XRD  xrd_SMP-2026-001  2026-09-19 09:00";
            key = "M3_8LiteralQuickLookTitle";
            oldCallback = get(groot, "DefaultFigureCloseRequestFcn");
            set(groot, "DefaultFigureCloseRequestFcn", ...
                @TestQuickLookAppearance.captureFigureTitle);
            tc.addTeardown(@() TestQuickLookAppearance.restoreCloseCallback( ...
                oldCallback, key));

            elab.visualization.quickLook("spectrum", parsed, pngPath, ...
                title=expectedTitle);
            captured = getappdata(groot, key);

            tc.verifyEqual(string(captured.String), expectedTitle);
            tc.verifyEqual(string(captured.Interpreter), "none");
        end
    end

    methods (Access = private)
        function useDarkFigureTheme(tc)
            probe = figure("Visible", "off");
            tc.addTeardown(@() TestQuickLookAppearance.closeIfValid(probe));
            tc.assumeTrue(isprop(probe, "Theme"), ...
                "This MATLAB release has no figure Theme property.");
            close(probe);

            s = settings;
            g = s.matlab.appearance.figure.GraphicsTheme;
            g.TemporaryValue = "dark";
            tc.addTeardown(@() clearTemporaryValue(g));
        end
    end

    methods (Static, Access = private)
        function captureFigureTitle(f, ~)
            ax = findobj(f, "Type", "axes");
            captured = struct("String", ax(1).Title.String, ...
                "Interpreter", ax(1).Title.Interpreter);
            setappdata(groot, "M3_8LiteralQuickLookTitle", captured);
            delete(f);
        end

        function restoreCloseCallback(callback, key)
            set(groot, "DefaultFigureCloseRequestFcn", callback);
            if isappdata(groot, key)
                rmappdata(groot, key);
            end
        end

        function closeIfValid(f)
            if isgraphics(f)
                close(f);
            end
        end
    end
end
