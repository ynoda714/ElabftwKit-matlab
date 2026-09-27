function files = writeMockRuns(outDir, opts)
% writeMockRuns  Write one synthetic instrument file per technique so the
%   whole pipeline can run without real hardware. Uses only base MATLAB.
%
%   files = elab.io.writeMockRuns(outDir)
%   files = elab.io.writeMockRuns(outDir, acquiredAt=datetime(...))
%
%   Produces: xrd_*.xy, raman_*.txt, ftir_*.dx, nmr_*.dx, lcms_*.csv,
%   sem_*.png (+ sem_*_meta.txt). Returns the string array of file paths
%   (sidecar meta files excluded).

    arguments
        outDir (1,1) string = string(fullfile("data", "inbox"))
        opts.acquiredAt (1,1) datetime = ...
            dateshift(datetime("today"), "start", "day") + hours(9)
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    rng(42)
    written = strings(0, 1);
    acquiredAt = opts.acquiredAt + minutes(40 * (0:5));
    isoAcquiredAt = string(acquiredAt, "yyyy-MM-dd'T'HH:mm:ss");
    jcampAcquiredAt = string(acquiredAt, "yyyy/MM/dd HH:mm:ss");

    % --- XRD (.xy, "#" header) -------------------------------------------
    tt = (10:0.02:80).';
    y = 50 + 30 * rand(size(tt));
    for pk = [21.3 28.4 40.5 50.1 62.9]
        y = y + (800 * rand + 400) .* exp(-((tt - pk).^2) / (2 * 0.08^2));
    end
    written(end + 1) = localWriteSpectrum(fullfile(outDir, "xrd_SMP-2026-001.xy"), "#", [ ...
        "instrument: XRD-01 Rigaku MiniFlex"; "acquired_at: " + isoAcquiredAt(1); ...
        "anode: Cu"; "voltage_kV: 40"; ...
        "current_mA: 15"; "scan_speed_deg_min: 5"; "operator: operator-a"], tt, y);

    % --- Raman (.txt) --------------------------------------------------
    sh = (200:1:1800).';
    r = 100 + 10 * randn(size(sh));
    for pk = [520 950 1350 1580]
        r = r + (500 * rand + 200) .* exp(-((sh - pk).^2) / (2 * 8^2));
    end
    written(end + 1) = localWriteSpectrum(fullfile(outDir, "raman_SMP-2026-002.txt"), "#", [ ...
        "instrument: Raman-01 inVia"; "acquired_at: " + isoAcquiredAt(2); ...
        "laser_nm: 532"; "power_mW: 5"; ...
        "exposure_s: 10"; "accumulations: 3"; "operator: operator-b"], sh, r);

    % --- FTIR (.dx, "##" header) --------------------------------------
    wn = (4000:-2:400).';
    a = 0.02 + 0.01 * rand(size(wn));
    for pk = [3400 2920 1720 1600 1100]
        a = a + (0.6 * rand + 0.2) .* exp(-((wn - pk).^2) / (2 * 25^2));
    end
    written(end + 1) = localWriteSpectrum(fullfile(outDir, "ftir_SMP-2026-003.dx"), "##", [ ...
        "TITLE= FTIR SMP-2026-003"; "instrument= FTIR-01 Nicolet iS50"; ...
        "LONGDATE= " + jcampAcquiredAt(3); ...
        "resolution_cm= 4"; "scans= 32"; "mode= ATR"; "operator= operator-b"], wn, a);

    % --- NMR (.dx) ---------------------------------------------------
    ppm = (12:-0.001:-1).';
    sig = 0.5 + 0.2 * randn(size(ppm));
    centres = [7.26 3.68 2.10 1.25];
    heights = [1200 800 1500 3000];
    for i = 1:numel(centres)
        sig = sig + heights(i) * (0.005^2) ./ ((ppm - centres(i)).^2 + 0.005^2) * 0.02;
    end
    written(end + 1) = localWriteSpectrum(fullfile(outDir, "nmr_SMP-2026-004.dx"), "##", [ ...
        "TITLE= 1H NMR SMP-2026-004"; "instrument= NMR-400 JEOL ECZ"; ...
        "LONGDATE= " + jcampAcquiredAt(4); ...
        "nucleus= 1H"; "frequency_MHz= 399.78"; "solvent= CDCl3"; ...
        "scans= 16"; "temperature_K= 298"; "operator= operator-c"], ppm, sig);

    % --- LC-MS chromatogram (.csv, [TRACE]/[PEAKS]) ------------------
    t = (0:0.01:12).';
    ic = 500 + 50 * randn(size(t));
    rt    = [1.83 2.71 5.44 8.90];
    area  = [12000 8000 15000 6000];
    sigma = [0.05 0.06 0.07 0.05];
    names = ["caffeine" "theobromine" "compound_X" "compound_Y"];
    for i = 1:numel(rt)
        ic = ic + area(i) .* exp(-((t - rt(i)).^2) / (2 * sigma(i)^2));
    end
    written(end + 1) = localWriteChromatogram(fullfile(outDir, "lcms_SMP-2026-005.csv"), [ ...
        "instrument: LCMS-01 Q-Exactive"; "acquired_at: " + isoAcquiredAt(5); ...
        "method: gradient_5-95_ACN_12min"; ...
        "column: C18 2.1x100mm 1.7um"; "flow_mL_min: 0.3"; "operator: operator-d"], ...
        t, ic, rt, area, sigma, names);

    % --- SEM image (.png + sidecar) -------------------------------
    [xx, yy] = meshgrid(linspace(-3, 3, 1024), linspace(-3, 3, 768));
    g = 0.5 + 0.35 * sin(3 * xx) .* cos(2 * yy) + 0.12 * randn(768, 1024);
    g = (g - min(g(:))) / (max(g(:)) - min(g(:)));
    semPath = fullfile(outDir, "sem_SMP-2026-006.png");
    imwrite(uint8(255 * g), semPath, "ImageModTime", acquiredAt(6));
    writelines([ ...
        "instrument: SEM-01 JSM-IT800"; "acquired_at: " + isoAcquiredAt(6); ...
        "hv_kV: 15"; "wd_mm: 10.2"; ...
        "magnification: 5000"; "detector: SE"; "pixel_size_nm: 24.5"; ...
        "operator: operator-a"], fullfile(outDir, "sem_SMP-2026-006_meta.txt"));
    written(end + 1) = string(semPath);

    files = written;
    logInfo("writeMockRuns: wrote %d mock files to %s", numel(files), outDir);
