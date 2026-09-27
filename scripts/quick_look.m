%% quick_look.m -- Tier 1 instant experience (no eLabFTW needed)
% Generate synthetic instrument files, parse each one, and render a
% quick-look figure per technique into result/runs/<ts>_quicklook/.
% This exercises the parser + visualization layers without any API call.
%
% Usage: open this file, press F5 (or Run).

addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));

logSection("QLK", "Quick look (offline)", "eLabFTW");

inboxDir = fullfile(tempname);          % throwaway input staging
files = elab.io.writeMockRuns(inboxDir);

runDir = makeRunDir("Prefix", "quicklook");
for k = 1:numel(files)
    [parsed, info] = elab.io.parseAny(files(k));
    [~, base] = fileparts(files(k));
    png = fullfile(runDir, base + "_quicklook.png");
    elab.visualization.quickLook(info.format, parsed, png);
    logInfo("quick_look: %-9s -> %s", info.technique, png);
end

rmdir(inboxDir, "s");
logInfo("quick_look: %d preview(s) in %s", numel(files), runDir);
