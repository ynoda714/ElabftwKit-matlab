%% build_test_catalog  Regenerate docs/test_catalog.md from the test folders.
%
%   Run from the project root after adding, renaming or removing a test:
%     addpath(genpath("src"));
%     run("scripts/build_test_catalog.m")
%
%   The text comes from buildTestCatalog (src/util). TestTestCatalog fails
%   while the committed catalog differs from what it returns.

addpath(genpath("src"));
projectRoot = string(resolveProjectRoot());
catalogPath = fullfile(projectRoot, "docs", "test_catalog.md");

md = buildTestCatalog(projectRoot);

fid = fopen(catalogPath, "w", "n", "UTF-8");
assert(fid > 0, "elab:scripts:buildTestCatalog:open", ...
    "Cannot open %s for writing.", catalogPath);
closer = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", md);
clear closer

logInfo("build_test_catalog: wrote %s", catalogPath);
