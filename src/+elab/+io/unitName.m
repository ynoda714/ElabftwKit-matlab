function [name, archiveName] = unitName(path, inboxDir)
% unitName  Return a stable inbox-relative name and an archive-safe name.

    arguments
        path (1,1) string
        inboxDir (1,1) string
    end

    if ~isfolder(path)
        [~, base, extension] = fileparts(path);
        name = string(base + extension);
        archiveName = name;
        return
    end
    absolutePath = localAbsolutePath(path);
    absoluteInbox = localAbsolutePath(inboxDir);
    normalizedPath = localNormalizePath(absolutePath);
    normalizedInbox = localNormalizePath(absoluteInbox);
    prefix = normalizedInbox + "\";
    if startsWith(normalizedPath, prefix, IgnoreCase=ispc)
        name = extractAfter(normalizedPath, strlength(prefix));
        name = replace(name, "\", "/");
    else
        name = string(char(java.io.File(char(absolutePath)).getName()));
    end
    archiveName = replace(name, "/", "_");
end

function path = localAbsolutePath(value)
    file = java.io.File(char(value));
    path = string(char(file.getAbsolutePath()));
end

function path = localNormalizePath(value)
    path = replace(string(value), "/", "\");
    while strlength(path) > 3 && endsWith(path, "\")
        path = extractBefore(path, strlength(path));
    end
end
