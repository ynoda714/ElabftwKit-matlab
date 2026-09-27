function nmrData = loadBruker(dataPath)
% nmr.io.loadBruker - Load Bruker NMR data from experiment folder
%
% Usage:
%   nmrData = nmr.io.loadBruker('path/to/bruker/1');
%
% Input:
%   dataPath - Bruker experiment folder containing 'fid' and 'acqus'
%              (typically the numbered experiment directory, e.g., .../1/)
%
% Output:
%   nmrData - Standard nmrData structure (see docs/nmr_data_spec.md)
%
% The GRPDLY digital filter correction is applied inside this parser so
% that raw.fid contains a clean FID ready for FFT (ADR-002).
%
% See also: nmr.io.loadVarian, nmr.io.loadJeol, nmr.io.loadJcampDx,
%           nmr.io.loadNmrMl, nmr.io.validateNmrData

    dataPath = char(dataPath);

    if ~isfolder(dataPath)
        error('nmr:io:loadBruker:notFound', 'Folder not found: %s', dataPath);
    end

    acqusFile  = fullfile(dataPath, 'acqus');
    fidFile    = fullfile(dataPath, 'fid');
    serFile    = fullfile(dataPath, 'ser');
    acqu2sFile = fullfile(dataPath, 'acqu2s');

    if ~isfile(acqusFile)
        error('nmr:io:loadBruker:noAcqus', 'acqus file not found in: %s', dataPath);
    end

    % --- Auto-detect 1D vs 2D ---
    is2D = isfile(serFile) && isfile(acqu2sFile);

    if is2D
        nmrData = load2D(dataPath, acqusFile, acqu2sFile, serFile);
    else
        nmrData = load1D(dataPath, acqusFile, fidFile);
    end
end

%% ====================================================================
%  load1D - Load 1D Bruker experiment (fid + acqus)
%  ====================================================================
function nmrData = load1D(dataPath, acqusFile, fidFile)

    if ~isfile(fidFile)
        hasAcqus = isfile(acqusFile);
        dirInfo  = dir(dataPath);
        fileNames = sort({dirInfo(~[dirInfo.isdir]).name});
        if isempty(fileNames)
            filesStr = '(directory is empty)';
        else
            filesStr = strjoin(fileNames, ', ');
        end
        error('nmr:io:loadBruker:noFid', ...
            ['fid file not found in: %s\n' ...
             '  acqus present : %s\n' ...
             '  directory contents: %s'], ...
            dataPath, mat2str(hasAcqus), filesStr);
    end

    % --- Parse acqus ---
    params = parseAcqus(acqusFile);
    nmr.util.log.debug('acqus parsed: BF1=%.6f MHz, SW_h=%.2f Hz, TD=%d, GRPDLY=%.4f', ...
        params.BF1, params.SW_h, params.TD, params.GRPDLY);

    % --- Read fid binary ---
    [fidRaw, dtypa] = readBrukerFid(fidFile, params);
    nmr.util.log.debug('FID binary: TD=%d, DTYPA=%d, npts_complex=%d', ...
        params.TD, dtypa, size(fidRaw, 1));

    % --- GRPDLY correction (parser-internal, ADR-002) ---
    [fidClean, grpdlyCorrected] = correctGrpdly(fidRaw, params.GRPDLY);

    nComplexPts = size(fidClean, 1);

    % --- Build nmrData ---
    nmrData.raw.fid     = fidClean;
    nmrData.raw.dim     = 1;
    at                  = params.TD / (2 * params.SW_h);
    nmrData.raw.time    = linspace(0, at, nComplexPts)';
    nmrData.raw.nblocks = 1;
    nmrData.raw.ntraces = 1;

    nmrData.spec = struct();

    nmrData.params.bf      = params.BF1;
    nmrData.params.sw_hz   = params.SW_h;
    nmrData.params.npts    = nComplexPts;
    nmrData.params.nucleus = normalizeNucleus(params.NUC1);
    % CAL-02 (1D): Use O1 carrier offset for absolute ppm axis, consistent with
    % the 2D treatment.  ppm = hz/BF1 + ref_ppm; with ref_ppm = O1/BF1 the axis
    % centre equals the actual irradiation frequency (e.g. ~4.7 ppm for H2O
    % presaturation experiments).  Synthetic acqus files omit O1; isfield guard
    % keeps ref_ppm=0 for them so existing unit tests are unaffected.
    if isfield(params, 'O1') && ~isnan(params.O1)
        nmrData.params.ref_ppm = params.O1 / params.BF1;
    else
        nmrData.params.ref_ppm = 0;
    end
    nmrData.params.grpdly  = params.GRPDLY;
    nmrData.params.at      = at;

    if isfield(params, 'SOLVENT')
        nmrData.params.solvent = params.SOLVENT;
    end
    if isfield(params, 'TE')
        nmrData.params.temp = params.TE;
    end
    % D-3 Phase 1 (ADR-014): store repetition delay d1 and excitation pulse width pw
    % Bruker acqus uses 0-indexed arrays: D[1]=d1 (MATLAB: D(2)), P[1]=p1 (MATLAB: P(2))
    if isfield(params, 'D') && numel(params.D) >= 2
        nmrData.params.d1 = params.D(2);  % D[1] = repetition delay (s)
    end
    if isfield(params, 'P') && numel(params.P) >= 2
        nmrData.params.pw = params.P(2);  % P[1] = excitation pulse width (us)
    end

    nmrData.proc.isFT              = false;
    nmrData.proc.isPhased          = false;
    nmrData.proc.ph0               = 0;
    nmrData.proc.ph1               = 0;
    nmrData.proc.grpdly_corrected  = grpdlyCorrected;

    nmrData.info.vendor      = 'Bruker';
    nmrData.info.source_path = dataPath;
    if isfield(params, 'PULPROG')
        nmrData.info.experiment = params.PULPROG;
    end
    nmrData.info.orig_header = params;

    nmr.io.validateNmrData(nmrData);

    nmr.util.log.info('Bruker 1D loaded: %s (%d pts, %s, %.1f MHz)', ...
        dataPath, nComplexPts, nmrData.params.nucleus, params.BF1);
