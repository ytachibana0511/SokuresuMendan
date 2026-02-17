# macOS 音声取り込み設定 (BlackHole + Multi-Output Device)

この手順は「相手音声をイヤホンで聴きながら、アプリで音声を取り込む」ための設定です。

## 1. BlackHole をインストール

- 例: Homebrew

```bash
brew install blackhole-2ch
```

インストール後、Audio MIDI設定に `BlackHole 2ch` が追加されます。

## 2. Multi-Output Device を作成

1. `Audio MIDI設定` を開く
2. 左下 `+` から `複数出力装置を作成`
3. 構成に以下を追加
   - `BlackHole 2ch`
   - 実際に聴く出力（例: AirPods / 内蔵出力）
4. ドリフト補正を必要に応じて有効化

## 3. 会議アプリ出力を Multi-Output Device にする

- Zoom / Meet / Teams などの出力デバイスを Multi-Output Device に設定
- これで「耳で聞く + BlackHoleへ分岐」が可能になります

## 4. SokuresuMendan 側

1. テストモードで入力ソースを `システム音声（BlackHole等）` に切替
2. `聞き取り開始`
3. ライブ文字起こしが更新されるか確認

## 5. よくある詰まり

- 音が聞こえない
  - Multi-Output Device に実イヤホン出力が含まれているか確認
- 文字起こしに出ない
  - 会議アプリが本当に Multi-Output Device を出力先にしているか確認
- 音が途切れる
  - Audio MIDI設定でサンプルレートを統一（48kHz 推奨）
- 大幅に遅い
  - プロキシの起動状態、CPU負荷、`silence_duration_ms` を確認
