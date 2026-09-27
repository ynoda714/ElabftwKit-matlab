classdef TestElabUtil < matlab.unittest.TestCase
    % TestElabUtil  Unit tests for the elab.util.* value helpers.

    methods (TestClassSetup)
        function addSrcToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));          % tests/unit
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(fullfile(projectRoot, "src"), ...
                    "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function test_inferType_variousValueTypes_returnsMatchingLabel(tc)
            tc.verifyEqual(elab.util.inferType(42), 'number');
            tc.verifyEqual(elab.util.inferType("x"), 'text');
            tc.verifyEqual(elab.util.inferType(true), 'checkbox');
            tc.verifyEqual(elab.util.inferType(datetime(2026, 1, 2)), 'date');
        end

        function test_toElabValue_logicalAndNumericInputs_returnsElabString(tc)
            tc.verifyEqual(elab.util.toElabValue(true), 'on');
            tc.verifyEqual(elab.util.toElabValue(false), '');
            tc.verifyEqual(elab.util.toElabValue(3.5), '3.5');
        end

        function test_toItems_variousShapes_returnsNormalisedList(tc)
            s = struct("a", {1, 2, 3});                 % 1x3 struct array
            tc.verifyEqual(numel(elab.util.toItems(s)), 3);
            tc.verifyEqual(elab.util.toItems({}), {});
            tc.verifyEqual(numel(elab.util.toItems(struct("a", 1))), 1);
        end

        function test_fieldStruct_typeOmitted_infersTypeAutomatically(tc)
            f = elab.util.fieldStruct("scans", 16);
            tc.verifyEqual(f.name, "scans");
            tc.verifyEqual(f.type, "number");
        end

        function test_fileHash_sameFileTwice_returnsStableHexDigest(tc)
            tmp = [tempname, '.txt'];
            fid = fopen(tmp, "w");
            fwrite(fid, 'abc');
            fclose(fid);
            cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
            h1 = elab.util.fileHash(tmp);
            h2 = elab.util.fileHash(tmp);
            tc.verifyEqual(h1, h2);
            tc.verifyEqual(h1, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
            tc.verifyNumElements(h1, 64);
            tc.verifyTrue(all(ismember(h1, '0123456789abcdef')));
        end

        function test_fileHash_emptyFile_returnsEmptyInputDigest(tc)
            tmp = [tempname, '.txt'];
            fid = fopen(tmp, "w");
            fclose(fid);
            cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
            actual = elab.util.fileHash(tmp);
            expected = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
            tc.verifyEqual(actual, expected);
        end

        function test_fileHash_missingFile_raisesOpenFailed(tc)
            tc.verifyError(@() elab.util.fileHash(tempname), "elab:util:fileHash:openFailed");
        end
    end
end
