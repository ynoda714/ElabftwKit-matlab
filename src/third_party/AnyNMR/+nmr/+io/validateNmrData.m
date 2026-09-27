function validateNmrData(nmrData)
% nmr.io.validateNmrData - Validate nmrData structure against spec
%
% Usage:
%   nmr.io.validateNmrData(nmrData);
%
% Throws error() if any required field is missing or has wrong type.
% See docs/nmr_data_spec.md for full specification.
% ADR-025: raw.fid may be empty when proc.isFT=true (spectrum input mode).
% ADR-026: info.vendor now accepts 'JCAMP-DX' and 'nmrML'.
%
% See also: nmr.io.loadBruker, nmr.io.loadVarian, nmr.io.loadJeol,
%           nmr.io.loadJcampDx, nmr.io.loadNmrMl

    %% 1. Required fields existence
    requiredFields = {
        'raw.fid',      'raw.dim',       'raw.time', ...
        'params.bf',    'params.sw_hz',  'params.npts', ...
        'params.nucleus', 'params.ref_ppm', ...
        'proc.isFT',   'proc.isPhased', ...
        'info.vendor',  'info.source_path'
    };

    for i = 1:numel(requiredFields)
        checkNestedField(nmrData, requiredFields{i});
    end

    %% 1b. Valid vendor check (ADR-026)
    validVendors = {'JEOL', 'Bruker', 'Varian', 'JCAMP-DX', 'nmrML'};
    if ~any(strcmp(nmrData.info.vendor, validVendors))
        error('nmr:validate:unknownVendor', ...
            'info.vendor "%s" is not a recognised value. Valid: %s', ...
            nmrData.info.vendor, strjoin(validVendors, ', '));
    end
    if isfield(nmrData.info, 'orig_vendor') && ~ischar(nmrData.info.orig_vendor) && ~isstring(nmrData.info.orig_vendor)
        error('nmr:validate:origVendorType', 'info.orig_vendor must be char or string');
    end

    %% 2. Spectrum input mode detection (ADR-025)
    % When proc.isFT=true AND raw.fid is empty, this is spectrum input mode.
    isSpectrumInput = nmrData.proc.isFT && isempty(nmrData.raw.fid);

    if ~isSpectrumInput
        %% 2a. FID mode: type checks
        if ~isnumeric(nmrData.raw.fid) || ~isa(nmrData.raw.fid, 'double')
            error('nmr:validate:fidType', 'raw.fid must be complex double, got %s', class(nmrData.raw.fid));
        end
        % P06 fix: detect truly real FID *and* complex-typed-but-zero-imaginary FID.
        if isreal(nmrData.raw.fid) || all(imag(nmrData.raw.fid(:)) == 0)
            nmr.util.log.warn('raw.fid has no imaginary component; expected complex FID from parser');
        end

        %% 2b. Physical validity: Inf/NaN and energy checks
        if any(~isfinite(nmrData.raw.fid(:)))
            nBad = sum(~isfinite(nmrData.raw.fid(:)));
            error('nmr:validate:fidInfNaN', ...
                'raw.fid contains %d non-finite values (Inf or NaN)', nBad);
        end
        fidRms = rms(abs(nmrData.raw.fid(:)));
        if fidRms == 0
            error('nmr:validate:fidAllZero', ...
                'raw.fid is all zeros (possible parser failure or empty acquisition)');
        end
    else
        %% 2c. Spectrum input mode: spec.data and spec.ppm must be present
        if ~isfield(nmrData, 'spec') || ~isfield(nmrData.spec, 'data') || isempty(nmrData.spec.data)
            error('nmr:validate:specDataMissing', ...
                'proc.isFT=true with empty raw.fid (spectrum input mode) requires spec.data');
        end
        if ~isfield(nmrData.spec, 'ppm') || isempty(nmrData.spec.ppm)
            error('nmr:validate:specPpmMissing', ...
                'proc.isFT=true with empty raw.fid (spectrum input mode) requires spec.ppm');
        end
    end

    if ~isnumeric(nmrData.params.bf) || nmrData.params.bf <= 0
        error('nmr:validate:bf', 'params.bf must be positive, got %.4f', nmrData.params.bf);
    end

    if ~isnumeric(nmrData.params.sw_hz) || nmrData.params.sw_hz <= 0
        error('nmr:validate:sw', 'params.sw_hz must be positive, got %.4f', nmrData.params.sw_hz);
    end

    if ~islogical(nmrData.proc.isFT)
        error('nmr:validate:isFT', 'proc.isFT must be logical');
    end

    if ~islogical(nmrData.proc.isPhased)
        error('nmr:validate:isPhased', 'proc.isPhased must be logical');
    end

    %% 3. Dimension checks (only for FID mode)
    if ~isSpectrumInput
        if nmrData.raw.dim == 1
            % Valid column counts:
            %   1             - standard 1D or averaged/concatenated multi-block
            %   nblocks       - arrayed 1D (each block = separate FID, e.g. J-03 T1 IR)
            nCols   = size(nmrData.raw.fid, 2);
            nblocks = 1;
            if isfield(nmrData.raw, 'nblocks') && nmrData.raw.nblocks > 1
                nblocks = nmrData.raw.nblocks;
            end
            validCols = (nCols == 1) || (nblocks > 1 && nCols == nblocks);
            if ~validCols
                error('nmr:validate:dim1D', ...
                    'raw.dim=1 but raw.fid has %d columns (expected 1 or %d=nblocks)', ...
                    nCols, nblocks);
            end
        elseif nmrData.raw.dim == 2
            if size(nmrData.raw.fid, 2) <= 1
                error('nmr:validate:dim2D', ...
                    'raw.dim=2 but raw.fid has %d columns (expected >1)', size(nmrData.raw.fid, 2));
            end
            % ADR-005: 2D data must carry all _f1 fields (params.*_f1 naming rule).
            % Exception: DOSY experiments are pseudo-2D (raw.grad is set);
            %   the gradient dimension is not a spectral F1 axis, so _f1 params
            %   are not required (and would be meaningless).
            isDosyPseudo2D = isfield(nmrData.raw, 'grad') && ~isempty(nmrData.raw.grad);
            if ~isDosyPseudo2D
                required_f1 = {'bf_f1', 'sw_hz_f1', 'npts_f1', 'nucleus_f1', 'fnmode_f1', 'ref_ppm_f1'};
                for k = 1:numel(required_f1)
                    if ~isfield(nmrData.params, required_f1{k})
                        error('nmr:validate:missingF1Field', ...
                            '2D data is missing required F1 parameter: params.%s', required_f1{k});
                    end
                end
                if nmrData.params.bf_f1 <= 0
                    error('nmr:validate:bf_f1', 'params.bf_f1 must be positive, got %.4f', nmrData.params.bf_f1);
                end
                if nmrData.params.sw_hz_f1 <= 0
                    error('nmr:validate:sw_f1', 'params.sw_hz_f1 must be positive, got %.4f', nmrData.params.sw_hz_f1);
                end
            end
        end
    end

    %% 4. Data point count
    if ~isSpectrumInput
        if size(nmrData.raw.fid, 1) ~= nmrData.params.npts
            error('nmr:validate:npts', ...
                'size(raw.fid,1)=%d != params.npts=%d', ...
                size(nmrData.raw.fid, 1), nmrData.params.npts);
        end
    else
        % Spectrum input mode: npts matches spec.data size
        if isfield(nmrData, 'spec') && isfield(nmrData.spec, 'data') && ~isempty(nmrData.spec.data)
            if numel(nmrData.spec.data) ~= nmrData.params.npts
                error('nmr:validate:nptsSpectrum', ...
                    'numel(spec.data)=%d != params.npts=%d', ...
                    numel(nmrData.spec.data), nmrData.params.npts);
            end
        end
    end

    %% 5. Processing state initial values (for parser output)
    % For spectrum input mode (proc.isFT=true), isFT=true is expected - no WARN.
    % For FID mode, proc.isFT should be false after parsing.
    if ~isSpectrumInput && nmrData.proc.isFT
        nmr.util.log.warn('validateNmrData: proc.isFT is true (expected false for raw FID data)');
    end

    %% 6. ppm range sanity (P09: nucleusTable-based, covers 1H/13C/19F/31P/15N/etc.)
    ppmRange = nmrData.params.sw_hz / nmrData.params.bf;
    nucleus  = nmrData.params.nucleus;
    if nmr.util.nucleusTable.isKnown(nucleus)
        info = nmr.util.nucleusTable.get(nucleus);
        expectedPpmSpan = info.ppm_max - info.ppm_min;
        if ppmRange > expectedPpmSpan * 3
            nmr.util.log.warn( ...
                'Suspicious ppm range for %s: %.1f ppm (expected <=%.0f)', ...
                nucleus, ppmRange, expectedPpmSpan * 3);
        end
        bfMin = info.gamma_rel * 60;
        bfMax = info.gamma_rel * 1400;
        if nmrData.params.bf < bfMin || nmrData.params.bf > bfMax
            nmr.util.log.warn( ...
                'Suspicious BF for %s: %.1f MHz (expected %.0f-%.0f)', ...
                nucleus, nmrData.params.bf, bfMin, bfMax);
        end
    end

    %% 7. spec.ppm axis direction check (if FT already done)
    if isfield(nmrData, 'spec') && isfield(nmrData.spec, 'ppm') && numel(nmrData.spec.ppm) > 1
        if nmrData.spec.ppm(1) < nmrData.spec.ppm(end)
            error('nmr:validate:ppmDirection', ...
                'spec.ppm must be descending (high->low ppm, downfield->upfield), got %.2f->%.2f', ...
                nmrData.spec.ppm(1), nmrData.spec.ppm(end));
        end
    end

    %% 8. assignments structure validation (ADR-027; optional field)
    if isfield(nmrData, 'assignments') && ~isempty(nmrData.assignments)
        validateAssignments_(nmrData.assignments);
    end

    nmr.util.log.debug('Validation passed: %d fields OK', numel(requiredFields));
end

%% --- Local functions ---

function validateAssignments_(assignments)
% validateAssignments_  Check that every assignments entry has the ADR-027 minimum fields.
    requiredAssignFields = {'peak_id', 'atom_label', 'source', 'notes'};
    for k = 1:numel(assignments)
        for j = 1:numel(requiredAssignFields)
            fname = requiredAssignFields{j};
            if ~isfield(assignments(k), fname)
                error('nmr:validate:assignmentsMissingField', ...
                    'assignments(%d).%s is missing (ADR-027)', k, fname);
            end
            if ~ischar(assignments(k).(fname)) && ~isstring(assignments(k).(fname))
                error('nmr:validate:assignmentsFieldType', ...
                    'assignments(%d).%s must be char or string, got %s (ADR-027)', ...
                    k, fname, class(assignments(k).(fname)));
            end
        end
    end
end

function checkNestedField(s, fieldPath)
    parts = strsplit(fieldPath, '.');
    current = s;
    for i = 1:numel(parts)
        if ~isstruct(current) || ~isfield(current, parts{i})
            error('nmr:validate:missingField', ...
                'Required field missing: %s', fieldPath);
        end
        current = current.(parts{i});
    end
end
