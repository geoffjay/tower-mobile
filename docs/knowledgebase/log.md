# Knowledge Base Update Log

## 2026-11-11
* **Scaffold**: Created the tower-mobile knowledge base at `docs/knowledgebase/` using the `okf-ify` skill. Initial structure: `index.md`, `log.md`, and concept directories (concepts, decisions, patterns, references, plans). OKF v0.2 conformant.
* **M1 done**: Flutter scaffold (Android) at repo root: `lib/src/api` (models, `TowerClient`, workflows extension), `lib/src/connection` (`TowerConnection` SSH tunnel + key bootstrap, `MachineRegistry`, `SessionController`), five screens (`lib/src/features`, four stubbed to M3). Analyzer 0 issues; boot smoke test passes; debug APK runs on Pixel 7 with Machines screen and all five tabs verified via UI dump. Authored by claude-code/1.0.
* **Research + plan**: Added `concepts/tower-api-surface.md` (tower REST/SSE API facts from the tower repo and a live server), `decisions/ssh-tunnel-transport.md` (SSH tunnel with first-connection key bootstrap; no herdr dependency), and `plans/mobile-v1.md` (Flutter Android v1: screens, milestones M1-M6, risks). Authored by claude-code/1.0; pending review.
