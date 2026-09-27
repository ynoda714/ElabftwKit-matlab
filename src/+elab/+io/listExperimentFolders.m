function paths = listExperimentFolders(inboxDir)
% listExperimentFolders  Find Bruker experiment folders below an inbox.

    arguments
        inboxDir (1,1) string
    end
    paths = strings(0, 1);
    if ~isfolder(inboxDir)
        return
    end
    paths = localFind(inboxDir);
    paths = sort(paths);
end

function paths = localFind(folder)
    paths = strings(0, 1);
    listing = dir(folder);
    names = string({listing.name});
    for k = 1:numel(listing)
        if ~listing(k).isdir || startsWith(names(k), ".")
            continue
        end
        child = string(fullfile(folder, names(k)));
        if isfile(fullfile(child, "acqus")) && ...
                (isfile(fullfile(child, "fid")) || isfile(fullfile(child, "ser")))
            paths(end + 1, 1) = child; %#ok<AGROW>
        else
            paths = [paths; localFind(child)]; %#ok<AGROW>
        end
    end
end
