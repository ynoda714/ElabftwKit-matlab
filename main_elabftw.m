%% main_elabftw.m -- eLabFTW x MATLAB facility logging front entry
% Set the MATLAB current folder to the project root. Edit Section 0a, then
% run sections one at a time from Section 0b with Ctrl+Enter (Run Section),
% or press F5 to run every section once. Section 4 creates one Report
% experiment every time it runs.
%
%   0a  User parameters      (edit here)
%   0b  Setup                (path, config, client)
%   1   One-time bootstrap   (create Instrument / Consumable items)
%   2   Generate mock runs   (synthetic instrument files, for trial)
%   3   Log the inbox        (scenario A1 + D1 + D2)
%   4   Monthly usage report (scenario R1)
%   5   QC check             (scenario A3)
%
% Prereqs: a reachable eLabFTW, config/settings.json created from the example,
% categories / item types / extra_fields set up (see docs/elab_structure.md).

%% 0a) User parameters (edit here)
opt.generateMock = true;                 % write synthetic files into the inbox
opt.doBootstrap  = true;                 % create Instrument / Consumable items
opt.reportYear   = year(datetime("today"));
opt.reportMonth  = month(datetime("today"));

%% 0b) Setup
addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));
logSection("MAIN", "Section 0b: Setup", "eLabFTW");

cfg = loadConfig();

sampleMap = string(cfg.watch.sample_map);
if ~isfile(sampleMap)
    exampleMap = replace(sampleMap, ".csv", ".example.csv");
    if isfile(exampleMap)
        copyfile(exampleMap, sampleMap);
        logInfo("Setup: created %s from the example", sampleMap);
    end
end

instrumentMap = string(cfg.watch.instrument_map);
if ~isfile(instrumentMap)
    exampleMap = replace(instrumentMap, ".csv", ".example.csv");
    if isfile(exampleMap)
        copyfile(exampleMap, instrumentMap);
        logInfo("Setup: created %s from the example", instrumentMap);
    end
end

qcSpecs = string(cfg.qc.spec_list);
if ~isfile(qcSpecs)
    exampleSpecs = replace(qcSpecs, ".csv", ".example.csv");
    if isfile(exampleSpecs)
        copyfile(exampleSpecs, qcSpecs);
        logInfo("Setup: created %s from the example", qcSpecs);
    end
end

apiKey = localResolveApiKey(cfg);
client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);
logInfo("Setup: client ready for %s", cfg.elab.base_url);

%% 1) One-time bootstrap -- create Instrument / Consumable items
logSection("MAIN", "Section 1: Bootstrap items", "eLabFTW");
if opt.doBootstrap
    elab.pipeline.bootstrapItems(client, cfg);
else
    logInfo("Bootstrap: skipped (opt.doBootstrap = false)");
end

%% 2) Generate mock instrument files
logSection("MAIN", "Section 2: Generate mock runs", "eLabFTW");
if opt.generateMock
    elab.io.writeMockRuns(cfg.watch.inbox_dir);
else
    logInfo("Mock: skipped (opt.generateMock = false)");
end

%% 3) Log the inbox -- scenario A1 (+ D1 ledger, D2 inventory)
logSection("MAIN", "Section 3: Watch and log", "eLabFTW");
results = elab.pipeline.watchAndLog(client, cfg);
disp(struct2table(results, "AsArray", true));

%% 4) Monthly usage report -- scenario R1
logSection("MAIN", "Section 4: Monthly usage report", "eLabFTW");
reportId = elab.pipeline.monthlyUsageReport(client, cfg, opt.reportYear, opt.reportMonth);

%% 5) QC check -- scenario A3 (standard-sample files in data/qc_inbox)
logSection("MAIN", "Section 5: QC check", "eLabFTW");
qcResults = elab.pipeline.qcInbox(client, cfg);
if ~isempty(qcResults)
    disp(struct2table(qcResults, "AsArray", true));
end

% =========================================================================
function key = localResolveApiKey(cfg)
% Resolve the eLabFTW API key from the env var named in config, then from
% config/apiKey.txt. Never commit the key.
    key = string(getenv(cfg.elab.api_key_env));
    if key ~= ""
        return
    end
    keyFile = fullfile("config", "apiKey.txt");
    if isfile(keyFile)
        key = strtrim(string(fileread(keyFile)));
        return
    end
    error("elab:main:apiKeyMissing", ...
        "No API key. Set env var %s or create config/apiKey.txt.", cfg.elab.api_key_env);
end
