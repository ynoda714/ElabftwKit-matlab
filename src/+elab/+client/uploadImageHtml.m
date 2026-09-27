function html = uploadImageHtml(client, kind, id, realName, opts)
% uploadImageHtml  Return an img element for an uploaded eLabFTW image.
%
%   html = elab.client.uploadImageHtml(client, kind, id, realName)
%   html = elab.client.uploadImageHtml(client, kind, id, realName, ...
%       width=600, alt="quick look")

    arguments
        client
        kind     (1,1) string
        id       (1,1) double
        realName (1,1) string
        opts.width (1,1) double {mustBePositive, mustBeFinite} = 600
        opts.alt   (1,1) string = ""
    end

    entry = client.getJson(sprintf("/%s/%d", kind, id));
    uploads = {};
    if isstruct(entry) && isfield(entry, "uploads")
        uploads = elab.util.toItems(entry.uploads);
    end

    selected = [];
    selectedId = -Inf;
    for k = 1:numel(uploads)
        upload = uploads{k};
        if ~isstruct(upload) || ~isfield(upload, "real_name") || ...
                string(upload.real_name) ~= realName || ~isfield(upload, "id")
            continue
        end
        uploadId = localNumericId(upload.id);
        if uploadId > selectedId
            selected = upload;
            selectedId = uploadId;
        end
    end

    if isempty(selected)
        error("elab:client:uploadImageHtml:notFound", ...
            "Upload '%s' was not found on %s entry #%d.", realName, kind, id);
    end

    if opts.alt == ""
        alt = realName;
    else
        alt = opts.alt;
    end
    src = "app/download.php?name=" + localQueryEncode(selected.real_name) + ...
        "&f=" + localQueryEncode(selected.long_name) + ...
        "&storage=" + string(selected.storage);
    html = sprintf('<img src="%s" width="%g" alt="%s">', ...
        localHtmlEscape(src), opts.width, localHtmlEscape(alt));
end

function value = localNumericId(raw)
    if isnumeric(raw) && isscalar(raw)
        value = double(raw);
    else
        value = str2double(string(raw));
    end
    if isnan(value)
        value = -Inf;
    end
end

function encoded = localQueryEncode(value)
    encoded = string(java.net.URLEncoder.encode(char(string(value)), 'UTF-8'));
    encoded = replace(encoded, "+", "%20");
end

function escaped = localHtmlEscape(value)
    escaped = replace(string(value), ...
        ["&", "<", ">", '"'], ["&amp;", "&lt;", "&gt;", "&quot;"]);
end
