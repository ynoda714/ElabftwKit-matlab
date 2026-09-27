function logSection(scriptId, label, layer)
% logSection  Print a section-start banner to the MATLAB Command Window.
%
%   logSection(scriptId, label, layer)
%
%   Emits an INFO-level banner that identifies the running script, the
%   current section title, and its layer.  Call this as the first
%   executable line of every %% section so that each section leaves a
%   clear trace in the log.
%
%   Arguments:
%     scriptId  (1,1) string  - Script identifier (e.g. "F01", "S01", "R01")
%     label     (1,1) string  - Section header text (e.g. "Section 0: Setup")
%     layer     (1,1) string  - Layer or phase label (e.g. "Foundation L1")
%
%   Output format:
%     [HH:MM:SS][INFO]  --- F01 | Section 0: Setup  [Foundation L1] ---
%
%   See also: logInfo, logWarn, logError, logProgress

    arguments
        scriptId  (1,1) string
        label     (1,1) string
        layer     (1,1) string
    end

    logInfo("--- %s | %s  [%s] ---", scriptId, label, layer);
end
