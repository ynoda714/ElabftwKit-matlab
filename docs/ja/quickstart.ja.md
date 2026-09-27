---
tracks_english_commit: "424dbf0"
---

> この日本語訳は英語版より古い場合があります。最新の情報は対応する英語版を参照してください。

[English Quick Start](../quickstart.md)

# Quick Start

このガイドでは、新しいチェックアウトからオフラインプレビュー、または eLabFTW への
一連の記録を実行するまでを説明します。

## 前提条件

- MATLAB R2022a 以降。add-on は不要です。
- Python は不要です。
- 到達可能な eLabFTW インスタンス。ローカルの Docker 環境については
  [ローカル eLabFTW のセットアップ](elabftw_setup.ja.md)に従ってください。
  この環境は `https://localhost:3148` の self-signed HTTPS を使います。
- Read/Write API key。`elab.api_key_env` で指定した環境変数
  （既定は `ELAB_API_KEY`）か、`config/apiKey.txt` の 1 行だけに保存します。
  どちらも Git では追跡されません。

## セットアップ

1. eLabFTW を起動します。リポジトリのローカル環境では
   [ローカル eLabFTW のセットアップ](elabftw_setup.ja.md)に従います。
2. [eLabFTW 情報設計](../elab_structure.md)に記載された Experiment category、
   Experiment status、Resource category、Template を作成します。すべての名前は、
   対応する設定値と 1 文字も違わず一致しなければなりません。
   Resource status は事前に作成しないでください。Section 1 が、不足している 5 つの
   定義と色を作成します。
   `elab.pipeline.bootstrapStructure` を使うと、この item bootstrap より前に、設定した
   category と Draft experiment status を作成できます。セットアップの詳細は
   [eLabFTW 情報設計](../elab_structure.md)にあります。
   Resource category の名前は `elab.instrument_category`、`sample_category`、
   `consumable_category`、`sop_category` で設定します。
3. プロジェクトルートで設定と 4 つのマスターデータ例をコピーします。

   ```powershell
   Copy-Item config\settings.example.json config\settings.json
   Copy-Item data\list\instruments.example.csv data\list\instruments.csv
   Copy-Item data\list\consumables.example.csv data\list\consumables.csv
   Copy-Item data\list\instrument_map.example.csv data\list\instrument_map.csv
   Copy-Item data\list\sample_map.example.csv data\list\sample_map.csv
   Copy-Item data\list\qc_specs.example.csv data\list\qc_specs.csv
   ```

   Section 0b は、コピー先がない場合に限り `instrument_map.example.csv` から
   `instrument_map.csv` を、`sample_map.example.csv` から `sample_map.csv` を、
   `qc_specs.example.csv` から `qc_specs.csv` をコピーします。
   instruments と consumables のリストはコピーしません。
4. サーバーに合うように `config/settings.json` を編集します。`elab.base_url`、
   `elab.ca_cert`（ローカル環境では `docker/certs/server.crt`）、Category name、
   `elab.labels.*` 以下のすべての値を設定します。API key は前提条件に記載した
   場所に保存し、`settings.json` には保存しません。

   取り込みに関する設定の既定値は次のとおりです。

   | 設定 | 既定値 | 動作 |
   |---|---:|---|
   | `elab.timezone` | `""` | 実行環境の IANA timezone を記録します。必要なら明示的に設定します。 |
   | `elab.instrument_category` | `"Instrument"` | Instrument 用の Resource category です。 |
   | `elab.sample_category` | `"Sample"` | Sample 用の Resource category です。 |
   | `elab.consumable_category` | `"Consumable"` | Consumable 用の Resource category です。 |
   | `elab.sop_category` | `"SOP"` | SOP 用の Resource category です。 |
   | `elab.item_search_limit` | `50` | `ensureItem` の候補数上限（正の整数）です。上限で完全一致が無ければ、重複 item を作る前に停止します。 |
   | `elab.report_list_limit` | `1000` | Report の Session 一覧上限（正の整数）です。上限に達しても Report は作成され、Notes に警告が付きます。 |
   | `ingest.attach_raw` | `"auto"` | 上限以下の raw ファイルだけを添付します。`always` / `never` で上書きできます。 |
   | `ingest.attach_raw_max_mb` | `25` | `auto` の raw ファイル添付上限です。超過時は raw ファイルを添付せず記録を作ります。 |
   | `ingest.archive_mode` | `"move"` | 処理済みファイルを移動します。`copy` は inbox の原本を残し、`leave` は入力ファイルを変更しません。 |

