%% demo_run.m -- reproduce a synthetic demonstration on an empty server
% Set the MATLAB current folder to the project root. Edit Section 0a, then
% run Sections 0b through 4 in order. This script composes parts from src.

%% 0a) User parameters (edit here)
opt.demoBaseUrl = "https://127.0.0.1:3149";
opt.month = dateshift(datetime("today"), "start", "month", -1);

%% 0b) Setup and target guard
addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));
logSection("DEMO", "Section 0b: Setup", "eLabFTW");

cfg = loadConfig(SettingsFile="config/settings.example.json");
cfg.elab.base_url = opt.demoBaseUrl;
allowedDemoBaseUrl = "https://127.0.0.1:3149";
cfg.elab.ca_cert = "docker/certs/server.crt";
cfg.watch.inbox_dir = "data/demo_inbox";
cfg.watch.processed_dir = "data/demo_processed";
cfg.watch.failed_dir = "data/demo_failed";
cfg.watch.instrument_map = "data/list/instrument_map.example.csv";
cfg.watch.sample_map = "data/list/sample_map.example.csv";
if ~isfile(cfg.elab.ca_cert)
    error("elab:demo:certificateMissing", ...
        "Demo certificate does not exist: %s.", cfg.elab.ca_cert);
end
apiKey = string(getenv(cfg.elab.api_key_env));
if apiKey == ""
    error("elab:demo:apiKeyMissing", ...
        "Set environment variable %s for this MATLAB session.", cfg.elab.api_key_env);
end
client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);
elab.util.assertDemoTarget(client, cfg, allowedBaseUrl=allowedDemoBaseUrl);

%% 1) Create the structure and items
logSection("DEMO", "Section 1: Bootstrap structure and items", "eLabFTW");
elab.pipeline.bootstrapStructure(client, cfg);
elab.pipeline.bootstrapItems(client, cfg, ...
    instrumentsCsv="data/list/instruments.example.csv", ...
    consumablesCsv="data/list/consumables.example.csv");

%% 2) Generate synthetic measurement inputs
logSection("DEMO", "Section 2: Generate demo runs", "eLabFTW");
files = elab.io.writeDemoRuns(cfg.watch.inbox_dir, month=opt.month);
disp(files);

%% 3) Log the inbox
logSection("DEMO", "Section 3: Watch and log", "eLabFTW");
results = elab.pipeline.watchAndLog(client, cfg, ...
    sourceLocator=@(~) struct("source_path", "(demo)", ...
        "source_host", "demo-workstation", "source_mtime", ""));
disp(struct2table(results, "AsArray", true));

%% 4) Create the monthly usage report
logSection("DEMO", "Section 4: Monthly usage report", "eLabFTW");
reportId = elab.pipeline.monthlyUsageReport(client, cfg, year(opt.month), month(opt.month));