end

%% ====================================================================
%  load2D - Load 2D Bruker experiment (ser + acqus + acqu2s)
%  ====================================================================
function nmrData = load2D(dataPath, acqusFile, acqu2sFile, serFile)

    % --- Parse F2 (acqus) and F1 (acqu2s) ---
    paramsF2 = parseAcqus(acqusFile);
    paramsF1 = parseAcqus(acqu2sFile);

    nF2 = paramsF2.TD / 2;   % complex points in F2
    nF1 = paramsF1.TD;        % number of t1 increments

    nmr.util.log.info( ...
        'Bruker 2D: acqus BF1=%.4f MHz, SW_h=%.2f Hz, TD=%d; acqu2s TD=%d, FnMODE=%d', ...
        paramsF2.BF1, paramsF2.SW_h, paramsF2.TD, paramsF1.TD, ...
        getfield_safe(paramsF1, 'FnMODE', 0));

    % --- Read ser binary (nF2 x nF1 complex) ---
    % Pass XDIM for de-tiling support (P02: Bruker XDIM sub-matrix handling)
    fidMatrix = readBrukerSer(serFile, paramsF2, paramsF1);

    % --- GRPDLY correction: apply to each F2 row (each t1 increment) ---
    [fidMatrix, grpdlyCorrected] = correctGrpdly2D(fidMatrix, paramsF2.GRPDLY);

    atF2 = paramsF2.TD / (2 * paramsF2.SW_h);
    atF1 = nF1 / paramsF1.SW_h;

    % --- Build nmrData ---
    nmrData.raw.fid     = fidMatrix;   % (nF2 x nF1) complex
    nmrData.raw.dim     = 2;
    nmrData.raw.time    = linspace(0, atF2, nF2)';
    nmrData.raw.time2   = linspace(0, atF1, nF1)';
    nmrData.raw.nblocks = nF1;
    nmrData.raw.ntraces = 1;

    nmrData.spec = struct();

    % F2 params (params.*)
    nmrData.params.bf      = paramsF2.BF1;
    nmrData.params.sw_hz   = paramsF2.SW_h;
    nmrData.params.npts    = nF2;
    nmrData.params.nucleus = normalizeNucleus(paramsF2.NUC1);
    % CAL-02: Use O1 carrier offset for absolute F2 ppm axis (Hz/MHz = ppm).
    % Synthetic acqus files omit O1; isfield guard keeps ref_ppm=0 for them.
    if isfield(paramsF2, 'O1') && ~isnan(paramsF2.O1)
        nmrData.params.ref_ppm = paramsF2.O1 / paramsF2.BF1;
    else
        nmrData.params.ref_ppm = 0;
    end
    nmrData.params.grpdly  = paramsF2.GRPDLY;
    nmrData.params.at      = atF2;

    if isfield(paramsF2, 'SOLVENT')
        nmrData.params.solvent = paramsF2.SOLVENT;
    end
    if isfield(paramsF2, 'TE')
        nmrData.params.temp = paramsF2.TE;
    end
    % D-3 Phase 1 (ADR-014): store repetition delay d1 and excitation pulse width pw (2D)
    if isfield(paramsF2, 'D') && numel(paramsF2.D) >= 2
        nmrData.params.d1 = paramsF2.D(2);
    end
    if isfield(paramsF2, 'P') && numel(paramsF2.P) >= 2
        nmrData.params.pw = paramsF2.P(2);
    end

    % F1 params (params.*_f1)
    nmrData.params.bf_f1      = paramsF1.BF1;
    nmrData.params.sw_hz_f1   = paramsF1.SW_h;
    nmrData.params.npts_f1    = nF1;
    nmrData.params.ni_f1      = nF1;
    nmrData.params.nucleus_f1 = normalizeNucleus(paramsF1.NUC1);
    fnModeCode = getfield_safe(paramsF1, 'FnMODE', 0);
    nmrData.params.fnmode_f1  = decodeFnMode(fnModeCode);
    % CAL-02 (rev.ISSUE-S08-01): Use acqu2s O1 for absolute F1 ppm axis.
    % acqu2s.O1 is the carrier offset (Hz) for the F1 nucleus, regardless of
    % which physical channel it occupies (e.g. channel 3 for 15N in triple-
    % channel experiments).  The former acqus.O2 approach was incorrect for
    % 3-channel experiments (1H/13C/15N) where O2 = 13C offset, not 15N.
    if isfield(paramsF1, 'O1') && ~isnan(paramsF1.O1)
        nmrData.params.ref_ppm_f1 = paramsF1.O1 / paramsF1.BF1;
    else
        nmrData.params.ref_ppm_f1 = 0;
    end

    nmrData.proc.isFT              = false;
    nmrData.proc.isPhased          = false;
    nmrData.proc.ph0               = 0;
    nmrData.proc.ph1               = 0;
    nmrData.proc.grpdly_corrected  = grpdlyCorrected;

    nmrData.info.vendor      = 'Bruker';
    nmrData.info.source_path = dataPath;
    if isfield(paramsF2, 'PULPROG')
        nmrData.info.experiment = paramsF2.PULPROG;
    end
    nmrData.info.orig_header = paramsF2;

    % --- DOSY mode detection (ADR-030) ---
    % difflist: gradient strength list (G/cm). Present in DOSY experiments.
    % vdlist: variable-delay list (T1/T2 arrayed); not a gradient list — skip.
    difflistFile = fullfile(dataPath, 'difflist');
    if isfile(difflistFile)
        nmrData = attachDosyParams(nmrData, difflistFile, paramsF2);
    end

    nmr.io.validateNmrData(nmrData);

    nmr.util.log.info('Bruker 2D loaded: %s (%dx%d, %s/%s, %.1f MHz)', ...
        dataPath, nF2, nF1, nmrData.params.nucleus, nmrData.params.nucleus_f1, paramsF2.BF1);
