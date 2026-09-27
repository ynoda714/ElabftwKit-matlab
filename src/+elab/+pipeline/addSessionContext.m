function session = addSessionContext(session, cfg, opts)
% addSessionContext  Add source location and timezone to one session.
%
%   session = elab.pipeline.addSessionContext(session, cfg, sourceLocator=..., timezoneResolver=...).

    arguments
        session (1,1) struct
        cfg (1,1) struct
        opts.sourceLocator (1,1) function_handle = @elab.io.sourceLocation
        opts.timezoneResolver (1,1) function_handle = @elab.util.resolveTimezone
    end
    session.source = opts.sourceLocator(session.filePath);
    session.timezone = opts.timezoneResolver(cfg);
end
