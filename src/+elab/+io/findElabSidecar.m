function path = findElabSidecar(folder, dataFileHash)
% findElabSidecar  Find the newest direct sidecar with a matching data hash.

    arguments
        folder (1,1) string
        dataFileHash (1,1) string
    end

    path = "";
    if ~isfolder(folder)
        return
    end
    entries = dir(fullfile(folder, "*.elab.json"));
    if isempty(entries)
        return
    end
    [~, order] = sort([entries.datenum], "descend");
    for index = order
        candidate = fullfile(entries(index).folder, entries(index).name);
        try
            payload = jsondecode(fileread(candidate));
            if isfield(payload, "data_file_hash") && ...
                    string(payload.data_file_hash) == dataFileHash
                path = string(candidate);
                return
            end
        catch
        end
    end
end
