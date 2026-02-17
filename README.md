# SokuresuMendan

SokuresuMendan is a local-first macOS MVP for live interview assistance.

- Goal: show a first answer draft in about 1 second
- Architecture: macOS menu-bar app + localhost proxy
- No external backend server

## Components

- `apps/macos/SokuresuMendanApp`: SwiftUI macOS app (menu bar, dashboard, overlay, test mode)
- `services/local-proxy`: Node.js + TypeScript localhost proxy (`127.0.0.1:39871`)

## Quick start

1. Start proxy

```bash
cd /Users/tachibanayuuki/Documents/SokuresuMendan/services/local-proxy
cp .env.example .env
# set OPENAI_API_KEY
npm install
npm run dev
```

2. Run macOS app

```bash
cd /Users/tachibanayuuki/Documents/SokuresuMendan/apps/macos/SokuresuMendanApp
swift run
```

3. Open Test Mode and verify Stage 0 -> Stage 1 -> Stage 2 flow.

## Speed strategy

- Stage 0: instant local template from delta-based question detection
- Stage 1: short 10-second answer streamed first
- Stage 2: async 30-second answer + 3 follow-up Q&A

## Privacy and legal notice

Use only in compliance with local laws, consent requirements, and meeting platform policies.
Data stays local in this MVP; API key is stored only in local `.env` (proxy side).

See also:
- [Japanese guide](./README.ja.md)
- [Security policy](./SECURITY.md)
- [macOS audio setup](./docs/SETUP_MACOS_AUDIO.md)
