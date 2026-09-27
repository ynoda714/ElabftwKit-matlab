function id = ensureCategory(client, endpoint, title, opts)
% ensureCategory  Find or create a team-scoped category or experiment status.
%
%   id = elab.client.ensureCategory(client, "experiments_categories", "Session")

    arguments
        client
        endpoint (1,1) string
        title (1,1) string
        opts.color (1,1) string = "29aeb9"
    end

    allowed = ["experiments_categories", "resources_categories", "experiments_status"];
    if ~ismember(endpoint, allowed)
        error("elab:client:ensureCategory:invalidEndpoint", ...
            "Unsupported category endpoint '%s'.", endpoint);
    end
    if isempty(regexp(char(opts.color), '^[0-9A-Fa-f]{6}$', 'once'))
        error("elab:client:ensureCategory:invalidColor", ...
            "Category color must be six hexadecimal digits without '#'.");
    end

    kind = "teams/current/" + endpoint;
    items = elab.util.toItems(client.getJson("/" + kind));
    for k = 1:numel(items)
        item = items{k};
        if isstruct(item) && isfield(item, "title") && strcmp(string(item.title), title)
            id = double(item.id);
            return
        end
    end

    id = client.createEntry(kind, struct());
    client.patchJson(kind, id, struct("title", title, "color", lower(opts.color)));
    item = client.getJson("/" + kind + "/" + id);
    if ~isstruct(item) || ~isfield(item, "title") || ~strcmp(string(item.title), title)
        error("elab:client:ensureCategory:notApplied", ...
            "Category #%d did not retain title '%s'.", id, title);
    end
end
