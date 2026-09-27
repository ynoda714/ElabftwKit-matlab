# Integrating with eLabFTW 5.6.12: notes from the wire

Things that cost us time when driving eLabFTW's REST API v2 from MATLAB, and that
are not in the official documentation. Every claim here was measured against a
running server, not inferred.

## Scope

| | |
|---|---|
| eLabFTW | 5.6.12 (`elabftw/elabimg@sha256:db6f369e0593203ff2d3045671eaadceca60ccfefa5ef22a9b62f485d3cd4a4f`) |
| MySQL | 8.4.11 |
| Host | Windows 11, Docker Desktop 29.1.2 |
| Client | MATLAB R2026a Update 2, `webread` + `matlab.net.http` only |
| Measured | 2026-09-11, 2026-09-13, 2026-09-14 and 2026-09-20 |

**Version matters more than usual here.** Several findings below are about field
names and route shapes, which are exactly the things that move between releases.
6.0.0 was already at release-candidate stage when these notes were written. Treat
everything as "true for 5.6.12" and re-check after an upgrade.

Parts 1 and 2 are language-agnostic. Part 3 is MATLAB-specific.

---

## Part 1: Standing the server up

### 1.1 A malformed `SECRET_KEY` lets you register but not log in

**Symptom.** Account creation succeeds. Logging in with the correct password returns
a generic "An error occurred". The password is not the problem.

**In the container log:**

```
elabftw.ERROR: Defuse\Crypto\Exception\BadFormatException:
  Encoded data is shorter than expected.
  at /elabftw/vendor/defuse/php-encryption/src/Encoding.php:233
  request: POST /app/controllers/LoginController.php
```

**Cause.** `SECRET_KEY` must be a `defuse/php-encryption` ASCII-safe key: **136
characters beginning `def000`**. A plain random hex string — the obvious thing to
reach for, e.g. `openssl rand -hex 32` — is 64 characters and fails to load as a key
at all.

Registration does not decrypt anything, so it succeeds. Login does, so only login
breaks. That split is what makes this hard to diagnose.

**Fix.** Have the container generate one:

```bash
docker compose exec web php -r 'require "/elabftw/vendor/autoload.php"; \
  echo \Defuse\Crypto\Key::createNewRandomKey()->saveToAsciiSafeString();'
```

Verify before restarting:

```bash
docker compose exec web php -r 'require "/elabftw/vendor/autoload.php"; \
  $k = \Defuse\Crypto\Key::loadFromAsciiSafeString(getenv("SECRET_KEY")); \
  $c = \Defuse\Crypto\Crypto::encrypt("test", $k); \
  echo \Defuse\Crypto\Crypto::decrypt($c, $k) === "test" ? "OK\n" : "NG\n";'
```

Password hashes are bcrypt and independent of `SECRET_KEY`, so existing accounts keep
working after the key is replaced.

> `https://get.elabftw.net/?secretkey` is the documented generator, but fetching it
> with `curl` returns the `elabctl.sh` script rather than a key. Use a browser, or
> generate in-container as above.

### 1.2 `DISABLE_HTTPS=true` is not a plain-HTTP mode

**Symptom.** With `DISABLE_HTTPS=true` and a port mapped to 443, the browser shows:

> eLabFTW works only in HTTPS. Please enable HTTPS on your server or ensure
> X-Forwarded-Proto header is correctly sent by the load balancer.

**Cause.** The flag means "TLS is terminated upstream — trust `X-Forwarded-Proto`",
not "serve plain HTTP". With no reverse proxy in front, nothing sets that header and
the application-level check rejects the request.

**Measured:**

```
GET /login.php  plain HTTP                      -> 400  (the message above)
GET /login.php  + X-Forwarded-Proto: https      -> 200  (login form renders)
```

**Fix.** For a local trial with no proxy, leave `DISABLE_HTTPS=false` and use the
self-signed certificate (see 1.4). Use `DISABLE_HTTPS=true` only when something in
front really does terminate TLS and set the header.

### 1.3 Attachments are not persisted unless you say so

Two volumes are needed, not one:

| Container path | Contents |
|---|---|
| `/var/lib/mysql` | database |
| **`/elabftw/uploads`** | **attachments** |

Mount only the first and every uploaded file disappears the next time the container
is recreated. The database survives, so the entries remain — pointing at files that
are gone.

