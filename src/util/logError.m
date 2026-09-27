function logError(msg, varargin)
% logError  Print an ERROR-level message to the console.
%
%   logError(msg)
%   logError(msg, arg1, arg2, ...)
%
%   msg supports sprintf-style format strings.
%   Output format: [HH:MM:SS][ERROR] <message>
%
%   Note: This function only prints the message. To stop execution,
%   the caller should throw an MException after calling logError.

    ts = char(datetime("now", "Format", "HH:mm:ss"));
    fprintf("[%s][ERROR] %s\n", ts, sprintf(msg, varargin{:}));
end
