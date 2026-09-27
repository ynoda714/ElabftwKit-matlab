function [attach, reason] = shouldAttachRaw(filePath, cfg, opts)
% shouldAttachRaw  Apply the configured raw-file attachment policy.

    arguments
        filePath (1,1) string
        cfg       (1,1) struct
        opts.pipeline (1,1) string = "ingest"
    end

    policy = "auto";
    maxMb = 25;
    if isfield(cfg, "ingest")
        if isfield(cfg.ingest, "attach_raw")
            policy = string(cfg.ingest.attach_raw);
        end
        if isfield(cfg.ingest, "attach_raw_max_mb")
            maxMb = double(cfg.ingest.attach_raw_max_mb);
        end
    end
    if ~ismember(policy, ["auto", "always", "never"])
        error("elab:io:shouldAttachRaw:invalidPolicy", ...
            "cfg.ingest.attach_raw must be one of: auto, always, never.");
    end

    if isfolder(filePath)
        attach = false;
        reason = "folder";
        if policy == "always"
            logWarn(opts.pipeline + ": %s is a folder; recorded its location and hash without attaching it", ...
                string(filePath));
        end
        return
    end

    if policy == "always"
        attach = true;
        reason = "always";
        return
    end
    if policy == "never"
        attach = false;
        reason = "disabled";
        return
    end

    info = dir(filePath);
    if isempty(info)
        error("elab:io:shouldAttachRaw:notFound", ...
            "File was not found: %s", filePath);
    end
    sizeMb = double(info(1).bytes) / (1024 * 1024);
    attach = sizeMb <= maxMb;
    if attach
        reason = "within_limit";
    else
        reason = "over_limit";
        logWarn(opts.pipeline + ": %s is %.1f MB, over the %g MB limit; " + ...
            "recorded its location and hash without attaching it", ...
            string(info(1).name), sizeMb, maxMb);
    end
end