### 1.4 The generated certificate has no SAN, and changes on every recreate

The entrypoint generates a self-signed certificate whose **CN is `openssl rand -hex 6`**
and which carries **no `subjectAltName` at all**:

```
subject = C=FR, ST=France, L=Paris, O=elabftw, CN=7503b4544353
subjectAltName = (none)
```

`/etc/nginx/certs/` lives in the container's writable layer, not a volume, so the
certificate is regenerated on every `down`/`up`. Anything that pins or trusts it
breaks on the next restart. Clients that verify hostnames cannot match `localhost`
against it at all.

**Mounting your own certificate is safe.** The entrypoint only generates one when the
file is absent:

```sh
# /usr/sbin/docker-entrypoint.sh
108:  if [ ! -f /etc/nginx/certs/server.crt ]; then
114:      randcn=$(openssl rand -hex 6)
115:      openssl req \
121:          -subj "/C=FR/ST=France/L=Paris/O=elabftw/CN=$randcn" \
122:          -keyout /etc/nginx/certs/server.key \
123:          -out   /etc/nginx/certs/server.crt
```

So generate a certificate carrying `subjectAltName = DNS:localhost, IP:127.0.0.1` and
bind-mount it read-only over `/etc/nginx/certs/server.crt` and `server.key`. nginx
reads those exact paths (`/etc/nginx/conf.d/elabftw.conf`). The result is stable
across recreates and verifiable by a client.

### 1.5 Timezone defaults to Europe/Paris

`TZ` and `PHP_TIMEZONE` both default to `Europe/Paris`. Set them explicitly, and
check all three layers rather than assuming the environment variable took:

```bash
docker compose exec web date                      # container
docker compose exec web php -r 'echo date("P");'  # PHP
docker compose exec mysql mysql -e "SELECT @@system_time_zone;"
```

Getting this wrong shifts recorded timestamps, which surfaces much later as
month-boundary errors in aggregation — where it is easily mistaken for a bug in your
own date arithmetic.

### 1.6 `Draft` is not a default status

Out of the box the experiment statuses are:

```
Running / Success / Need to be redone / Fail
```

If your workflow assumes a "created by a machine, awaiting human review" state, create
it yourself. Note what your client does when the status is missing — silently falling
back to the server default means the policy stops applying without anyone noticing.

### 1.7 `up -d` returning is not the service being ready

Measured on the same machine, same images, warm cache:

| | |
|---|---|
| `docker compose up -d` returns | **6.5 s** |
| Both containers healthy, page answers | **124 s** |

Use `docker compose up -d --wait`. Quoting the first number in a setup guide makes
readers diagnose a working stack as broken — which happened to us before we measured
the second one.

---

## Part 2: The API contract

### 2.1 Categories and statuses are team-scoped

There is no top-level route for them:

```
GET /api/v2/experiments_categories               -> 400  "Invalid endpoint"
GET /api/v2/teams/current/experiments_categories -> 200
GET /api/v2/teams/{id}/experiments_categories    -> 200
```

`teams/current` follows the API key's team context and saves a round trip to discover
the numeric team id.

The same applies to `experiments_status`, `resources_categories` and `items_status`.
`items_types` is top-level — but see the next section before you use it.

### 2.2 Three different names for what looks like one thing

This one cost the most time.

| Concept | UI page | DB table | **API name** |
|---|---|---|---|
| Item categories (Instrument, Sample, …) | *Resource categories* (`/resources-categories.php`) | `items_categories` | **`resources_categories`** |
| Resource templates | *Resource templates* (`/resources-templates.php`) | `items_types` | `items_types` |

Three traps in one:

- The **API name does not match the table name.** `GET /api/v2/items_categories`
  returns 400; `resources_categories` is the name. It is defined in
  `src/Enums/ApiSubModels.php` as `ResourcesCategories = 'resources_categories'`.
- **`items_types` exists and returns 200**, so it looks like the right endpoint. It is
  a different concept, and on a fresh instance it returns `[]` — which reads as "no
  categories created yet" rather than "wrong endpoint".
- The UI page is *Resource categories*, singular **Resource**.

### 2.3 `category` and `status`, not `category_id` and `status_id`

