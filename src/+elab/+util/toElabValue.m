function s = toElabValue(v)
% toElabValue  Convert a MATLAB value to the string eLabFTW stores for an
%   extra field. eLabFTW keeps every extra-field value as text.
%
%   s = elab.util.toElabValue(v)  returns a char row vector.

    if islogical(v)
        if v
            s = "on";
        else
            s = "";
        end
    elseif isdatetime(v)
        if v.Hour ~= 0 || v.Minute ~= 0 || v.Second ~= 0
            s = string(v, "yyyy-MM-dd'T'HH:mm");
        else
            s = string(v, "yyyy-MM-dd");
        end
    elseif isnumeric(v)
        if isscalar(v)
            s = string(num2str(v, 10));
        else
            s = strjoin(string(v), ", ");
        end
    elseif isstring(v) || ischar(v)
        s = string(v);
    else
        s = string(jsonencode(v));
    end
    s = char(s);
end
