function [instrumentId, sampleId] = linkSessionItems(client, cfg, experimentId, binding)
% linkSessionItems  Link a session experiment to its bound Instrument and Sample.
%
%   [instrumentId, sampleId] = elab.pipeline.linkSessionItems(client, cfg, experimentId, binding).

    instrumentId = [];
    sampleId = [];
    if isempty(binding)
        return
    end
    if strlength(string(binding.instrument_title)) > 0
        instrumentType = string(binding.instrument_type);
        if instrumentType == ""
            instrumentType = cfg.elab.instrument_category;
        end
        instrumentId = elab.client.ensureItem(client, instrumentType, binding.instrument_title);
        client.linkTo("experiments", experimentId, "items", instrumentId);
    end
    if strlength(string(binding.sample_id)) > 0
        sampleId = elab.client.ensureItem(client, cfg.elab.sample_category, binding.sample_id);
        client.linkTo("experiments", experimentId, "items", sampleId);
    end
end
