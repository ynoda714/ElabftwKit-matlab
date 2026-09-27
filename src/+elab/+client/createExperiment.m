function id = createExperiment(client, categoryName, titleStr, opts)
% createExperiment  Create an experiment in a named category.
%
%   id = elab.client.createExperiment(client, "Session", "XRD SMP-2026-001", ...
%           body="...", date="2026-09-08", status="Draft", ...
%           tags=["PRJ-A" "XRD-01"])
%
%   If status is omitted or empty, the server default is left unchanged.

    arguments
        client
        categoryName (1,1) string
        titleStr     (1,1) string
        opts.body    (1,1) string = ""
        opts.date    (1,1) string = string(datetime("today"), "yyyy-MM-dd")
        opts.status  (1,1) string = ""
        opts.tags    (1,:) string = string.empty(1, 0)
    end

    catId = elab.client.resolveId(client, "experiments_categories", categoryName);
    id = client.createEntry("experiments", struct());

    fields = struct("title", titleStr, "date", opts.date, "category", catId);
    if opts.body ~= ""
        fields.body = opts.body;
    end
    if opts.status ~= ""
        try
            fields.status = elab.client.resolveId(client, "experiments_status", opts.status);
        catch
            logWarn("createExperiment: status '%s' not found; leaving server default", opts.status);
        end
    end
    client.patchJson("experiments", id, fields);

    for t = opts.tags
        if t == ""
            continue
        end
        try
            client.tag("experiments", id, t);
        catch e
            logWarn("createExperiment: could not add tag '%s': %s", t, e.message);
        end
    end
end
