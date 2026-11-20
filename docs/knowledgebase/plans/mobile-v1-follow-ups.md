---
type: Plan
title: "tower-mobile v1: follow-ups"
description: "Work left after milestones M1-M6: unverified paths, unseen UI, and cleanup."
status: draft
generated:
  by: claude-code/1.0
  at: "2026-11-12T04:18:24Z"
---

# tower-mobile v1: follow-ups

Milestones M1-M6 of [tower-mobile v1](mobile-v1.md) are built and run on a
Pixel 7 against the host `kobo`. This page lists what is not yet proven or
not yet clean. Each item says what to do and how to know it is done.

## Unverified action paths

The request formats for these actions match the tower source, and the
error paths were run against a throwaway `tower serve`. The success paths
never ran, because that server had no agents and no agent-sent messages.

- **Send a prompt.** Prompt a real agent from the agent page and from
  the Fleet tile. Done when the agent starts work and the app shows its
  new state.
- **Answer a message.** Answer a question, approve, deny and dismiss from
  the Inbox. Done when the message leaves the pending list on the
  server.
- **Assign a job.** Assign a queued job to an idle agent, and to a busy
  agent (the job is reserved and the app shows the waiting reason).
- **Release a job.** Release an assigned job. The app sends the task's
  `owner_id` as `as`. Done when the job returns to `queued`.
- **Run a workflow.** Start a run with required inputs from the app. Done
  when the run appears in Recent runs and the run page follows it.

## Unseen UI

- **Inbox badge.** kobo's inbox was empty. Done when a pending message
  makes the count show on the tab icon and answering it clears the count.
- **Cancel run.** No run was open. Done when the two-press cancel stops a
  running run and the run page shows `canceled`.
- **Agent terminal text.** The UI dump does not expose the text. Check
  by eye that the tail shows the agent's last lines and refreshes.
- **"Reconnecting (n/5)" text.** `AppShell` now renders `SessionState.error`
  in a shell banner during reconnect; still check it by eye during a drop.
- **Feed cursor replay.** No event was missed during the tests. Done
  when an event that arrives during a feed outage shows up after the
  feed resumes, without a manual refresh.

## Cleanup

- **Done: `TowerConnection.connectLocal`.** Removed the unused test-only
  constructor and made `TowerConnection.ssh` non-nullable.
## Gaps to decide

- **Tests.** The suite has 5 tests (shell boot, host switcher, and the SSE
  parser). The feed
  retry and pause logic and the session recovery loop have no automated
  test. Add them if the connection layer changes again.
- **Multiple machines.** Switching between machines is in the app, but
  only kobo was tried. Add a second machine and switch between both with
  the feed and badge following the active one.
- **Host key change.** Refusing a changed fingerprint is coded and not
  exercised.

## Design

- **Done: Material 3 Expressive.** The app uses the pub.dev package
  `material_3_expressive` 1.2.1 on Flutter 3.47.5. No Flutter upgrade was
  needed. The package needs `material_ui` instead of
  `package:flutter/material.dart`, so every file now imports
  `package:material_ui/material_ui.dart`.
- **Done: theme.** `M3EMaterialApp` follows the phone's light and dark
  setting (`autoTheming`), uses Android wallpaper colors
  (`dynamicColoring`, from `dynamic_color`), and falls back to a blue-grey
  seed. The app draws under the system bars.
- **Done: components and surfaces.** `M3EAppBar.top`, `M3ENavigationBar`
  (with native `badgeCount`), `M3EList`, `M3EListItem`, `M3ECard`,
  `M3EExtendedFab`, `M3EIconButton`, `M3EButton`, and `M3ELoadingIndicator`
  render the screens. Semantic status pills harmonize with the active
  dynamic color scheme via `Color.harmonizeWith`. Modal sheets and detail
  views pad above the Android gesture bar.
- **Done: navigation and action UX.** Host switching moved from a fifth
  bottom tab into an app-bar pill and modal sheet. That leaves four roomy
  tabs (`Fleet`, `Inbox`, `Jobs`, `Workflows`) and fixes the cramped
  `"Workflows"` label. Boot auto-connects the active key-bootstrapped host.
  Job actions stay on `JobDetailScreen` and refresh in place. Starting a
  workflow opens `RunDetailScreen`. Destructive confirms (cancel job,
  cancel run, dismiss message, remove host) use two presses with a 3-second
  reset.
- **Open: M3E form inputs and dialogs.** Text fields, dropdowns, and
  dialogs still use stock Material widgets.
