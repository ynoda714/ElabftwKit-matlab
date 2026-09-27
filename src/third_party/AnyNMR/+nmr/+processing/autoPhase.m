function nmrData = autoPhase(nmrData, varargin)
% nmr.processing.autoPhase - Automatic phase correction via entropy minimization
%
% Usage:
%   nmrData = nmr.processing.autoPhase(nmrData);
%   nmrData = nmr.processing.autoPhase(nmrData, 'order', 0);
%   nmrData = nmr.processing.autoPhase(nmrData, 'method', 'abs', 'nStart', 4);
%
% Options (Name-Value):
%   'order'       (0 or 1, default 1)  - correction order (0 = ph0 only, 1 = ph0+ph1)
%   'ph0_init'    (numeric, default []) - initial ph0 estimate (degrees). When empty
%                  (default), auto-estimated from angle(fid(1)) if raw.fid is available
%   'ph1_init'    (numeric, default 0)  - initial ph1 estimate (degrees)
%   'penalty'     (numeric, default 1)  - weight on negativity penalty term
%   'initFromFid' (logical, default true) - estimate ph0_init from FID first point
%   'method'      ('deriv'|'abs', default 'deriv') -- cost function:
%                  'deriv': entropy of |diff(real(s))| -- original Chen 2002
%                  'abs':   entropy of |real(s)| -- smoother landscape, more robust
%                           for multi-peak spectra with local-minimum risk (P03)
%   'nStart'      (int >= 1, default 1) -- multi-start count. When > 1, optimization
%                  seeds ph0 uniformly over [-180, 180) in addition to ph0_init.
%                  Effective against local minima in multi-peak or large-ph1 cases.
%
% Algorithm:
%   Cost = H(s) + lambda * P(s)
%   'deriv': H = -sum(p_n * ln(p_n)), p_n = |ds_n| / sum(|ds_n|), ds = diff(real(s))
%   'abs':   H = -sum(p_n * ln(p_n)), p_n = |real(s_n)| / sum(|real(s)|)
%   P = sum(min(real(s), 0).^2) / N  (negativity penalty)
%
%   Chen et al., J. Magn. Reson. 158, 164-168, 2002.
%
% Notes:
%   - Requires proc.isFT = true
%   - Uses fminsearch (Nelder-Mead) for optimization
%   - Calls correctPhase with the optimized parameters after convergence
%   - History entry is recorded as 'autoPhase' (not 'correctPhase')
%
% See also: nmr.processing.correctPhase, nmr.processing.autoPhaseF1,
%           nmr.processing.applyPreset

    if ~nmrData.proc.isFT
        error('nmr:processing:autoPhase:notFT', ...
            'autoPhase requires proc.isFT = true. Call doFFT first.');
    end

    p = inputParser;
    addParameter(p, 'order',       1,       @(x) isnumeric(x) && (x == 0 || x == 1));
    addParameter(p, 'ph0_init',    [],      @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'ph1_init',    0,       @isnumeric);
    addParameter(p, 'penalty',     1,       @isnumeric);
    addParameter(p, 'initFromFid', true,    @islogical);
    addParameter(p, 'method',      'deriv', @(x) any(strcmp(x, {'deriv','abs'})));
    addParameter(p, 'nStart',      1,       @(x) isnumeric(x) && x >= 1);
    parse(p, varargin{:});
    order    = p.Results.order;
    ph0_init = p.Results.ph0_init;
    ph1_init = p.Results.ph1_init;
    lambda   = p.Results.penalty;
    method   = p.Results.method;
    nStart   = max(1, round(p.Results.nStart));

    % Auto-estimate ph0 from FID first point when ph0_init is not explicit
    if isempty(ph0_init)
        if p.Results.initFromFid && isfield(nmrData, 'raw') && ...
                isfield(nmrData.raw, 'fid') && ~isempty(nmrData.raw.fid)
            fid1D    = nmrData.raw.fid(:, 1);   % first column (1D or F2 of 2D)
            fid1_amp = abs(fid1D(1));
            fid_max  = max(abs(fid1D));
            if fid_max > 0 && fid1_amp / fid_max < (1/20)
                % FID(1) amplitude < 5% of peak FID amplitude: phase angle of FID(1)
                % is unreliable (dominated by noise or GRPDLY offset). Fall back to
                % ph0_init = 0 to avoid steering the optimizer into a bad local minimum
                % (S01-T5). Observed in water-suppressed Bruker experiments where
                % decayed or near-zero FID(1) caused ph1 ≈ -900° misconvergence.
                ph0_init = 0;
                nmr.util.log.warn( ...
                    'autoPhase: FID(1) amp=%.3g < FID max/20=%.3g; ph0_init fallback to 0deg (S01-T5)', ...
                    fid1_amp, fid_max / 20);
            else
                ph0_init = -angle(fid1D(1)) * (180 / pi);
                nmr.util.log.info('autoPhase: ph0_init estimated from FID(1) = %.2fdeg', ph0_init);
            end
        else
            ph0_init = 0;
        end
    end

    % Snapshot of unphased spectrum for the objective function.
    % For multi-column data (e.g. DOSY: nPts x nGrad), use column 1 only.
    % Column 1 corresponds to the weakest gradient step (highest SNR), which
    % provides the best signal for phase optimization.  The resulting ph0/ph1
    % is then applied identically to all columns by correctPhase.
    isMultiCol = size(nmrData.spec.data, 2) > 1;
    if isMultiCol
        spec0 = nmrData.spec.data(:, 1);  % representative: highest SNR column
    else
        spec0 = nmrData.spec.data(:);
    end
    N     = numel(spec0);

    % Penalty selector (captured by phaseCost closure):
    %   nir_penalty  -- use relative negative-integral ratio abs(sum(neg))/sum(abs(s))
    %     → correct for JEOL data where firstPointCorr is SKIPPED (grpdly shift means
    %       FID(1) is NOT the t=0 sample; applying FID(1)/2 correction would introduce
    %       a flat -0.5 DC offset that makes |sum(neg^2)/N| unreliable).
    %   sum_neg2_penalty -- original sum(min(s,0)^2)/N
    %     → correct for Bruker/Varian/Synthetic where firstPointCorr IS applied; the
    %       -peak/2/N DC contribution is tiny and the large-amplitude inverted peaks
    %       are correctly penalised by their squared amplitude.
    use_nir_penalty = isfield(nmrData, 'proc') && ...
                      isfield(nmrData.proc, 'first_point_corr_skip') && ...
                      nmrData.proc.first_point_corr_skip;

    % --- Build ph0 candidate seeds for multi-start ---
    if nStart == 1
        ph0_cands = ph0_init;
    else
        grid_tmp  = linspace(-180, 180, nStart + 1);
        ph0_cands = unique([ph0_init, grid_tmp(1:end-1)]);
    end

    % --- Optimization (multi-start: keep global minimum) ---
    opts = optimset('Display', 'off', 'TolX', 1e-4, 'TolFun', 1e-6, ...
                    'MaxIter', 3000, 'MaxFunEvals', 10000);

    if order == 0
        x0_base = @(ph0_c) ph0_c;
    else
        x0_base = @(ph0_c) [ph0_c, ph1_init];
    end

    best_cost = Inf;
    x_opt     = x0_base(ph0_init);
    exitflag  = -1;

    for k_start = 1:numel(ph0_cands)
        x0_k = x0_base(ph0_cands(k_start));
        [x_k, c_k, f_k] = fminsearch(@phaseCost, x0_k, opts);
        if c_k < best_cost
            best_cost = c_k;
            x_opt     = x_k;
            exitflag  = f_k;
        end
    end

    if exitflag <= 0
        nmr.util.log.warn('autoPhase: fminsearch did not converge (exitflag=%d)', exitflag);
    end

    ph0_opt = x_opt(1);
    ph1_opt = 0;
    if numel(x_opt) > 1
        ph1_opt = x_opt(2);
    end

    % Warn if phase values are suspiciously large
    if abs(ph0_opt) > 360
        nmr.util.log.warn('autoPhase: |ph0|=%.1fdeg > 360deg -- unexpected; verify result', ph0_opt);
    end
    if abs(ph1_opt) > 500
        nmr.util.log.warn('autoPhase: |ph1|=%.1fdeg > 500deg -- possible large GRPDLY artifact', ph1_opt);
    end

    % Apply the optimized correction (adds a 'correctPhase' entry to history)
    nmrData = nmr.processing.correctPhase(nmrData, ph0_opt, ph1_opt, 'pivot', 0.5);

    % Relabel the last history entry so callers see 'autoPhase' operation
    nmrData.proc.history(end).operation = 'autoPhase';
    nmrData.proc.history(end).params    = struct( ...
        'ph0', ph0_opt, 'ph1', ph1_opt, 'pivot', 0.5, ...
        'order', order, 'exitflag', exitflag, ...
        'method', method, 'nStart', nStart, 'penalty', lambda);

    nmr.util.log.info('autoPhase: ph0=%.2fdeg, ph1=%.2fdeg (exitflag=%d, method=%s)', ...
        ph0_opt, ph1_opt, exitflag, method);

    % --- B-1: Compute phase quality metrics (ADR-013) ---
    % For multi-column data (DOSY), use column 1 for quality metrics.
    % Using all columns would inflate neg_integral_ratio because later gradient
    % steps have near-noise-level signals with ~50% negative values.
    if isMultiCol
        sPhased = real(nmrData.spec.data(:, 1));
    else
        sPhased = real(nmrData.spec.data(:));
    end
    Np = numel(sPhased);

    neg_mask              = sPhased < 0;
    neg_fraction          = sum(neg_mask) / Np;
    total_integral        = sum(abs(sPhased));
    if total_integral > 0
        neg_integral_ratio = abs(sum(sPhased(neg_mask))) / total_integral;
    else
        neg_integral_ratio = 0;
    end
    maxPos = max(sPhased);
    if maxPos > 0
        largest_neg_peak = abs(min(sPhased)) / maxPos;
    else
        largest_neg_peak = 0;
    end

    nmrData.proc.phase_quality = struct( ...
        'negative_fraction',      neg_fraction, ...
        'negative_integral_ratio', neg_integral_ratio, ...
        'largest_negative_peak',   largest_neg_peak);

    % Nucleus-aware warning threshold for neg_integral_ratio:
    %   1H (standard):  0.10  -- dense spectrum, well-determined baseline
    %   1H (DOSY):      0.50  -- DOSY spectral window is sparse (typically < 5%
    %                            signal points); the noise floor before baseline
    %                            correction is slightly negative, making the
    %                            neg_integral_ratio artificially high even when
    %                            phasing is correct (S-12 measured 0.305 on a
    %                            physically valid DOSY acquisition).
    %   sparse (13C/19F/31P): 0.60 -- low-SNR spectra with noise-dominant baselines
    nir_thresh = 0.10;
    nuc_str = '';
    if isfield(nmrData, 'params') && isfield(nmrData.params, 'nucleus')
        nuc_str = lower(strrep(char(nmrData.params.nucleus), ' ', ''));
    end
    % Detect DOSY: multi-column spec.data with non-empty raw.grad
    is_dosy = isMultiCol && isfield(nmrData, 'raw') && isfield(nmrData.raw, 'grad') ...
              && ~isempty(nmrData.raw.grad);
    if is_dosy
        nir_thresh = 0.50;   % relaxed: DOSY noise floor effect (S-12)
    elseif ~strcmp(nuc_str, '1h')
        nir_thresh = 0.60;
    end

    if neg_integral_ratio > nir_thresh
        nmr.util.log.warn( ...
            'autoPhase: negative_integral_ratio=%.3f > %.2f (nucleus=%s) -- phase correction may be suboptimal', ...
            neg_integral_ratio, nir_thresh, nuc_str);
    end
    nmr.util.log.info( ...
        'autoPhase: phase_quality: neg_frac=%.3f  neg_int_ratio=%.3f  largest_neg=%.3f', ...
        neg_fraction, neg_integral_ratio, largest_neg_peak);

    % ----------------------------------------------------------------
    % Nested objective function -- captures spec0, N, lambda, method
    % ----------------------------------------------------------------
    function cost = phaseCost(params)
        ph0_c = params(1);
        ph1_c = 0;
        if numel(params) > 1
            ph1_c = params(2);
        end
        n_c = (0:N-1)';
        phi = (ph0_c + ph1_c .* (n_c/N - 0.5)) .* (pi/180);
        s   = real(spec0 .* exp(1i .* phi));

        % Select entropy basis: derivative ('deriv') or absolute-spectrum ('abs')
        if strcmp(method, 'abs')
            % Entropy of |real(s)| -- smoother landscape, robust for multi-peak (P03)
            s_use = abs(s);
        else
            % Entropy of |first derivative| -- original Chen 2002 formulation
            s_use = abs(diff(s));
        end

        s_tot = sum(s_use);
        if s_tot < eps
            cost = Inf;
            return;
        end
        p_n           = s_use ./ s_tot;
        p_n(p_n <= 0) = eps;          % guard against log(0)
        H             = -sum(p_n .* log(p_n));

        % Penalty for negative signal.
        % Two strategies depending on whether firstPointCorr was skipped:
        %
        % nir (JEOL / firstPointCorr=false):
        %   neg_penalty = abs(sum(neg)) / sum(abs(s))  in [0,1]
        %   Correctly ranks few-large-negatives vs many-small-negatives,
        %   avoids the local minimum where inverted broad baseline looks "good"
        %   in sum(neg^2) metric.  Invariant to overall amplitude scaling.
        %
        % sum_neg2 (Bruker/Varian/Synthetic + firstPointCorr=true):
        %   neg_penalty = sum(min(s,0)^2) / N
        %   Correct when firstPointCorr is applied: the -FID(1)/(2N) DC shift
        %   is small, so inverted signal peaks dominate via their large amplitude.
        if use_nir_penalty
            s_abs_tot = sum(abs(s));
            if s_abs_tot > eps
                neg_penalty = abs(sum(min(s, 0))) / s_abs_tot;
            else
                neg_penalty = 0;
            end
        else
            neg_penalty = sum(min(s, 0).^2) / N;
        end

        cost = H + lambda * neg_penalty;
    end
end