## サーバーなしで試す

プロジェクトルートからオフラインの quick-look script を実行します。

```matlab
addpath(genpath("src"));
run("scripts/quick_look.m")
```

6 つの mock instrument ファイルを作成して解析し、プレビュー図を
`result/runs/<timestamp>_quicklook/` 以下に出力します。API call は行いません。

## 一連の処理を実行する

`main_elabftw.m` を開き、MATLAB の current folder を project root にします。
必要に応じて Section 0a の 4 つの option を編集します。

| Option | 既定値 | 意味 |
|---|---:|---|
| `opt.generateMock` | `true` | Section 2 で 6 つの決定的な mock instrument ファイルを書き込みます。 |
| `opt.doBootstrap` | `true` | Section 1 で不足している Instrument と Consumable item を作成します。 |
| `opt.reportYear` | 現在の年 | Section 4 で使う Report year を指定します。 |
| `opt.reportMonth` | 現在の月 | Section 4 で使う Report month を指定します。 |

Section 0b から Ctrl+Enter を押すと、section を 1 つずつ実行できます。代わりに
F5 を押すと、ファイルに並んだすべての section を 1 回ずつ実行できます。

## Sections

| Section | 処理 | eLabFTW とファイルへの影響 |
|---|---|---|
| Section 0a | 4 つの user option を定義します。 | ファイルを変更せず、API 呼び出しも行いません。 |
| Section 0b | `src/` を path に追加し、プロジェクトルートを解決し、設定と API key を読み、2 つの不足したリストファイルを準備して client を構築します。 | `sample_map.csv` と `qc_specs.csv` の例をコピーすることがあります。eLabFTW entry は作りません。 |
| Section 1 | `opt.doBootstrap` が `true` のとき item を bootstrap します。 | 5 つの本来の Resource status を作成してから、CSV リストから Instrument と Consumable item を作り、新しい item に色付きの OK / InStock status を割り当てます。同じ title の既存 item は変更しません。リストがなければ警告を出して skip します。 |
| Section 2 | `opt.generateMock` が `true` のとき mock run を生成します。 | 当日 09:00 から 40 分おきに測定された決定的な XRD、Raman、FTIR、NMR、LC-MS、SEM ファイルを `data/inbox/` に書き込みます。 |
| Section 3 | measurement inbox を処理します。 | Draft Session experiment を作成し、設定に従って raw ファイルを upload し、quick-look 図は常に upload します。一致する item を link し、台帳と在庫を更新し、設定した保管処理を行って `.elab.json` sidecar を書きます。 |
| Section 4 | `opt.reportYear` と `opt.reportMonth` の Report を作ります。 | 測定日で Session を選び、section を実行するたびに 1 件の Report experiment と、その CSV と chart の出力を作成します。 |
| Section 5 | `data/qc_inbox/` の standard-sample ファイルを `qc_specs.csv` と照合します。 | 一致したファイルに Draft QC experiment を作ります。acceptance rule がないファイルは inbox に残ります。 |

## 期待される結果

- Section 1 は `data/list/instruments.csv` と `data/list/consumables.csv` を
  読みます。Instrument と Consumable item を作りますが、同じ title の既存 item は
  上書きしません。どちらかのファイルがなければ警告を記録し、そのリストを
  skip します。5 つの Resource status は手作業で準備する必要がありません。
  Resource 一覧では色付きの印として表示され、filter にも使えます。既存 item にある
  custom `status` の値は残り、次に台帳、在庫、QC の該当する更新を行ったとき、
  本来の status が割り当てられます。
- Section 2 は XRD、Raman、FTIR、NMR、LC-MS、SEM の 6 つのファイルを
  `data/inbox/` に書き込みます。測定日時は当日 09:00 から 40 分おきです。同じ日に
  繰り返し生成した内容は同一ですが、別の日に生成すると内容が変わり、新しい測定として
  記録されます。