```
PATCH /api/v2/experiments/<id>
  {"category_id": 7}   -> 400
  {"category": 7}      -> 200   category_title = ...
  {"status_id": 5}     -> 400
  {"status": 5}        -> 200   status_title = Draft
```

Composite PATCH requests are processed sequentially. The server applies keys in JSON
order, stops at the first rejected key, returns 400, and leaves earlier changes in place.
The result therefore depends on key order. These two requests were measured against
separate experiments:

```
  PATCH {"title":"AAA_title_first","date":"2026-09-11","category_id":7}
    -> 400
  GET
    -> title = "AAA_title_first", date = "2026-09-11"

  # This experiment was created with title = "seed_2" before the test.
  PATCH {"category_id":7,"title":"BBB_category_first","date":"2026-09-11"}
    -> 400
  GET
    -> title = "seed_2"
```

An empty creation request also receives server defaults rather than blank fields:

```
  POST /api/v2/experiments {}  -> 201
  GET
    -> title = "Untitled"
    -> date = current server date ("2026-09-11" in this measurement)
    -> category = null, status = null
```

If a rejected key comes before `title` or `date`, those later keys are not applied; if
it comes after them, their changes remain. Do not interpret a 400 response as a no-op:
doing so leads to incorrect retry and idempotency decisions after a partial update.

Resource statuses use the same field name. On 2026-09-20, the verifier measured the
complete lifecycle with disposable resource status #1 and item #62, then deleted both:

```
POST  /api/v2/teams/current/items_status {}
  -> created status #1 with title = "Untitled"
PATCH /api/v2/teams/current/items_status/1 {"title":"...","color":"28a745"}
  -> 200; both title and color applied
PATCH /api/v2/items/62 {"status":1}
  -> 200; status_title and status_color populated
PATCH /api/v2/items/62 {"status_id":1}
  -> 400
DELETE /api/v2/teams/current/items_status/1
  -> deleted
```

Creating a resource status is therefore a two-step operation: POST creates an
`Untitled` row and PATCH supplies its `title` and six-digit color without `#`.

### 2.4 An item's category is ignored on POST

```
POST  /api/v2/items          {"category_id": 1}  -> created, but category = null
PATCH /api/v2/items/<id>     {"category_id": 1}  -> 400
PATCH /api/v2/items/<id>     {"category": 1}     -> 200   category_title = Instrument
```

The POST does not error — it silently ignores the field. Create, then PATCH the
category, then read it back and verify.

### 2.5 Link routes need a `Content-Type`, not a body

```
POST /api/v2/experiments/<id>/items_links/<itemid>
  no body, no Content-Type          -> 400
  Content-Type: application/json    -> 201
  Content-Type + {}                 -> 201
```

The header is what matters; the body may be empty. An HTTP client that omits
`Content-Type` when there is nothing to send will fail here.

### 2.6 Valid top-level endpoints

A request to an unknown endpoint returns the list, which is the fastest way to check a
name on your own version:

```
apikeys, batch, compounds, config, dspace, experiments, experiments_templates,
exports, extra_fields_keys, event, events, favtags, idps, idps_sources, import,
info, instance, items, items_types, reports, storage_units, team_tags, teams,
todolist, unfinished_steps, users
```

### 2.7 `extra_fields` need no template

`metadata.extra_fields` can be written to an entry that has no template and no
category, and read back intact. Field types travel with the values in the request.

Pre-defining templates is worthwhile for how entries look and behave in the UI, but it
is **not** a prerequisite for API writes. Useful to know before hand-entering several
dozen field definitions.

### 2.8 Search extra fields with the `extrafield:` query syntax

**Symptom.** A plain full-text query for a known `data_file_hash` value returns no
matches, even though the value is present in an experiment's metadata.

**Measured:**

```
GET /api/v2/experiments?q=extrafield:data_file_hash:<hash>    -> matching experiment only
GET /api/v2/experiments?q=extrafield:data_file_hash:<absent>  -> n=0
GET /api/v2/experiments?q=<hash>                              -> n=0

GET /api/v2/experiments?limit=2                               -> newest 2 experiments
GET /api/v2/experiments?limit=2&offset=2                      -> next 2 experiments
```

The `q` value must be URL-encoded, including the separators in the `extrafield:`
expression.

