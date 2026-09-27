function binding = matchSample(map, fileName)
% matchSample  Match one filename to a sample-map binding.
%
%   binding = elab.pipeline.matchSample(map, fileName) returns a struct or [].

    binding = [];
    for k = 1:height(map)
        if contains(fileName, map.match_substring(k), "IgnoreCase", true)
            binding = table2struct(map(k, :));
            return
        end
    end
end
