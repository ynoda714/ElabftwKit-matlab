# Run a local eLabFTW with Docker (Windows)

[Japanese version](ja/elabftw_setup.ja.md)

Official installation instructions: https://doc.elabftw.net/install.html

This guide uses the repository's `docker/compose.yml` to run a trial environment
with self-signed HTTPS at `https://localhost:3148`. The database and attachments
are stored in Docker named volumes, so recreating containers preserves them.

## Persistence model

The database and attachments use named volumes. On Windows Docker Desktop, a host
bind mount can encounter permission problems with the container's runtime user
(UID 101). For a trial environment, reliable startup and recreation without manual
permission changes take precedence over browsing the files directly in Explorer.

The default attachment-volume name is `elabftw-uploads`, and the default database volume
name is `elabftw-mysql-data`. Set their environment-file variables to use
different names. Inspect them with `docker volume ls`; use the temporary-container
procedure below to create a backup.

## First-time setup

1. Install and start **Docker Desktop for Windows**.
2. In PowerShell, change to the repository's `docker` directory.
3. Copy the secret template.

   ```powershell
   Copy-Item .env.example .env
   ```

4. Set distinct, sufficiently long random values for the three entries in
   `docker/.env`. `ELABFTW_SECRET_KEY` can also be generated at
   https://get.elabftw.net/?secretkey. `.env` is not tracked by Git; never commit
   real values.
5. From the `docker` directory, run the following command to create a localhost
   certificate. Its ten-year validity is for the trial environment, and its SAN
   includes `DNS:localhost` and `IP:127.0.0.1`.

   ```powershell
   docker run --rm --entrypoint sh --mount "type=bind,source=${PWD},target=/work" elabftw/elabimg:stable -c "mkdir -p /work/certs && openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 -keyout /work/certs/server.key -out /work/certs/server.crt -subj '/CN=localhost/O=eLabFTW local trial' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -addext 'basicConstraints=critical,CA:TRUE' && chmod 600 /work/certs/server.key"
   ```

   `docker/certs/` is not tracked by Git; never commit the private key.
6. Start the services and initialize the database.

   ```powershell
   docker compose up -d
   docker compose exec web bin/init db:install
   ```

7. Open `https://localhost:3148` in a browser, accept the self-signed-certificate
   warning once, create the first **Sysadmin account**, and create one **Team**.
8. In the upper-right menu, open **Settings -> API keys** and issue a
   **Read/Write** key.
9. Store the API key in an environment variable or `config/apiKey.txt` for MATLAB.
   Neither location is tracked by Git. If you copy `config/settings.example.json`,
   its local `base_url` is already `https://localhost:3148`. Set `ca_cert` to
   `docker/certs/server.crt`; because the SAN matches localhost, keep
   `allow_self_signed` set to `false`.

   ```powershell
   setx ELAB_API_KEY "3-xxxxxxxxxxxxxxxx"
   ```

## Confirm startup

Confirm that `https://localhost:3148` opens in a browser. Because the certificate
is self-signed, accept the browser warning on first use. After issuing an API key,
you can confirm connectivity with `curl.exe` and `--insecure`.

```powershell
curl.exe --insecure -H "Authorization: $env:ELAB_API_KEY" https://localhost:3148/api/v2/experiments
```

Connectivity is working when JSON is returned, including an empty array (`[]`).

To check reads and writes through the MATLAB Client together, run the following
from the project root. The script reads `/info` and `/experiments`, resolves a
category, and creates and deletes a Draft check entry. In an environment without
categories, it temporarily creates and removes a check category. This check is not
part of the offline default test suite.

```matlab
addpath(genpath("src"));
run("scripts/live_connection_check.m")
```

To inspect the certificate being served, run the following. Confirm that the
generated certificate's SHA-256 fingerprint, subject, and SAN are displayed.

```powershell
docker compose exec web sh -lc "openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -subject -fingerprint -sha256 -ext subjectAltName"
docker compose exec web openssl x509 -in /etc/nginx/certs/server.crt -noout -subject -fingerprint -sha256 -ext subjectAltName
```

To confirm that the same certificate survives container recreation, record its
fingerprint, run the following, then run the certificate check again and compare it.

```powershell
docker compose down
docker compose up -d --wait
```

## Stop and recreate

```powershell
docker compose down
docker compose up -d
```

`down` removes only containers and the network; it keeps the database and
attachments in the named volumes. A following `up -d` therefore recreates the
services with existing data.

```powershell
docker compose down -v
```

`down -v` also removes Compose-managed named volumes. It deletes the database and
attachments, so use it only when intentionally rebuilding the environment from
scratch. The environment file determines which volumes are removed; when using
`--env-file`, it removes the volumes for that environment.

## Run a separate demo server

Use a separate, empty server for demonstrations or screen materials. Its volume
names, port, and project name differ from the development server, so it does not
share the development data.

