function folderPath = writeMockNmrRun(outDir, opts)
% writeMockNmrRun  Write one deterministic synthetic Bruker experiment folder.
    arguments
        outDir (1,1) string = string(fullfile("data", "inbox"))
        opts.acquiredAt (1,1) datetime = ...
            dateshift(datetime("today"), "start", "day") + hours(9)
        opts.name (1,1) string = "nmr_bruker_SMP-2026-007"
        opts.timezone (1,1) string = "Asia/Tokyo"
        opts.variant (1,1) string = "normal"
    end
    variants = ["normal" "dateZero" "dateAbsent" "noAudit" "multiAudit" ...
        "twoDimensional" "emptyFid"];
    if ~ismember(opts.variant, variants)
        error("elab:io:writeMockNmrRun:invalidVariant", "unknown variant %s", opts.variant);
    end
    try
        at = datetime(year(opts.acquiredAt), month(opts.acquiredAt), ...
            day(opts.acquiredAt), hour(opts.acquiredAt), minute(opts.acquiredAt), ...
            second(opts.acquiredAt), TimeZone=opts.timezone);
    catch cause
        throwAsCaller(MException( ...
            "elab:io:writeMockNmrRun:invalidTimezone", ...
            "invalid timezone %s: %s", opts.timezone, cause.message));
    end
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    folderPath = string(fullfile(outDir, opts.name));
    if ~isfolder(folderPath)
        mkdir(folderPath);
    end
    localClearVariantFiles(folderPath);
    rng(42);
    td = 16384;
    swH = 8012.820513;
    localWriteAcqus(fullfile(folderPath, "acqus"), td, swH, at, opts.variant);
    if opts.variant == "twoDimensional"
        localWriteFid(fullfile(folderPath, "ser"), td, swH);
        lines = ["##TITLE= Synthetic second dimension"; "##$TD= 64"];
        writelines(lines, fullfile(folderPath, "acqu2s"));
    else
        localWriteFid(fullfile(folderPath, "fid"), td, swH);
        if opts.variant == "emptyFid"
            fid = fopen(fullfile(folderPath, "fid"), "w");
            fclose(fid);
        end
    end
    if opts.variant ~= "noAudit"
        localWriteAudit(fullfile(folderPath, "audita.txt"), at, opts.variant);
    end
    auxLines = ["##TITLE= Synthetic auxiliary parameter file"; "##$AUX= 1"];
    writelines(auxLines, fullfile(folderPath, "uxnmr.par"));
    pdata = fullfile(folderPath, "pdata", "1");
    if ~isfolder(pdata)
        mkdir(pdata);
    end
    procLines = ["##TITLE= Synthetic processed parameters"; "##$SI= 16384"];
    writelines(procLines, fullfile(pdata, "procs"));
    localWriteMeta(fullfile(folderPath, "elab_mock_meta.txt"), opts.acquiredAt);
    logInfo("writeMockNmrRun: wrote synthetic Bruker 1D run to %s", folderPath);
end

function localClearVariantFiles(folder)
    names = ["fid" "ser" "acqu2s" "audita.txt"];
    for name = names
        path = fullfile(folder, name);
        if isfile(path)
            delete(path);
        end
    end
end

