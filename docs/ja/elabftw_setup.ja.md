---
tracks_english_commit: "07870f2"
---

> この日本語訳は英語版より古い場合があります。最新の情報は対応する英語版を参照してください。

[English version](../elabftw_setup.md)

# Docker でローカル eLabFTW を動かす (Windows)

公式のインストール手順: https://doc.elabftw.net/install.html

このガイドでは、リポジトリの `docker/compose.yml` を使い、`https://localhost:3148`
で self-signed HTTPS の試用環境を動かします。database と attachment は Docker の
named volume に保存されるため、container を再作成してもデータは残ります。

## 永続化の仕組み

database と attachment は named volume を使います。Windows の Docker Desktop では、
host bind mount を使うと container の実行ユーザー(UID 101)との権限問題が起きることが
あります。試用環境では、Explorer から直接ファイルを見られることよりも、手動の権限変更なしに
確実に起動・再作成できることを優先します。

既定の attachment volume 名は `elabftw-uploads`、既定の database volume 名は
`elabftw-mysql-data` です。別名にしたい場合は環境ファイルの変数を設定してください。
`docker volume ls` で確認できます。バックアップを作るには下記の一時 container の手順を
使います。

## 初回セットアップ

1. **Docker Desktop for Windows** をインストールして起動します。
2. PowerShell でリポジトリの `docker` ディレクトリに移動します。
3. secret のテンプレートをコピーします。

   ```powershell
   Copy-Item .env.example .env
   ```

4. `docker/.env` の 3 つの項目に、それぞれ異なる十分に長いランダムな値を設定します。
   `ELABFTW_SECRET_KEY` は https://get.elabftw.net/?secretkey でも生成できます。
   `.env` は Git で追跡されません。実際の値を commit しないでください。
5. `docker` ディレクトリから次のコマンドを実行し、localhost 用の証明書を作ります。
   有効期限の 10 年は試用環境向けの設定で、SAN には `DNS:localhost` と
   `IP:127.0.0.1` を含みます。

   ```powershell
   docker run --rm --entrypoint sh --mount "type=bind,source=${PWD},target=/work" elabftw/elabimg:stable -c "mkdir -p /work/certs && openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 -keyout /work/certs/server.key -out /work/certs/server.crt -subj '/CN=localhost/O=eLabFTW local trial' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -addext 'basicConstraints=critical,CA:TRUE' && chmod 600 /work/certs/server.key"
   ```

   `docker/certs/` は Git で追跡されません。秘密鍵を commit しないでください。
6. サービスを起動し、database を初期化します。

   ```powershell
   docker compose up -d
   docker compose exec web bin/init db:install
   ```

7. ブラウザで `https://localhost:3148` を開き、self-signed 証明書の警告を一度承認し、
   最初の **Sysadmin account** を作り、**Team** を 1 つ作ります。
8. 右上のメニューから **Settings -> API keys** を開き、**Read/Write** の
   key を発行します。
9. MATLAB 用に、API key を環境変数か `config/apiKey.txt` に保存します。どちらも
   Git では追跡されません。`config/settings.example.json` をコピーした場合、既定の
   `base_url` はすでに `https://localhost:3148` です。`ca_cert` は
   `docker/certs/server.crt` に設定します。SAN が localhost と一致するため、
   `allow_self_signed` は `false` のままにします。

   ```powershell
   setx ELAB_API_KEY "3-xxxxxxxxxxxxxxxx"
   ```

## 起動を確認する

ブラウザで `https://localhost:3148` が開くことを確認します。証明書は self-signed
なので、初回はブラウザの警告を承認してください。API key を発行した後は、
`curl.exe` と `--insecure` で疎通を確認できます。

```powershell
curl.exe --insecure -H "Authorization: $env:ELAB_API_KEY" https://localhost:3148/api/v2/experiments
```

空配列(`[]`)を含む JSON が返れば、疎通は成功しています。

