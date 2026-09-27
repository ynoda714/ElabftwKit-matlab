function path = writeProvenanceJson(path, document)
% writeProvenanceJson  Write deterministic formatted provenance JSON.
    arguments
        path (1,1) string
        document (1,1) struct
    end
    fid = fopen(path, "w", "n", "UTF-8");
    if fid < 0
        error("elab:io:writeProvenanceJson:openFailed", "could not open provenance output.");
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, jsonencode(document, PrettyPrint=true), "char");
    fwrite(fid, newline, "char");
end
