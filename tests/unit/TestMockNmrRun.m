classdef TestMockNmrRun < matlab.unittest.TestCase
    % TestMockNmrRun  Contracts for synthetic Bruker 1D folders.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function test_write_defaultRun_createsRequiredFiles(tc)
            folder = tc.writeRun();

            tc.verifyTrue(isfile(fullfile(folder, "acqus")));
            tc.verifyTrue(isfile(fullfile(folder, "fid")));
            tc.verifyTrue(isfile(fullfile(folder, "elab_mock_meta.txt")));
        end

        function test_write_defaultRun_includesRequiredAcqusParameters(tc)
            folder = tc.writeRun();
            acqus = string(fileread(fullfile(folder, "acqus")));

            tc.verifySubstring(acqus, "##$BF1= ");
            tc.verifySubstring(acqus, "##$SW_h= ");
            tc.verifySubstring(acqus, "##$TD= ");
            tc.verifySubstring(acqus, "##$NUC1= ");
            tc.verifySubstring(acqus, "##$GRPDLY= ");
            tc.verifySubstring(acqus, "##$DTYPA= ");
            tc.verifySubstring(acqus, "##$BYTORDA= ");
        end

        function test_write_defaultRun_fidSizeMatchesTd(tc)
            folder = tc.writeRun();
            td = tc.acqusTd(fullfile(folder, "acqus"));
            fidInfo = dir(fullfile(folder, "fid"));

            tc.verifyEqual(fidInfo.bytes, td * 4);
        end

        function test_write_sameAcquiredAt_createsByteIdenticalFid(tc)
            acquiredAt = datetime(2026, 9, 24, 10, 20, 30);
            firstFolder = tc.writeRun(acquiredAt=acquiredAt);
            secondFolder = tc.writeRun(acquiredAt=acquiredAt);
            firstBytes = tc.readBytes(fullfile(firstFolder, "fid"));
            secondBytes = tc.readBytes(fullfile(secondFolder, "fid"));

            tc.verifyEqual(secondBytes, firstBytes);
        end

        function test_write_customAcquiredAt_preservesIsoMetadata(tc)
            acquiredAt = datetime(2026, 9, 24, 10, 20, 30);
            folder = tc.writeRun(acquiredAt=acquiredAt);
            meta = splitlines(string(fileread(fullfile(folder, "elab_mock_meta.txt"))));
            expected = "acquired_at: " + string(acquiredAt, "yyyy-MM-dd'T'HH:mm:ss");

            tc.verifyTrue(any(meta == expected));
        end

        function test_write_customName_createsRequestedFolder(tc)
            name = "nmr_bruker_SMP-2026-099";
            folder = tc.writeRun(name=name);
            [~, folderName] = fileparts(folder);

            tc.verifyEqual(string(folderName), name);
        end

        function test_write_defaultRun_returnsExistingFolder(tc)
            folder = tc.writeRun();

            tc.verifyTrue(isfolder(folder));
        end
    end

    methods (Access = private)
        function folder = writeRun(tc, opts)
            arguments
                tc
                opts.acquiredAt (1,1) datetime = datetime(2026, 9, 24, 9, 0, 0)
                opts.name (1,1) string = "nmr_bruker_SMP-2026-007"
            end
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = elab.io.writeMockNmrRun(string(fixture.Folder), ...
                acquiredAt=opts.acquiredAt, name=opts.name);
        end

        function td = acqusTd(~, acqusPath)
            tokens = regexp(fileread(acqusPath), "##\$TD=\s*(\d+)", "tokens", "once");
            td = str2double(tokens{1});
        end

        function bytes = readBytes(~, path)
            fid = fopen(path, "r");
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            bytes = fread(fid, Inf, "*uint8");
        end
    end
end