**Implication.** Use the server-side `extrafield:` query rather than paging through
all experiments. `watchAndLog` performs this lookup once per input file; paging would
add multiple round trips per file and require decoding every retrieved experiment's
metadata on the client.

### 2.9 Unknown query parameters are silently ignored

**Symptom.** A misspelled or invented filter does not produce a 400 response.
Instead, the request succeeds and appears at first glance to be a valid search.

**Measured:**

```
GET /api/v2/experiments?totally_bogus_param=xyz       -> 200, all experiments
GET /api/v2/experiments?extra_fields_search=<hash>    -> 200, all experiments
```

Neither parameter filters the response, and neither is rejected.

**Implication.** A malformed search returns all entries, not zero entries. Code that
takes the first result can therefore misidentify an unrelated experiment as a match.
Always revalidate the requested field and value on the client. This is why
`findExperimentByExtraField` narrows candidates on the server and then checks each
candidate's decoded metadata locally.

### 2.10 Filter experiment dates with `extended`, not `since` or `before`

`GET /experiments` in 5.6.12 does not use `since` or `before` as date filters. They
are silently ignored in the same way as the unknown parameters in 2.9.

**Measured with 37 experiments dated 2026-09-01, 2026-09-11, or 2026-09-12:**

```
state=1,2,3&limit=1000                                      -> 37
state=1,2,3&since=2026-09-12&before=2026-09-12&limit=1000    -> 37
since=1999-01-01&before=1999-01-31&limit=1000                -> 1 (dated 2026-09-11)
totally_bogus=1&limit=1000                                   -> 1 (the same experiment)
```

The measured date filter is the `date:` expression in `extended`. A `..` range
includes both endpoints, while `<` is strict and `>=` includes its boundary:

```
extended=date:2026-09-01..2026-09-10                         -> 0
extended=date:2026-09-01..2026-09-11                         -> includes 2026-09-11
extended=date:2026-09-11..2026-09-30                         -> includes 2026-09-11
extended=date:<2026-09-11                                    -> 0
extended=date:<2026-09-12                                    -> includes 2026-09-11
extended=date:>=2026-09-11                                   -> includes 2026-09-11
state=1,2,3&extended=date:>=2026-09-01 AND date:<2026-09-12  -> 35
state=1,2,3&extended=date:>=2026-09-12 AND date:<2026-10-01  -> 2
state=1,2,3&extended=date:>=2026-08-01 AND date:<2026-09-01  -> 0
extended=garbage:::                                          -> 400
```

The requests above sent the spaces around `AND` URL-encoded as `%20`; sending them
unencoded was not tried. The malformed `extended` value above
returned `400` with an extended-search syntax error; it did not return an
unfiltered result. These measurements cover the `date:` syntax only.

### 2.11 A plain experiment listing omits `metadata`

**Symptom.** An experiment has extra fields when fetched on its own, but the same
experiment in a `GET /experiments` listing has no metadata. Code that reads
`extra_fields` from the listing sees every field as missing and falls back to its
defaults without any error.

**Measured with the same 37 experiments as 2.10.** 17 of them have metadata when
fetched individually; 20 have none.

```
GET /experiments/12                                   -> metadata present, 17 extra fields
GET /experiments?limit=5                              -> metadata null
GET /experiments?q=XRD&limit=5                        -> metadata null  (same experiment 12)
GET /experiments?q=extrafield:data_file_hash:<hash>   -> metadata present
GET /experiments?cat=7&extended=date:>=2026-09-01 AND date:<2026-10-01
                                                      -> metadata present, 17 extra fields

Per experiment, all 37, compared with GET /experiments/<id>:
  state=1,2,3&limit=40                     -> null for all 37, including the 17 that have metadata
  state=1,2,3&extended=date:>=2026-09-01   -> present for exactly the 17 that have metadata
```

Through MATLAB `webread`, the plain listing yields structs with no `metadata` field
at all, while the `extended` listing yields the metadata JSON text.

**What was and was not established.** A plain listing and a plain full-text `q`
returned no metadata. The `extrafield:` query and the `extended` `date:` query did.
Other `extended` expressions and other query forms were not tried, and the reason for
the difference was not investigated.

**Implication.** Do not assume a listing carries `metadata` because one query form
did. When a listed entry has no metadata, fetch it individually before concluding it
has no extra fields.


### 2.12 PATCHing `metadata` replaces all extra fields; `updatemetadatafield` updates one