MATLAB Client を通して読み書きを確認するには、プロジェクトルートから次を実行します。
このスクリプトは `/info` と `/experiments` を読み、category を解決し、Draft の
確認用 entry を作成・削除します。category がない環境では、確認用 category を
一時的に作成・削除します。このチェックはオフラインの既定 test suite には含まれません。

```matlab
addpath(genpath("src"));
run("scripts/live_connection_check.m")
```

配信されている証明書を調べるには、次を実行します。生成した証明書の SHA-256
fingerprint、subject、SAN が表示されることを確認します。

```powershell
docker compose exec web sh -lc "openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -subject -fingerprint -sha256 -ext subjectAltName"
docker compose exec web openssl x509 -in /etc/nginx/certs/server.crt -noout -subject -fingerprint -sha256 -ext subjectAltName
```

同じ証明書が container 再作成後も残ることを確認するには、fingerprint を記録してから
次を実行し、証明書チェックをもう一度実行して比較します。

```powershell
docker compose down
docker compose up -d --wait
```

## 停止と再作成

```powershell
docker compose down
docker compose up -d
```

`down` は container と network だけを削除し、database と attachment は named volume に
残ります。したがって続けて `up -d` を実行すると、既存データのままサービスが
再作成されます。

```powershell
docker compose down -v
```

`down -v` は Compose が管理する named volume も削除します。database と attachment が
消えるため、意図的に環境をゼロから作り直すときだけ使ってください。どの volume が
削除されるかは環境ファイルによって決まります。`--env-file` を使う場合は、その
環境用の volume だけが削除されます。

## 別のデモ用サーバーを動かす

デモや画面用の資料には、別の空のサーバーを使います。volume 名、port、project 名が
開発用サーバーと異なるため、開発用のデータを共有しません。

リポジトリのルートから `docker/.env.demo.example` を `docker/.env.demo` に
コピーします。3 つの secret の値は開発環境とは別の値にしてください。すべての
コマンドで `docker compose --env-file .env.demo ...` を使います。既存の
`docker/certs/` の証明書は SAN が `localhost` なので、port だけが変わる場合は
そのまま使い回せます。

`docker` ディレクトリから、別のサーバーを起動して初期化します。

```powershell
docker compose --env-file .env.demo up -d
docker compose --env-file .env.demo exec web bin/init db:install
```

ブラウザでは `localhost` ではなく `https://127.0.0.1:3149` を開いてください。
両方のサーバーが同じ名前の session cookie を設定し、ブラウザは同じ host name の
port 間で cookie を共有します。`https://localhost:3148` の開発用サーバーに
ログインしていると、`localhost:3149` のデモ用サーバーはその cookie を受け取り、
たとえば API key を発行しようとしたときに "Authentication required" を返します。
証明書は `127.0.0.1` もカバーしており、ブラウザはこれを別の host として扱うため、
デモ用サーバーはそこで独自の cookie を保てます。

最初の Sysadmin と Team は、中立的な内容で作成してください。たとえば name は
`Demo Admin`、email は `demo-admin@example.com` などです。続けて
**Settings -> API keys** で Read/Write の key を発行します。開発用の key とは
別に保管してください。たとえば、デモ用サーバーと通信する MATLAB session でだけ
設定する環境変数などです。

MATLAB では `elab.base_url` を `https://127.0.0.1:3149` に設定します。
`elab.ca_cert` は `docker/certs/server.crt` のままにします。category と item は
[eLabFTW 情報設計](../elab_structure.md)の説明に従って準備します。

デモ用サーバーだけを削除・再作成するには、まず次のコマンドを実行し、volume 名が
開発用の名前ではなく `elabftw-demo-*` になっていることを確認します。

```powershell
docker compose --env-file .env.demo config
docker compose --env-file .env.demo down -v
```

`down -v` は環境ファイルで選ばれた named volume を削除するため、設定でデモ用の
volume 名を確認するまで実行しないでください。

