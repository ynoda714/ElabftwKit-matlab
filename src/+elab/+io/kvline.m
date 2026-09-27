function [name, value] = kvline(L)
% kvline  Split "key: value" or "key = value" (optional leading #/##).
%
%   [name, value] = elab.io.kvline(L)
%   Returns "", "" when the line is not a key/value pair.

    name = "";
    value = "";
    s = regexprep(strtrim(string(L)), "^#+\s*", "");
    tok = regexp(s, "^([^:=]+?)\s*[:=]\s*(.+?)\s*$", "tokens", "once");
    if numel(tok) == 2
        name = string(tok{1});
        value = string(tok{2});
        % Ignore decorated separator lines such as "--- data: x y ---".
        if ~isempty(regexp(name, "^[-*~_]{2,}", "once"))
            name = "";
            value = "";
            return
        end
        % Ignore JCAMP-DX data markers such as ##XYPOINTS= (XY..XY).
        if contains(value, "..") || ...
                startsWith(upper(name), ["XYDATA" "XYPOINTS" "PEAKTABLE" "END"])
            name = "";
            value = "";
        end
    end
end
