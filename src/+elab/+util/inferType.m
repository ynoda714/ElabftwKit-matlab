function t = inferType(v)
% inferType  Guess an eLabFTW extra-field type from a MATLAB value.
%
%   t = elab.util.inferType(v)  returns one of
%   "text" | "number" | "date" | "datetime-local" | "checkbox".

    if islogical(v)
        t = "checkbox";
    elseif isdatetime(v)
        if v.Hour ~= 0 || v.Minute ~= 0 || v.Second ~= 0
            t = "datetime-local";
        else
            t = "date";
        end
    elseif isnumeric(v) && isscalar(v)
        t = "number";
    else
        t = "text";
    end
    t = char(t);
end
