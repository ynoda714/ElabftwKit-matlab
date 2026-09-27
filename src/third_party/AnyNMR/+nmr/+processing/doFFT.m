function nmrData = doFFT(nmrData, varargin)
% nmr.processing.doFFT - Apply FFT to FID or iFFT to spectrum
%
% Usage:
%   nmrData = nmr.processing.doFFT(nmrData);
%   nmrData = nmr.processing.doFFT(nmrData, 'inverse', true);
%   nmrData = nmr.processing.doFFT(nmrData, 'firstPointCorr', true);
%
% Options (Name-Value):
%   'inverse'         (logical, false) - apply iFFT instead of FFT
%   'firstPointCorr'  (logical, true)  - divide first FID point by 2 before FFT
%                     to prevent a DC baseline offset (standard NMR correction)
%                     Default changed to true in M4.7 Phase B (ADR-013 / B-4).
%
% Notes:
%   - Forward FFT: reads proc.fid if present, else raw.fid -> writes spec.data
%   - Spectrum axis convention: index 1 = +sw/2 Hz (downfield / high ppm),
%     matching calcAxes: hz = linspace(sw/2, -sw/2, npts)
%     Implemented as: flip(fftshift(fft(fid)))
%   - calcAxes is automatically called after forward FFT to update ppm/hz axes
%   - iFFT: spec.data -> proc.fid  (raw.fid is never overwritten)
%   - proc.isFT is updated accordingly
%   - Processing history is appended to proc.history
%
% See also: nmr.processing.doFFT2D, nmr.processing.zeroFill,
%           nmr.processing.applyWindow, nmr.processing.autoPhase

    p = inputParser;
    addParameter(p, 'inverse',        false, @islogical);
    addParameter(p, 'firstPointCorr', true,  @islogical);  % B-4: default true (ADR-013)
    parse(p, varargin{:});
    doInverse = p.Results.inverse;
    fpCorr    = p.Results.firstPointCorr;

    % Vendor override: if the nmrData signals that firstPointCorr should be
    % skipped (e.g. JEOL after correctGrpdly, where FID(1) is not at t=0),
    % and the caller did not explicitly set firstPointCorr, disable it.
    if fpCorr && ~doInverse && ...
            ismember('firstPointCorr', p.UsingDefaults) && ...
            isfield(nmrData, 'proc') && ...
            isfield(nmrData.proc, 'first_point_corr_skip') && ...
            nmrData.proc.first_point_corr_skip
        fpCorr = false;
    end

    if doInverse
        %% ---- iFFT: spec.data -> proc.fid ----
        if ~nmrData.proc.isFT
            error('nmr:processing:doFFT:notFT', ...
                'proc.isFT is false; cannot apply iFFT to non-FT data');
        end
        % Inverse of flip(fftshift(fft(fid))) is ifft(ifftshift(flip(spec)))
        % Algebraically: ifft(ifftshift(flip(flip(fftshift(fft(fid)))))) = ifft(fft(fid)) = fid
        nmrData.proc.fid  = ifft(ifftshift(flip(nmrData.spec.data, 1), 1), [], 1);
        nmrData.proc.isFT = false;
        opName   = 'iFFT';
        opParams = struct('direction', 'inverse');
        nmr.util.log.info('doFFT: iFFT applied (%d pts)', size(nmrData.spec.data, 1));

    else
        %% ---- Forward FFT: fid -> spec.data ----
        if nmrData.proc.isFT
            nmr.util.log.warn('doFFT: proc.isFT is already true; reapplying FFT');
        end

        % Select FID source: windowed/ZF (proc.fid) takes precedence over raw
        if isfield(nmrData.proc, 'fid') && ~isempty(nmrData.proc.fid)
            fid = nmrData.proc.fid;
        else
            fid = nmrData.raw.fid;
        end

        % Optional first-point correction: divide FID(1) by 2
        % Prevents a flat DC baseline offset (1/2 of the DC component is removed)
        if fpCorr && size(fid, 1) >= 1
            fid(1, :) = fid(1, :) / 2;
        end

        N = size(fid, 1);

        % FFT with NMR convention: high ppm (downfield) at index 1
        % fftshift rearranges DC to center; flip reverses to match
        % hz = linspace(sw/2, -sw/2, N) from calcAxes
        nmrData.spec.data = flip(fftshift(fft(fid, [], 1), 1), 1);

        % Update point count and recompute ppm / hz axes
        nmrData.params.npts = N;
        nmrData.proc.isFT   = true;
        nmrData = nmr.util.calcAxes(nmrData);

        opName   = 'FFT';
        opParams = struct('firstPointCorr', fpCorr, 'npts', N);
        nmr.util.log.info('doFFT: FFT applied (%d pts)', N);
    end

    %% Append history
    entry.operation = opName;
    entry.params    = opParams;
    entry.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    if ~isfield(nmrData.proc, 'history') || isempty(nmrData.proc.history)
        nmrData.proc.history = entry;
    else
        nmrData.proc.history(end+1) = entry;
    end
end
