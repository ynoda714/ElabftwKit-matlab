function manifest = experimentManifest(folder)
% experimentManifest  Create complete and core manifests for an experiment folder.

    arguments
        folder (1,1) string
    end
    if ~isfolder(folder)
        error("elab:io:experimentManifest:notFolder", "not a folder: %s", folder);
    end
    if ~isfile(fullfile(folder, "acqus")) || ...
            ~(isfile(fullfile(folder, "fid")) || isfile(fullfile(folder, "ser")))
        error("elab:io:experimentManifest:notExperiment", "not an experiment folder: %s", folder);
    end
    files = localFiles(folder, "");
    paths = string({files.path});
    [~, order] = sort(paths);
    files = files(order);
    entries = repmat(struct("path", "", "bytes", 0, "sha256", "", "isCore", false), numel(files), 1);
    for k = 1:numel(files)
        entries(k).path = files(k).path;
        entries(k).bytes = files(k).bytes;
        entries(k).sha256 = string(elab.util.fileHash(files(k).absolutePath));
        entries(k).isCore = files(k).isCore;
    end
    fullText = localText(entries);
    coreText = localText(entries([entries.isCore]));
    manifest = struct("entries", entries, "fullText", fullText, "coreText", coreText, ...
        "fullHash", localHash(fullText), "coreHash", localHash(coreText));
end

function files = localFiles(folder, relative)
    files = repmat(struct("path", "", "absolutePath", "", "bytes", 0, "isCore", false), 0, 1);
    listing = dir(folder);
    for k = 1:numel(listing)
        name = string(listing(k).name);
        if name == "." || name == ".." || startsWith(name, ".") || ...
                any(strcmpi(name, ["Thumbs.db" "desktop.ini"]))
            continue
        end
        childRelative = name;
        if relative ~= "", childRelative = relative + "/" + name; end
        child = string(fullfile(folder, name));
        if listing(k).isdir
            if relative == "" && name == "pdata"
                continue
            end
            files = [files; localFiles(child, childRelative)]; %#ok<AGROW>
        else
            coreNames = ["acqus" "acqu2s" "acqu3s" "fid" "ser" "audita.txt"];
            files(end + 1, 1) = struct("path", childRelative, "absolutePath", child, ...
                "bytes", listing(k).bytes, "isCore", relative == "" && ismember(name, coreNames)); %#ok<AGROW>
        end
    end
end

function text = localText(entries)
    text = "elab-manifest 1" + newline;
    for k = 1:numel(entries)
        text = text + entries(k).sha256 + "  " + string(entries(k).bytes) + "  " + entries(k).path + newline;
    end
    text = replace(text, newline, sprintf("\n"));
end

function hex = localHash(text)
    bytes = unicode2native(char(text), "UTF-8");
    md = java.security.MessageDigest.getInstance("SHA-256");
    digest = typecast(md.digest(uint8(bytes)), "uint8");
    hex = string(lower(sprintf("%02x", digest)));
end