function localWriteAcqus(path, td, swH, at, variant)
    header = "$$ " + string(at, "yyyy-MM-dd HH:mm:ss.SSS") + " " + ...
        localOffset(at) + " mock-user@mock-host " + ...
        "C:/mock/nmr_bruker_SMP-2026-007/acqus";
    dateLine = "##$DATE= " + string(floor(posixtime(at)));
    if variant == "dateZero"
        dateLine = "##$DATE= 0";
    end
    lines = [ ...
        "##TITLE= Parameter file, TopSpin 4.1.4"
        "##JCAMPDX= 5.0"
        "##DATATYPE= Parameter Values"
        "##ORIGIN= synthetic (elab.io.writeMockNmrRun)"
        "##OWNER= mock-owner"
        header];
    if variant ~= "dateAbsent"
        lines(end + 1) = dateLine;
    end
    parameterLines = [ ...
        "##$NS= 16"
        "##$DS= 2"
        "##$INSTRUM= <spect>"
        "##$BF1= 400.130000"
        "##$SW_h= " + compose("%.6f", swH)
        "##$TD= " + string(td)
        "##$NUC1= <1H>"
        "##$GRPDLY= 0"
        "##$DTYPA= 0"
        "##$BYTORDA= 0"
        "##$PULPROG= <zg30>"
        "##$SOLVENT= <CDCl3>"
        "##$TE= 298.0"
        "##$O1= 2000.65"
        "##$D= (0..1)"
        "0 1.0"
        "##$P= (0..1)"
        "0 10.5"];
    lines = [lines; parameterLines];
    writelines(lines, path);
end

function localWriteAudit(path, at, variant)
    if variant == "multiAudit"
        firstStart = at - minutes(3) - seconds(38);
        firstEnd = at - minutes(3);
        first = localAuditEntry(1, firstStart, firstEnd);
        second = localAuditEntry(2, at - seconds(38), at);
        lines = [first; second];
    else
        lines = localAuditEntry(1, at - seconds(38), at);
    end
    header = [ ...
        "##TITLE= Audit trail, TopSpin 4.1.4"
        "##JCAMPDX= 5.01"
        "##ORIGIN= synthetic (elab.io.writeMockNmrRun)"
        "##OWNER= mock-owner"
        "##AUDIT TRAIL=  $$ (NUMBER, WHEN, WHO, WHERE, PROCESS, VERSION, WHAT)"];
    writelines([header; lines; "##END="], path);
end

function lines = localAuditEntry(number, started, completed)
    s = string(started, "yyyy-MM-dd HH:mm:ss.SSS") + " " + localOffset(started);
    e = string(completed, "yyyy-MM-dd HH:mm:ss.SSS") + " " + localOffset(completed);
    lines = [ ...
        "(   " + string(number) + ",<" + e + ...
        ">,<mock-owner>,<mock-host>,<go4>,<TopSpin 4.1.4>,"
        "      <created by zg on data set with UUID '00000000-0000-0000-0000-000000000000'"
        "       started at " + s + ","
        "       completed at " + e
        ">)"];
end

function text = localOffset(value)
    total = round(minutes(tzoffset(value)));
    signText = "+";
    if total < 0
        signText = "-";
    end
    total = abs(total);
    text = signText + compose("%02d%02d", floor(total / 60), mod(total, 60));
end

function localWriteFid(path, td, swH)
    npts = td / 2; t = (0:npts - 1).' / swH;
    first = 0.35 * exp(-t / .25) .* exp(1i * 2 * pi * 300 * t);
    second = .55 * exp(-t / .40) .* exp(-1i * 2 * pi * 150 * t);
    noise = .002 * (randn(npts, 1) + 1i * randn(npts, 1));
    value = first + second + noise;
    realPart = int32(round(real(value) * 2e6));
    imaginaryPart = int32(round(imag(value) * 2e6));
    bytes = reshape([realPart, imaginaryPart].', [], 1);
    fid = fopen(path, "w", "ieee-le");
    assert(fid > 0, "elab:io:writeMockNmrRun:openFid", ...
        "Cannot open %s for writing.", path);
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, bytes, "int32");
end

function localWriteMeta(path, acquiredAt)
    lines = [ ...
        "# This is synthetic data generated by elab.io.writeMockNmrRun for tests and demos."
        "# It does not represent any real facility, instrument, or sample."
        "instrument: NMR-Bruker-01 Bruker AVANCE III"
        "acquired_at: " + string(acquiredAt, "yyyy-MM-dd'T'HH:mm:ss")
        "sample_id: SMP-2026-007"
        "operator: operator-a"];
    writelines(lines, path);
end
