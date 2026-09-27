function [parsed, info] = parseAny(filePath)
% parseAny  Detect the format of an instrument file and parse it.
%
%   [parsed, info] = elab.io.parseAny(filePath)

    arguments
        filePath (1,1) string
    end
    info = elab.io.detectFormat(filePath);
    switch info.format
        case "spectrum"
            info.parser = "elab.io.parseSpectrum";
            parsed = elab.io.parseSpectrum(filePath, info.technique);
        case "chromatogram"
            info.parser = "elab.io.parseChromatogram";
            parsed = elab.io.parseChromatogram(filePath, info.technique);
        case "image"
            info.parser = "elab.io.parseImageMeta";
            parsed = elab.io.parseImageMeta(filePath, info.metaPath);
        case "nmr_folder"
            info.parser = "elab.io.parseBrukerExperiment";
            parsed = elab.io.parseBrukerExperiment(filePath);
        otherwise
            error("elab:io:parseAny:unhandled", "unhandled format for %s", filePath);
    end
end
