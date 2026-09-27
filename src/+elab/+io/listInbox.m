function files = listInbox(folder)
% listInbox  Return input files from an instrument inbox.
%
%   files = elab.io.listInbox(folder)
%
%   Hidden dotfiles, Windows Explorer metadata files, and image sidecars
%   are excluded. Returned paths are a column string array.

    arguments
        folder (1,1) string
    end

    d = dir(fullfile(folder, "*"));
    d = d(~[d.isdir]);
    names = string({d.name});
    ignored = startsWith(names, ".") | ...
        ismember(lower(names), ["thumbs.db", "desktop.ini"]);
    ignoredCount = nnz(ignored);
    if ignoredCount > 0
        logDebug("listInbox: ignored %d non-input file(s) in inbox", ...
            ignoredCount);
    end
    names = names(~ignored);
    names = names(~endsWith(names, "_meta.txt"));
    files = fullfile(folder, names(:));
end
