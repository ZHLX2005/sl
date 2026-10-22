# claude-session-bridge

A local HTTP endpoint that sends a prompt to a live Claude Code session, chosen
by the directory that session runs in.

Every session that loads this mod starts one small Node process
(`bridge/server.mjs`). The first session to come up takes the hub port
(default `8787`) and keeps it; the others retry until it is free, so the hub
outlives the session that started it. The hub keeps a registry of the live
sessions on disk under `~/.claude/session-bridge/` and routes each request to
the session whose directory was named. The prompt enters that session as an
ordinary turn, and the turn's answer is what the request gets back.

## Using it

The bridge serves a small console on the hub port, so it is easiest to open it
in a browser:

```
http://127.0.0.1:8787/
```

The console shows the live sessions, looks up the session IDs of a directory,
and sends a prompt to a session, showing what it answered. It runs on the
bridge's own origin, so it needs no CORS setup; it reads the token from the
bridge itself (`GET /token`) and keeps it in the browser's local storage.

The token lives in `~/.claude/session-bridge/token`; every API request must
carry it, in the `x-bridge-token` header or in the body's `token` field.
Inside the session, `/session-bridge` prints the endpoint, the token file and
the live sessions.

```bash
TOKEN=$(cat ~/.claude/session-bridge/token)

# the live sessions
curl -s http://127.0.0.1:8787/sessions -H "x-bridge-token: $TOKEN"

# just the session IDs for one cwd (cwd matches the session directory or project root)
curl -sG http://127.0.0.1:8787/sessions \
  -H "x-bridge-token: $TOKEN" \
  --data-urlencode "cwd=D:/code/my-project"

# a prompt for the session running in a directory
curl -s -X POST http://127.0.0.1:8787/prompt \
  -H "content-type: application/json" \
  -H "x-bridge-token: $TOKEN" \
  -d '{"cwd": "D:/code/my-project", "prompt": "run the tests and report"}'
```

The body of `POST /prompt` takes `cwd` (the directory of the session to
talk to; its project root is accepted too), `prompt` (the text to send) and
`session` (which session to pick when several run in that directory; the
newest one is taken otherwise). The answer is the session's final text for
that turn.

## What it needs

Node on the machine (`node` on the `PATH`; the mod looks for it there), and
nothing else: the bridge is plain Node with no dependencies. The port, the
on/off switch and the answer timeout are the mod's own settings, under
`/config`.

## What it is not

The endpoint listens on `127.0.0.1` only, and every request needs the token,
so only programs on this machine that can read the token file can drive a
session. The bridge does not run the prompt itself: the session does, exactly
as it would for a prompt typed at its own prompt box.