end

%% ====================================================================
%  parseAcqus - Parse Bruker acqus parameter file
%  ====================================================================
function params = parseAcqus(filepath)
    fid = fopen(filepath, 'r', 'n', 'UTF-8');
    if fid == -1
        error('nmr:io:loadBruker:cantOpenAcqus', 'Cannot open acqus: %s', filepath);
    end
    cleanupObj = onCleanup(@() fclose(fid));

    params = struct();

    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line); break; end
        line = strtrim(line);

        % Bruker acqus format:
        %   ##$PARAMNAME= value
        %   ##$PARAMNAME= (0..N-1)
        %   <list values on next lines>
        if ~startsWith(line, '##$')
            continue;
        end

        eqIdx = find(line == '=', 1);
        if isempty(eqIdx); continue; end

        rawName = strtrim(line(4:eqIdx-1));
        valStr  = strtrim(line(eqIdx+1:end));

        fieldName = matlab.lang.makeValidName(rawName);

        if startsWith(valStr, '(')
            % Array parameter: skip (read raw values below)
            nItems = parseArrayCount(valStr);
            arrVals = readAcqusArray(fid, nItems);
            params.(fieldName) = arrVals;
        elseif startsWith(valStr, '<')
            % String value: <text>
            params.(fieldName) = extractAngle(valStr);
        else
            % Scalar numeric or string
            numVal = str2double(valStr);
            if ~isnan(numVal)
                params.(fieldName) = numVal;
            else
                params.(fieldName) = valStr;
            end
        end
    end

    % --- Ensure required fields exist with sensible defaults ---
    if ~isfield(params, 'GRPDLY') || isnan(params.GRPDLY) || params.GRPDLY <= 0
        params.GRPDLY = 0;
    end
    if ~isfield(params, 'DTYPA')
        % P10: DTYPA absent in some TopSpin 4.x acqus files.
        % Float64 instruments may omit this field; warn so operators can investigate.
        nmr.util.log.warn('acqus: DTYPA not found; defaulting to int32 (DTYPA=0). Float64 instruments may produce garbled FID.');
        params.DTYPA = 0;   % default int32
    end
    if ~isfield(params, 'BYTORDA')
        params.BYTORDA = 0; % default little-endian
    end
    if ~isfield(params, 'XDIM') || isnan(params.XDIM)
        params.XDIM = 0;    % 0 = default (no tiling)
    end