## attachment をバックアップする

named volume の内容を tar archive にまとめるには、一時 container を使います。
`docker` ディレクトリから PowerShell で次を実行します。

```powershell
New-Item -ItemType Directory -Force backup | Out-Null
docker run --rm --mount source=elabftw-uploads,target=/data,readonly --mount type=bind,source=${PWD}\backup,target=/backup alpine tar czf /backup/uploads.tar.gz -C /data .
```

バックアップの保存先である `docker/backup/` は commit しないでください。

## 固定した版とアップグレード方針

この試用環境は eLabFTW 5.6.12 と MySQL 8.4.11 に固定しています。この
リポジトリに記載・記録されたすべての API の挙動は、eLabFTW 5.6.12 に対して
測定したものです。Compose file は計画的なアップグレードのために読みやすい
version tag を使い、実際にテストした build を特定できるよう、各 tag の隣に
確認済みの image digest を記録しています。

アップグレードするには、`docker/compose.yml` の image tag を編集してから、
`docker` ディレクトリでサービスを再作成します。`down` に `-v` を付けないでください。
named volume 内の database と upload したファイルが削除されてしまいます。

```powershell
docker compose down
docker compose up -d --wait
```

アップグレード後は必ず API contract を再確認してください。最低限
`scripts/live_connection_check.m` を実行し、失敗したチェックはすべて記録してから
新しい版を使ってください。eLabFTW 6.0.0 系は現在開発中で、major アップグレードは
API contract を変える可能性があります。本番環境では、この試用環境が優先する
再現性とは別に、security update を取り込む方針も定める必要があります。

## Windows Docker Desktop での実測

以下は Windows Docker Desktop で実測した挙動です。

- 2026-09-10、image の download を含む最初の `docker compose up -d` は
  110.2 秒かかりました。
- 2026-09-11、image を download 済みの状態で `docker compose down` に続けて
  `up -d` を実行したところ、**コマンドが戻るまで 6.5 秒、両方の container が
  healthy になりページが開くまで 124 秒** かかりました。この 2 つの時間を
  混同しないでください。`up -d` は container の作成後に戻り、サービスが
  応答した後ではありません。待ちたい場合は、health check の通過後に戻る
  `docker compose up -d --wait` を使ってください。数秒後にブラウザを開くと、
  起動に失敗したように誤解する可能性があります。
- `docker compose exec web bin/init db:install` は成功しました。
- self-signed 証明書を承認した状態で、`https://localhost:3148/login.php` は
  HTTP 200 を返しました。
- attachment の永続性は、別々の probe ファイルで 2 回確認しました。どちらの場合も、
  `docker compose down` に続けて `up -d` を実行した前後で SHA-256 が一致しました。
  - `m1-1-persistence-probe.txt`:
    `f1414fcccbcf2c93e3f1d334b44ca84ff04c0ad09e0eb534bf3cc110f4076f1f`
  - 削除済みの確認用 probe:
    `855aca1696c6d3b78448f9eba24c113abcbc938181dcb3579a563a9ee05c9b75`
- 再作成後も `login.php` はインストール画面に戻らず 200 を返し続けたため、
  database volume も永続化していることを確認しました。
- タイムゾーンは 3 層すべてで有効でした。container の `JST`、PHP の
  `Asia/Tokyo (+09:00)`、MySQL の `@@system_time_zone = JST` です。

## 本番運用への移行

- 施設の server に置く前に、self-signed 証明書を信頼された TLS 証明書に
  置き換えてください。
- 装置 PC と用途ごとに API key を分けて発行してください。装置 PC には
  Read/Write、reporting 端末には Read only にします。可能であれば、装置専用の
  service account を使ってください。
- raw データの正本は別に保管してください。設定した attachment 方針が許す場合に
  限り、raw の入力に eLabFTW の attachment を使います。大規模な導入では
  S3 backend も使えます。
