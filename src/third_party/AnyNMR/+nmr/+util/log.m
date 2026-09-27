classdef log
    % nmr.util.log - Logging utility for NMR processing pipeline
    %
    % Usage:
    %   nmr.util.log.info('Processing %d points', npts);
    %   nmr.util.log.warn('Missing parameter: %s', name);
    %   nmr.util.log.error('File not found: %s', path);
    %   nmr.util.log.progress(i, n, 'items');
    %
    % See also: nmr.util.printMeta

    methods (Static)
        function info(msg, varargin)
            if nargin > 1
                msg = sprintf(msg, varargin{:});
            end
            fprintf('[%s][INFO] %s\n', datestr(now, 'HH:MM:SS'), msg);
        end

        function warn(msg, varargin)
            if nargin > 1
                msg = sprintf(msg, varargin{:});
            end
            fprintf('[%s][WARN] %s\n', datestr(now, 'HH:MM:SS'), msg);
        end

        function err(msg, varargin)
            % Named 'err' to avoid shadowing built-in error()
            if nargin > 1
                msg = sprintf(msg, varargin{:});
            end
            fprintf(2, '[%s][ERROR] %s\n', datestr(now, 'HH:MM:SS'), msg);
        end

        function debug(msg, varargin)
            % Outputs only when env var NMR_LOG_VERBOSE=1 is set.
            % Use for parser internals that are too noisy for normal runs.
            if ~strcmpi(getenv('NMR_LOG_VERBOSE'), '1'); return; end
            if nargin > 1
                msg = sprintf(msg, varargin{:});
            end
            fprintf('[%s][DEBUG] %s\n', datestr(now, 'HH:MM:SS'), msg);
        end

        function print(msg, varargin)
            % Plain output without timestamp -- for formatted summaries and tables.
            if nargin > 1
                msg = sprintf(msg, varargin{:});
            end
            fprintf('%s\n', msg);
        end

        function progress(i, n, label)
            if nargin < 3; label = 'items'; end
            pct = round(100 * i / n);
            barLen = 10;
            filled = round(barLen * i / n);
            bar = [repmat('#', 1, filled), repmat('-', 1, barLen - filled)];
            fprintf('\r[%s] %3d%% (%2d/%2d) %s', bar, pct, i, n, label);
            if i == n
                fprintf('\n');
            end
        end
    end
end
