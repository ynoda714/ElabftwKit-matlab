function tf = isOnline()
% isOnline  Detect whether the current session is running in MATLAB Online.
%
%   tf = pybridge.isOnline()
%
%   Returns true if running in MATLAB Online, false for Desktop.
%
%   Detection order (docs/platform_support.md):
%     1. ismatlabonline()  - Available in R2023b+; most reliable
%     2. Env var MATLAB_ONLINE="true"  - Set by MATLAB Online infrastructure
%     3. ispc() == false AND computer("arch") == "glnxa64"  - Heuristic fallback
%        (MATLAB Online runs on Linux x64; Desktop Windows is "pcwin64")
%
%   Note: The heuristic (step 3) cannot distinguish MATLAB Online from a
%   Linux Desktop.  Prefer steps 1-2 whenever available.

    % --- Step 1: ismatlabonline() (R2023b+) ---
    if exist("ismatlabonline", "builtin") || exist("ismatlabonline", "file")
        tf = ismatlabonline();
        return;
    end

    % --- Step 2: environment variable set by MATLAB Online infrastructure ---
    envVal = getenv("MATLAB_ONLINE");
    if ~isempty(envVal)
        tf = strcmpi(envVal, "true") || strcmp(envVal, "1");
        return;
    end

    % --- Step 3: heuristic fallback ---
    tf = ~ispc() && isequal(computer("arch"), "glnxa64");
end
