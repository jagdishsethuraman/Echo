# Echo — Product & Engineering Roadmap

This document outlines the strategic engineering roadmap, architectural milestones, and planned features for **Echo**.

---

## 🗺️ Milestone Overview

```
 v1.0 [SHIPPED]          v1.3 [SHIPPED]          v1.4 [CURRENT]          v2.0 [FUTURE]
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ Core Native App  │──▶│ Hardened Audio   │──▶│ Local LLM Notes  │──▶│ Semantic Search  │
│ Phonon-2 STT     │   │ Dynamic Notes    │   │ Hotkey Remapper  │   │ Bi-dir Obsidian  │
│ Universal Paste  │   │ Graphite UI / TCC│   │ Speaker Diarize  │   │ Raycast/Alfred   │
│ SQLite & Memory  │   │ Bounded Queue    │   │ Voice Profiles   │   │ Cloud Optional   │
└──────────────────┘   └──────────────────┘   └──────────────────┘   └──────────────────┘
```

---

## 🚀 Shipped: v1.0.0 — Production Core & Offline Engine

- [x] **Unified Single-Binary Architecture:** Combined push-to-talk cursor dictation (Handy style) and dual-channel meeting intelligence (Meetily style) into a single Swift binary, saving 1.2 GB duplicate model RAM.
- [x] **Offline Speech Engine (Phonon-2):** Embedded `fermionresearch/phonon-2` (158 MB INT6 Parakeet-TDT 0.6B) running locally through the `fermion` process at up to 37.7x real-time speed. Device defaults to CPU (`ECHO_FERMION_DEVICE`).
- [x] **CoreAudio 16kHz Tap:** Native microphone tap with automatic hardware resampling to 16kHz 16-bit mono PCM.
- [x] **ScreenCaptureKit System Loopback:** Zero-echo attendee audio loopback using macOS ScreenCaptureKit with `excludesCurrentProcessAudio = true` (no virtual audio drivers or bots needed).
- [x] **Rolling Energy VAD:** Dual-detector voice activity detector segmenting multi-speaker speech upon 600ms natural silence boundaries.
- [x] **Push-to-Talk & Live Streaming HUD:** Non-activating floating `NSPanel` (`canBecomeKey=false`) streaming recognized words live every 650ms with audio waveform meters and blinking cursor.
- [x] **Universal Auto-Paste Pipeline:** `AXUIElement` direct value replacement → synthetic `Cmd+V` (25ms settle + `.maskCommand` isolation) → direct Unicode typing fallback. Text is also left on the clipboard as a manual fallback.
- [x] **Local SQLite Backend (`echo.sqlite`):** Native WAL-mode persistence using macOS `libsqlite3` archiving sessions, utterances, and quick dictations across app restarts. Live writes run on a serial utility queue, `user_version` migrations add indexes, empty/stale sessions are pruned at launch, and the menu exposes a Meeting History submenu with copy/delete actions.
- [x] **Word Memory & Speech Lexicon Engine:** Whole-word boundary regex engine (`\b(pattern)\b`) correcting phonetically ambiguous STT outputs in real time across live streams and active cursor typing.
- [x] **Graphite Frost Bento Meeting Studio:** 62/38 Bento grid with neutral frosted graphite surfaces, a cool frost-blue accent, live VU meters, and Markdown export.
- [x] **Adaptive Pill Menu Bar:** Menu bar status item adapting dynamically from minimal glyph `◉` to active recording timer `● MM:SS`.
- [x] **Permanent TCC Code Signing:** Ad-hoc sealed bundle signed with `-r="designated => identifier \"com.ragavij.echo\""` preserving Accessibility permissions across builds.

---

## ⚡ Next Milestone: v1.1.0 — Local LLM Intelligence & Customization

- [ ] **Local LLM Executive Summarizer:**
  - Bridge to local Ollama / MLX endpoint (`http://127.0.0.1:11434/v1` or native Llama.cpp).
  - Automatically synthesizes meeting transcripts into structured executive summaries:
    - *Key Decisions* (consensus points).
    - *Action Items* with inferred assignees.
    - *Follow-ups & Next Steps*.
- [ ] **Custom Hotkey Remapping:**
  - Preferences pane to remap the push-to-talk trigger from `Control` to `Fn / Globe`, `Right ⌘`, double-tap `Control`, or custom combinations.
  - Global push-to-talk toggle switch (Hold-to-talk vs Tap-to-toggle).
- [ ] **Audio Sensitivity & VAD Tuning:**
  - User-configurable microphone gain and silence duration threshold (300ms–1200ms) for fast vs slow speakers.
- [ ] **Timeline Search & Filter:**
  - In-app text search across current and historical meeting sessions.

---

## 🔮 Future Milestone: v1.2.0 — Acoustic Diarization & Multilingual

- [ ] **Speaker Diarization (Multi-Speaker Separation):**
  - Integrate lightweight CoreML speaker embedding model to distinguish multiple meeting attendees (`Speaker 1`, `Speaker 2`, `Speaker 3`).
- [ ] **Voice Profile Enrollment ("My Voice"):**
  - Record a 10-second reference audio sample during onboarding to guarantee 100% separation between your voice and remote conference participants.
- [ ] **Multilingual Speech Models:**
  - Downloadable model weights for multi-language Whisper / Parakeet models.
  - Dynamic language selector in menu bar item and studio top bar.
- [ ] **Meeting Chapter Markers:**
  - Automatic silence-based chapter markers and topical segmentation.

---

## 🌌 Long-Term Vision: v2.0.0 — Second Brain Knowledge Mesh

- [ ] **Bi-Directional Obsidian Vault Sync:**
  - Automated sync into designated Obsidian vault directory (`second brain/Meetings/`).
  - Intelligent entity extraction generating `[[Wikilinks]]` for people, projects, and products mentioned in speech.
- [ ] **Local Semantic Vector Search:**
  - Index all historical spoken conversations into local SQLite `vec0` / sqlite-vss vector database.
  - Natural language search: *"What did Sarah say about the Q3 budget last Tuesday?"*
- [ ] **Raycast & Alfred Extensions:**
  - Native Raycast command palette extension to trigger quick dictation, browse past transcripts, and manage custom dictionary words.
