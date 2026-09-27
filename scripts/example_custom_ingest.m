%% example_custom_ingest.m -- Build a local session-ingest assembly
% Edit Section 0, then run Sections 1 through 4 in order with Run Section.
% This example creates session records and links matching items. It does not
% update instrument or consumable ledgers.

%% 0) User parameters
opt.extraFieldName = "assembly";
opt.extraFieldValue = "example_custom_ingest";
opt.extraFieldType = "text";
opt.attachCustomFigure = true;

%% 1) Setup
addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));
logSection("EXAMPLE", "Section 1: Setup", "Custom ingest");

cfg = loadConfig();
apiKey = localResolveApiKey(cfg);
client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);
logInfo("example_custom_ingest: client ready for %s", cfg.elab.base_url);

%% 2) Per-run preparation
logSection("EXAMPLE", "Section 2: Prepare", "Custom ingest");
runDir = makeRunDir("Prefix", "custom_ingest");
kitInfo = elab.util.kitVersion();
sampleMap = elab.pipeline.readSampleMap(cfg);
files = elab.io.listInbox(cfg.watch.inbox_dir);
results = repmat(struct("file", "", "status", "", "experimentId", [], ...
    "message", ""), numel(files), 1);
logInfo("example_custom_ingest: found %d file(s)", numel(files));

%% 3) Process each file
logSection("EXAMPLE", "Section 3: Process files", "Custom ingest");
extraFields = elab.util.fieldStruct(opt.extraFieldName, opt.extraFieldValue, ...
    opt.extraFieldType);
for k = 1:numel(files)
    filePath = files(k);
    results(k).file = filePath;
    try
        [~, fileName, extension] = fileparts(filePath);
        binding = elab.pipeline.matchSample(sampleMap, fileName + extension);
        session = elab.pipeline.readSessionFile(filePath, cfg);
        existingId = elab.pipeline.findLoggedSession(client, cfg, session);
        if ~isempty(existingId)
            elab.pipeline.archiveIngested(filePath, "skipped", cfg);
            results(k).status = "skipped";
            results(k).experimentId = existingId;
            results(k).message = "A matching data_file_hash already exists.";
            logInfo("example_custom_ingest: skipped %s", session.fileName);
            continue
        end

        session = elab.pipeline.addSessionContext(session, cfg);
        [experimentId, ~] = elab.pipeline.createSessionExperiment(client, cfg, ...
            session, binding, runDir, kitInfo, extraFields=extraFields);
        elab.pipeline.linkSessionItems(client, cfg, experimentId, binding);
        if opt.attachCustomFigure && ismember(session.info.format, ...
                ["spectrum", "chromatogram"])
            customPng = localAttachCustomFigure(client, experimentId, session, runDir);
            logInfo("example_custom_ingest: attached custom figure %s", customPng);
        end
        archivedPath = elab.pipeline.archiveIngested(filePath, "logged", cfg);
        elab.pipeline.writeSessionSidecar(session, experimentId, cfg, kitInfo, ...
            archivedPath, runDir);
        results(k).status = "logged";
        results(k).experimentId = experimentId;
        results(k).message = "Record created.";
        logInfo("example_custom_ingest: logged %s as experiment #%d", ...
            session.fileName, experimentId);
    catch exception
        elab.pipeline.archiveIngested(filePath, "failed", cfg);
        results(k).status = "failed";
        results(k).message = string(exception.message);
        logWarn("example_custom_ingest: failed %s: %s", filePath, exception.message);
    end
end

%% 4) Show results
logSection("EXAMPLE", "Section 4: Results", "Custom ingest");
if isempty(results)
    logInfo("example_custom_ingest: no files to process");
else
    disp(struct2table(results, "AsArray", true));
end

% =========================================================================
function key = localResolveApiKey(cfg)
% Resolve the API key from its environment variable, then from apiKey.txt.
    key = string(getenv(cfg.elab.api_key_env));
    if key ~= ""
        return
    end
    keyFile = fullfile("config", "apiKey.txt");
    if isfile(keyFile)
        key = strtrim(string(fileread(keyFile)));
        return
    end
    error("elab:example:apiKeyMissing", ...
        "No API key. Set env var %s or create config/apiKey.txt.", cfg.elab.api_key_env);
end

function pngPath = localAttachCustomFigure(client, experimentId, session, runDir)
% Render and attach one custom plot for a spectrum or chromatogram.
    pngPath = fullfile(runDir, session.baseName + "_custom.png");
    f = elab.visualization.lightFigure();
    cleaner = onCleanup(@() close(f));
    ax = axes(f);
    if session.info.format == "spectrum"
        plot(ax, session.parsed.x, session.parsed.y);
        xlabel(ax, session.parsed.xlabel);
        ylabel(ax, session.parsed.ylabel);
    else
        plot(ax, session.parsed.t, session.parsed.intensity);
        xlabel(ax, "Time");
        ylabel(ax, "Intensity");
    end
    title(ax, session.fileName, "Interpreter", "none");
    grid(ax, "on");
    exportgraphics(f, pngPath, "Resolution", 120);
    client.uploadFile("experiments", experimentId, pngPath, "custom quick look");
    clear cleaner
end
