function T = reconcileBookings(client, cfg, sinceDate, beforeDate)
% reconcileBookings  Scenario D3 (sketch): line up scheduler events against
%   logged sessions for a date range so a facility manager can spot
%   no-shows (booked, no data) and unbooked usage (data, no booking).
%
%   T = elab.pipeline.reconcileBookings(client, cfg, sinceDate, beforeDate)
%
%   This is intentionally a starting point: robust matching needs the
%   Instrument item id on BOTH sides (event.item and the session's items
%   link) plus overlap on the day. Adapt the keys below to your schema --
%   inspect one event with:  client.getJson("/events/<id>")

    arguments
        client
        cfg        (1,1) struct
        sinceDate  (1,1) string
        beforeDate (1,1) string = string(datetime("today"), "yyyy-MM-dd")
    end

    events = elab.util.toItems(client.getJson("/events", ...
        {"since", sinceDate, "before", beforeDate, "limit", 500}));
    if numel(events) >= 500
        logWarn("reconcileBookings: events list reached the limit of 500; " + ...
            "the reconciliation may be incomplete");
    end
    catId = elab.client.resolveId(client, "experiments_categories", cfg.elab.session_category);
    sessions = elab.util.toItems(client.getJson("/experiments", ...
        {"cat", catId, "since", sinceDate, "before", beforeDate, "limit", 500}));
    if numel(sessions) >= 500
        logWarn("reconcileBookings: sessions list reached the limit of 500; " + ...
            "the reconciliation may be incomplete");
    end

    evDays = strings(0, 1);
    for k = 1:numel(events)
        startVal = localGet(events{k}, "start", "");
        evDays(end + 1) = extractBefore(string(startVal) + "T", "T"); %#ok<AGROW>
    end
    seDays = strings(0, 1);
    for k = 1:numel(sessions)
        seDays(end + 1) = string(localGet(sessions{k}, "date", "")); %#ok<AGROW>
    end

    bookedDaysNoData = setdiff(unique(evDays), unique(seDays));
    dataDaysNoBooking = setdiff(unique(seDays), unique(evDays));

    T = table(numel(events), numel(sessions), ...
        numel(bookedDaysNoData), numel(dataDaysNoBooking), ...
        "VariableNames", {'events', 'sessions', ...
                          'booked_days_no_data', 'data_days_no_booking'});

    logInfo("reconcileBookings: %d events / %d sessions in [%s, %s)", ...
        numel(events), numel(sessions), sinceDate, beforeDate);
    logInfo("  booked, no data  : %s", strjoin(bookedDaysNoData, ", "));
    logInfo("  data, no booking : %s", strjoin(dataDaysNoBooking, ", "));
end

function v = localGet(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
