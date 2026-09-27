function tests = test_pipeline_smoke()
% test_pipeline_smoke  Offline end-to-end check of the parse + visualize path.
%
%   Generates synthetic instrument files, parses each, and renders a
%   quick-look PNG. No eLabFTW connection is required.
%
%   Run:
%     addpath(genpath("src"));
%     results = runtests("tests/smoke/test_pipeline_smoke.m");

    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    thisDir = fileparts(mfilename("fullpath"));          % tests/smoke
    projectRoot = fileparts(fileparts(thisDir));
    tc.TestData.projectRoot = projectRoot;
    tc.TestData.origDir = cd(projectRoot);
    addpath(genpath(fullfile(projectRoot, "src")));
    tc.TestData.mockDir = tempname;
    tc.TestData.outDir = tempname;
    mkdir(tc.TestData.outDir);
    tc.TestData.files = elab.io.writeMockRuns(tc.TestData.mockDir);
end

function teardownOnce(tc)
    cd(tc.TestData.origDir);
    if isfolder(tc.TestData.mockDir), rmdir(tc.TestData.mockDir, "s"); end
    if isfolder(tc.TestData.outDir),  rmdir(tc.TestData.outDir, "s");  end
end

function test_parseAndRender_allSixFormats_producesNonemptyPreview(tc)
    files = tc.TestData.files;
    expectedFormats = containers.Map( ...
        {'xrd', 'raman', 'ftir', 'nmr', 'lcms', 'sem'}, ...
        {'spectrum', 'spectrum', 'spectrum', 'spectrum', 'chromatogram', 'image'});
    verifyEqual(tc, numel(files), 6);
    for k = 1:numel(files)
        [parsed, info] = elab.io.parseAny(files(k));
        [~, base] = fileparts(files(k));
        technique = extractBefore(base, "_");
        expectedFormat = string(expectedFormats(char(technique)));
        verifyEqual(tc, info.format, expectedFormat, ...
            "wrong format for technique: " + technique);
        png = fullfile(tc.TestData.outDir, base + ".png");
        elab.visualization.quickLook(info.format, parsed, png);
        assertTrue(tc, isfile(png), "expected preview: " + png);
        imageInfo = imfinfo(png);
        verifyGreaterThan(tc, imageInfo.Width, 0, ...
            "preview width must be positive for technique: " + technique);
        verifyGreaterThan(tc, imageInfo.Height, 0, ...
            "preview height must be positive for technique: " + technique);
        fileInfo = dir(png);
        verifyGreaterThan(tc, fileInfo.bytes, 0, ...
            "preview file must be nonempty for technique: " + technique);
    end
end

function test_detectFormat_allSixTechniques_identifiesEachTechnique(tc)
    got = strings(1, 0);
    for k = 1:numel(tc.TestData.files)
        got(end + 1) = elab.io.detectFormat(tc.TestData.files(k)).technique; %#ok<AGROW>
    end
    for want = ["xrd" "raman" "ftir" "nmr" "lcms" "sem"]
        verifyTrue(tc, any(got == want), "technique not detected: " + want);
    end
end
