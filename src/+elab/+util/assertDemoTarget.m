function assertDemoTarget(client, cfg, opts)
% assertDemoTarget  Stop a demo run before it writes to an unsafe server.

    arguments
        client
        cfg (1,1) struct
        opts.allowedBaseUrl (1,1) string
        opts.allowNonEmpty (1,1) logical = false
    end

    actual = string(cfg.elab.base_url);
    if actual ~= opts.allowedBaseUrl
        error("elab:demo:wrongServer", ...
            "Demo target is '%s'; allowed target is '%s'.", actual, opts.allowedBaseUrl);
    end
    experiments = elab.util.toItems(client.getJson("/experiments"));
    if ~opts.allowNonEmpty && ~isempty(experiments)
        error("elab:demo:serverNotEmpty", ...
            "Demo target already contains %d experiment(s).", numel(experiments));
    end
end
