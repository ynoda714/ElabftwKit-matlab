classdef TestDockerCompose < matlab.unittest.TestCase
    % TestDockerCompose  Guard isolated demonstration Compose settings.

    methods (Test)
        function test_uploadsVolumeUsesConfigurableDefault(tc)
            compose = TestDockerCompose.composeText();

            tc.verifyTrue(contains(compose, ...
                "${ELABFTW_UPLOADS_VOLUME:-elabftw-uploads}"));
        end

        function test_mysqlVolumeUsesConfigurableDefault(tc)
            compose = TestDockerCompose.composeText();

            tc.verifyTrue(contains(compose, ...
                "${ELABFTW_MYSQL_VOLUME:-elabftw-mysql-data}"));
        end

        function test_portUsesConfigurableDefault(tc)
            compose = TestDockerCompose.composeText();

            tc.verifyNotEmpty(regexp(compose, ...
                '(?m)^\s*-\s+"\$\{ELABFTW_PORT:-3148\}:443"\s*$', "once"));
        end

        function test_siteUrlFollowsConfigurablePort(tc)
            compose = TestDockerCompose.composeText();

            tc.verifyNotEmpty(regexp(compose, ...
                '(?m)^\s*SITE_URL:\s+https://localhost:\$\{ELABFTW_PORT:-3148\}\s*$', "once"));
        end

        function test_projectNameUsesDockerDefault(tc)
            compose = TestDockerCompose.composeText();

            tc.verifyNotEmpty(regexp(compose, ...
                '(?m)^name:\s+\$\{ELABFTW_PROJECT_NAME:-docker\}\s*$', "once"));
        end

        function test_imageTagsAndDigestCommentsRemain(tc)
            compose = TestDockerCompose.composeText();
            expected = [ ...
                "image: elabftw/elabimg:5.6.12"; ...
                "image: mysql:8.4.11"; ...
                "sha256:db6f369e0593203ff2d3045671eaadceca60ccfefa5ef22a9b62f485d3cd4a4f"; ...
                "sha256:3466ba4a4828aa8d46fb7c3bc16b67b781c98413cf4ea0fac6feaa6e881faa26"];

            present = arrayfun(@(entry) contains(compose, entry), expected);
            tc.verifyTrue(all(present));
        end

        function test_demoTemplateDefinesEveryComposeVariable(tc)
            composeNames = TestDockerCompose.composeVariableNames();
            demoNames = TestDockerCompose.demoVariableNames();

            tc.verifyEqual(numel(composeNames), 7);
            missing = setdiff(composeNames, demoNames);
            tc.verifyEmpty(missing);
        end

        function test_demoTemplateUsesDistinctRuntimeNames(tc)
            values = TestDockerCompose.demoRuntimeValues();

            tc.verifyNotEqual(values.projectName, "docker");
            tc.verifyNotEqual(values.port, "3148");
            tc.verifyNotEqual(values.uploadsVolume, "elabftw-uploads");
            tc.verifyNotEqual(values.mysqlVolume, "elabftw-mysql-data");
        end

        function test_demoTemplateLeavesSecretsEmpty(tc)
            values = TestDockerCompose.demoSecretValues();

            tc.verifyEmpty(values);
        end

        function test_demoGuideMentionsEnvironmentFile(tc)
            section = TestDockerCompose.demoGuideSection();

            tc.verifyTrue(contains(section, "--env-file"));
            tc.verifyTrue(contains(section, ".env.demo"));
        end

        function test_demoGuideRequiresConfigurationCheckBeforeDeletion(tc)
            section = TestDockerCompose.demoGuideSection();

            tc.verifyTrue(contains(section, "down -v"));
            tc.verifyTrue(contains(section, ...
                "docker compose --env-file .env.demo config"));
        end
    end

    methods (Static, Access = private)
        function text = composeText()
            root = TestDockerCompose.projectRoot();
            text = string(fileread(fullfile(root, "docker", "compose.yml")));
        end

        function names = composeVariableNames()
            matches = regexp(TestDockerCompose.composeText(), ...
                '\$\{(ELABFTW_[A-Z_]+)(?::-[^}]*)?\}', "tokens");
            names = unique(string(cellfun(@(match) match{1}, matches, ...
                UniformOutput=false)));
        end

        function names = demoVariableNames()
            template = TestDockerCompose.demoTemplateText();
            matches = regexp(template, '(?m)^(ELABFTW_[A-Z_]+)=', "tokens");
            names = string(cellfun(@(match) match{1}, matches, UniformOutput=false));
        end

        function values = demoRuntimeValues()
            values = struct( ...
                "projectName", TestDockerCompose.demoValue("ELABFTW_PROJECT_NAME"), ...
                "port", TestDockerCompose.demoValue("ELABFTW_PORT"), ...
                "uploadsVolume", TestDockerCompose.demoValue("ELABFTW_UPLOADS_VOLUME"), ...
                "mysqlVolume", TestDockerCompose.demoValue("ELABFTW_MYSQL_VOLUME"));
        end

        function values = demoSecretValues()
            names = ["ELABFTW_SECRET_KEY"; "ELABFTW_DB_PASSWORD"; ...
                "ELABFTW_DB_ROOT_PASSWORD"];
            values = arrayfun(@TestDockerCompose.demoValue, names);
            values = values(values ~= "");
        end

        function value = demoValue(name)
            template = TestDockerCompose.demoTemplateText();
            token = regexp(template, '(?m)^' + name + '=([^\r\n]*)$', "tokens", "once");
            assert(~isempty(token), "Missing demo-template key: %s", name);
            value = string(token{1});
        end

        function text = demoTemplateText()
            root = TestDockerCompose.projectRoot();
            text = string(fileread(fullfile(root, "docker", ".env.demo.example")));
        end

        function section = demoGuideSection()
            root = TestDockerCompose.projectRoot();
            guide = string(fileread(fullfile(root, "docs", "elabftw_setup.md")));
            section = extractAfter(guide, "## Run a separate demo server");
            section = extractBefore(section, newline + "## ");
        end

        function root = projectRoot()
            root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end
end