- 最初の Section 3 では、6 件の Draft Session experiment を作ります。
  それぞれに quick-look 図を添付し、既定の `auto` では 25 MB 以下の
  raw ファイルも添付します。quick-look 図は各 experiment の本文にも表示されます。
  custom field は Measurement、Instrument parameters、Provenance の見出しでまとまり、
  最初の group が Session の概要を、Provenance が kit・MATLAB・parser・preview の設定を
  記録します。
  `instrument_map.csv` は安定したファイルパターンを個別の Instrument に、`sample_map.csv` は
  測定パターンを Sample にそれぞれ束縛します。2 つの Instrument が同じ技法を使う場合は、
  装置固有の prefix やフォルダ名など、区別できる部分文字列を使ってください。
  record はどちらか一方の束縛だけを持つこともできます。Instrument だけの record は台帳を
  更新し、Sample だけの record は更新しません。曖昧な一致は link しません。
  `instrument_title` を使う旧形式の sample map は、移行の間、警告付きで受け付けられます。
  既定では処理済みファイルを `data/processed/` に移動し、その隣に
  再構築用 sidecar を書きます。同名ファイルは上書きせず timestamp suffix を付けます。
  `copy` は inbox の原本を残し、`leave` は sidecar を run directory に書いて入力ファイルを
  変更しません。同じファイルをもう一度入れると、Session category 内に `data_file_hash` がすでに存在する
  ため `skipped` になります。同じ hash の QC experiment があっても Session
  は `skipped` になりません。したがって、Section 2 と Section 3 を 2 回目に実行すると、
  Section 3 が最初の実行で記録した決定的な 6 つの mock instrument ファイルはすべて `skipped`
  になります。
- Section 4 は測定日が指定した月に含まれる Session を集計し、Report experiment を
  作ります。本文には対象期間と合計の要約、装置時間の積み上げグラフ、読みやすい装置・project・
  operator の表、推定値を説明する注記が表示されます。
  既存のレポートを検索しないため、実行するたびに Report experiment が 1 件増えます。
  そのため F5 を 2 回押すと、指定した月の Report が
  2 件作られます。
- Section 5 は `data/qc_inbox/` のファイルを `qc_specs.csv` で評価し、QC category に
  Draft experiment を作ります。一致する rule がないファイルは inbox に残ります。
  QC category 内に同じ `data_file_hash` の experiment がすでにある場合に限り、ファイルは
  `skipped` になります。したがって、Section 3 で記録済みの決定的な mock instrument ファイルを
  `data/qc_inbox/` に置くと、QC experiment が 1 件作られます。その同じ standard-sample
  ファイルを Section 5 に再投入したときは `skipped` になります。

### もう一度実行する

同じファイルを再投入しても、同じ category の experiment は 1 件だけです。
`skipped` になったファイルは台帳と在庫の処理に進まないため、使用量と消費量が二重に反映されることはありません。
このワークフローは一度に 1 つだけ実行してください。2 つの MATLAB session、2 台の computer、重複する scheduled run から同時に実行しないでください。
並行実行すると、両方が重複確認を通過して experiment が重複し、台帳または在庫の更新が片方失われることがあります。
途中で止まった実行のやり直しも保証の範囲外です。結果は停止した位置によって変わり、復旧機能は今後のバージョンで対応予定です。
別の日に生成した mock data は測定日時が異なるため、新しい測定として記録されます。
Section 4 は意図的に異なり、実行するたびに Report experiment が 1 件増えます。

MATLAB が生成する eLabFTW entry はすべて、人が確認するための Draft です。

## NMR 実験フォルダを記録する

Bruker の 1 次元 experiment フォルダを 1 つ `data/inbox/` に置きます。フォルダ自体が
1 件の測定であり、`acqus` と `fid` を含む必要があります。`ser` を含むフォルダは
2 次元データであり、対応していないため `data/failed/` に移動されます。

オフラインで試すための合成フォルダを作るには、次を実行します。

```matlab
addpath(genpath("src"));
folderPath = elab.io.writeMockNmrRun("data/inbox");
```

この例は合成データだけを作成します。実データを使うことも配布することもありません。

