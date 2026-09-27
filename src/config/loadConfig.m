function cfg = loadConfig(opts)
% loadConfig  Load project configuration with environment-variable overrides.
%
%   cfg = loadConfig()
%   cfg = loadConfig(SettingsFile="config/settings.example.json")
%
%   Priority (highest to lowest):
%     1. Environment variables: <PREFIX>_<SECTION>_<KEY>
%        (e.g., ELAB_ELAB_BASE_URL, ELAB_RUNTIME_EVAL_MODE)
%     2. config/settings.json  (if present)
%     3. Built-in defaults
%
%   The prefix is defined once here (ENV_PREFIX). Only scalar leaf values
%   (string / numeric / logical) one level below a section are env-overridable.
%
%   Returns:
%     cfg (struct) with sections:
%       .elab    - eLabFTW connection and the label vocabulary written back
%       .watch   - instrument inbox folders and the sample map
%       .python  - MATLAB<->Python bridge (dormant unless the project uses it)
%       .output / .run - artifact directories (see makeRunDir)

    arguments
        opts.SettingsFile (1,1) string = string(fullfile("config", "settings.json"))
    end

    ENV_PREFIX = "ELAB";

    cfg = buildDefaults();
    cfg = applyJsonFile(cfg, opts.SettingsFile);
    cfg = applyEnvVars(cfg, ENV_PREFIX);
    validateConfig(cfg);
end

% =========================================================================
function cfg = buildDefaults()
    % --- eLabFTW connection ---
    % The API key is NEVER stored here. Set the env var named by api_key_env
    % (default ELAB_API_KEY), or place it in config/apiKey.txt (git-ignored).
    cfg.elab.base_url          = "https://localhost:3148";  % no trailing slash
    cfg.elab.api_key_env       = "ELAB_API_KEY";
    cfg.elab.ca_cert           = "";  % empty uses the system default CA store
    cfg.elab.allow_self_signed = false;
    cfg.elab.session_category  = "Session";        % rename to your eLabFTW category
    cfg.elab.qc_category       = "QC";
    cfg.elab.report_category   = "Report";
    cfg.elab.instrument_category = "Instrument";
    cfg.elab.sample_category     = "Sample";
    cfg.elab.consumable_category = "Consumable";
    cfg.elab.sop_category        = "SOP";
    cfg.elab.draft_status      = "Draft";
    cfg.elab.extra_field_search_limit = 400;
    cfg.elab.item_search_limit = 50;
    cfg.elab.report_list_limit = 1000;
    cfg.elab.timezone          = "";  % empty uses the execution environment

    % Label vocabulary written into eLabFTW item status fields. Kept in config
    % (not in .m source) so the .m layer stays ASCII-only and the labels can
    % match the language of the target eLabFTW without code changes.
    cfg.elab.labels.qc_tag                                 = "QC";
    cfg.elab.labels.instrument_status_ok                   = "OK";
    cfg.elab.labels.instrument_status_check                = "Check";
    cfg.elab.labels.instrument_status_calibration_overdue  = "CalibrationOverdue";
    cfg.elab.labels.consumable_status_ok                   = "InStock";
    cfg.elab.labels.consumable_status_reorder              = "Reorder";
    cfg.elab.labels.field_group_measurement                = "Measurement";
    cfg.elab.labels.field_group_instrument_params          = "Instrument parameters";
    cfg.elab.labels.field_group_provenance                 = "Provenance";

    % --- Instrument inbox watcher ---
    cfg.watch.inbox_dir     = "data/inbox";
    cfg.watch.processed_dir = "data/processed";
    cfg.watch.failed_dir    = "data/failed";
    cfg.watch.sample_map    = "data/list/sample_map.csv";
    cfg.watch.instrument_map = "data/list/instrument_map.csv";
    cfg.watch.nominal_run_minutes = 10;

    % --- QC inbox ---
    cfg.qc.inbox_dir = "data/qc_inbox";
    cfg.qc.spec_list = "data/list/qc_specs.csv";

    % --- Shared ingestion policy ---
    cfg.ingest.attach_raw        = "auto";
    cfg.ingest.attach_raw_max_mb = 25;
    cfg.ingest.archive_mode      = "move";

    % --- Python bridge (see docs/python_integration.md). Unused by default. ---
    cfg.python.version        = "3.10";
    cfg.python.embedded_dir   = "python_env";
    cfg.python.execution_mode = "OutOfProcess";
    cfg.python.external_path   = "";
    cfg.python.proxy          = "";
    cfg.python.packages       = strings(1, 0);
    cfg.python.verify_imports = strings(1, 0);

    % --- Outputs ---
    cfg.output.root_dir    = "result/intermediate";
    cfg.run.root_dir       = "result/runs";
    cfg.run.publish_latest = true;
