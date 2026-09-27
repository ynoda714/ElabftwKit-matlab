function s = parseSpectrum(filePath, technique)
% parseSpectrum  Read a 2-column spectrum with a "#"/"##" key:value header.
%   Handles the XRD (.xy), Raman (.txt) and FTIR/NMR (.dx) mock files.
%
%   s = elab.io.parseSpectrum(filePath, technique)
%     s.x, s.y            : numeric column vectors
%     s.params           : struct array (name/value/type) for extra_fields
%     s.xlabel, s.ylabel : axis labels for the quick-look figure

    arguments
        filePath  (1,1) string
        technique (1,1) string = "unknown"
    end

    lines = readlines(filePath);
    hdr = repmat(struct("name", "", "value", "", "type", "text"), 0, 1);
    xy = zeros(0, 2);

    for i = 1:numel(lines)
        L = strtrim(lines(i));
        if L == ""
            continue
        end
        if startsWith(L, "#")
            [nm, vl] = elab.io.kvline(L);
            if nm ~= ""
                hdr(end + 1) = struct("name", nm, "value", vl, "type", "text"); %#ok<AGROW>
            end
            continue
        end
        nums = str2double(regexp(L, "[,;\t ]+", "split"));
        nums = nums(~isnan(nums));
        if numel(nums) >= 2
            xy(end + 1, 1:2) = nums(1:2); %#ok<AGROW>
        end
    end

    if isempty(xy)
        error("elab:io:parseSpectrum:noData", ...
            "no 2-column numeric data found in %s", filePath);
    end

    s.x = xy(:, 1);
    s.y = xy(:, 2);

    computed = [ ...
        struct("name", "n_points", "value", numel(s.x), "type", "number"), ...
        struct("name", "x_min",    "value", min(s.x),   "type", "number"), ...
        struct("name", "x_max",    "value", max(s.x),   "type", "number")];
    s.params = [reshape(hdr, 1, []), computed];

    switch technique
        case "xrd"
            s.xlabel = "2\theta (deg)";         s.ylabel = "Intensity (counts)";
        case "raman"
            s.xlabel = "Raman shift (cm^{-1})"; s.ylabel = "Intensity (a.u.)";
        case "ftir"
            s.xlabel = "Wavenumber (cm^{-1})";  s.ylabel = "Absorbance";
        case "nmr"
            s.xlabel = "Chemical shift (ppm)";  s.ylabel = "Intensity (a.u.)";
        otherwise
            s.xlabel = "x";                     s.ylabel = "y";
    end
end