end

%% ====================================================================
%  readBrukerFid - Read Bruker fid binary file
%  ====================================================================
function [fidData, dtypa] = readBrukerFid(filepath, params)
    % BYTORDA: 0 = little-endian, 1 = big-endian
    if params.BYTORDA == 1
        byteOrder = 'ieee-be';
    else
        byteOrder = 'ieee-le';
    end

    % DTYPA: 0 = int32, 2 = float64
    dtypa = params.DTYPA;
    if dtypa == 2
        precision = 'float64';
        bytesPerSample = 8;
    else
        precision = 'int32';
        bytesPerSample = 4;
    end

    % P10: heuristic float64 detection when DTYPA=0 but file is clearly too large.
    % Bruker pads to 256-byte blocks, so int32 max size ~ TD*4 + 252 bytes.
    % If file size > TD*6, it cannot be int32 and is very likely float64.
    % Threshold TD*6 is safe for TD>=256 (all real NMR data).
    fileInfo = dir(filepath);
    if dtypa == 0 && fileInfo.bytes > params.TD * 6
        nmr.util.log.warn( ...  
            'DTYPA=0 (int32) but fid file size (%d B) greatly exceeds int32 expectation (%d B); switching to float64 (P10).', ...
            fileInfo.bytes, params.TD * 4);
        precision = 'float64';
        bytesPerSample = 8;
        dtypa = 2;
    end

    fid = fopen(filepath, 'rb', byteOrder);
    if fid == -1
        error('nmr:io:loadBruker:cantOpenFid', 'Cannot open fid: %s', filepath);
    end
    cleanupObj = onCleanup(@() fclose(fid));

    % Determine actual data size from file
    nTotalSamples = fileInfo.bytes / bytesPerSample;

    % TD = total real+imag points; read up to TD but respect file size
    nRead = min(params.TD, nTotalSamples);
    rawData = fread(fid, nRead, precision);

    % Bruker pads data to 256-byte blocks; rawData may be longer than TD
    % Use exactly TD points (already limited above) and zero-pad if shorter
    if numel(rawData) < params.TD
        rawData(end+1:params.TD) = 0;
    end

    rawData = double(rawData(1:params.TD));

    % Interleaved real/imag -> complex
    realPart = rawData(1:2:end);
    imagPart = rawData(2:2:end);
    fidData  = complex(realPart, imagPart);   % column vector (TD/2 x 1)
end

