---
tracks_english_commit: "6de5d22"
---

> この日本語訳は英語版より古い場合があります。最新の情報は対応する英語版を参照してください。

# eLabFTW x MATLAB Facility Logging Kit

> **これは非公式の、コミュニティが保守するプロジェクトです。** eLabFTW の開発元である Deltablot との
> 提携・支援・承認はありません。「eLabFTW」は Deltablot の登録商標です。

[English README](../../README.md)

このキットは、共用機器室や大学研究室で、装置出力ファイルを構造化された eLabFTW レコードにします。
MATLAB が測定ファイルを読み、Draft レコードを作成し、元ファイルとクイックルック図を添付します。
利用時間や在庫のような設備記録も更新できます。

## これは何か、何でないか

- **部品の集まりであり、完成品ではありません。** このキットは、装置出力ファイルを構造化された eLabFTW レコードにし、
  利用台帳、消耗品在庫、月次レポートをその上に組み立てる方法を示します。ほとんどの部分は疑似ファイルだけで
  確認されています。[確認済みの範囲](#確認済みの範囲)を参照してください。
- **NMR が最も作り込まれた部分です。** Bruker experiment フォルダを 1 つの測定単位として記録し、各ファイルの
  hash、データから読み取った測定日時、クイックルック図、そして固定・無改変の外部 NMR 処理ライブラリで作った
  provenance record を持ちます（[Third-Party Notices](../../THIRD_PARTY_NOTICES.md) と
  [Platform Support](../platform_support.md) を参照）。実 experiment ファイルで、実サーバーに対しても
  確認済みです。実機の接続は未確認です。
- **他の reader は例です。** XRD、Raman、FTIR、LC-MS、SEM の reader は、このキットが定義した単純なレイアウトを
  扱うデモであり、どの装置の native な形式でもありません。適応させるには
  [Adding a Format](../adding_a_format.md) に従ってください。
- **提供していないもの:** 予約突合、課金、アクセス制御、スペクトル編集。すべてのレコードは、人が確認するための
  Draft として作られます。

## サーバーなしで試す

プロジェクトルートで次を実行します。

```matlab
addpath(genpath("src"));
run("scripts/quick_look.m")
```

このスクリプトは疑似測定ファイルを作成し、パースしてクイックルック図を描画します。
eLabFTW もネットワーク接続も必要ありません。

## eLabFTW に接続する

MATLAB R2022a 以降と eLabFTW インスタンスが必要です。MATLAB のアドオンは不要です。
このキットは、stock の eLabFTW サーバーと REST API v2 だけで通信します。API key 以外に、
サーバー側の変更・plugin・管理者側のインストールは一切必要ありません。
対応する接続経路は eLabFTW 5.6.12 で確認されています。サーバー設定、configuration、
最初の記録実行については [Quick Start](quickstart.ja.md) を参照してください。

まだサーバーをお持ちでない場合、このリポジトリにはローカルの試用サーバー用 Docker Compose ファイルが
含まれています（Windows、Docker Desktop）。概略: `docker/.env.example` を `docker/.env` にコピーして
秘密情報を設定し、localhost 用の証明書を作り、`docker` ディレクトリから `docker compose up -d` を実行して
データベースを初期化し、`https://localhost:3148` で最初のアカウントと API key を作成します。詳しい手順と、
デモ用の 2 つ目の別サーバーの立て方は [Local eLabFTW setup](elabftw_setup.ja.md) にあります。

## 現在利用できる機能

| シナリオ | 内容 | 状態 |
|---|---|---|
| オフライン preview | 疑似入力を作り、パースしてクイックルック図を書き出します。 | [Available now](../verification.md#offline-preview) |
| A1 セッション記録 | inbox ファイルから Draft セッションレコードを作り、重複ファイルをスキップします。 | [Available now](../verification.md#session-logging) |
| A3 QC | 標準試料ファイルを確認して判定を記録します。 | [Available now](../verification.md#qc-check) |
| D1 装置台帳 | リンクした装置の利用時間と校正フィールドを更新します。 | [Available now](../verification.md#instrument-ledger) |
| D2 消耗品在庫 | 数量を更新し、設定された再発注状態を適用します。 | [Available now](../verification.md#consumable-inventory) |
| R1 月次利用レポート | CSV 要約と図を含むレポートレコードを作成します。 | [Available now](../verification.md#monthly-report) |
| NMR experiment フォルダ | Bruker experiment フォルダを 1 つの単位として、hash・クイックルック図・provenance ファイルとともに記録します。 | [Available now](../verification.md#nmr-folders-live) |
| D3 予約突合 | 予約と記録済みセッションを比較します。 | Planned |

## 確認済みの範囲

上のサーバー確認は、NMR を除き、このキットが作成する疑似入力ファイルで実施しています。実機はまだ接続していません。

公開データセット由来の実 NMR experiment フォルダを、実サーバーに対して
（[live server](../verification.md#nmr-folders-live)）、また別途オフラインでサーバーなしに
（[synthetic input](../verification.md#nmr-folders-synthetic)、[real files](../verification.md#nmr-folders-real)）
確認しています。環境、手順、結果は [Verification Record](../verification.md) を参照してください。

## 独自のワークフローを組む

[Assembly Guide](assembly_guide.ja.md) には、手動バッチから独自の ingest ワークフローまで、
提供された部品を組み合わせる 4 つの方法があります。

## レコードの作られ方

- すべてのレコードは Draft で作られ、人が確認して署名します。
- `data_file_hash` で同じ入力ファイルを識別し、重複レコードを防ぎます。
- 実行ごとの成果物は `result/runs/<timestamp>/` に書き出されます。
- 添付、archive、カテゴリ名、上限は MATLAB のソースを編集せずに設定できます。

## データ方針

正本は eLabFTW のレコードではなく、装置が出力した原本のファイルです。このキットは、装置 PC や共有フォルダから
原本を読み取り専用で読みます。eLabFTW が受け取るのは、そこから作った 1 つのレコードであり、唯一のコピーでは
ありません。raw ファイルをレコードに添付するのは、それが単一ファイルで、設定した上限（既定 25 MB）以下のときだけです。
それを超える、または複数ファイルの入力は、hash と場所で記録します。実行が成功すると、既定では入力ファイルを
移動します（`copy` を設定すればコピーに、`leave` を設定すればそのままに変更できます）。同名の既存ファイルを
上書きすることはありません。測定日時は UTC に正規化せず、元のタイムゾーンのまま保持します。正確な設定キーは
[Function Reference](../function_reference.md) と [Algorithm Guide](../algorithm_guide.md) を参照してください。

## 文書

| 文書 | 目的 |
|---|---|
| [Quick Start](quickstart.ja.md) | サーバーを設定し、提供されたワークフローを実行します。 |
| [Local eLabFTW setup](elabftw_setup.ja.md) | Docker でローカルの試用サーバーと、別のデモ用サーバーを立てます。 |
| [Demo Guide](../demo_guide.md) | 空のサーバーからデモを再現します。 |
| [Assembly Guide](assembly_guide.ja.md) | 提供された部品からワークフローを選択または組み立てます。 |
| [Adding a Format](../adding_a_format.md) | 単一ファイルまたはフォルダ形式の装置形式を追加します。 |
| [eLabFTW Structure](../elab_structure.md) | 必要なカテゴリ、フィールド、アイテムを設定します。 |
| [Function Reference](../function_reference.md) | 公開された MATLAB 関数とオプションを調べます。 |
| [Algorithm Guide](../algorithm_guide.md) | パース、指標、テスト根拠を理解します。 |
| [Log Format](../log_format.md) | コンソール出力と実行ごとの成果物を読み取ります。 |
| [Platform Support](../platform_support.md) | キットを実行した MATLAB の版とプラットフォームを確認します。 |
| [Verification Record](../verification.md) | 確認した環境、手順、結果を確認します。 |
| [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) | 外部ソフトウェアと先行実装の通知を確認します。 |

## ライセンスと eLabFTW との関係

このキットは [MIT License](../../LICENSE) で提供されます。利用者が用意した eLabFTW サーバーと
REST API で通信します。eLabFTW 本体はこのプロジェクトに同梱もフォークもされていません。

## 訳語の方針

画面や設定に現れる語は、英語版と一致させるため英語のまま記載します。カテゴリ名、設定キー、
ボタン名、`Draft` などがこれに当たります。一般的な説明では日本語を使います。たとえば
`Draft`、`Session`、`data_file_hash` は英語のままにし、file、record、ledger、inventory は
それぞれ「ファイル」「レコード」「台帳」「在庫」とします。
