function id = findExperimentByExtraField(client, kind, fieldName, value, opts)
% findExperimentByExtraField  Return the lowest id whose extra field matches.
%
%   id = elab.client.findExperimentByExtraField(client, "experiments", ...
%           "data_file_hash", hashString)
%   id = elab.client.findExperimentByExtraField(client, "experiments", ...
%           "data_file_hash", hashString, category="Session")
%
%   Used for idempotency: re-running the watcher does not duplicate entries.
%   The server narrows the candidates, then each result is verified locally.

    arguments
        client
        kind      (1,1) string
        fieldName (1,1) string
        value     (1,1) string
        opts.category (1,1) string = ""
    end

    cfg = loadConfig();
    limit = cfg.elab.extra_field_search_limit;
    query = "extrafield:" + fieldName + ":" + value;
    categoryId = [];
    if strlength(opts.category) == 0
        queryArgs = {"q", query, "limit", limit};
    else
        if kind == "experiments"
            categoryEndpoint = "experiments_categories";
        elseif kind == "items"
            categoryEndpoint = "resources_categories";
        else
            error("elab:client:findExperimentByExtraField:unsupportedKind", ...
                "Category-scoped lookup does not support kind '%s'.", kind);
        end
        categoryId = elab.client.resolveId(client, categoryEndpoint, opts.category);
        queryArgs = {"q", query, "cat", categoryId, "limit", limit};
    end
    list = client.getJson("/" + kind, queryArgs);
    items = elab.util.toItems(list);
    if numel(items) >= limit
        logWarn("findExperimentByExtraField: search returned the configured " + ...
            "limit of %d entries; the duplicate check may be incomplete", limit);
    end

    key = matlab.lang.makeValidName(fieldName);
    matchingIds = zeros(1, 0);
    refetchedCount = 0;

    for k = 1:numel(items)
        m = items{k};
        if ~isempty(categoryId) && ~localHasCategory(m)
            m = client.getJson(sprintf("/%s/%d", kind, double(m.id)));
            refetchedCount = refetchedCount + 1;
        end
        if ~isempty(categoryId) && ~localHasCategory(m)
            logWarn("findExperimentByExtraField: category is unknown for entry id %d; " + ...
                "excluding it from matches", double(m.id));
            continue
        end
        if ~isempty(categoryId) && ...
                ~localCategoryMatches(m, categoryId, opts.category)
            continue
        end
        if ~isfield(m, "metadata") || isempty(m.metadata)
            continue
        end
        try
            md = jsondecode(m.metadata);
        catch
            continue
        end
        if ~isfield(md, "extra_fields") || ~isfield(md.extra_fields, key)
            continue
        end
        ef = md.extra_fields.(key);
        if isfield(ef, "value") && string(ef.value) == value
            matchingIds(end + 1) = double(m.id); %#ok<AGROW>
        end
    end

    if refetchedCount > 0
        logWarn("findExperimentByExtraField: refetched %d candidate(s) to determine category", ...
            refetchedCount);
    end

    if isempty(matchingIds)
        id = [];
        return
    end
    if numel(matchingIds) > 1
        logWarn("findExperimentByExtraField: found %d entries with " + ...
            "extra field '%s' equal to '%s'; returning the lowest id", ...
            numel(matchingIds), fieldName, value);
    end
    id = min(matchingIds);
end

function tf = localHasCategory(item)
    hasNumericId = isstruct(item) && isfield(item, "category") && ...
        isnumeric(item.category) && isscalar(item.category) && ...
        isfinite(item.category);
    hasTitle = isstruct(item) && isfield(item, "category_title") && ...
        (ischar(item.category_title) || isstring(item.category_title)) && ...
        isscalar(string(item.category_title)) && ...
        strlength(string(item.category_title)) > 0;
    tf = hasNumericId || hasTitle;
end

function tf = localCategoryMatches(item, categoryId, categoryTitle)
    numericMatch = isfield(item, "category") && isnumeric(item.category) && ...
        isscalar(item.category) && double(item.category) == categoryId;
    titleMatch = isfield(item, "category_title") && ...
        strcmpi(string(item.category_title), categoryTitle);
    tf = numericMatch || titleMatch;
end