%% ====================================================================
%  correctGrpdly - Remove Bruker digital filter group delay
%  ====================================================================
function [fidOut, corrected] = correctGrpdly(fidIn, grpdly)
    if grpdly <= 0
        fidOut    = fidIn;
        corrected = false;
        return;
    end

    % Why round(grpdly)?
    %   GRPDLY stored in acqus is a rational number (e.g. 67.9833). The integer
    %   part maps to whole-sample positions in a circular left-shift.  The
    %   fractional remainder frac = grpdly - round(grpdly) is at most +/-0.5 sample.
    %   Residual phase error from the uncompensated fraction:
    %       Deltaphi(k) = 2pi * |frac| * k / N   (worst case at k = N-1)
    %   For frac = 0.5 and N = 8192:  Deltaphi_max ~ 0.044deg
    %   This is well below the phase-noise floor of a typical spectrum (>1deg),
    %   so frequency-domain correction exp(-1i*2pi*frac*k/N) is not justified.
    %   Conclusion (M3.7 P04, see ADR-002): integer shift only; frac correction skipped.
    shift    = round(grpdly);
    npts     = numel(fidIn);

    if shift >= npts
        nmr.util.log.warn('GRPDLY shift (%d) >= npts (%d); skipping correction', shift, npts);
        fidOut    = fidIn;
        corrected = false;
        return;
    end

    % Left-shift (remove leading digital filter artefact)
    fidOut    = fidIn([shift+1:end, 1:shift]);
    % Zero out the wrapped tail (formerly the leading artefact region)
    fidOut(end-shift+1:end) = 0;
    corrected = true;
end

%% ====================================================================
%  Helper functions
%% ====================================================================

function result = startsWith(str, prefix)
    result = numel(str) >= numel(prefix) && strcmp(str(1:numel(prefix)), prefix);
end

function n = parseArrayCount(valStr)
% Parse "(0..N-1)" -> N
    tokens = regexp(valStr, '\(0\.\.\s*(\d+)\)', 'tokens');
    if ~isempty(tokens)
        n = str2double(tokens{1}{1}) + 1;
    else
        n = 0;
    end
end

function vals = readAcqusArray(fid, nItems)
% Read numeric array values that follow a ##$PARAM= (0..N-1) line
    vals = zeros(1, nItems);
    idx  = 0;
    while idx < nItems && ~feof(fid)
        pos  = ftell(fid);          % save position before read
        line = fgetl(fid);
        if ~ischar(line); break; end
        line = strtrim(line);
        if isempty(line) || startsWith(line, '##') || startsWith(line, '$')
            fseek(fid, pos, 'bof'); % put back the ##$ / $ line so parseAcqus sees it
            break;
        end
        nums = str2num(line); %#ok<ST2NM>  % may be multi-value per line
        for k = 1:numel(nums)
            idx = idx + 1;
            if idx <= nItems
                vals(idx) = nums(k);
            end
        end
    end
    if nItems == 1
        vals = vals(1);   % return scalar for single-element arrays
    end
end

function s = extractAngle(text)
% Extract text between < and >
    q1 = find(text == '<', 1, 'first');
    q2 = find(text == '>', 1, 'last');
    if ~isempty(q1) && ~isempty(q2) && q2 > q1
        s = text(q1+1 : q2-1);
    else
        s = strtrim(text);
    end
end

function std = normalizeNucleus(brukerNucleus)
% Convert Bruker nucleus name to standard format
% Bruker: '1H', '13C', '15N', '31P' -- often already correct
% Some versions use: 'H1', 'C13' -- convert those too
    brukerNucleus = strtrim(brukerNucleus);
    % Remove leading/trailing < > if present
    brukerNucleus = strrep(brukerNucleus, '<', '');
    brukerNucleus = strrep(brukerNucleus, '>', '');
    brukerNucleus = strtrim(brukerNucleus);

    % Already in standard form (digit first): 1H, 13C, etc.
    if ~isempty(regexp(brukerNucleus, '^\d+[A-Za-z]+$', 'once'))
        std = brukerNucleus;
        return;
    end

    % Element-first form: H1 -> 1H, C13 -> 13C
    tokens = regexp(brukerNucleus, '^([A-Za-z]+)(\d+)$', 'tokens');
    if ~isempty(tokens)
        std = [tokens{1}{2} tokens{1}{1}];
    else
        std = brukerNucleus;
    end
end

