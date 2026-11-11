---
okf_version: "0.2"
---

# tower-mobile knowledge base

This is the working knowledge base for the tower-mobile project, conforming to the
[Open Knowledge Format (OKF) v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md).

It consolidates working knowledge about the project: what tower-mobile is, how it is
structured, decisions and their rationale, recurring patterns, and plans.
It is authored by people and agents and meant to be read by both.

## For agents (policy)

This section is the single source of truth for how agents should use this knowledge
base. Tooling injects it into context automatically, so it does not depend on
`CLAUDE.md`/`AGENTS.md` being picked up.

Agents wired to this knowledge base:

* **opencode** — via the `instructions` array in `.opencode/opencode.jsonc`.
* **oh-my-pi** — via the `.omp/extensions/kb-hooks.ts` extension.

**Consult before acting.** Before working on a task, scan the entries below and
read any concept/decision/pattern doc relevant to what you are about to change.
Prefer the recorded decision or pattern over re-deriving one. This index is the
map; read the specific doc on demand rather than guessing.

**Update after acting.** Update the knowledge base when a change would make an
existing entry wrong or leave a new fact unrecorded. In particular:

* A new architectural decision or a change to startup/threading →
  add or update a [decision](decisions/index.md) and relevant concept docs.
* A new recurring convention → add a [pattern](patterns/index.md).
* A new concept or architectural understanding → add a [concept](concepts/index.md).
* A forward-looking plan or roadmap item → add a [plan](plans/index.md).
* An external source or spec referenced by the KB → add a [reference](references/index.md).

Concept docs require YAML frontmatter with a `type` field; `index.md` and
`log.md` are reserved. When you add a doc, add a one-line pointer to the matching
category index below and a line to [`log.md`](log.md). If you deliberately decide
*not* to record a change, that is fine — the policy is judgement, not a mandate
to touch the KB on every edit.

## Concepts

* [Tower API surface for a mobile client](concepts/tower-api-surface.md) - what the tower server exposes over HTTP/SSE and how a remote client reaches it.

## Decisions

* [SSH tunnel transport, no herdr dependency](decisions/ssh-tunnel-transport.md) - the app talks to the tower REST API over an SSH tunnel; herdr is not required on the host.

## Patterns

* _(empty — add pattern docs here)_

## Plans

* [tower-mobile v1: Flutter Android client](plans/mobile-v1.md) - implementation plan for the first Android release.

## References

* [OKF spec](references/okf-spec.md) - pointer to the Open Knowledge Format v0.2 specification.
