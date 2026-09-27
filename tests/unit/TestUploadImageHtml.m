classdef TestUploadImageHtml < matlab.unittest.TestCase
    % TestUploadImageHtml  Uploaded-image HTML lookup and encoding tests.

    methods (TestClassSetup)
        function addSourceToPath(tc)
            thisDir = fileparts(mfilename("fullpath"));
            projectRoot = fileparts(fileparts(thisDir));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(projectRoot, "src"), "IncludingSubfolders", true));
        end
    end

    methods (Test)
        function testBuildsImageFromStructUpload(tc)
            upload = tc.upload(7, "plot.png", "stored-7.png", 1);
            fake = tc.clientWithUploads(upload);

            html = elab.client.uploadImageHtml( ...
                fake, "experiments", 501, "plot.png");

            tc.verifySubstring(html, "name=plot.png");
            tc.verifySubstring(html, "f=stored-7.png");
            tc.verifySubstring(html, "storage=1");
            tc.verifySubstring(html, 'width="600"');
            tc.verifySubstring(html, 'alt="plot.png"');
        end

        function testUsesNewestDuplicateUpload(tc)
            uploads = [ ...
                tc.upload(7, "plot.png", "old.png", 1), ...
                tc.upload(9, "plot.png", "new.png", 1)];
            fake = tc.clientWithUploads(uploads);

            html = elab.client.uploadImageHtml( ...
                fake, "experiments", 501, "plot.png");

            tc.verifySubstring(html, "f=new.png");
            tc.verifyFalse(contains(html, "f=old.png"));
        end

        function testMissingUploadErrors(tc)
            fake = tc.clientWithUploads(tc.upload(7, "other.png", "stored.png", 1));

            tc.verifyError(@() elab.client.uploadImageHtml( ...
                fake, "experiments", 501, "plot.png"), ...
                "elab:client:uploadImageHtml:notFound");
        end

        function testEncodesQueryAndEscapesAttributes(tc)
            upload = tc.upload(7, "a b&c.png", 'stored name&".png', 1);
            fake = tc.clientWithUploads(upload);

            html = elab.client.uploadImageHtml(fake, "experiments", 501, ...
                "a b&c.png", alt='<preview & "check">');

            tc.verifySubstring(html, "name=a%20b%26c.png");
            tc.verifySubstring(html, "f=stored%20name%26%22.png");
            tc.verifySubstring(html, "&amp;f=");
            tc.verifySubstring(html, 'alt="&lt;preview &amp; &quot;check&quot;&gt;"');
            tc.verifyFalse(contains(html, "a b"));
            tc.verifyFalse(contains(html, "&c.png"));
        end

        function testAcceptsCellUploadsForItems(tc)
            uploads = {tc.upload(7, "plot.png", "stored-7.png", 1)};
            fake = FakeElabClient();
            fake.setGetResponse("/items/501", struct("uploads", {uploads}));

            html = elab.client.uploadImageHtml( ...
                fake, "items", 501, "plot.png", width=320);

            tc.verifySubstring(html, "f=stored-7.png");
            tc.verifySubstring(html, 'width="320"');
        end
    end

    methods (Access = private)
        function fake = clientWithUploads(~, uploads)
            fake = FakeElabClient();
            fake.setGetResponse("/experiments/501", struct("uploads", uploads));
        end
    end

    methods (Static, Access = private)
        function value = upload(id, realName, longName, storage)
            value = struct("id", id, "real_name", realName, ...
                "long_name", longName, "storage", storage);
        end
    end
end
