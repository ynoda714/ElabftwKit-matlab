classdef FakeElabClient < handle
    % FakeElabClient  Recording test double for the client helper tests.
    % Metadata mutation mirrors the measured eLabFTW 5.6.12 behavior in
    % docs/elabftw-5.6.12-api-notes.md section 2.12: metadata PATCH replaces
    % the value, while updatemetadatafield changes existing fields only.

    properties
        Calls = {}
        CreatedId = 501
        IgnoreMetadataFieldUpdates = false
        IgnoreMetadataPatches = false
        IgnoredMetadataFieldNames = strings(1, 0)
        FailCreateKinds = strings(1, 0)
        IgnoreStatusTitlePatches = false
        IgnoreCategoryTitlePatches = false
        StatefulExperiments = false
    end

    properties (Access = private)
        GetResponses
    end

    methods
        function obj = FakeElabClient()
            obj.GetResponses = containers.Map( ...
                "KeyType", "char", "ValueType", "any");
        end

        function setGetResponse(obj, route, response)
            obj.GetResponses(char(route)) = response;
        end

        function response = getJson(obj, varargin)
            obj.record("getJson", varargin);
            route = char(string(varargin{1}));
            if ~isKey(obj.GetResponses, route)
                error("FakeElabClient:unexpectedGetJson", ...
                    "No response configured for route '%s'.", route);
            end
            response = obj.GetResponses(route);
        end

        function id = createEntry(obj, varargin)
            obj.record("createEntry", varargin);
            kind = string(varargin{1});
            if any(obj.FailCreateKinds == kind)
                error("FakeElabClient:createFailed", ...
                    "Injected create failure for %s.", kind);
            end
            if kind == "teams/current/items_status"
                id = 600 + sum(cellfun(@(call) call.Method == "createEntry" && ...
                    string(call.Arguments{1}) == kind, obj.Calls));
                item = struct("id", id, "title", "Untitled", "color", "");
                obj.GetResponses(char("/teams/current/items_status/" + id)) = item;
            elseif startsWith(kind, "teams/current/")
                id = 700 + sum(cellfun(@(call) call.Method == "createEntry" && ...
                    string(call.Arguments{1}) == kind, obj.Calls));
                item = struct("id", id, "title", "Untitled", "color", "");
                obj.GetResponses(char("/" + kind + "/" + id)) = item;
            elseif kind == "experiments" && obj.StatefulExperiments
                id = obj.CreatedId + sum(cellfun(@(call) ...
                    call.Method == "createEntry" && ...
                    string(call.Arguments{1}) == kind, obj.Calls)) - 1;
                obj.GetResponses(char("/experiments/" + id)) = struct("id", id);
            else
                if kind == "items"
                    id = obj.CreatedId + sum(cellfun(@(call) ...
                        call.Method == "createEntry" && ...
                        string(call.Arguments{1}) == kind, obj.Calls)) - 1;
                    obj.GetResponses(char("/items/" + id)) = struct( ...
                        "id", id, "title", "Untitled", "category", []);
                else
                    id = obj.CreatedId;
                end
            end
        end

        function patchJson(obj, varargin)
            obj.record("patchJson", varargin);
            kind = string(varargin{1});
            id = double(varargin{2});
            payload = varargin{3};
            route = char(sprintf("/%s/%d", kind, id));
            if ~isKey(obj.GetResponses, route)
                return
            end

            response = obj.GetResponses(route);
            if ~isstruct(response)
                return
            end
            if kind == "teams/current/items_status"
                if isfield(payload, "title") && ~obj.IgnoreStatusTitlePatches
                    response.title = payload.title;
                end
                if isfield(payload, "color")
                    response.color = payload.color;
                end
                obj.GetResponses(route) = response;
                obj.updateStatusList(response);
                return
            end
            if startsWith(kind, "teams/current/")
                if isfield(payload, "title") && ~obj.IgnoreCategoryTitlePatches
                    response.title = payload.title;
                end
                if isfield(payload, "color")
                    response.color = payload.color;
                end
                obj.GetResponses(route) = response;
                obj.updateTeamList(kind, response);
                return
            end
            if kind == "experiments" && obj.StatefulExperiments
                names = string(fieldnames(payload));
                for k = 1:numel(names)
                    response.(names(k)) = payload.(names(k));
                end
                obj.GetResponses(route) = response;
                obj.updateExperimentList(response);
                return
            end
            if kind == "items"
                if isfield(payload, "title")
                    response.title = payload.title;
                end
                if isfield(payload, "category")
                    response.category = payload.category;
                end
            end
            if kind == "items" && isfield(payload, "status") && ...
                    isnumeric(payload.status)
                response.status = payload.status;
                status = obj.statusById(payload.status);
                if ~isempty(status)
                    response.status_title = status.title;
                    response.status_color = status.color;
                end
                obj.GetResponses(route) = response;
                obj.updateItemList(response);
                return
            end
            if kind == "items" && (isfield(payload, "title") || ...
                    isfield(payload, "category"))
                obj.GetResponses(route) = response;
                obj.updateItemList(response);
                return
            end
            if isfield(payload, "metadata")
                if obj.IgnoreMetadataPatches
                    return
                end
                response.metadata = payload.metadata;
                obj.GetResponses(route) = response;
                if kind == "items"
                    obj.updateItemList(response);
                end
                return
            end
            if obj.IgnoreMetadataFieldUpdates || ~isfield(payload, "action") || ...
                    string(payload.action) ~= "updatemetadatafield" || ...
                    ~isfield(response, "metadata") || isempty(response.metadata)
                return
            end

            metadata = jsondecode(response.metadata);
            if ~isstruct(metadata) || ~isfield(metadata, "extra_fields") || ...
                    ~isstruct(metadata.extra_fields)
                return
            end
            payloadNames = setdiff(string(fieldnames(payload)), "action", "stable");
            for k = 1:numel(payloadNames)
                name = payloadNames(k);
                if any(obj.IgnoredMetadataFieldNames == name)
                    continue
                end
                if ~(ischar(payload.(name)) || isstring(payload.(name)))
                    error("FakeElabClient:metadataFieldValueNotString", ...
                        "eLabFTW 5.6.12 rejects non-string metadata field values.");
                end
                if isfield(metadata.extra_fields, name)
                    metadata.extra_fields.(name).value = payload.(name);
                end
            end
            response.metadata = jsonencode(metadata);
            obj.GetResponses(route) = response;
            if kind == "items"
                obj.updateItemList(response);
            end
        end

        function tag(obj, varargin)
            obj.record("tag", varargin);
        end

        function uploadFile(obj, varargin)
            obj.record("uploadFile", varargin);
        end

        function linkTo(obj, varargin)
            obj.record("linkTo", varargin);
        end

        function captureExtraFields(obj, varargin)
            obj.record("setExtraFieldsInput", varargin);
        end
    end

    methods (Access = private)
        function updateStatusList(obj, item)
            route = '/teams/current/items_status';
            if isKey(obj.GetResponses, route)
                items = elab.util.toItems(obj.GetResponses(route));
            else
                items = {};
            end
            replaced = false;
            for k = 1:numel(items)
                if double(items{k}.id) == double(item.id)
                    items{k} = item;
                    replaced = true;
                    break
                end
            end
            if ~replaced
                items{end + 1} = item;
            end
            obj.GetResponses(route) = items;
        end

        function item = statusById(obj, id)
            item = [];
            route = char("/teams/current/items_status/" + double(id));
            if isKey(obj.GetResponses, route)
                item = obj.GetResponses(route);
                return
            end
            listRoute = '/teams/current/items_status';
            if isKey(obj.GetResponses, listRoute)
                items = elab.util.toItems(obj.GetResponses(listRoute));
                for k = 1:numel(items)
                    if double(items{k}.id) == double(id)
                        item = items{k};
                        return
                    end
                end
            end
        end

        function updateItemList(obj, item)
            route = '/items';
            if isKey(obj.GetResponses, route)
                items = elab.util.toItems(obj.GetResponses(route));
            else
                items = {};
            end
            replaced = false;
            for k = 1:numel(items)
                if double(items{k}.id) == double(item.id)
                    items{k} = item;
                    replaced = true;
                    break
                end
            end
            if ~replaced
                items{end + 1} = item;
            end
            obj.GetResponses(route) = items;
        end

        function updateExperimentList(obj, item)
            route = '/experiments';
            if isKey(obj.GetResponses, route)
                items = elab.util.toItems(obj.GetResponses(route));
            else
                items = {};
            end
            replaced = false;
            for k = 1:numel(items)
                if double(items{k}.id) == double(item.id)
                    items{k} = item;
                    replaced = true;
                    break
                end
            end
            if ~replaced
                items{end + 1} = item;
            end
            obj.GetResponses(route) = items;
        end

        function updateTeamList(obj, kind, item)
            route = char("/" + kind);
            if isKey(obj.GetResponses, route)
                items = elab.util.toItems(obj.GetResponses(route));
            else
                items = {};
            end
            replaced = false;
            for k = 1:numel(items)
                if double(items{k}.id) == double(item.id)
                    items{k} = item;
                    replaced = true;
                    break
                end
            end
            if ~replaced
                items{end + 1} = item;
            end
            obj.GetResponses(route) = items;
        end

        function record(obj, methodName, arguments)
            obj.Calls{end + 1} = struct( ...
                "Method", methodName, "Arguments", {arguments});
        end
    end
end
