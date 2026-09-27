function id = findLoggedSession(client, cfg, session)
% findLoggedSession  Find a same-hash session in the configured category.
%
%   id = elab.pipeline.findLoggedSession(client, cfg, session) returns an id or [].

    id = elab.client.findExperimentByExtraField(client, "experiments", ...
        "data_file_hash", string(session.hash), category=cfg.elab.session_category);
end
