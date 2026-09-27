function info = anynmrInfo(opts)
% anynmrInfo  Read and optionally verify vendored AnyNMR source metadata.
    arguments
        opts.verify (1,1) logical = false
        opts.root (1,1) string = ""
    end
    root = opts.root;
    if root == ""
        root = string(fileparts(fileparts(fileparts(fileparts( ...
            mfilename("fullpath"))))));
    end
    vendorRoot = fullfile(root, "src", "third_party", "AnyNMR");
    manifestPath = fullfile(vendorRoot, "UPSTREAM.json");
    if ~isfile(manifestPath)
        error("elab:util:anynmrInfo:noUpstream", "UPSTREAM.json was not found.");
    end
    try
        info = jsondecode(fileread(manifestPath));
    catch exception
        throwAsCaller(MException("elab:util:anynmrInfo:invalidUpstream", ...
            "UPSTREAM.json is invalid: %s", exception.message));
    end
    required = ["name", "url", "tag", "commit", "license", "fetched", "files", "files_hash"];
    if ~all(isfield(info, required))
        error("elab:util:anynmrInfo:invalidUpstream", "UPSTREAM.json is missing required keys.");
    end
    if ~opts.verify
        return
    end
    paths = string({info.files.path});
    expected = lower(string({info.files.sha256}));
    actual = strings(size(paths));
    mismatches = strings(0, 1);
    for index = 1:numel(paths)
        filePath = fullfile(vendorRoot, paths(index));
        if ~isfile(filePath)
            mismatches(end + 1, 1) = paths(index); %#ok<AGROW>
            continue
        end
        actual(index) = string(elab.util.fileHash(filePath));
        if actual(index) ~= expected(index)
            mismatches(end + 1, 1) = paths(index); %#ok<AGROW>
        end
    end
    actualHash = localFilesHash(paths, actual);
    if actualHash ~= string(info.files_hash) && isempty(mismatches)
        mismatches = "files_hash";
    end
    info.files_verified = isempty(mismatches);
    info.mismatches = mismatches;
end

function value = localFilesHash(paths, hashes)
    lines = join(lower(hashes) + "  " + paths, newline) + newline;
    bytes = unicode2native(char(lines), "UTF-8");
    digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
    value = lower(string(sprintf("%02x", typecast(digest, "uint8"))));
end
