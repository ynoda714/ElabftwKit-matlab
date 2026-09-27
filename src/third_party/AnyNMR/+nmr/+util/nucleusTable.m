classdef nucleusTable
% nmr.util.nucleusTable - Nucleus constants for sanity checks and 2D heteronuclear
%
% Usage:
%   info = nmr.util.nucleusTable.get('1H');
%   bf   = nmr.util.nucleusTable.inferBf('13C', bf1H);
%   tf   = nmr.util.nucleusTable.isKnown('19F');
%
% Reference: IUPAC 2001 receptivity / gyromagnetic ratios
%
% See also: nmr.processing.setReference, nmr.relax.computeDosyB

    properties (Constant, Access = private)
        % Table columns: nucleus, gamma_rel (relative to 1H), ppm_range_min, ppm_range_max
        % gamma_rel = gamma / gamma_1H
        DATA = {
            '1H',   1.000000,    -5,   20;
            '2H',   0.153506,   -20,   20;
            '13C',  0.251450,  -20,  250;
            '15N',  0.101329, -400,  100;
            '19F',  0.941271, -350,    0;
            '31P',  0.404808, -100,  100;
            '29Si', 0.198371, -400,   50;
            '11B',  0.320860,  -50,  100;
            '23Na', 0.264515,    0,   30;
            '17O',  0.135532, -100, 1500;
        }
    end

    methods (Static)
        function info = get(nucleus)
        % get - Return constants struct for a nucleus
        %
        % Returns struct with fields: nucleus, gamma_rel, ppm_min, ppm_max
        % Throws error if nucleus is not in table.
            nucleus = strtrim(nucleus);
            data = nmr.util.nucleusTable.DATA;
            for k = 1:size(data, 1)
                if strcmp(data{k,1}, nucleus)
                    info.nucleus   = nucleus;
                    info.gamma_rel = data{k,2};
                    info.ppm_min   = data{k,3};
                    info.ppm_max   = data{k,4};
                    return;
                end
            end
            error('nmr:util:nucleusTable:unknown', ...
                'Unknown nucleus: ''%s''. Known: %s', ...
                nucleus, strjoin(nmr.util.nucleusTable.list(), ', '));
        end

        function tf = isKnown(nucleus)
        % isKnown - Return true if nucleus is in the table
            nucleus = strtrim(nucleus);
            data = nmr.util.nucleusTable.DATA;
            tf = false;
            for k = 1:size(data, 1)
                if strcmp(data{k,1}, nucleus)
                    tf = true;
                    return;
                end
            end
        end

        function bf2 = inferBf(nucleus2, bf1H)
        % inferBf - Estimate BF for nucleus2 given the 1H frequency
        %
        %   bf2 = gamma_rel(nucleus2) * bf1H
        %
        % Example:
        %   bf13C = nmr.util.nucleusTable.inferBf('13C', 600.2);  % -> ~150.9 MHz
            info = nmr.util.nucleusTable.get(nucleus2);
            bf2  = info.gamma_rel * bf1H;
        end

        function tf = isPpmInRange(nucleus, ppm_range)
        % isPpmInRange - Sanity check: is the observed ppm range plausible?
        %
        %   ppm_range = sw_hz / bf  (total ppm window)
        %
        % Returns false if ppm_range is suspiciously large.
            info = nmr.util.nucleusTable.get(nucleus);
            expected = info.ppm_max - info.ppm_min;
            tf = ppm_range <= expected * 3;   % allow 3x margin for safety
        end

        function nuclei = list()
        % list - Return cell array of all known nucleus strings
            data = nmr.util.nucleusTable.DATA;
            nuclei = data(:,1)';
        end
    end
end