From the repository root, copy `docker/.env.demo.example` to `docker/.env.demo`.
Set the three secret values to values different from the development environment.
Use `docker compose --env-file .env.demo ...` for every command. The existing
`docker/certs/` certificate can be shared because its SAN is `localhost`, which
remains valid when only the port changes.

From the `docker` directory, start and initialize the separate server.

```powershell
docker compose --env-file .env.demo up -d
docker compose --env-file .env.demo exec web bin/init db:install
```

Open `https://127.0.0.1:3149` in the browser, not `localhost`. Both servers set a
session cookie with the same name, and a browser shares cookies between ports of
one host name. If you are logged in to the development server at
`https://localhost:3148`, the demo server at `localhost:3149` receives that cookie
and answers "Authentication required", for example when you issue an API key. The
certificate also covers `127.0.0.1`, which the browser treats as a separate host, so
the demo server keeps its own cookies there.

Create the first Sysadmin and Team with neutral details, for example the name
`Demo Admin` and email `demo-admin@example.com`. Then issue a Read/Write key under
**Settings -> API keys**. Keep it apart from the development key, for example in an
environment variable that you set only for the MATLAB session that talks to the demo
server.

For MATLAB, set `elab.base_url` to `https://127.0.0.1:3149`. Keep
`elab.ca_cert` as `docker/certs/server.crt`. Prepare categories and items as
described in [eLabFTW Structure](elab_structure.md).

To delete and recreate only the demo server, first run the following command and
confirm that the volume names are `elabftw-demo-*`, not the development names.

```powershell
docker compose --env-file .env.demo config
docker compose --env-file .env.demo down -v
```

The `down -v` command removes the named volumes selected by the environment file,
so do not run it until the configuration confirms the demo volume names.

## Back up attachments

Use a temporary container to package the named-volume content as a tar archive.
Run this in PowerShell from the `docker` directory.

```powershell
New-Item -ItemType Directory -Force backup | Out-Null
docker run --rm --mount source=elabftw-uploads,target=/data,readonly --mount type=bind,source=${PWD}\backup,target=/backup alpine tar czf /backup/uploads.tar.gz -C /data .
```

Do not commit the backup destination, `docker/backup/`.

## Pinned versions and upgrade policy

This trial environment is pinned to eLabFTW 5.6.12 and MySQL 8.4.11. All documented
and recorded API behavior in this repository was measured against eLabFTW 5.6.12.
The Compose file uses readable version tags for planned upgrades and records the
verified image digest next to each tag so the exact tested build remains identifiable.

To upgrade, edit the image tag in `docker/compose.yml`, then recreate the services
from the `docker` directory. Do not add `-v` to `down`, because that would delete
the database and uploaded files in the named volumes.

```powershell
docker compose down
docker compose up -d --wait
```

After every upgrade, recheck the API contract. At minimum, run
`scripts/live_connection_check.m` and record every failed check before relying on
the new version. The eLabFTW 6.0.0 series is currently under development, and a
major upgrade may change the API contract. A production deployment must also define
a separate security-update adoption process; that goal differs from this trial
environment's reproducibility priority.

## Measurements on Windows Docker Desktop

The following behavior was measured on Windows Docker Desktop.

- On 2026-09-10, the first `docker compose up -d`, including image download, took
  110.2 seconds.
- On 2026-09-11, with images already downloaded, `docker compose down` followed by
  `up -d` took **6.5 seconds until the command returned and 124 seconds until both
  containers were healthy and the page opened**. Do not confuse these two times:
  `up -d` returns after container creation, not after the service responds. When
  waiting, use `docker compose up -d --wait`, which returns after health checks
  pass. Opening a browser after only a few seconds can wrongly suggest that startup
  failed.
- `docker compose exec web bin/init db:install` succeeded.
- `https://localhost:3148/login.php` returned HTTP 200 when the self-signed
  certificate was accepted.
- Attachment persistence was checked twice with separate probe files. In both
  cases, SHA-256 matched before and after `docker compose down` followed by `up -d`.
  - `m1-1-persistence-probe.txt`:
    `f1414fcccbcf2c93e3f1d334b44ca84ff04c0ad09e0eb534bf3cc110f4076f1f`
  - A removed verification probe:
    `855aca1696c6d3b78448f9eba24c113abcbc938181dcb3579a563a9ee05c9b75`
- After recreation, `login.php` still returned 200 rather than returning to the
  installation screen, confirming that the database volume also persisted.
- Time zones were active at all three layers: container `JST`, PHP
  `Asia/Tokyo (+09:00)`, and MySQL `@@system_time_zone = JST`.

## Move to production operation

- Replace the self-signed certificate with a trusted TLS certificate before placing
  the service on a facility server.
- Issue API keys separately for each instrument PC and purpose: Read/Write for
  instrument PCs and Read only for reporting terminals. Where possible, use a
  dedicated service account for an instrument.
- Keep a separate durable primary copy of raw data. Use eLabFTW attachments for the
  raw input only when the configured attachment policy permits it; large deployments
  can also use an S3 backend.
