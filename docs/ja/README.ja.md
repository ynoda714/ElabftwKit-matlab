---
tracks_english_commit: "f90e7b7"
---

> この日本語訳は英語版より古い場合があります。最新の情報は対応する英語版を参照してください。

# eLabFTW x MATLAB Facility Logging Kit

このキットは、共用機器室や大学研究室で、装置出力ファイルを構造化された eLabFTW レコードにします。
MATLAB が測定ファイルを読み、Draft レコードを作成し、元ファイルとクイックルック図を添付します。
利用時間や在庫のような設備記録も更新できます。

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
対応する接続経路は eLabFTW 5.6.12 で確認されています。サーバー設定、configuration、
最初の記録実行については [Quick Start](quickstart.ja.md) を参照してください。

## 現在利用できる機能

| シナリオ | 内容 | 状態 |
|---|---|---|
| オフライン preview | 疑似入力を作り、パースしてクイックルック図を書き出します。 | [Available now](../verification.md#offline-preview) |
| A1 セッション記録 | inbox ファイルから Draft セッションレコードを作り、重複ファイルをスキップします。 | [Available now](../verification.md#session-logging) |
| A3 QC | 標準試料ファイルを確認して判定を記録します。 | [Available now](../verification.md#qc-check) |
| D1 装置台帳 | リンクした装置の利用時間と校正フィールドを更新します。 | [Available now](../verification.md#instrument-ledger) |
| D2 消耗品在庫 | 数量を更新し、設定された再発注状態を適用します。 | [Available now](../verification.md#consumable-inventory) |
| R1 月次利用レポート | CSV 要約と図を含むレポートレコードを作成します。 | [Available now](../verification.md#monthly-report) |
| D3 予約突合 | 予約と記録済みセッションを比較します。 | Planned |

## 確認済みの範囲

上の確認は、このキットが作成する疑似入力ファイルで実施しています。実機はまだ接続していません。
環境、手順、結果は [Verification Record](../verification.md) を参照してください。

## 独自のワークフローを組む

[Assembly Guide](../assembly_guide.md) には、手動バッチから独自の ingest ワークフローまで、
提供された部品を組み合わせる 4 つの方法があります。

## レコードの作られ方

- すべてのレコードは Draft で作られ、人が確認して署名します。
- `data_file_hash` で同じ入力ファイルを識別し、重複レコードを防ぎます。
- 実行ごとの成果物は `result/runs/<timestamp>/` に書き出されます。
- 添付、archive、カテゴリ名、上限は MATLAB のソースを編集せずに設定できます。

## 文書

| 文書 | 目的 |
|---|---|
| [Quick Start](quickstart.ja.md) | サーバーを設定し、提供されたワークフローを実行します。 |
| [Assembly Guide](../assembly_guide.md) | 提供された部品からワークフローを選択または組み立てます。 |
| [eLabFTW Structure](../elab_structure.md) | 必要なカテゴリ、フィールド、アイテムを設定します。 |
| [Function Reference](../function_reference.md) | 公開された MATLAB 関数とオプションを調べます。 |
| [Algorithm Guide](../algorithm_guide.md) | パース、指標、テスト根拠を理解します。 |
| [Log Format](../log_format.md) | コンソール出力と実行ごとの成果物を読み取ります。 |
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
