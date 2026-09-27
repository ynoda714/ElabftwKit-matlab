function [id, items] = ensureItemStatus(client, title, color, opts)
% ensureItemStatus  Find or create a team-scoped resource status.
%
%   id = elab.client.ensureItemStatus(client, "OK", "28a745")
%
%   Creation follows the eLabFTW 5.6.12 two-step API: create an Untitled
%   status, then patch its title and color. The title is read back before
%   the id is returned. Pass a previously fetched items list to share one
%   list request across several status definitions.

    arguments
        client
        title (1,1) string
        color (1,1) string
        opts.items = "__FETCH__"
    end

    if isempty(regexp(char(color), '^[0-9A-Fa-f]{6}$', 'once'))
        error("elab:client:ensureItemStatus:invalidColor", ...
            "Resource status color must be six hexadecimal digits without '#'.");
    end

    if isstring(opts.items) && isscalar(opts.items) && opts.items == "__FETCH__"
        raw = client.getJson("/teams/current/items_status");
        items = elab.util.toItems(raw);
    else
        items = elab.util.toItems(opts.items);
    end

    for k = 1:numel(items)
        item = items{k};
        if isstruct(item) && isfield(item, "title") && ...
                strcmpi(string(item.title), title)
            id = double(item.id);
            return
        end
    end

    id = client.createEntry("teams/current/items_status", struct());
    client.patchJson("teams/current/items_status", id, ...
        struct("title", title, "color", lower(color)));
    item = client.getJson("/teams/current/items_status/" + id);
    if ~isstruct(item) || ~isfield(item, "title") || ...
            ~strcmp(string(item.title), title)
        error("elab:client:ensureItemStatus:notApplied", ...
            "Resource status #%d did not retain title '%s'.", id, title);
    end
    items{end + 1} = item;
end
