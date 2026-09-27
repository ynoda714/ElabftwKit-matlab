function sidecarPath = writeElabSidecar(dataPath, payload)
% writeElabSidecar  Best-effort write of <base>.elab.json.

    arguments
        dataPath (1,1) string
        payload  (1,1) struct
    end

    if isfield(payload, "data_unit") && string(payload.data_unit) == "folder"
        parent = fileparts(dataPath);
        sidecarPath = string(fullfile(parent, string(java.io.File(char(dataPath)).getName()) + ".elab.json"));
    else
        [folder, base] = fileparts(dataPath);
        sidecarPath = string(fullfile(folder, base + ".elab.json"));
    end
    try
        writelines(string(jsonencode(payload)), sidecarPath);
    catch exception
        logWarn("writeElabSidecar: could not write %s: %s", ...
            sidecarPath, exception.message);
        sidecarPath = "";
    end
end
