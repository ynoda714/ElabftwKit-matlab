function hex = fileHash(filePath)
% fileHash  Lowercase hex SHA-256 of a file, used as an idempotency key.
%
%   hex = elab.util.fileHash(filePath)

    fid = fopen(filePath, "r");
    if fid < 0
        error("elab:util:fileHash:openFailed", "cannot open %s", filePath);
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, "*uint8");

    if isempty(bytes)
        hex = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        return
    end
    md = java.security.MessageDigest.getInstance("SHA-256");
    digest = typecast(md.digest(bytes), "uint8");
    hex = char(lower(string(sprintf("%02x", digest))));
end