%% ====================================================================
%  readBrukerSer - Read Bruker ser binary (2D FID matrix)
%  ====================================================================
function fidMatrix = readBrukerSer(serFile, paramsF2, paramsF1)
% Reads the Bruker `ser` file.
% Layout: TD(F1) rows x TD(F2) samples (int32 or float64, little-endian by default).
% Each row: interleaved real/imag -> complex (same as 1D fid).
%
% XDIM note (P02): When XDIM > 1, some old TopSpin / TS3.x instruments write the
% `ser` file in a tiled sub-matrix format, causing cross-peak position errors with
% naive sequential reshape.  Current implementation: WARN when XDIM > 1 and fall
% back to sequential reshape.  Full de-tiling to be added when reference data with
% XDIM > 1 becomes available.
%
% Returns: fidMatrix (nF2_complex x nF1) complex double

    if paramsF2.BYTORDA == 1
        byteOrder = 'ieee-be';
    else
        byteOrder = 'ieee-le';
    end

    if paramsF2.DTYPA == 2
        precision      = 'float64';
        bytesPerSample = 8;
    else
        precision      = 'int32';
        bytesPerSample = 4;
    end

    tdF2 = paramsF2.TD;   % real+imag samples per row
    tdF1 = paramsF1.TD;   % number of rows (t1 increments)

    % XDIM: sub-matrix tile size (0 or 1 = standard sequential storage)
    xdim = getfield_safe(paramsF2, 'XDIM', 0);
    if xdim > 1
        nmr.util.log.warn( ...
            ['Bruker ser: XDIM=%d detected. Old TopSpin tile format may cause ' ...
             'cross-peak position errors. Loaded with sequential reshape; ' ...
             'verify spectrum manually.'], xdim);
    end

    % Validate file size
    serInfo   = dir(serFile);
    availPts  = floor(serInfo.bytes / bytesPerSample);
    needed    = tdF2 * tdF1;

    if availPts < needed
        nmr.util.log.warn('ser file is smaller than expected: need %d pts, got %d. Padding with zeros.', needed, availPts);
    end

    fid = fopen(serFile, 'rb', byteOrder);
    if fid == -1
        error('nmr:io:loadBruker:cantOpenSer', 'Cannot open ser: %s', serFile);
    end
    c = onCleanup(@() fclose(fid));

    nRead   = min(needed, availPts);
    rawFlat = fread(fid, nRead, precision);
    rawFlat = double(rawFlat);

    % Zero-pad if needed
    if numel(rawFlat) < needed
        rawFlat(end+1:needed) = 0;
    end

    % Reshape to (tdF2 x tdF1): each column = one t1 increment FID (interleaved)
    rawMatrix = reshape(rawFlat(1:needed), tdF2, tdF1);

    % De-interleave: odd rows = real, even rows = imag
    realPart  = rawMatrix(1:2:end, :);   % (tdF2/2 x tdF1)
    imagPart  = rawMatrix(2:2:end, :);   % (tdF2/2 x tdF1)
    fidMatrix = complex(realPart, imagPart);  % (nF2_complex x nF1)
end

%% ====================================================================
%  correctGrpdly2D - Apply GRPDLY correction to each F2 trace of 2D FID
%  ====================================================================
function [fidOut, corrected] = correctGrpdly2D(fidMatrix, grpdly)
    if grpdly <= 0
        fidOut    = fidMatrix;
        corrected = false;
        return;
    end

    % See correctGrpdly (above) for the round(grpdly) rationale and fractional-part
    % evaluation (M3.7 P04, ADR-002). The same conclusion applies to every F2 row.
    shift = round(grpdly);
    nF2   = size(fidMatrix, 1);

    if shift >= nF2
        nmr.util.log.warn('GRPDLY shift (%d) >= nF2 (%d); skipping 2D correction', shift, nF2);
        fidOut    = fidMatrix;
        corrected = false;
        return;
    end

    % Vectorised circular left-shift of all F2 traces simultaneously
    fidOut = [fidMatrix(shift+1:end, :); fidMatrix(1:shift, :)];
    fidOut(end-shift+1:end, :) = 0;
    corrected = true;
end

