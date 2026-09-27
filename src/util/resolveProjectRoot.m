function projectRoot = resolveProjectRoot()
% resolveProjectRoot  Find the project root directory from any run context.
%
%   projectRoot = resolveProjectRoot()
%
%   Uses a 3-stage fallback strategy to locate the project root from any
%   execution context (Desktop Ctrl+Enter, MCP evaluate_matlab_code,
%   MATLAB Online).  Markers are the src/ and config/ folders, which every
%   project generated from this template is guaranteed to have.
%
%   Stage 1: pwd already contains src/ and config/ -- return immediately.
%   Stage 2 (Method A): which("logInfo") -> fileparts x3 -> cd and return.
%   Stage 3 (Method B): scan /MATLAB Drive with isfolder() -> cd and return.
%   Fallback: return pwd (Desktop will not reach here in normal usage).
%
%   Note: This function calls cd() when the project root differs from pwd.
%   The caller should add src/ to the MATLAB path BEFORE calling this
%   function (bootstrap lines in Section 0 handle this).

    % Stage 1: pwd is already the project root
    if isfolder(fullfile(pwd, "src")) && isfolder(fullfile(pwd, "config"))
        projectRoot = pwd;
        return;
    end

    % Stage 2 (Method A): recover from logInfo location on path
    wh = which("logInfo");
    if ~isempty(wh)
        try
            candidate = fileparts(fileparts(fileparts(wh)));  % util/ -> src/ -> root
            if isfolder(fullfile(candidate, "src")) && isfolder(fullfile(candidate, "config"))
                cd(candidate);
                projectRoot = pwd;
                return;
            end
        catch
        end
    end

    % Stage 3 (Method B): scan /MATLAB Drive (MATLAB Online)
    try
        items = dir("/MATLAB Drive");
        for k = 1:numel(items)
            if startsWith(items(k).name, '.'); continue; end
            cand = fullfile("/MATLAB Drive", items(k).name);
            if isfolder(cand) && isfolder(fullfile(cand, "src")) && isfolder(fullfile(cand, "config"))
                cd(cand);
                projectRoot = pwd;
                return;
            end
        end
    catch
    end

    % Fallback: return pwd (Desktop environment should not reach here)
    projectRoot = pwd;
end
