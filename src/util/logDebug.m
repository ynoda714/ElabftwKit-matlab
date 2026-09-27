function logDebug(msg, varargin)
% logDebug  Print a DEBUG-level message to the console (verbose mode only).
%
%   logDebug(msg)
%   logDebug(msg, arg1, arg2, ...)
%
%   Output is suppressed unless environment variable APP_LOG_VERBOSE=1.
%   (Rename APP_ to your project prefix when adopting the template.)
%   Output format: [HH:MM:SS][DEBUG] <message>

    if ~strcmp(getenv("APP_LOG_VERBOSE"), "1")
        return;
    end
    ts = char(datetime("now", "Format", "HH:mm:ss"));
    fprintf("[%s][DEBUG] %s\n", ts, sprintf(msg, varargin{:}));
end
