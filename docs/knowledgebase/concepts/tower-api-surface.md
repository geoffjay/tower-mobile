---
type: Concept
title: Tower API surface for a mobile client
description: What the tower server exposes over HTTP/SSE and how a remote client reaches it.
status: draft
generated:
  by: claude-code/1.0
  at: "2026-11-11T17:33:17Z"
---

# Tower API surface for a mobile client

The tower server (`~/Projects/tower`, Rust) exposes a JSON REST API, an SSE
event feed, and an MCP endpoint. This entry records what a remote client —
tower-mobile — can use, and how it reaches the server. Facts come from the
`tower` source and a live `tower serve` on 2026-11-11.

## Transport and auth

- TCP listener: `[server] bind_tcp` in `config.toml`, default
  `127.0.0.1:8266` (loopback only, no TLS) — `crates/tower-server/src/config.rs`.
- Every TCP request needs `Authorization: Bearer <token>`. The token is a
  52-char hex string in the token file (0600): `$TOWER_HOME/token`, else the
  XDG data dir (`~/Library/Application Support/tower/token` on macOS).
  Compare this against the constant-time path in
  `crates/tower-server/src/auth.rs`.
- A unix socket (`tower.sock`) serves the same routes with no token check.
  A phone cannot use it.
- There is no TLS and no rate limit. The bearer token is full operator
  control. Treat it as a secret. Rotation: delete the token file and restart
  `tower serve`.
- `GET /healthz` answers `{ok, version, started_at, db}`. Use it as the
  connect-then-health probe.

## Endpoints tower-mobile uses

`GET /v1/schema` prints every route and event type. The mobile client can
self-discover at runtime, but v1 hard-codes the routes it needs.

| Area | Route | Notes |
| --- | --- | --- |
| Fleet | `GET /v1/agents` | `{agents: [Agent]}`; list of all agent seats |
| Fleet detail | `GET /v1/agents/{id}` | `{agent}`; `{id}` accepts name or id |
| Agent output | `GET /v1/agents/{id}/read?format=ansi` | `{output}`; snapshot of the terminal screen |
| Prompt | `POST /v1/agents/{id}/prompt` | `{text, wait?}` → `{ok, state, stalled}` |
| Interrupt / stop | `POST /v1/agents/{id}/interrupt`, `…/stop` | `{ok}`; stop body `{remove?}` |
| Inbox | `GET /v1/messages?to=me&status=pending` | `{messages: [Message]}`; what `tower inbox` calls |
| Respond | `POST /v1/messages/{id}/respond` | `{parts? , approve?}`; approvals need `approve`, questions need a text part; 409 when not pending |
| Dismiss | `POST /v1/messages/{id}/dismiss` | status → `dismissed` |
| Jobs list | `GET /v1/tasks` | `?state=&tags=&owner=&mine=&since=` filters |
| Job detail | `GET /v1/tasks/{id}` | `{task, trail}`; trail is the job's events, oldest first |
| Queue job | `POST /v1/tasks` | `{title, description?, priority?, tags?, assign?, not_before?, lease_s?, max_attempts?, pre_run?, post_run?}` → `{task, waiting}` |
| Assign job | `POST /v1/tasks/{id}/assign` | `{to, lease_s?}` → `{task, waiting}`; a busy agent gets a reserved job, `waiting` explains why |
| Cancel / release | `POST /v1/tasks/{id}/cancel`, `…/release` | cancel interrupts the owner |
| Workflows | `GET /v1/workflows` | `{workflows}` with `open_runs` per workflow |
| Workflow detail | `GET /v1/workflows/{name}` | `{workflow, definition, source, schedules, runs}` |
| Start run | `POST /v1/workflows/{name}/runs` | `{input: {k: v}}` → `{run}` |
| Runs | `GET /v1/runs`, `GET /v1/runs/{id}` | detail adds `steps` and `waiting_for` |
| Cancel run | `POST /v1/runs/{id}/cancel` | `{run}` |
| Events | `GET /v1/events` (SSE), `GET /v1/events/history` | history: `?before=&limit=&filter=&exclude=&subject=` (limit ≤ 500) |

