---
tracks_english_commit: "72c5e1c"
---

> この日本語訳は英語版より古い場合があります。最新の情報は対応する英語版を参照してください。

[English Assembly Guide](../assembly_guide.md)

# 組み立てガイド

## 原則

`src/` は、装置ファイルの読み込み、記録の作成、item のリンク、図の描画のための部品を提供します。
入口のスクリプトは一つの固定製品ではなく組み立て例なので、各施設の運用に合う流れを選べます。

## 4 つの組み立て例

| 例 | できること | 状態 | 入口 |
|---|---|---|---|
| A. 監視・自動記録（推奨） | 人が起動しなくても inbox のファイルを記録します。 | 予定 | — |
| B. 手動バッチ | 選んだワークフローの section をまとめて実行します。 | 現在利用可 | [`main_elabftw.m`](../../main_elabftw.m) |
| C. GUI | 画面からワークフローを開始します。 | 予定 | — |
| D. 自分で組む | 選んだ部品で施設用のワークフローを組みます。 | 現在利用可 | [`scripts/example_custom_ingest.m`](../../scripts/example_custom_ingest.m) |

## A. 監視・自動記録（推奨）

自動記録は、人が各実行を始めなくても記録を残せるため、推奨する理想形です。これは予定であり、まだ提供していません。当面は、手動バッチの Section 3 を人が定期的に実行してください。

同時に 2 つの取り込みを実行しないでください。重複の判定は、一度に一つの実行を前提にしています。

## B. 手動バッチ

[`main_elabftw.m`](../../main_elabftw.m) は section ごとに実行できます。

| Section | 内容 |
|---|---|
| 0a | 利用者パラメータを設定します。 |
| 0b | path、configuration、client を準備します。 |
| 1 | 最初の Instrument と Consumable item を作成します。 |
| 2 | 試行用の synthetic instrument ファイルを作成します。 |
| 3 | inbox の測定ファイルを記録します。 |
| 4 | 月次利用レポートを作成します。 |
| 5 | QC ファイルを処理します。 |

設定と最初の実行は [Quick Start](quickstart.ja.md) を参照してください。

## C. GUI

GUI は予定です。

## D. 自分で組む

以下の取り込み stage は、付属のワークフローが使う部品です。完全な契約は [Session ingest stages](../function_reference.md#session-ingest-stages) を参照してください。

| 段 | 呼び方 | 受け取るもの → 返すもの | 差し替えの例 |
|---|---|---|---|
| 対応表を読む | `readSampleMap` | 設定 → sample-map table | 施設で保守する対応表を使います。 |
| ファイルを対応付ける | `matchSample` | map とファイル名 → `binding` | ファイル名ではなく barcode を対応付けます。 |
| ファイルを読む | `readSessionFile` | ファイル path → `session` | 施設で対応するファイル format を読みます。 |
| 重複を調べる | `findLoggedSession` | client、設定、`session` → 既存 id または空 | 検索元を変えても確認は残します。 |
| context を加える | `addSessionContext` | `session` → source と timezone を含む `session` | ローカルの provenance 値を加えます。 |
| 記録を作る | `createSessionExperiment` | `session`、`binding`、run context → experiment id | `extraFields` で field を足します。 |
| item をリンクする | `linkSessionItems` | experiment id と `binding` → linked item id | 記録だけの flow では省きます。 |
| 退避する | `archiveIngested` | ファイル、outcome、設定 → archive path | 施設の retention policy を使います。 |
| sidecar を書く | `writeSessionSidecar` | session、記録 id、archive context → sidecar | sidecar output を省きます。 |

`session` は装置ファイル一つを読んだ構造化結果で、context を加えると source location と timezone を持ちます。`binding` は sample map の一致した一行で、一致しないときは空です。

次の順で stage を組みます。対応表を読み、ファイルを列挙し、各ファイルを対応付けて読み、既存の記録を確認し、context を加え、記録を作り、item をリンクしてから退避し、sidecar を書きます。item link、`updateInstrumentLedger`、`consumeInventory`、sidecar JSON は省いたり差し替えたりできます。重複の確認を省いてはいけません。同じファイルから二つの記録が作られるためです。退避も省いてはいけません。次の実行で同じファイルを再び読むためです。`leave` retention setting では、退避は意図的にファイルの move も copy もしません。

`createSessionExperiment(..., extraFields=...)` に施設固有の field を渡せます。field は標準 field の後ろに追加されます。

[`scripts/example_custom_ingest.m`](../../scripts/example_custom_ingest.m) は、section ごとに実行できる例です。Section 0 で追加 field とカスタム図を添付するかを設定し、Sections 1 から 4 を順に実行します。この例はファイルを読み、記録を作成し、一致した item をリンクし、ファイルを退避して sidecar を書きます。Instrument と Consumable の台帳は意図的に更新しません。

custom spectrum または chromatogram の図を作るときは、`figure` を直接呼ぶ代わりに [`lightFigure`](../function_reference.md#srcelabvisualization) を使います。直接作った図は、dark theme など実行者の MATLAB theme を保存画像に残すことがあります。ファイル名や sample 名などデータ由来の文字には、underscore を TeX として解釈させないよう `Interpreter="none"` を使います。描画の動作は [`lightFigure` と `quickLook`](../function_reference.md#srcelabvisualization) を参照してください。

## すべての組み立て例に共通する規則

- 記録を作る前に `findLoggedSession` で重複を確認します。この段を飛ばすと、同じファイルの記録を二つ作ることがあります。
- 一度に実行する取り込みは一つだけにします。
- 図は `lightFigure` で作り、データ由来の文字には `Interpreter="none"` を指定します。保存される図は light theme になり、label を文字どおりに表示します。
- 記録は常に Draft で作られます。人が確認し、署名します。
