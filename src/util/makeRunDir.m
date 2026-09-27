function runDir = makeRunDir(varargin)
% makeRunDir  Create a timestamped output directory and return its path.
%
%   runDir = makeRunDir()
%   runDir = makeRunDir('Prefix', 'smoke')
%   runDir = makeRunDir('Prefix', 'batch_01', 'BaseDir', 'result/batch')
%
%   Parameters:
%     Prefix  (string) - Optional suffix appended after the timestamp.
%                        Example: 'smoke' -> '20260417_120000_smoke/'
%     BaseDir (string) - Base directory. Default: 'result/runs'
%
%   Returns:
%     runDir (string) - Relative path to the created directory.
%
%   All output artifacts should be written to paths under runDir.
%   Never call mkdir directly; always use makeRunDir instead.

    p = inputParser();
    p.addParameter("Prefix", "", @(x) ischar(x) || isStringScalar(x));
    p.addParameter("BaseDir", "result/runs", @(x) ischar(x) || isStringScalar(x));
    p.parse(varargin{:});

    ts = char(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    prefix = string(p.Results.Prefix);
    baseDir = string(p.Results.BaseDir);

    if prefix == ""
        dirName = ts;
    else
        dirName = ts + "_" + prefix;
    end

    runDir  = fullfile(baseDir, dirName);
    counter = 0;
    while isfolder(runDir) && counter < 99
        counter = counter + 1;
        runDir  = fullfile(baseDir, sprintf("%s_%02d", dirName, counter));
    end
    mkdir(runDir);
    logDebug("makeRunDir: created %s", runDir);
end
