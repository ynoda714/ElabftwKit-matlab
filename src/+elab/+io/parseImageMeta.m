function s = parseImageMeta(imagePath, metaPath)
% parseImageMeta  Pair an SEM/microscopy image with its key:value sidecar.
%
%   s = elab.io.parseImageMeta(imagePath, metaPath)
%     s.imagePath : the image file
%     s.params    : struct array for extra_fields (dimensions + sidecar values)

    arguments
        imagePath (1,1) string
        metaPath  (1,1) string = ""
    end

    s.imagePath = imagePath;
    s.params = repmat(struct("name", "", "value", "", "type", "text"), 0, 1);

    info = imfinfo(imagePath);
    s.params(end + 1) = struct("name", "image_width_px",  "value", info(1).Width,  "type", "number");
    s.params(end + 1) = struct("name", "image_height_px", "value", info(1).Height, "type", "number");

    if metaPath ~= "" && isfile(metaPath)
        lines = readlines(metaPath);
        for i = 1:numel(lines)
            [nm, vl] = elab.io.kvline(lines(i));
            if nm ~= ""
                s.params(end + 1) = struct("name", nm, "value", vl, "type", "text"); %#ok<AGROW>
            end
        end
    end
    s.params = reshape(s.params, 1, []);
end
