function s = bodyText(resp)
% bodyText  Best-effort readable text of an HTTP response body, for errors.
%
%   s = elab.util.bodyText(resp)  where resp is a matlab.net.http.ResponseMessage.

    try
        d = resp.Body.Data;
        if ischar(d) || isstring(d)
            s = string(d);
        else
            s = string(jsonencode(d));
        end
    catch
        s = "<no readable body>";
    end
end
