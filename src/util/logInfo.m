function logInfo(msg, varargin)
% logInfo  Print an INFO-level message to the console.
%
%   logInfo(msg)
%   logInfo(msg, arg1, arg2, ...)
%
%   msg supports sprintf-style format strings.
%   Output format: [HH:MM:SS][INFO]  <message>

    ts = char(datetime("now", "Format", "HH:mm:ss"));
    fprintf("[%s][INFO]  %s\n", ts, sprintf(msg, varargin{:}));
end
