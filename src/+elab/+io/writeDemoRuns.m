function files = writeDemoRuns(outDir, opts)
% writeDemoRuns  Write deterministic synthetic inputs for a demonstration run.
%
%   files = elab.io.writeDemoRuns("data/demo_inbox")
%   files = elab.io.writeDemoRuns("data/demo_inbox", month=datetime(2026, 8, 1))

    arguments
        outDir (1,1) string
        opts.month (1,1) datetime = dateshift(datetime("today"), "start", "month", -1)
    end

    monthStart = dateshift(opts.month, "start", "month");
    todayStart = dateshift(datetime("today"), "start", "day");
    if monthStart > dateshift(todayStart, "start", "month")
        error("elab:io:writeDemoRuns:futureMonth", ...
            "Demo month must not be in the future.");
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    days = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22];
    selected = [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5];
    if monthStart == dateshift(todayStart, "start", "month")
        lastDay = day(todayStart);
    else
        lastDay = day(dateshift(monthStart, "end", "month"));
    end
    if max(days) > lastDay
        error("elab:io:writeDemoRuns:monthTooShort", ...
            "Demo month needs at least 22 completed calendar days.");
    end

    targets = [ ...
        "xrd_demo_01_SMP-2026-001.xy"
        "raman_demo_02_SMP-2026-002.txt"
        "ftir_demo_03_SMP-2026-003.dx"
        "nmr_SMP-2026-004_demo_04.dx"
        "lcms_demo_05_SMP-2026-005.csv"
        "sem_demo_06_SMP-2026-006.png"
        "xrd_demo_07_SMP-2026-001.xy"
        "raman_demo_08_SMP-2026-002.txt"
        "ftir_demo_09_SMP-2026-003.dx"
        "nmr_SMP-2026-004_demo_10.dx"
        "lcms_demo_11_SMP-2026-005.csv"];
    staging = string(tempname(char(outDir)));
    mkdir(staging);
    cleanup = onCleanup(@() localRemoveFolder(staging)); %#ok<NASGU>
    files = strings(0, 1);

    for k = 1:numel(targets)
        acquiredAt = monthStart + days(k) - 1 + hours(9);
        sourceFiles = elab.io.writeMockRuns(staging, acquiredAt=acquiredAt);
        source = sourceFiles(selected(k));
        target = string(fullfile(outDir, targets(k)));
        movefile(source, target);
        if selected(k) == 6
            sourceMeta = replace(source, ".png", "_meta.txt");
            targetMeta = replace(target, ".png", "_meta.txt");
            movefile(sourceMeta, targetMeta);
        end
        files(end + 1, 1) = localAbsolutePath(target); %#ok<AGROW>
    end

    folderAt = monthStart + 23 - 1 + hours(9);
    folder = elab.io.writeMockNmrRun(outDir, acquiredAt=folderAt, ...
        name="nmr_bruker_demo_SMP-2026-007", variant="noAudit");
    files(end + 1, 1) = localAbsolutePath(folder); %#ok<AGROW>
    logInfo("writeDemoRuns: wrote %d demo inputs to %s", numel(files), outDir);
end

function path = localAbsolutePath(value)
    file = java.io.File(char(value));
    path = string(char(file.getAbsolutePath()));
end

function localRemoveFolder(folder)
    if isfolder(folder)
        rmdir(folder, "s");
    end
end
