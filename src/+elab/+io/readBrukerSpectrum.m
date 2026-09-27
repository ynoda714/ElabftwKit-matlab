function spectrum = readBrukerSpectrum(folder)
% readBrukerSpectrum  Build a minimal preview spectrum with vendored AnyNMR.
    arguments
        folder (1,1) string
    end
    if ~isfolder(folder)
        error("elab:io:readBrukerSpectrum:notFolder", "input must be a folder.");
    end
    if isempty(which("nmr.io.loadBruker"))
        error("elab:io:readBrukerSpectrum:anynmrMissing", "vendored AnyNMR is not on the MATLAB path.");
    end
    try
        output = evalc("data = nmr.io.loadBruker(folder); data = nmr.processing.doFFT(data); data = nmr.processing.autoPhase(data);");
        if strlength(string(output)) > 0
            logDebug("readBrukerSpectrum: %s", strtrim(string(output)));
        end
    catch exception
        message = replace(string(exception.message), folder, "<folder>");
        throwAsCaller(MException("elab:io:readBrukerSpectrum:processingFailed", ...
            "AnyNMR %s: %s", exception.identifier, message));
    end
    steps = data.proc.history;
    if isfield(steps, "timestamp")
        steps = rmfield(steps, "timestamp");
    end
    spectrum = struct("x", data.spec.ppm(:), "y", real(data.spec.data(:)), ...
        "xlabel", "Chemical shift (ppm)", "ylabel", "Intensity (a.u.)", ...
        "steps", steps, "ph0", data.proc.ph0, "ph1", data.proc.ph1);
end