end

% ---------------------------------------------------------------------------

function path = localWriteSpectrum(path, marker, headerLines, x, y)
    % NOTE: fprintf here targets a file id (fid), i.e. file writing, not
    % console logging. Console logging uses the src/util log helpers.
    fid = fopen(path, "w");
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for i = 1:numel(headerLines)
        fprintf(fid, "%s %s\n", marker, headerLines(i));
    end
    if marker == "##"
        fprintf(fid, "##XYPOINTS= (XY..XY)\n");
    else
        fprintf(fid, "# --- data: x y ---\n");
    end
    fprintf(fid, "%.6g %.6g\n", [x, y].');
    path = string(path);
end

function path = localWriteChromatogram(path, headerLines, t, ic, rt, area, sigma, names)
    fid = fopen(path, "w");
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for i = 1:numel(headerLines)
        fprintf(fid, "# %s\n", headerLines(i));
    end
    fprintf(fid, "[TRACE]\ntime_min,intensity\n");
    fprintf(fid, "%.4f,%.2f\n", [t, ic].');
    fprintf(fid, "[PEAKS]\nrt_min,area,height,name\n");
    for i = 1:numel(rt)
        h = area(i) / (sigma(i) * sqrt(2 * pi));
        fprintf(fid, "%.3f,%.1f,%.1f,%s\n", rt(i), area(i), h, names(i));
    end
    path = string(path);
end
