# TROUBLESHOOTING

## proxy not reachable

症状:
- ダッシュボードで `プロキシ接続: NG`

確認:
1. `services/local-proxy` で `npm run dev` が起動中か
2. `curl http://127.0.0.1:39871/health` が 200 を返すか
3. 他プロセスが `39871` を占有していないか

## 音が取れない

症状:
- ライブ文字起こしが空のまま

確認:
1. macOS のマイク許可をアプリに付与したか
2. 入力ソースが正しいか（マイク or BlackHole）
3. BlackHole の経路設定（Multi-Output Device）が正しいか

## transcription が遅い

確認:
1. ネットワーク遅延（OpenAI 接続）
2. CPU負荷が高すぎないか
3. `server_vad.silence_duration_ms` が長すぎないか（短め推奨）
4. 早期 commit が発火しているか（高確度質問時）

## Stage1 が出ない

確認:
1. `/generate-stage1` が 200 で応答しているか
2. `OPENAI_API_KEY` を `.env` に設定したか
3. fallback モードになっていないか（`/health` の `mode`）
4. 質問テキストが空ではないか

## API キーエラー

症状:
- `OpenAI error 401/403` など

対応:
1. `.env` の `OPENAI_API_KEY` を再確認
2. 余分な空白や改行を除去
3. キーが有効か OpenAI ダッシュボードで確認
4. キーは絶対にコミットしない
