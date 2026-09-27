function nmrData = calcAxes(nmrData)
% nmr.util.calcAxes - Compute ppm and Hz axes from nmrData params (idempotent)
%
% Recalculates spec.ppm and spec.hz from params without modifying spec.data.
% Call this after any change to params.ref_ppm, params.sw_hz, or params.bf.
%
% Usage:
%   nmrData = nmr.util.calcAxes(nmrData);
%
% Axes formulae (see docs/nmr_data_spec.md sec.3):
%   hz  = linspace(sw_hz/2, -sw_hz/2, npts)
%   ppm = hz / bf + ref_ppm
%
% See also: nmr.processing.setReference, nmr.util.detectVendor

    sw   = nmrData.params.sw_hz;
    npts = nmrData.params.npts;
    bf   = nmrData.params.bf;
    ref  = nmrData.params.ref_ppm;

    % F2 axes (Hz and ppm) -- column vectors
    nmrData.spec.hz  = linspace(sw/2, -sw/2, npts)';
    nmrData.spec.ppm = nmrData.spec.hz / bf + ref;

    % F1 axes (2D only -- uses params.*_f1 fields set by parsers/doFFT2D)
    if isfield(nmrData.params, 'sw_hz_f1') && ...
       isfield(nmrData.params, 'npts_f1') && isfield(nmrData.params, 'bf_f1')

        sw_f1   = nmrData.params.sw_hz_f1;
        npts_f1 = nmrData.params.npts_f1;
        bf_f1   = nmrData.params.bf_f1;
        ref_f1  = 0;
        if isfield(nmrData.params, 'ref_ppm_f1')
            ref_f1 = nmrData.params.ref_ppm_f1;
        end

        nmrData.spec.hz_f1  = linspace(sw_f1/2, -sw_f1/2, npts_f1)';
        nmrData.spec.ppm_f1 = nmrData.spec.hz_f1 / bf_f1 + ref_f1;
    end
end
