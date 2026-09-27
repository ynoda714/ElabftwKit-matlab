%% live_connection_check -- Manual live eLabFTW transport check
% This script is intentionally excluded from the offline test suite.

clear restoreDir
scriptPath = string(mfilename("fullpath"));
projectRoot = fileparts(fileparts(scriptPath));
originalDir = cd(projectRoot);
restoreDir = onCleanup(@() cd(originalDir));
addpath(genpath("src"));

cfg = loadConfig();
apiKey = string(getenv(cfg.elab.api_key_env));
if apiKey == "" && isfile(fullfile("config", "apiKey.txt"))
    apiKey = strtrim(string(fileread(fullfile("config", "apiKey.txt"))));
end
if apiKey == ""
    error("elab:liveCheck:apiKeyMissing", ...
        "Set %s or create config/apiKey.txt before running the live check.", ...
        cfg.elab.api_key_env);
end
if cfg.elab.ca_cert == "" || ~isfile(cfg.elab.ca_cert)
    error("elab:liveCheck:certificateMissing", ...
        "Set elab.ca_cert to docker/certs/server.crt before running the live check.");
end

client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);

info = client.getJson("/info");
logInfo("Live check: GET /info succeeded (%s)", class(info));

experiments = elab.util.toItems(client.getJson("/experiments"));
logInfo("Live check: GET /experiments succeeded (%d entries)", numel(experiments));

categoryName = cfg.elab.session_category;
categoryId = elab.client.resolveId(client, ...
    "experiments_categories", categoryName);
logInfo("Live check: category '%s' resolved to id %d", categoryName, categoryId);

draftId = NaN;
itemId = NaN;
[~, uniquePart] = fileparts(tempname);
checkTitle = "M1-4 live check " + string(uniquePart);
itemTitle = checkTitle + " item";
try
    draftId = elab.client.createExperiment(client, categoryName, checkTitle, ...
        status=cfg.elab.draft_status);
    experiment = client.getJson("/experiments/" + string(draftId));
    localVerifyField(experiment, "title", checkTitle);
    localVerifyField(experiment, "category_title", categoryName);
    localVerifyField(experiment, "status_title", cfg.elab.draft_status);
    logInfo("Live check: createExperiment values verified for experiment %d", draftId);

    extraField = elab.util.fieldStruct( ...
        "M1-4 transport check", "PATCH succeeded", "text");
    elab.client.setExtraFields(client, "experiments", draftId, extraField);
    logInfo("Live check: set extra fields on Draft experiment %d", draftId);

    % mfilename("fullpath") drops the extension, so append it before upload.
    client.uploadFile("experiments", draftId, scriptPath + ".m", ...
        "M1-4 live transport check");
    logInfo("Live check: uploaded an attachment to Draft experiment %d", draftId);

    client.tag("experiments", draftId, "M1-4-live-check");
    logInfo("Live check: tagged Draft experiment %d", draftId);

    itemId = elab.client.ensureItem(client, cfg.elab.instrument_category, itemTitle);
    item = client.getJson("/items/" + string(itemId));
    localVerifyField(item, "title", itemTitle);
    localVerifyField(item, "category_title", cfg.elab.instrument_category);
    itemIdAgain = elab.client.ensureItem(client, cfg.elab.instrument_category, itemTitle);
    if itemIdAgain ~= itemId
        error("elab:liveCheck:itemSearchMismatch", ...
            "ensureItem returned %d instead of existing item %d.", itemIdAgain, itemId);
    end
    logInfo("Live check: ensureItem values and category filtering verified for item %d", ...
        itemId);

    client.linkTo("experiments", draftId, "items", itemId);
    logInfo("Live check: linked Draft experiment %d to temporary item %d", ...
        draftId, itemId);

    client.deleteEntry("experiments", draftId);
    logInfo("Live check: deleted Draft experiment %d", draftId);
    draftId = NaN;

    if ~isnan(itemId)
        client.deleteEntry("items", itemId);
        logInfo("Live check: deleted temporary item %d", itemId);
        itemId = NaN;
    end

catch ME
    localDeleteIfCreated(client, "experiments", draftId, "Draft experiment");
    localDeleteIfCreated(client, "items", itemId, "temporary item");
    rethrow(ME);
end

logInfo("Live check: all transport checks completed");

function localDeleteIfCreated(client, kind, id, label)
    if isnan(id)
        return
    end
    try
        client.deleteEntry(kind, id);
        logInfo("Live check cleanup: deleted %s %d", label, id);
    catch ME
        logWarn("Live check cleanup: could not delete %s %d: %s", ...
            label, id, ME.message);
    end
end

function localVerifyField(entry, fieldName, expected)
    if ~isstruct(entry) || ~isfield(entry, fieldName)
        error("elab:liveCheck:missingField", ...
            "GET response does not contain field '%s'.", fieldName);
    end
    actual = string(entry.(fieldName));
    if ~strcmp(actual, string(expected))
        error("elab:liveCheck:valueMismatch", ...
            "Field '%s' is '%s'; expected '%s'.", fieldName, actual, expected);
    end
end