**Symptom.** Writing one extra field to an existing item makes every other extra field
disappear. The request succeeds.

**Measured on throwaway items (each deleted afterwards):**

```
PATCH /items/<id> {"metadata": "{\"extra_fields\": {usage_hours_total, calibration_due}}"}  -> 200
GET                                                            -> usage_hours_total, calibration_due
PATCH /items/<id> {"metadata": "{\"extra_fields\": {status}}"}  -> 200
GET                                                            -> status only
```

The `metadata` value is stored as sent. There is no merge with what was there.

**The field-level update.** An `action` of `updatemetadatafield` changes the value of
fields that already exist and leaves everything else in place:

```
seed: extra_fields {usage_hours_total, calibration_due, "装置 メモ" (select, options ["a"])}
      plus a top-level "elabftw" key
PATCH {"action":"updatemetadatafield","usage_hours_total":"13"}           -> 200, value 13, all else unchanged
PATCH {"action":"updatemetadatafield","usage_hours_total":"20",
       "calibration_due":"2027-01-01"}                                   -> 200, both updated
PATCH {"action":"updatemetadatafield","装置 メモ":"b"}                     -> 200, updated; options kept
PATCH {"action":"updatemetadatafield","usage_hours_total":21.5}          -> 500  (JSON number)
PATCH {"action":"updatemetadatafield","calibration_due":"not-a-date"}    -> 200, stored as sent
PATCH {"action":"updatemetadatafield","status":"Check"}                  -> 200, nothing happens (field absent)
PATCH {"action":"updatemetadatafield","extra_fields":{"usage_hours_total":"14"}} -> 200, nothing happens
PATCH /experiments/<id> {"action":"updatemetadatafield",...}             -> 200, same behaviour on experiments
```

Three traps:

- **A field that does not exist is silently ignored** with `200`. Read the entry back to
  confirm the value changed.
- **Values must be JSON strings.** A JSON number returns `500`.
- **Values are not validated** against the field type or its options.

**Why not read, merge and write the whole `metadata` back.** In MATLAB R2026a,
`jsondecode` followed by `jsonencode` does not reproduce the original: a key such as
`"装置 メモ"` becomes `"x____"`, a one-element array `[3]` becomes `3`, and `null` becomes
`[]`. Fields an administrator created in the eLabFTW UI are exactly the ones that break.
Update existing fields with `updatemetadatafield`; write the whole `metadata` only to an
entry that has none yet.

**Adding a missing field while preserving metadata.** The field-level action cannot
create a field. For that case, preserve the server's original JSON text and insert
one encoded member immediately after the `{` matched by
`"extra_fields"\s*:\s*\{`. Add a comma after the new member only when the object was
not empty, PATCH the resulting metadata text, and read it back. Do not pass the
complete metadata through `jsondecode` and `jsonencode`.

This was measured on 2026-09-20 by the verifying agent using throwaway items #59
and #60. An object containing a top-level `elabftw` member, a Japanese extra-field
key, select `options`, and existing numeric fields retained all of them after the
text insertion. A later `updatemetadatafield` request could change the inserted
field. Inserting into `{"extra_fields":{}}` also produced valid metadata. Both
items were deleted and confirmed with `state=3`.

### 2.13 Extra-field groups and positions control the rendered layout

Measured on 2026-09-21 with disposable experiments #116 and #117, both deleted and
confirmed with `state=3` afterwards:

- `metadata.elabftw.extra_fields_groups`, encoded as an array of objects with numeric
  `id` and text `name`, renders those names as group headings in the experiment UI.
- An extra field's `group_id` selects its heading, and its `position` determines its
  order within that group. The order of keys in the saved JSON does not determine the
  rendered order; a field saved earlier appeared later when its `position` required it.
- `PATCH {"action":"updatemetadatafield", ...}` changes field values while retaining
  each field's `group_id` and `position` and retaining the top-level
  `elabftw.extra_fields_groups` definitions.

Existing records measured before this change had no top-level `elabftw` member. They
remain valid ungrouped metadata and are not migrated.

---

## Part 3: Calling it from MATLAB

No add-ons; `webread` plus `matlab.net.http`.

### 3.1 `webwrite` cannot PATCH this server