対応するフォルダでは、`##$DATE` から取得した測定日時を使い、有効な audit 由来の
所要時間が 1 つに定まらない場合は、取得設定から計算した所要時間を source
`calculated` として記録します。フォルダ全体の hash を、原本を変えずに記録し、
quick-look 図と、AnyNMR の版・処理条件を含む `provenance.json` を作成します。
provenance file には timestamp・利用者名・path を含めません。フォルダ自体は
添付されず、代わりに元の場所と hash が記録されます。

AnyNMR の処理が失敗した場合は、警告付きで記録は続きますが、preview と
`provenance.json` は作られません。Instrument と Sample の束縛には、
[期待される結果](#期待される結果)にある既存の `instrument_map.csv` と
`sample_map.csv` の説明を使ってください。実サーバへの NMR 記録の書き込みは、
実 experiment フォルダで確認済みです（[Verification Record](../verification.md#nmr-folders-live)）。
実機の接続は未確認です。実行した MATLAB の版とプラットフォームは
[Platform Support](../platform_support.md) を参照してください。

## API を直接呼ぶ

次の例は `main_elabftw.m` と同じ順序で API key を探し、設定から 2 つの
TLS setting を client に渡します。

```matlab
addpath(genpath("src"));
resolveProjectRoot();
addpath(genpath("src"));
cfg = loadConfig();

apiKey = string(getenv(cfg.elab.api_key_env));
if apiKey == ""
    keyFile = fullfile("config", "apiKey.txt");
    if isfile(keyFile)
        apiKey = strtrim(string(fileread(keyFile)));
    else
        error("elab:main:apiKeyMissing", ...
            "No API key. Set env var %s or create config/apiKey.txt.", ...
            cfg.elab.api_key_env);
    end
end

client = elab.client.Client(cfg.elab.base_url, apiKey, ...
    cfg.elab.allow_self_signed, cfg.elab.ca_cert);
info = client.getJson("/info")
```

## Tests を実行する

unit test とオフライン smoke test を1つの suite として実行します。

```matlab
addpath(genpath("src"));
suite = [testsuite("tests/unit"), testsuite("tests/smoke")];
runner = matlab.unittest.TestRunner.withNoPlugins;
results = runner.run(suite);
fprintf("RESULT: %d PASS / %d FAIL / %d Total\n", ...
    sum([results.Passed]), sum([results.Failed]), numel(results));
```

## Troubleshooting

**`elab:main:apiKeyMissing`**

`elab.api_key_env` で指定した環境変数を設定するか、
`config/apiKey.txt` の 1 行に key を保存します。

**`elab:client:resolveId:notFound`**

設定の Category name または Resource category name は eLabFTW と完全に
一致する必要があります。再入力せず、name をコピーしてください。たとえば日本語名の
`QC・校正` は U+30FB KATAKANA MIDDLE DOT を含み、別の middle-dot character では
ありません。[eLabFTW 情報設計](../elab_structure.md)も参照してください。

**`MATLAB:webservices:SSLConnectionSystemFailure` または `SEC_E_UNTRUSTED_ROOT`**

`elab.ca_cert` に発行元の certificate ファイルを設定します。ローカル環境では
`docker/certs/server.crt` を使います。`elab.allow_self_signed` は host-name verification
だけを無効にします。certificate-chain verification は無効にしないため、これだけでは
untrusted-root error を解決できません。

**API operation が HTTP error を返す**

`<base_url>/api/v2/` の live Swagger documentation と
`src/+elab/+client/Client.m` の route を比較してください。eLabFTW API route は
server version によって異なる場合があります。

**生成されたファイルの場所**

run artifact は `result/runs/` 以下の timestamp directory にあります。

## Log format

通常の出力ではリポジトリの logging helper を使います。run は次のように表示されます。

```text
[HH:MM:SS][INFO]  --- MAIN | Section 3: Watch and log  [eLabFTW] ---
[HH:MM:SS][INFO]  watchAndLog: 6 file(s)
[HH:MM:SS][INFO]    [logged] xrd_SMP-2026-001.xy  https://localhost:3148/experiments.php?mode=view&id=12
[HH:MM:SS][WARN]  consumeInventory: 'X' has no numeric 'quantity' extra field; skipping.
```
