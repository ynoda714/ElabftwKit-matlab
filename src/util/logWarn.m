function logWarn(msg, varargin)
% logWarn  Print a WARN-level message to the console.
%
%   logWarn(msg)
%   logWarn(msg, arg1, arg2, ...)
%
%   msg supports sprintf-style format strings.
%   Output format: [HH:MM:SS][WARN]  <message>

    ts = char(datetime("now", "Format", "HH:mm:ss"));
    fprintf("[%s][WARN]  %s\n", ts, sprintf(msg, varargin{:}));
end
