---
type: Decision
title: SSH tunnel transport, no herdr dependency
description: tower-mobile talks to the tower REST API over an SSH tunnel; herdr is not required on the host.
status: draft
generated:
  by: claude-code/1.0
  at: "2026-11-11T17:33:17Z"
---

# SSH tunnel transport, no herdr dependency

Date: 2026-11-11. Status: proposed.

## Context

tower-mobile must monitor and control a tower server that runs on a user
machine. The tower TCP listener binds loopback by default
(`127.0.0.1:8266`), has no TLS, and no rate limiting. The bearer token is
the only auth and grants full operator control.

Two connection designs were candidates:

1. SSH into the machine, then call the tower API through a local port
   forward to `127.0.0.1:8266`.
2. Rely on herdr, already on the host, and reuse its `tower` CLI or its
   panels through SSH sessions.

See [Tower API surface for a mobile client](../concepts/tower-api-surface.md)
for the API facts behind this decision.

## Decision

tower-mobile connects to each machine with SSH, and forwards the tower API
over that connection. The app talks plain JSON REST + SSE to the forwarded
port. The app does not need herdr on the host.

First connection: the user supplies host, SSH username, and password. The
app generates an SSH key pair on the device, then runs one bootstrap
script over the password session:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys  # append the device public key
```

Later connections authenticate with that key. The app never stores the
password; it keeps it only in memory for the bootstrap session. The user
may replace or clear the device key from the host at any time.

Over each SSH connection the app opens a local forward
`127.0.0.1:<ephemeral> → 127.0.0.1:8266` and sends
`Authorization: Bearer <token>` on every request. The app fetches the
token once per connection with a single SSH command:
`cat "$TOWER_HOME/token"` (fallback: `~/Library/Application Support/tower/token`
on macOS, `~/.local/share/tower/token` on Linux).

## Rationale

- **Loopback bind is the security boundary.** The tower server has no TLS
  and no rate limiting. Exposing `bind_tcp` to the network would make the
  bearer token the only defense. An SSH tunnel keeps the server
  loopback-only; SSH supplies the transport auth and encryption.
- **The REST API covers every requirement.** Fleet, inbox, prompt, jobs,
  workflow runs, and the SSE feed are all JSON-over-HTTP. herdr adds no
  capability the app needs; its panels drive the same routes through the
  CLI.
- **herdr's own remote story is SSH anyway.** The herdr app runs a remote
  machine's `tower` CLI over SSH. A tunnel plus direct HTTP removes the
  CLI subprocess layer and the `sh`+`curl` dependency herdr's events panel
  carries.
- **SSH fits mobile constraints.** `dartssh2` (active, Android support)
  gives the app a pure-Dart SSH client with password, public-key, and
  local-forwarding support. No host-side changes are needed.

## Consequences

- The phone must reach the machine's SSH port (LAN, VPN, or public address
  with SSH exposed). Machines behind strict NAT need a VPN such as
  Tailscale. Out of scope for v1.
- SSH disconnects pause the app. The app reconnects and resumes the SSE
  feed at the last cursor. Event seqs are per server, so a machine switch
  resets the cursor.
- Two channels are used per machine: SSH for connect/health/token
  bootstrap, and HTTP/SSE through the tunnel for everything else.
- Key bootstrap is a one-time append to `authorized_keys`. If the host
  forbids key auth, the app falls back to password auth per connection,
  and the user accepts that risk. [INFERENCE] Standard sshd default
  allows public-key auth; a hardened host may not.
- Multi-machine means one SSH connection per machine, and the user
  switches between them. The active machine's state is the screen the
  user sees; only the active connection stays open in v1 to save battery.

## Alternatives rejected

- **Expose the tower API directly** (change `bind_tcp`, add TLS via a
  reverse proxy). Rejected: it widens the attack surface of a token-only
  API and asks the user to run and secure a proxy. SSH already exists on
  these machines.
- **Depend on herdr as a proxy.** Rejected: herdr is a desktop TUI; its
  panels are not a service. Driving the CLI per action over SSH adds a
  process spawn per request, and the events panel depends on `sh` and
  `curl` on the host.
- **`tower node` remote machines.** Rejected for v1: it is a phase-5 stub
  in the tower source ("arrives in phase 5", `crates/tower-server/src/cli.rs`).
