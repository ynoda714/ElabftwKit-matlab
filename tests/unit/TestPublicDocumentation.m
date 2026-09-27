classdef TestPublicDocumentation < matlab.unittest.TestCase
    % TestPublicDocumentation  Guard public English documentation.

    methods (Test)
        function test_publicDocuments_haveNoJapaneseCharacters(tc)
            violations = TestPublicDocumentation.japaneseCharacterViolations();
            tc.verifyEmpty(violations);
        end

        function test_functionReference_listsEverySourceFunction(tc)
            root = TestPublicDocumentation.projectRoot();
            reference = string(fileread(fullfile(root, "docs", "function_reference.md")));
            files = dir(fullfile(root, "src", "**", "*.m"));
            files = files(~contains(string({files.folder}), "+pybridge"));
            names = erase(string({files.name}), ".m");

            listed = arrayfun(@(name) contains(reference, name), names);
            missing = names(~listed);
            tc.verifyEmpty(missing, ...
                "Functions missing from docs/function_reference.md: " + strjoin(missing, ", "));
        end

        function test_publicDocumentation_linksResolveIncludingAnchors(tc)
            violations = TestPublicDocumentation.linkViolations();
            tc.verifyEmpty(violations);
        end

        function test_publicDocumentation_referencesExistingElabApis(tc)
            references = TestPublicDocumentation.documentApiReferences();
            missing = TestPublicDocumentation.missingElabApis(references);

            tc.verifyGreaterThanOrEqual(numel(references), 2);
            tc.verifyEmpty(missing);
        end

        function test_readmeAndChangelog_omitComparisonTerms(tc)
            violations = TestPublicDocumentation.comparisonTermViolations();
            probe = 'We compare with PPMS.';
            probePattern = ['(?i)\<' regexptranslate('escape', 'PPMS') '\>'];

            tc.verifyNotEmpty(regexp(probe, probePattern, 'once'));
            tc.verifyEmpty(violations);
        end

        function test_readme_statesNmrLiveServerAndInstrumentScope(tc)
            root = TestPublicDocumentation.projectRoot();
            readme = string(fileread(fullfile(root, "README.md")));

            tc.verifyTrue(contains(readme, "live server"));
            tc.verifyTrue(contains(readme, "connected instrument"));
        end

        function test_readme_nmrFolderRowUsesAvailableNowStatus(tc)
            root = TestPublicDocumentation.projectRoot();
            readme = string(fileread(fullfile(root, "README.md")));
            row = string(regexp(readme, '(?m)^\| NMR experiment folders .+$', 'match', 'once'));

            tc.verifyNotEmpty(row);
            tc.verifyTrue(contains(row, "Available now"));
            tc.verifyFalse(contains(row, "Checked offline"));
        end

        function test_readme_linksNmrVerificationRecords(tc)
            root = TestPublicDocumentation.projectRoot();
            readme = string(fileread(fullfile(root, "README.md")));
            row = string(regexp(readme, '(?m)^\| NMR experiment folders .+$', 'match', 'once'));

            tc.verifyTrue(contains(row, "docs/verification.md#nmr-folders-live"));
            tc.verifyTrue(contains(readme, "docs/verification.md#nmr-folders-real"));
            tc.verifyTrue(contains(readme, "docs/verification.md#nmr-folders-synthetic"));
        end

        function test_quickstart_hasNmrExperimentFolderSection(tc)
            root = TestPublicDocumentation.projectRoot();
            quickstart = string(fileread(fullfile(root, "docs", "quickstart.md")));

            tc.verifyTrue(contains(quickstart, "## Log an NMR experiment folder"));
        end

        function test_quickstart_runningAgainRemainsInWhatToExpect(tc)
            root = TestPublicDocumentation.projectRoot();
            quickstart = string(fileread(fullfile(root, "docs", "quickstart.md")));
            beforeRunningAgain = extractBefore(quickstart, "### Running it again");
            headings = string(regexp(beforeRunningAgain, '(?m)^## [^\r\n]+', 'match'));

            tc.verifyTrue(contains(quickstart, "### Running it again"));
            tc.verifyEqual(headings(end), "## What to expect");
        end

        function test_quickstart_nmrFolderSectionMentionsUnsupportedSer(tc)
            root = TestPublicDocumentation.projectRoot();
            quickstart = string(fileread(fullfile(root, "docs", "quickstart.md")));
            nmrSection = extractAfter(quickstart, "## Log an NMR experiment folder");
            nmrSection = extractBefore(nmrSection, newline + "## ");

            tc.verifyNotEmpty(regexp(nmrSection, '\<ser\>', 'once'));
        end

        function test_readmeDocumentsTableLinksLocalElabftwSetup(tc)
            root = TestPublicDocumentation.projectRoot();
            readme = string(fileread(fullfile(root, "README.md")));
            documents = extractAfter(readme, "## Documents");
            documents = extractBefore(documents, newline + "## ");
            row = "| [Local eLabFTW setup](docs/elabftw_setup.md) | Run a local trial server with Docker, and a separate demo server. |";

            tc.verifyTrue(contains(readme, "[Local eLabFTW setup](docs/elabftw_setup.md)"));
            tc.verifyTrue(contains(documents, row));
        end

        function test_readmeOpening_identifiesUnofficialProject(tc)
            opening = TestPublicDocumentation.readmeOpening();

            tc.verifyTrue(contains(opening, "unofficial"));
        end

        function test_readmeOpening_identifiesDeltablot(tc)
            opening = TestPublicDocumentation.readmeOpening();

            tc.verifyTrue(contains(opening, "Deltablot"));
        end

        function test_readmeOpening_limitsAffiliationAndEndorsement(tc)
            opening = TestPublicDocumentation.readmeOpening();

            tc.verifyTrue(contains(opening, "affiliated") && contains(opening, "endorsed"));
        end

        function test_readmeConnectionSectionStatesRestApiAndNoPlugin(tc)
            readme = TestPublicDocumentation.readPublicDocument("README.md");
            section = TestPublicDocumentation.markdownSection(readme, "## Connect to eLabFTW");

            tc.verifyTrue(contains(section, "REST API v2") && contains(section, "plugin"));
        end

        function test_readmeHasDataPolicyHeading(tc)
            readme = TestPublicDocumentation.readPublicDocument("README.md");

            tc.verifyTrue(contains(readme, "## Data policy"));
        end

        function test_readmeDataPolicyStatesDefaultAttachmentLimit(tc)
            readme = TestPublicDocumentation.readPublicDocument("README.md");
            section = TestPublicDocumentation.markdownSection(readme, "## Data policy");

            tc.verifyTrue(contains(section, "25 MB"));
        end

        function test_contributingProhibitsRealDataAndPersonalInformation(tc)
            contributing = TestPublicDocumentation.readPublicDocument("CONTRIBUTING.md");

            tc.verifyTrue(contains(contributing, "real instrument files") && ...
                contains(contributing, "personal information"));
        end
    end

    methods (Static)
        function documents = publicDocuments()
            root = TestPublicDocumentation.projectRoot();
            documents = fullfile(root, [ ...
                "README.md", "THIRD_PARTY_NOTICES.md", "CONTRIBUTING.md", ...
                "data/README.md", ...
                "docs/function_reference.md", "docs/log_format.md", ...
                "docs/elab_structure.md", "docs/quickstart.md", ...
                "docs/assembly_guide.md", "docs/algorithm_guide.md", ...
                "docs/demo_guide.md", ...
                "docs/elabftw_setup.md", "docs/elabftw-5.6.12-api-notes.md", ...
                "docs/verification.md", "CHANGELOG.md", ...
                "docs/adding_a_format.md", "docs/platform_support.md", ...
                "docs/python_integration.md", "docs/test_catalog.md", ...
                "docs/templates/experiment_record.md", ...
                "docs/templates/pr_template.md", "docs/templates/task_template.md", ...
                "docs/templates/gitignore_public.txt"]);
        end
    end

    methods (Static, Access = private)
        function violations = japaneseCharacterViolations()
            allowed = [ ...
                struct( ...
                    "text", string(char([hex2dec('0051'), hex2dec('0043'), ...
                    hex2dec('30FB'), hex2dec('6821'), hex2dec('6B63')])), ...
                    "reason", "QC category example: U+30FB is part of the configured name."), ...
                struct( ...
                    "text", string(char([hex2dec('88C5'), hex2dec('7F6E'), ...
                    hex2dec('0020'), hex2dec('30E1'), hex2dec('30E2')])), ...
                    "reason", "Recorded API field name in the measured API notes.")];
            violations = strings(0, 1);
            for document = TestPublicDocumentation.publicDocuments()
                text = string(fileread(document));
                for entry = allowed
                    text = replace(text, entry.text, "");
                end
                codeUnits = double(char(text));
                hasJapanese = any((codeUnits >= hex2dec('3040') & codeUnits <= hex2dec('30FF')) | ...
                    (codeUnits >= hex2dec('3400') & codeUnits <= hex2dec('4DBF')) | ...
                    (codeUnits >= hex2dec('4E00') & codeUnits <= hex2dec('9FFF')) | ...
                    (codeUnits >= hex2dec('F900') & codeUnits <= hex2dec('FAFF')));
                if hasJapanese
                    violations(end + 1) = "Unexpected Japanese characters in " + document; %#ok<AGROW>
                end
            end
        end

        function references = documentApiReferences()
            root = TestPublicDocumentation.projectRoot();
            documents = fullfile(root, [ ...
                "README.md", "docs/quickstart.md", "CHANGELOG.md", ...
                "docs/assembly_guide.md", "docs/demo_guide.md"]);
            textParts = arrayfun(@fileread, documents, UniformOutput=false);
            text = join(string(textParts), newline);
            packages = '(client|io|pipeline|util|visualization)';
            pattern = ['elab\.' packages '(\.[A-Za-z][A-Za-z0-9_]*)*'];
            references = unique(string(regexp(text, pattern, 'match')));
        end

        function missing = missingElabApis(references)
            root = TestPublicDocumentation.projectRoot();
            missing = strings(0, 1);
            for reference = references(:).'
                parts = split(reference, ".");
                folder = fullfile(root, "src", "+elab");
                exists = false;
                for index = 2:numel(parts)
                    name = parts(index);
                    if index == numel(parts)
                        exists = isfolder(fullfile(folder, "+" + name)) || ...
                            isfile(fullfile(folder, name + ".m"));
                    else
                        folder = fullfile(folder, "+" + name);
                    end
                end
                if ~exists
                    missing(end + 1) = reference; %#ok<AGROW>
                end
            end
        end

        function violations = comparisonTermViolations()
            root = TestPublicDocumentation.projectRoot();
            documents = fullfile(root, ["README.md", "CHANGELOG.md"]);
            terms = ["PPMS", "iLab", "Clustermarket", "Stratocore", ...
                "Chemotion", "ChemConverter", "Open IRIS", "nmrXiv", ...
                "NP-MRD", "GakuNin", "ARIM", "Kyoto", "NAIST", "Kyushu"];
            violations = strings(0, 1);
            for document = documents
                text = string(fileread(document));
                for term = terms
                    pattern = ['(?i)\<' regexptranslate('escape', char(term)) '\>'];
                    if ~isempty(regexp(text, pattern, 'once'))
                        violations(end + 1) = term + " in " + document; %#ok<AGROW>
                    end
                end
            end
        end

        function violations = linkViolations()
            documents = TestPublicDocumentation.publicDocuments();
            violations = strings(0, 1);
            for source = documents
                links = regexp(string(fileread(source)), ...
                    "\[[^\]]*\]\(([^)\s]+)", "tokens");
                for token = links
                    target = string(token{1}{1});
                    if startsWith(target, ["http:", "https:", "mailto:", "../../issues/"])
                        continue
                    end
                    parts = split(target, "#", 2);
                    destination = parts(1);
                    if destination == ""
                        destinationPath = source;
                    else
                        destinationPath = fullfile(fileparts(source), destination);
                    end
                    if ~endsWith(lower(destinationPath), ".md")
                        continue
                    end
                    destinationPath = TestPublicDocumentation.canonicalPath(destinationPath);
                    if ~isfile(destinationPath)
                        violations(end + 1) = "Missing link target: " + source + " -> " + target; %#ok<AGROW>
                        continue
                    end
                    if numel(parts) == 2 && parts(2) ~= "" && ...
                            ~ismember(parts(2), TestPublicDocumentation.headingAnchors(destinationPath))
                        violations(end + 1) = "Missing link anchor: " + source + " -> " + target; %#ok<AGROW>
                    end
                end
            end
        end

        function anchors = headingAnchors(document)
            lines = splitlines(string(fileread(document)));
            headings = regexprep(lines(startsWith(lines, "#")), "^#+\s*", "");
            anchors = strings(0, 1);
            for heading = headings(:).'
                anchor = lower(erase(heading, "`"));
                characters = char(anchor);
                keep = isstrprop(characters, "alphanum") | ...
                    ismember(characters, ['_', ' ', '-']);
                anchor = string(characters(keep));
                anchor = replace(strtrim(anchor), " ", "-");
                if anchor ~= ""
                    anchors(end + 1) = anchor; %#ok<AGROW>
                end
            end
            explicitTokens = regexp(fileread(document), ...
                '<a\s+id="([^"]+)"', "tokens");
            explicit = string(cellfun(@(token) token{1}, explicitTokens, ...
                "UniformOutput", false));
            anchors = [anchors(:); explicit(:)];
        end

        function path = canonicalPath(path)
            path = string(java.io.File(char(path)).getCanonicalPath());
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end

        function opening = readmeOpening()
            root = TestPublicDocumentation.projectRoot();
            documents = TestPublicDocumentation.publicDocuments();
            readme = documents(documents == fullfile(root, "README.md"));
            opening = extractBefore(string(fileread(readme)), 501);
        end

        function text = readPublicDocument(name)
            root = TestPublicDocumentation.projectRoot();
            documents = TestPublicDocumentation.publicDocuments();
            document = documents(documents == fullfile(root, name));
            text = string(fileread(document));
        end

        function section = markdownSection(document, heading)
            section = extractAfter(document, heading);
            section = extractBefore(section, newline + "## ");
        end
    end
end