end

% =========================================================================
function validateConfig(cfg)
    validateChoice(cfg.ingest.attach_raw, ...
        ["auto", "always", "never"], "ingest.attach_raw");
    validateChoice(cfg.ingest.archive_mode, ...
        ["move", "copy", "leave"], "ingest.archive_mode");
    validatePositiveInteger(cfg.elab.item_search_limit, "elab.item_search_limit");
    validatePositiveInteger(cfg.elab.report_list_limit, "elab.report_list_limit");
end

function validatePositiveInteger(value, key)
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
            value > 0 && value == floor(value))
        error("elab:config:loadConfig:invalidPositiveInteger", ...
            "%s must be a positive integer.", key);
    end
end

function validateChoice(value, allowed, key)
    if ~isStringScalar(value) || ~ismember(string(value), allowed)
        error("elab:config:loadConfig:invalidChoice", ...
            "%s must be one of: %s.", key, strjoin(allowed, ", "));
    end
end

% =========================================================================
function cfg = applyJsonFile(cfg, jsonPath)
    defaultPath = string(fullfile("config", "settings.json"));
    if ~isfile(jsonPath)
        if string(jsonPath) == defaultPath
            logDebug("loadConfig: settings.json not found, using defaults");
            return;
        end
        error("elab:config:loadConfig:settingsNotFound", ...
            "Settings file does not exist: %s.", jsonPath);
    end
    try
        raw = jsondecode(fileread(jsonPath));
        cfg = mergeStruct(cfg, raw);
        logDebug("loadConfig: loaded %s", jsonPath);
    catch ME
        logWarn("loadConfig: failed to parse settings.json (%s), using defaults", ME.message);
    end
end

% =========================================================================
function cfg = applyEnvVars(cfg, prefix)
% Apply environment variable overrides.
% Naming convention: <PREFIX>_<SECTION>_<KEY> in UPPER_CASE.
% Example: ELAB_ELAB_BASE_URL overrides cfg.elab.base_url.
% Only scalar leaf values (string / numeric / logical) are overridable.

    sections = fieldnames(cfg);
    for si = 1:numel(sections)
        sec = sections{si};
        if ~isstruct(cfg.(sec))
            continue;
        end
        keys = fieldnames(cfg.(sec));
        for ki = 1:numel(keys)
            key = keys{ki};
            orig = cfg.(sec).(key);
            if ~(isStringScalar(orig) || (isnumeric(orig) && isscalar(orig)) || islogical(orig))
                continue;
            end
            envName = upper(prefix + "_" + sec + "_" + key);
            val = getenv(envName);
            if isempty(val)
                continue;
            end
            if islogical(orig)
                cfg.(sec).(key) = strcmpi(val, "true") || strcmp(val, "1");
            elseif isnumeric(orig)
                parsed = str2double(val);
                if ~isnan(parsed)
                    cfg.(sec).(key) = parsed;
                end
            else
                cfg.(sec).(key) = string(val);
            end
            logDebug("loadConfig: %s overridden by env var %s", sec + "." + key, envName);
        end
    end
end

% =========================================================================
function out = mergeStruct(base, override)
% mergeStruct  Merge override fields into base; only update fields present in base.
%   Fields absent from base (e.g., JSON comment keys like "_comment") are ignored.

    out = base;
    fields = fieldnames(override);
    for k = 1:numel(fields)
        f = fields{k};
        if ~isfield(base, f)
            continue; % skip unknown / comment fields
        end
        if isstruct(base.(f)) && isstruct(override.(f))
            out.(f) = mergeStruct(base.(f), override.(f));
        else
            val = override.(f);
            if isStringScalar(base.(f)) && ischar(val)
                val = string(val);
            end
            if isstring(base.(f)) && ~isscalar(base.(f)) && ...
                    (iscell(val) || ischar(val) || isempty(val))
                val = string(val);
                val = reshape(val, 1, []);
            end
            out.(f) = val;
        end
    end
end