## SSE event feed

`GET /v1/events` is the live feed the TUI and web UI consume.

- Resume cursor: `?cursor=<seq>` or the `Last-Event-ID` header. No cursor
  starts live at head.
- Filters: `?filter=type:task`, `?exclude=type:agent.output`,
  `?subject=agent:<id>`.
- Events arrive as SSE batches named `tower-batch`; `id:` is the seq; the
  data is newline-joined `Event` JSON payloads.
- Keep-alive comment every 15 s. Set the client read-timeout above that.
- Event kinds of interest: `agent.state`, `agent.output`, `task.created`,
  `task.status`, `task.assigned`, `message.created`, `message.status`,
  `workflow.run.started`, `workflow.run.completed`,
  `workflow.run.failed`, `workflow.run.canceled`,
  `workflow.step.started`, `workflow.step.completed`,
  `workflow.step.failed`.

## Domain types (fields verbatim)

All ids are ULID strings. Timestamps are ms-epoch integers.

- **Agent**: `id, name, kind, machine_id, pane_id?, workdir?, worktree?,
  state, desired_state, permissions, adopted, config, model?, args[],
  created_at, updated_at`. `AgentState`: `unknown | launching | idle |
  working | blocked | done | dead`.
- **Task**: `id, agent_id?, owner_id?, origin, external_ref?, context_id?,
  title, description?, state, priority, tags[], attempt_count,
  max_attempts, lease_expires_at?, lease_s, target_agent_id?,
  not_before?, schedule_id?, occurrence_at?, pre_run?, post_run?, hook?,
  result?, created_at, updated_at`. `TaskState`: `queued | assigned |
  working | input-required | completed | failed | canceled | rejected`.
- **Message**: `id, task_id?, from_kind, from_id, to_kind, to_id, kind,
  parts[], status, deadline_at?, responded_at?, created_at`.
  `MessageKind`: `prompt | question | answer | approval |
  approval-response | notice | delegation | broadcast`. `MessageStatus`:
  `pending | delivered | answered | dismissed | expired | failed`.
- **Workflow**: `id, name, description?, enabled, current_version,
  created_at, updated_at`. **WorkflowRun**: `id, workflow_id,
  workflow_name, version, state, input, trigger, result?, error?,
  created_at, ended_at?`. `RunState`: `waiting | running | completed |
  failed | canceled`. **WorkflowStep**: `id, run_id, node_id, visit,
  state, activated_by[], task_id?, agent_id?, outcome?, result?, error?,
  created_at, started_at?, ended_at?`.
- **Event**: `seq, ts, kind, subject_type?, subject_id?, payload`.

## Error envelope

Every error is `{"error": {"code": <code>, "message": <string>,
"detail"?: <json>}}`. Codes: `not_found`, `conflict`, `timeout`, `driver`,
`invalid`, `unauthorized`, `machine_offline`. Map them to UI messages; a
401 means the tunnel or the token failed, not the action.

## What a mobile client must not assume

- `bind_tcp` stays loopback by default. The phone cannot dial it directly.
  See [SSH tunnel transport, no herdr dependency](../decisions/ssh-tunnel-transport.md).
- `tower node` (remote machines, phase 5) is a stub. Multi-machine in
  tower-mobile means several SSH targets, one per tower server.
- The read-only web UI (`/ui`) has its own scoped token. Do not reuse it
  for the mobile app; it cannot write.
- Herdr app panels poll at 10 s and drive actions through the `tower` CLI
  over SSH. tower-mobile replaces that with direct HTTP over a tunnel.
  See [tower-mobile v1: Flutter Android client](../plans/mobile-v1.md).
