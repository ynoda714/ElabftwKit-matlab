function info = detectFormat(filePath)
% detectFormat  Classify an instrument output file for the facility watcher.
%
%   info = elab.io.detectFormat(filePath)
%     info.format    : "spectrum" | "chromatogram" | "image" | "unknown"
%     info.technique : "xrd" | "raman" | "ftir" | "nmr" | "lcms" | "sem" | "unknown"
%     info.metaPath  : sidecar metadata file for images ("" otherwise)

    arguments
        filePath (1,1) string
    end
    if isfolder(filePath)
        info = struct("format", "unknown", "technique", "unknown", "metaPath", "");
        if isfile(fullfile(filePath, "acqus")) && ...
                (isfile(fullfile(filePath, "fid")) || isfile(fullfile(filePath, "ser")))
            info.format = "nmr_folder";
            info.technique = "nmr";
        end
        return
    end
    [folder, base, ext] = fileparts(filePath);
    ext = lower(ext);

    info = struct("format", "unknown", "technique", "unknown", "metaPath", "");

    prefix = lower(extractBefore(base + "_", "_"));
    if ismember(prefix, ["xrd" "raman" "ftir" "nmr" "lcms" "sem"])
        info.technique = prefix;
    end

    if ismember(ext, [".png" ".tif" ".tiff" ".jpg" ".jpeg" ".bmp"])
        info.format = "image";
        cand = string(fullfile(folder, base + "_meta.txt"));
        if isfile(cand)
            info.metaPath = cand;
        end
        return
    end

    head = "";
    fid = fopen(filePath, "r");
    if fid > 0
        head = string(fread(fid, 4000, "*char")');
        fclose(fid);
    end
    if contains(head, "[PEAKS]", "IgnoreCase", true) || ...
            contains(head, "[TRACE]", "IgnoreCase", true)
        info.format = "chromatogram";
    else
        info.format = "spectrum";
    end
end
