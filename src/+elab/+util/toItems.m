function items = toItems(data)
% toItems  Normalise a decoded JSON array to a cell array of structs.
%
%   webread / matlab.net.http may return a struct array or a cell array
%   depending on homogeneity; callers want one shape.
%
%   items = elab.util.toItems(data)

    if iscell(data)
        items = data;
    elseif isstruct(data)
        items = num2cell(data);
    elseif isempty(data)
        items = {};
    else
        items = {data};
    end
end
