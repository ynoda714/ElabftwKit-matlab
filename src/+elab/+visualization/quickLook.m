function [pngPath, profile] = quickLook(format, parsed, outPngPath, opts)
% quickLook  Render a small preview PNG to attach to the eLabFTW entry.
%   Uses only base MATLAB (no Image Processing Toolbox).
%
%   pngPath = elab.visualization.quickLook(format, parsed, outPngPath)
%   [pngPath, profile] = elab.visualization.quickLook(...)
%   pngPath = elab.visualization.quickLook(..., title="XRD  sample")

    arguments
        format     (1,1) string
        parsed     (1,1) struct
        outPngPath (1,1) string
        opts.title (1,1) string = "Quick look"
    end

    figurePosition = [100 100 900 460];
    resolutionDpi = 120;
    imageMaxDimension = 1200;
    switch format
        case {"spectrum", "nmr_folder"}
            if format == "nmr_folder" && ~isfield(parsed, "spectrum")
                error("elab:visualization:quickLook:noPreview", ...
                    "no preview for format '%s'", format);
            end
            f = elab.visualization.lightFigure(figurePosition);
            if format == "nmr_folder"
                spectrum = parsed.spectrum;
                plot(spectrum.x, spectrum.y, "LineWidth", 1);
                xlabel(spectrum.xlabel); ylabel(spectrum.ylabel);
            else
                plot(parsed.x, parsed.y, "LineWidth", 1);
                xlabel(parsed.xlabel); ylabel(parsed.ylabel);
            end
            grid on
            if format == "nmr_folder" || contains(parsed.xlabel, "ppm")
                set(gca, "XDir", "reverse");     % NMR convention
            end
            title(opts.title, "Interpreter", "none");
            exportgraphics(f, outPngPath, "Resolution", resolutionDpi);
            close(f)
            profile = sprintf("light;%dx%d;%ddpi;interp=none", ...
                figurePosition(3), figurePosition(4), resolutionDpi);

        case "chromatogram"
            f = elab.visualization.lightFigure(figurePosition);
            plot(parsed.t, parsed.intensity, "LineWidth", 1);
            grid on
            vn = string(parsed.peaks.Properties.VariableNames);
            if ~isempty(parsed.peaks) && any(vn == "rt_min")
                rt = parsed.peaks.rt_min;
                for r = 1:numel(rt)
                    xline(rt(r), "r:");
                end
            end
            xlabel(parsed.xlabel); ylabel(parsed.ylabel);
            title(opts.title, "Interpreter", "none");
            exportgraphics(f, outPngPath, "Resolution", resolutionDpi);
            close(f)
            profile = sprintf("light;%dx%d;%ddpi;interp=none", ...
                figurePosition(3), figurePosition(4), resolutionDpi);

        case "image"
            img = imread(parsed.imagePath);
            mx = max(size(img, 1), size(img, 2));
            if mx > imageMaxDimension
                step = ceil(mx / imageMaxDimension);
                img = img(1:step:end, 1:step:end, :);
            end
            imwrite(img, outPngPath);
            profile = sprintf("copy;maxdim=%d", imageMaxDimension);

        otherwise
            error("elab:visualization:quickLook:noPreview", ...
                "no preview for format '%s'", format);
    end
    pngPath = outPngPath;
end
