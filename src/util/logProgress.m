function logProgress(i, n, label)
% logProgress  Display an in-place progress bar on the console.
%
%   logProgress(i, n, label)
%
%   i     - current index (1-based integer)
%   n     - total count (positive integer)
%   label - description string shown after the bar
%
%   Output format: [####------]  40% ( 4/10) label
%   Uses carriage return (\r) for in-place overwrite.
%   Prints a newline on the final step (i == n).

    BAR_WIDTH = 10;
    pct = i / n;
    filled = round(pct * BAR_WIDTH);
    bar = [repmat('#', 1, filled), repmat('-', 1, BAR_WIDTH - filled)];
    fprintf("\r[%s] %3d%% (%*d/%d) %s", ...
        bar, round(pct * 100), numel(num2str(n)), i, n, label);
    if i >= n
        fprintf("\n");
    end
end