%% ====================================================================
%  decodeFnMode - Convert Bruker FnMODE integer to string label
%  ====================================================================
function modeStr = decodeFnMode(code)
    labels = {'Undefined', 'QF', 'QSEQ', 'TPPI', 'States', 'States-TPPI', 'Echo-AntiEcho'};
    idx = double(code) + 1;   % 0-indexed -> 1-indexed
    if idx >= 1 && idx <= numel(labels)
        modeStr = labels{idx};
    else
        modeStr = sprintf('Unknown(%d)', double(code));
    end
end

%% ====================================================================
%  getfield_safe - Get struct field with fallback default
%  ====================================================================
function v = getfield_safe(s, fname, default)
    if isfield(s, fname)
        v = s.(fname);
    else
        v = default;
    end
end

%% ====================================================================
%  attachDosyParams - Attach DOSY-specific fields to nmrData (ADR-030)
%  ====================================================================
function nmrData = attachDosyParams(nmrData, difflistFile, params)
    % Read gradient list and convert G/cm -> T/m
    % Bruker difflist stores absolute gradient strengths in G/cm.
    % computeDosyB requires T/m.  Conversion: 1 G/cm = 0.01 T/m.
    gradGcm = readDifflist(difflistFile);
    if isempty(gradGcm)
        nmr.util.log.warn('DOSY: difflist is empty; raw.grad not set');
        return;
    end
    nmrData.raw.grad = gradGcm * 0.01;   % G/cm -> T/m

    % dosy_delta (small delta): gradient pulse duration (s)
    % Convention for most Bruker DOSY sequences: P[30] (acqus P array, 0-indexed).
    % For Doneshot / OneShot variants, each encoding bloc uses P[30] as the half-pulse,
    % so the effective delta = 2*P[30].  We store P[30]/1e6 (i.e. the single-pulse
    % duration) and note this in the log.  Full Stejskal-Tanner delta can be computed
    % at analysis time based on the pulse program.
    if isfield(params, 'P') && numel(params.P) >= 31
        nmrData.params.dosy_delta = params.P(31) / 1e6;   % P[30] (us) -> s
        nmr.util.log.debug('DOSY: dosy_delta = P[30]/1e6 = %.6f s (raw; for OneShot sequences effective delta = 2x)', ...
            nmrData.params.dosy_delta);
    else
        nmr.util.log.warn('DOSY: P[30] not found in acqus; dosy_delta not set. Set nmrData.params.dosy_delta manually.');
    end

    % dosy_Delta (big Delta): diffusion delay (s)
    % Convention: D[20] (acqus D array, 0-indexed) = diffusion time for
    % ledbpgp2s, stebpgp1s, and Doneshot family sequences.
    if isfield(params, 'D') && numel(params.D) >= 21
        nmrData.params.dosy_Delta = params.D(21);   % D[20] (s)
        nmr.util.log.debug('DOSY: dosy_Delta = D[20] = %.6f s', nmrData.params.dosy_Delta);
    else
        nmr.util.log.warn('DOSY: D[20] not found in acqus; dosy_Delta not set. Set nmrData.params.dosy_Delta manually.');
    end

    nGrad = numel(nmrData.raw.grad);
    nmr.util.log.info('DOSY mode: difflist -> %d gradient steps (%.3f..%.3f T/m)', ...
        nGrad, nmrData.raw.grad(1), nmrData.raw.grad(end));
end

%% ====================================================================
%  readDifflist - Read Bruker difflist / gradient list file
%  ====================================================================
function gradVals = readDifflist(filepath)
    % Read a Bruker difflist file: one floating-point value per line (G/cm).
    % Comment lines starting with '#' are skipped.
    fid_file = fopen(filepath, 'r');
    if fid_file == -1
        error('nmr:io:loadBruker:cantOpenDifflist', 'Cannot open difflist: %s', filepath);
    end
    cleanupObj = onCleanup(@() fclose(fid_file));

    gradVals = zeros(256, 1);   % pre-allocate (typical max nGrad)
    n = 0;
    while ~feof(fid_file)
        line = strtrim(fgetl(fid_file));
        if ~ischar(line) || isempty(line) || startsWith(line, '#')
            continue;
        end
        val = str2double(line);
        if ~isnan(val)
            n = n + 1;
            gradVals(n) = val;
        end
    end
    gradVals = gradVals(1:n);   % trim to actual count
end
