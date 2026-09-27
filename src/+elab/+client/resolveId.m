function id = resolveId(client, endpoint, name)
% resolveId  Map a human name to its numeric id for a lookup endpoint.
%
%   id = elab.client.resolveId(client, "experiments_categories", "Session")
%
%   endpoint: "experiments_categories" | "experiments_status" |
%             "resources_categories" | "items_status" | "items_types"
%   resources_categories are item categories. items_types are resource
%   templates and are retained here only for callers that need templates.
%   If name is already numeric it is returned as-is.

    arguments
        client
        endpoint (1,1) string
        name     (1,1) string
    end

    if ~isnan(str2double(name))
        id = str2double(name);
        return
    end

    if any(endpoint == ["experiments_categories", "experiments_status", ...
            "resources_categories", "items_status"])
        % The current-team route follows the API key's team context and
        % avoids a separate request just to discover the numeric team id.
        route = "/teams/current/" + endpoint;
    else
        route = "/" + endpoint;
    end

    list = client.getJson(route);
    items = elab.util.toItems(list);
    for k = 1:numel(items)
        it = items{k};
        if isstruct(it) && isfield(it, "title") && strcmpi(string(it.title), name)
            id = double(it.id);
            return
        end
    end

    error("elab:client:resolveId:notFound", ...
        "No entry titled '%s' under %s. Create it in the eLabFTW admin panel first.", ...
        name, route);
end
