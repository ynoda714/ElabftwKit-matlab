function info = kitVersion(~)
% kitVersion  Count calls made by the M4-7 QC inbox test fixture.

    global M47KitVersionCalls
    M47KitVersionCalls = M47KitVersionCalls + 1;
    info = struct("version", "0.1.0-dev", "commit", "test");
end
