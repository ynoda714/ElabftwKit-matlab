function source = sourceLocation(filePath, opts)
% sourceLocation  Describe the original file as seen during ingestion.

    arguments
        filePath (1,1) string
        opts.computerName (1,1) string = ""
        opts.environmentReader (1,1) function_handle = @getenv
        opts.fileInfo (1,1) struct = struct()
    end

    isFolder = isfolder(filePath);
    info = opts.fileInfo;
    if isFolder && isempty(fieldnames(info))
        info = dir(fullfile(filePath, "fid"));
        if isempty(info)
            info = dir(fullfile(filePath, "ser"));
        end
    elseif isempty(fieldnames(info))
        info = dir(filePath);
    end
    if isempty(info)
        error("elab:io:sourceLocation:notFound", ...
            "File or folder was not found: %s", filePath);
    end
    if isFolder
        absolutePath = string(char(java.io.File(char(filePath)).getAbsolutePath()));
    else
        absolutePath = string(fullfile(info(1).folder, info(1).name));
    end
    if startsWith(absolutePath, "\\")
        remainder = extractAfter(absolutePath, 2);
        parts = split(remainder, "\");
        sourceHost = parts(1);
    else
        sourceHost = opts.computerName;
        if sourceHost == ""
            sourceHost = string(opts.environmentReader("COMPUTERNAME"));
        end
        if sourceHost == ""
            sourceHost = string(opts.environmentReader("HOSTNAME"));
        end
    end
    modified = datetime(info(1).datenum, "ConvertFrom", "datenum");
    source = struct( ...
        "source_path", absolutePath, ...
        "source_host", sourceHost, ...
        "source_mtime", string(modified, "yyyy-MM-dd'T'HH:mm"));
end