```
curl -X PATCH -H 'Content-Type: application/json' -d '{"title":"x"}'   -> 200
webwrite(url, struct("title","x"), opts)              % opts.RequestMethod="patch"
                                                                        -> 400
webwrite(url, jsonencode(struct("title","x")), opts)                    -> 400
matlab.net.http + MessageBody with UTF-8 payload                        -> 200
```

curl succeeds against the same URL with the same body, so the route and payload are
fine. Route PATCH through `matlab.net.http`:

```matlab
hdr = [matlab.net.http.HeaderField("Authorization", apiKey), ...
       matlab.net.http.HeaderField("Content-Type", "application/json")];
body = matlab.net.http.MessageBody;
body.Payload = unicode2native(jsonencode(fields), "UTF-8");
req = matlab.net.http.RequestMessage('PATCH', hdr, body);
```

Building `MessageBody` from bytes also avoids the body being JSON-encoded a second
time, which happens if you hand `jsonencode`'s output to the message as a string.

GET via `webread` works and needs no change.

### 3.2 `RequestMessage` rejects a `string` method

```matlab
matlab.net.http.RequestMessage("POST", hdr)   % string -> MATLAB:RequestMessage:invalidType
matlab.net.http.RequestMessage('POST', hdr)   % char   -> OK
matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.POST, hdr)  % enum -> OK
```

In a codebase that prefers `"..."` literals this is easy to introduce and it fails at
construction, before any request is sent — so a transport-layer test will catch it but
a unit test that never reaches the network will not.

### 3.3 TLS options are narrower than you may expect

In R2026a, `matlab.net.http.HTTPOptions` exposes **`CertificateFilename` and
`VerifyServerName` only**. There is no `VerifyServerCertificate`. `weboptions` has
`CertificateFilename` but **no way to skip hostname verification at all**.

Against the stock self-signed certificate from 1.4:

| Approach | Result |
|---|---|
| `weboptions` + `CertificateFilename = ''` | fail |
| `weboptions` + the server's certificate | fail — hostname mismatch |
| `matlab.net.http` + `VerifyServerName = false` | fail — `SEC_E_UNTRUSTED_ROOT` |
| `matlab.net.http` + certificate file + `VerifyServerName = false` | **200** |

Note that the only working combination excludes `webread`, because `weboptions` cannot
relax the hostname check. If your client uses `webread` for GET — a reasonable choice,
since its decoding is simpler — you need a certificate whose SAN actually matches the
host you connect to. That is the practical argument for 1.4: replacing the
certificate is what keeps both transports usable.

---

## Quick reference

| You want | 5.6.12 |
|---|---|
| List experiment categories | `GET /teams/current/experiments_categories` |
| List statuses | `GET /teams/current/experiments_status` |
| List item categories | `GET /teams/current/resources_categories` |
| Set an experiment's category | `PATCH /experiments/<id>` `{"category": <id>}` |
| Set an experiment's status | `PATCH /experiments/<id>` `{"status": <id>}` |
| Set an item's category | create, then `PATCH /items/<id>` `{"category": <id>}` |
| Link an experiment to an item | `POST /experiments/<id>/items_links/<itemid>` with a `Content-Type` |
| New entry's id | `Location` response header on `POST` |
| Search an extra-field value | `GET /experiments?q=extrafield:<field>:<value>` with URL-encoded `q` |
| Treat search results as matches | Revalidate the field and value client-side; unknown parameters return unfiltered `200` |
| Filter experiments by a half-open date range | `GET /experiments?extended=date:>={start} AND date:<{end}` with URL-encoded spaces; recheck returned `date` values client-side |
| Read extra fields of listed experiments | Do not rely on the listing: a plain listing returns `metadata` null; fetch `GET /experiments/<id>` when it is absent |
| Change some extra fields of an existing entry | `PATCH {"action":"updatemetadatafield","<field>":"<string>"}`; absent fields are ignored with `200`, so read back. PATCHing `metadata` replaces every field |
| Add one missing extra field | Insert one JSON member into the original `metadata` text's `extra_fields` object, PATCH the text, and read back; do not decode and re-encode the complete metadata |

## Reproducing these

The compose file, certificate generation, and a script that exercises the whole
transport layer against a live server live in this repository. See
[`elabftw_setup.md`](elabftw_setup.md) for the environment and
`scripts/live_connection_check.m` for the checks.
