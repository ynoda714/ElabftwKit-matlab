classdef TestAcquiredAt < matlab.unittest.TestCase
    % TestAcquiredAt  Acquisition-time extraction and mock-data contracts.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testMockRunsCarryFortyMinuteSequenceAcrossMidnight(tc)
            folder = tc.tempFolder();
            startTime = datetime(2026, 8, 31, 23, 10, 0);
            files = elab.io.writeMockRuns(folder, acquiredAt=startTime);
            actual = NaT(size(files));
            sources = strings(size(files));

            for k = 1:numel(files)
                parsed = elab.io.parseAny(files(k));
                [actual(k), sources(k)] = elab.io.readAcquiredAt(files(k), parsed);
            end

            expected = startTime + minutes(40 * (0:5));
            tc.verifyEqual(sources, repmat("file", size(files)));
            tc.verifyEqual(actual, expected);
            tc.verifyEqual(string(actual(3), "yyyy-MM-dd HH:mm"), ...
                "2026-09-01 00:30");
        end

        function testMissingHeaderFallsBackToFileMtime(tc)
            filePath = fullfile(tc.tempFolder(), "no_time.xy");
            writelines("1 2", filePath);
            expected = datetime(2026, 7, 15, 8, 30, 0, "TimeZone", "local");
            java.io.File(char(filePath)).setLastModified(posixtime(expected) * 1000);

            [actual, source] = elab.io.readAcquiredAt(filePath, tc.emptyParsed());

            tc.verifyEqual(source, "file_mtime");
            tc.verifyEqual(actual, datetime(2026, 7, 15, 8, 30, 0), ...
                AbsTol=seconds(1));
        end

        function testInvalidCalendarDateWarnsAndFallsBack(tc)
            [filePath, expected] = tc.mtimeFile();
            parsed = tc.parsedParam("acquired_at", "2026-02-30T09:00:00");

            output = evalc( ...
                "[actual, source] = elab.io.readAcquiredAt(filePath, parsed);");

            tc.verifySubstring(output, "no_time.xy");
            tc.verifySubstring(output, "2026-02-30T09:00:00");
            tc.verifyEqual(source, "file_mtime");
            tc.verifyEqual(actual, expected, AbsTol=seconds(1));
        end

        function testOffsetValueWarnsAndFallsBack(tc)
            [filePath, expected] = tc.mtimeFile();
            parsed = tc.parsedParam( ...
                "ACQUIRED_AT", "2026-09-18T09:00:00+09:00");

            output = evalc( ...
                "[actual, source] = elab.io.readAcquiredAt(filePath, parsed);");

            tc.verifySubstring(output, "2026-09-18T09:00:00+09:00");
            tc.verifyEqual(source, "file_mtime");
            tc.verifyEqual(actual, expected, AbsTol=seconds(1));
        end

        function testLongDateIsReadCaseInsensitively(tc)
            parsed = tc.parsedParam("longdate", "2026/09/18 10:20:00");

            [actual, source] = elab.io.readAcquiredAt( ...
                fullfile(tc.tempFolder(), "missing.dx"), parsed);

            tc.verifyEqual(source, "file");
            tc.verifyEqual(actual, datetime(2026, 9, 18, 10, 20, 0));
            tc.verifyEqual(actual.TimeZone, '');
        end

        function testMissingFileAndHeaderReturnUnknown(tc)
            [actual, source] = elab.io.readAcquiredAt( ...
                fullfile(tc.tempFolder(), "missing.xy"), tc.emptyParsed());

            tc.verifyEqual(source, "unknown");
            tc.verifyTrue(isnat(actual));
        end

        function testDefaultMockStartIsTodayAtNine(tc)
            before = datetime("today") + hours(9);
            files = elab.io.writeMockRuns(tc.tempFolder());
            parsed = elab.io.parseAny(files(1));
            [actual, source] = elab.io.readAcquiredAt(files(1), parsed);
            after = datetime("today") + hours(9);

            tc.verifyEqual(source, "file");
            tc.verifyTrue(actual == before || actual == after);
        end

        function testMockRunsWithSameAcquiredAtAreByteIdentical(tc)
            acquiredAt = datetime(2026, 9, 18, 9, 0, 0);
            firstFolder = tc.tempFolder();
            secondFolder = tc.tempFolder();
            firstFiles = elab.io.writeMockRuns(firstFolder, acquiredAt=acquiredAt);
            firstHashes = tc.mockRunHashes(firstFolder, firstFiles);
            pause(1.1);
            secondFiles = elab.io.writeMockRuns(secondFolder, acquiredAt=acquiredAt);
            secondHashes = tc.mockRunHashes(secondFolder, secondFiles);

            tc.verifyEqual(secondHashes, firstHashes);
        end

        function testSemPngChangesWithAcquiredAt(tc)
            firstFolder = tc.tempFolder();
            secondFolder = tc.tempFolder();
            firstFiles = elab.io.writeMockRuns(firstFolder, ...
                acquiredAt=datetime(2026, 9, 18, 9, 0, 0));
            secondFiles = elab.io.writeMockRuns(secondFolder, ...
                acquiredAt=datetime(2026, 9, 19, 9, 0, 0));
            firstHash = string(elab.util.fileHash(firstFiles(6)));
            secondHash = string(elab.util.fileHash(secondFiles(6)));

            tc.verifyNotEqual(secondHash, firstHash);
        end
    end

    methods (Access = private)
        function folder = tempFolder(tc)
            fixture = matlab.unittest.fixtures.TemporaryFolderFixture;
            tc.applyFixture(fixture);
            folder = string(fixture.Folder);
        end

        function [filePath, expected] = mtimeFile(tc)
            filePath = fullfile(tc.tempFolder(), "no_time.xy");
            writelines("1 2", filePath);
            zoned = datetime(2026, 7, 15, 8, 30, 0, "TimeZone", "local");
            java.io.File(char(filePath)).setLastModified(posixtime(zoned) * 1000);
            expected = datetime(2026, 7, 15, 8, 30, 0);
        end

        function hashes = mockRunHashes(~, folder, files)
            paths = [files(:); fullfile(folder, "sem_SMP-2026-006_meta.txt")];
            hashes = strings(size(paths));
            for k = 1:numel(paths)
                hashes(k) = string(elab.util.fileHash(paths(k)));
            end
        end
    end

    methods (Static, Access = private)
        function parsed = emptyParsed()
            parsed.params = repmat( ...
                struct("name", "", "value", "", "type", "text"), 0, 1);
        end

        function parsed = parsedParam(name, value)
            parsed.params = struct("name", name, "value", value, "type", "text");
        end
    end
end
