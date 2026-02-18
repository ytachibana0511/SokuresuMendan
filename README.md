# SokuresuMendan

SokuresuMendan は、**面談中に質問を検出し、回答案を最速で提示する** macOS 向けローカル完結 MVP です。

- 最重要目標: **質問に対して体感1秒で最初の回答案を表示**
- 構成: macOS アプリ + localhost プロキシ
- 外部サーバー: **なし**（ユーザー端末内のみ）

## 1. これは何か

面談中の音声/テキストから質問を拾い、次の3段階で回答を出します。

1. **Stage 0 (0.0〜0.2秒目標)**: ローカルテンプレを即表示（LLM呼び出しなし）
2. **Stage 1 (体感1秒の主役)**: 即答用の短い回答をストリーミング生成
3. **Stage 2 (後追い)**: 詳細回答を「即答版の続き」として追記

## 2. 完全ローカル完結

- macOSアプリはローカルで常駐し、画面に字幕/回答案を表示
- `services/local-proxy` は `127.0.0.1:39871` でのみ待ち受け
- OpenAI APIキーはプロキシの `.env` で管理（端末内）
- リポジトリに API キーや音声データを保存しない設計

## 3. 最短セットアップ

### 3-1. ローカルプロキシ起動

```bash
cd services/local-proxy
cp .env.example .env
# .env の OPENAI_API_KEY にキーを設定
npm install
npm run dev
```

ヘルスチェック:

```bash
curl http://127.0.0.1:39871/health
```

### 3-2. macOSアプリ起動

```bash
cd apps/macos/SokuresuMendanApp
swift run
```

### 3-3. APIキー設定（プロキシ側）

- `services/local-proxy/.env` の `OPENAI_API_KEY` を設定
- アプリ側ではキーを保持しません

### 3-4. テストモード（テキスト）で動作確認

1. メニューバー `速レス面談` → `テストモード`
2. テキスト質問を入力
3. `Stage1/2生成` を押す
4. Stage 0 → Stage 1 → Stage 2 の順に更新されることを確認

### 3-5. マイクテスト

1. 入力ソースを `マイク` にする
2. `聞き取り開始`
3. 話しながら、字幕と質問検出が更新されることを確認

### 3-6. システム音声取り込み（YouTube/Zoom/Teams等）を使う場合

`システム音声（BlackHole等）` 入力を使う場合は **BlackHole のインストールが必要** です。

1. BlackHoleをインストール（例）

```bash
brew install blackhole-2ch
```

2. `Audio MIDI設定` で `複数出力装置` を作成し、`BlackHole 2ch` と実際に聴く出力（AirPods等）を含める
3. 会議アプリ / ブラウザの出力先を `複数出力装置` にする
4. SokuresuMendan 側の入力ソースを `システム音声（BlackHole等）` にして `聞き取り開始`

補足: `マイク` モードのみ使う場合、BlackHoleは不要です。

- [docs/SETUP_MACOS_AUDIO.md](./docs/SETUP_MACOS_AUDIO.md) を参照

## 4. 速度最適化の実装

### Stage 0 即表示

- delta（増分）を受けた時点で質問らしさをルール判定
- カテゴリ（自己紹介/設計/テスト等）を推定
- カテゴリ別の 3行テンプレを即表示

### Stage 1 を最短化

- 即答用の短い回答のみを生成
- 出力制約: 最大2文 or 箇条書き3点
- ストリーミング最初の文字が来た時点で UI 更新

### Stage 2 は後追い

- Stage 1 後に非同期で開始
- 詳細回答を「即答版の続き」として追記
- UI は「追記中…」表示で待たせる

### 常時接続 / Warm

- `/ws/transcribe` は Listening 中は接続維持
- `server_vad` の `silence_duration_ms` を短め設定
- 高確度質問で手動 commit を実行（早期確定）

## 5. 画面構成

- **メニューバー**: 聞き取り開始/停止、テストモード、設定、ダッシュボードを開く、終了
- **ダッシュボード（日本語UI）**:
  - 接続状態（プロキシ/文字起こし/生成）
  - 入力デバイス名
  - レイテンシ（質問検出まで / Stage1初回表示まで）
  - 質問（暫定/確定）
  - 回答（即答版 + 追記版）
  - 過去回答履歴（可変高さ）
  - ボタン: 生成 / コピー / クリア
- Panic ホットキー: `Option + Command + H`

## 6. プロフィール機能（ローカル暗号化）

- 取り込み: `.txt/.md/.json` または貼り付け
- 複数プロファイル管理
- 保存先: Application Support
- 暗号化: CryptoKit AES-GCM
- 鍵管理: Keychain
- 生成時は `全文` を送らず、`短い要約 + 関連箇条書き(最大5件)` を送信

## 7. テスト

### macOSアプリ

```bash
cd apps/macos/SokuresuMendanApp
swift test
```

- `QuestionDetectorTests`: delta質問判定・カテゴリ推定・重複抑制
- `StageJSONParserTests`: Stage1/Stage2 JSONパース

### ローカルプロキシ

```bash
cd services/local-proxy
npm run check
npm run build
```

## 8. 法令・規約・プライバシー注意

本アプリは面談支援ツールです。録音/文字起こし/生成は、各国法令・相手の同意・会議ツール規約に従ってください。初回起動時に日本語の注意事項を表示します。

## 9. リポジトリ構成

```text
/apps/macos/SokuresuMendanApp
/services/local-proxy
/docs
README.ja.md
README.md
LICENSE
SECURITY.md
```
