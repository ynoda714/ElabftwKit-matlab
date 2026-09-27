classdef Client
    % Client  Minimal eLabFTW REST API v2 client (no MATLAB add-ons required).
    %
    %   c = elab.client.Client(baseUrl, apiKey)
    %   c = elab.client.Client(baseUrl, apiKey, allowSelfSigned)
    %   c = elab.client.Client(baseUrl, apiKey, allowSelfSigned, caCert)
    %
    %   Only the calls this project needs are implemented. Routes follow the
    %   eLabFTW v2 API; if the target server version differs, open the live
    %   Swagger at  <baseUrl>/api/v2/  and adjust the paths in this file.
    %   See docs/adr.md ADR-002 for why this thin wrapper is used instead of
    %   the File Exchange elabapi package.

    properties (SetAccess = immutable)
        ApiRoot         (1,1) string
        ApiKey          (1,1) string
        CaCertificate   (1,1) string
        AllowSelfSigned (1,1) logical
        Web                                  % weboptions template
    end

    methods
        function obj = Client(baseUrl, apiKey, allowSelfSigned, caCert)
            arguments
                baseUrl (1,1) string
                apiKey  (1,1) string
                allowSelfSigned (1,1) logical = false
                caCert (1,1) string = ""
            end
            obj.ApiRoot = regexprep(baseUrl, "/+$", "") + "/api/v2";
            obj.ApiKey  = apiKey;
            obj.CaCertificate = caCert;
            obj.AllowSelfSigned = allowSelfSigned;

            wargs = {"HeaderFields", {'Authorization', char(apiKey)}, ...
                     "ContentType", "json", "Timeout", 30};
            if caCert ~= ""
                wargs = [wargs, {"CertificateFilename", char(caCert)}];
            end
            obj.Web = weboptions(wargs{:});
        end

        function data = getJson(obj, path, query)
            % getJson  GET <path> with optional {name,value,...} query pairs.
            arguments
                obj
                path  (1,1) string
                query cell = {}
            end
            o = obj.Web; o.RequestMethod = "get";
            if isempty(query)
                data = webread(obj.ApiRoot + path, o);
            else
                data = webread(obj.ApiRoot + path, query{:}, o);
            end
        end

        function data = patchJson(obj, kind, id, fields)
            % patchJson  PATCH /<kind>/<id> with a struct body (sent as JSON).
            arguments
                obj
                kind   (1,1) string
                id     (1,1) double
                fields (1,1) struct
            end
            resp = obj.sendRaw("PATCH", ...
                obj.ApiRoot + sprintf("/%s/%d", kind, id), fields);
            data = resp.Body.Data;
        end

        function id = createEntry(obj, kind, payload)
            % createEntry  POST /<kind>; the new numeric id comes back in the
            %   Location response header.
            arguments
                obj
                kind    (1,1) string
                payload (1,1) struct = struct()
            end
            resp = obj.sendRaw("POST", obj.ApiRoot + "/" + kind, payload);
            loc = resp.getFields("Location");
            if isempty(loc)
                error("elab:client:createEntry:noLocation", ...
                    "POST /%s returned no Location header", kind);
            end
            parts = split(string(loc(1).Value), "/");
            id = str2double(parts(end));
            if isnan(id)
                error("elab:client:createEntry:badLocation", ...
                    "cannot parse id from Location '%s'", string(loc(1).Value));
            end
        end

        function up = uploadFile(obj, kind, id, filePath, comment)
            % uploadFile  POST /<kind>/<id>/uploads as multipart/form-data.
            arguments
                obj
                kind     (1,1) string
                id       (1,1) double
                filePath (1,1) string
                comment  (1,1) string = ""
            end
            fp = matlab.net.http.io.FileProvider(filePath);
            if comment == ""
                mp = matlab.net.http.io.MultipartFormProvider("file", fp);
            else
                mp = matlab.net.http.io.MultipartFormProvider( ...
                    "file", fp, "comment", matlab.net.http.io.StringProvider(comment));
            end
            resp = obj.sendRaw("POST", ...
                obj.ApiRoot + sprintf("/%s/%d/uploads", kind, id), mp, true);
            up = resp.Body.Data;
        end

        function linkTo(obj, fromKind, fromId, toKind, toId)
            % linkTo  Link an experiment/item to a database item or experiment.
            %   Route: POST /<fromKind>/<fromId>/<toKind>_links/<toId>
            arguments
                obj
                fromKind (1,1) string
                fromId   (1,1) double
                toKind   (1,1) string      % "items" | "experiments"
                toId     (1,1) double
            end
            url = obj.ApiRoot + sprintf("/%s/%d/%s_links/%d", ...
                fromKind, fromId, toKind, toId);
            % eLabFTW 5.6.12 rejects a bodyless POST because it has no
            % Content-Type header. An empty JSON object satisfies the route.
            obj.sendRaw("POST", url, struct());
        end

        function tag(obj, kind, id, tagText)
            % tag  POST /<kind>/<id>/tags  {"tag": "..."}
            arguments
                obj
                kind    (1,1) string
                id      (1,1) double
                tagText (1,1) string
            end
            obj.sendRaw("POST", obj.ApiRoot + sprintf("/%s/%d/tags", kind, id), ...
                struct("tag", tagText));
        end

        function deleteEntry(obj, kind, id)
            % deleteEntry  DELETE /<kind>/<id>.
            arguments
                obj
                kind (1,1) string
                id   (1,1) double
            end
            obj.sendRaw("DELETE", obj.ApiRoot + sprintf("/%s/%d", kind, id));
        end
    end

    methods (Access = private)
        function resp = sendRaw(obj, method, url, payload, isMultipart)
            arguments
                obj
                method      (1,1) string
                url         (1,1) string
                payload = []
                isMultipart (1,1) logical = false
            end
            import matlab.net.http.*
            import matlab.net.http.field.*
            hdr = HeaderField("Authorization", obj.ApiKey);
            requestMethod = char(method);
            if isempty(payload)
                req = RequestMessage(requestMethod, hdr);
            elseif isMultipart
                req = RequestMessage(requestMethod, hdr, payload);   % payload is a provider
            else
                hdr(end + 1) = HeaderField("Content-Type", "application/json");
                body = MessageBody;
                body.Payload = unicode2native(jsonencode(payload), "UTF-8");
                req = RequestMessage(requestMethod, hdr, body);
            end
            opts = matlab.net.http.HTTPOptions("ConnectTimeout", 60);
            if obj.CaCertificate ~= ""
                opts.CertificateFilename = char(obj.CaCertificate);
            end
            if obj.AllowSelfSigned
                % This flag skips host-name matching only; the certificate
                % chain is still verified against CaCertificate/system CAs.
                opts.VerifyServerName = false;
            end
            resp = req.send(url, opts);
            if resp.StatusCode >= matlab.net.http.StatusCode.MultipleChoices
                error("elab:client:sendRaw:httpError", "%s %s -> %s\n%s", ...
                    method, url, string(resp.StatusCode), elab.util.bodyText(resp));
            end
        end
    end
end
