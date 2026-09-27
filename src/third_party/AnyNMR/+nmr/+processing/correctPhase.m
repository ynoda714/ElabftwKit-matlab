function nmrData = correctPhase(nmrData, ph0, ph1, varargin)
% nmr.processing.correctPhase - Apply manual zero- and first-order phase correction
%
% Usage:
%   nmrData = nmr.processing.correctPhase(nmrData, ph0, ph1);
%   nmrData = nmr.processing.correctPhase(nmrData, ph0, ph1, 'pivot', 0.5);
%
% Inputs:
%   ph0   - Zero-order phase correction (degrees)
%   ph1   - First-order phase correction (degrees, total across the spectrum)
%
% Options (Name-Value):
%   'pivot'  (numeric in [0,1], default 0.5)
%            Pivot point for ph1 as a fraction of the spectrum width.
%            0   = left edge (index 1, highest ppm / downfield)
%            0.5 = center (default; matches TopSpin/MestReNova convention, ADR-012)
%            1   = right edge (lowest ppm / upfield)
%            Phase formula: phi(n) = (ph0 + ph1*(n/N - pivot)) * pi/180
%
% Notes:
%   - Requires proc.isFT = true
%   - Modifies spec.data in-place (raw.fid is preserved)
%   - Accumulates into proc.ph0 and proc.ph1 (additive)
%   - Sets proc.isPhased = true
%
% See also: nmr.processing.autoPhase, nmr.processing.correctPhaseF1

    if ~nmrData.proc.isFT
        error('nmr:processing:correctPhase:notFT', ...
            'correctPhase requires proc.isFT = true. Call doFFT first.');
    end

    p = inputParser;
    addParameter(p, 'pivot', 0.5, @(x) isnumeric(x) && x >= 0 && x <= 1);
    parse(p, varargin{:});
    pivot = p.Results.pivot;

    N = size(nmrData.spec.data, 1);
    n = (0:N-1)';

    % Phase vector (radians): phi(n) = (ph0 + ph1*(n/N - pivot)) * deg2rad
    phi = (ph0 + ph1 .* (n/N - pivot)) .* (pi/180);

    nmrData.spec.data = nmrData.spec.data .* exp(1i .* phi);

    % Accumulate phase parameters
    nmrData.proc.ph0      = nmrData.proc.ph0 + ph0;
    nmrData.proc.ph1      = nmrData.proc.ph1 + ph1;
    nmrData.proc.isPhased = true;

    %% Append history
    entry.operation = 'correctPhase';
    entry.params    = struct('ph0', ph0, 'ph1', ph1, 'pivot', pivot);
    entry.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    if ~isfield(nmrData.proc, 'history') || isempty(nmrData.proc.history)
        nmrData.proc.history = entry;
    else
        nmrData.proc.history(end+1) = entry;
    end

    nmr.util.log.info('correctPhase: ph0=%.2fdeg, ph1=%.2fdeg, pivot=%.2f', ph0, ph1, pivot);
end
