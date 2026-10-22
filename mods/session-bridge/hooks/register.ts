import type { EngineInterface, Register } from 'claude-code'

/**
 * claude-session-bridge
 *
 * A local HTTP endpoint that sends a prompt to a live Claude Code session,
 * chosen by the directory that session runs in.
 *
 * The mod holds no server of its own: it starts one small Node process
 * (`bridge/server.mjs`) per session. That process serves the fixed hub port,
 * keeps a registry of the live sessions on disk and routes a request to the
 * session whose directory was named. A prompt arrives here as one JSON line
 * on the child's stdout; the mod submits it with `$.prompt.submit` and writes
 * the turn's answer back where the child is waiting for it.
 */

const PLUGIN = 'session-bridge'

type BridgeLine =
  | { type: 'ready'; port: number; hubPort: number; cwd: string; sessionId: string }
  | { type: 'hub'; port: number }
  | { type: 'prompt'; id: string; text: string }

type Reply = {
  ok: boolean
  text?: string
  error?: string
  aborted?: boolean
}

type RegistryEntry = {
  cwd: string
  root: string
  sessionId: string
  port: number
  pid: number
  startedAt: number
}

// The session's own state. A hot reload starts the module over, and the
// session's start hook fills these in again.

let hubPort = 8787
let replyTimeoutMs = 600_000
let enabled = true

let registryDir = ''
let sessionCwd = ''
let sessionRoot = ''
let sessionId = ''
let heartbeatPath = ''
let stopping = false
let failures = 0

/** The requests whose turn has started, in the order the turns started. */
const submitted: string[] = []
let completed = 0
/** Who answers each request, once its turn has ended. */
const waiting = new Map<string, (reply: Reply) => void>()

export const register: Register = (on, options) => {
  hubPort = readNumber(options.port, 8787)
  replyTimeoutMs = readNumber(options.timeoutMs, 600_000)
  enabled = options.enabled !== false

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    sessionCwd = e.cwd
    sessionRoot = await $.session.root().catch(() => e.cwd)
    sessionId = await $.session.id().catch(() => '')
    registryDir = await resolveRegistryDir($)
    heartbeatPath = joinPath(registryDir, 'heartbeat', `${sessionId || 'session'}.txt`)

    if (enabled) {
      await beat($)
      $.clock.every(5000, () => {
        void beat($)
      })
      void runBridge($).catch((error) => {
        $.ui.log(`[${PLUGIN}] ${describe(error)}`, { to: 'debug' })
      })
    }

    await $.command.register({
      name: 'session-bridge',
      description: 'Shows the local HTTP bridge: its endpoint, its token and the live sessions.',
    })

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)

    if (e.agentId === undefined) {
      const id = submitted[completed]
      if (id !== undefined) {
        completed += 1
        const answer = waiting.get(id)
        waiting.delete(id)
        if (answer) {
          answer({
            ok: !e.isAborted,
            text: e.answer,
            aborted: e.isAborted,
            error: e.isAborted ? 'the turn was interrupted' : undefined,
          })
        }
      }
    }

    return result
  })

  on('session.end', async ($, e, next) => {
    // A /clear or a resume ends the session but not the process: the bridge
    // stays, and the session it serves carries on under another id.
    if (e.reason !== 'clear' && e.reason !== 'resume') {
      stopping = true
    }
    for (const answer of waiting.values()) {
      answer({ ok: false, error: 'the session ended before the turn did' })
    }
    waiting.clear()
    return next(e)
  })

  on('command.run', { command: 'session-bridge' }, async ($) => {
    const sessions = await readRegistry($)
    const tokenFile = joinPath(registryDir, 'token')
    const lines = [
      PLUGIN,
      `  endpoint   : http://127.0.0.1:${hubPort}`,
      `  token file : ${tokenFile}`,
      `  registry   : ${registryDir}`,
      `  this session: ${sessionCwd}`,
    ]
    if (sessions.length === 0) {
      lines.push('  live sessions: none')
    } else {
      lines.push('  live sessions:')
      for (const entry of sessions) {
        lines.push(`    ${entry.cwd}  (session ${entry.sessionId}, port ${entry.port})`)
      }
    }
    lines.push('')
    lines.push('  send a prompt:')
    lines.push(`    curl -s -X POST http://127.0.0.1:${hubPort}/prompt \\`)
    lines.push('      -H "content-type: application/json" \\')
    lines.push(`      -H "x-bridge-token: $(cat '${tokenFile}')" \\`)
    lines.push(
      `      -d '{"cwd": ${JSON.stringify(sessionCwd)}, "prompt": "your prompt here"}'`,
    )
    return { text: lines.join('\n') }
  })

  return undefined
}

// ------------------------------------------------------------------- bridge

/**
 * The mod's own pulse. The bridge reads it and leaves when it stops: a bridge
 * whose session died would otherwise hold the hub port for ever.
 */
async function beat($: EngineInterface): Promise<void> {
  if (!heartbeatPath) return
  try {
    await $.fs.write(heartbeatPath, String(Date.now()))
  } catch {
    // the bridge will notice and wait for the next beat
  }
}

/**
 * The bridge, and the loop that reads what it says. The loop is the child's
 * life: it ends with the child, or with this module.
 */
async function runBridge($: EngineInterface): Promise<void> {
  const node = await findNode($)
  if (!node) {
    failures += 1
    $.ui.toast(`${PLUGIN}: node was not found, so the HTTP bridge stays off.`)
    return
  }

  const script = joinPath($.plugin.root, 'bridge', 'server.mjs')
  const child = $.process.spawn({
    argv: [
      node,
      script,
      '--registry',
      registryDir,
      '--cwd',
      sessionCwd,
      '--root',
      sessionRoot,
      '--session',
      sessionId,
      '--hub-port',
      String(hubPort),
      '--heartbeat',
      heartbeatPath,
      '--timeout-ms',
      String(replyTimeoutMs),
    ],
    cwd: sessionCwd,
  })

  let buffer = ''
  for await (const chunk of child) {
    if (chunk.stream === 'stderr') {
      $.ui.log(`[${PLUGIN}] ${chunk.text.trim()}`, { to: 'debug' })
      continue
    }
    buffer += chunk.text
    let newline = buffer.indexOf('\n')
    while (newline >= 0) {
      const line = buffer.slice(0, newline).trim()
      buffer = buffer.slice(newline + 1)
      if (line) {
        void onLine($, line)
      }
      newline = buffer.indexOf('\n')
    }
  }

  if (stopping) return

  failures += 1
  if (failures > 5) {
    $.ui.toast(`${PLUGIN}: the HTTP bridge keeps failing, so it stays off.`)
    return
  }
  await $.clock.sleep(2000)
  await runBridge($)
}

async function onLine($: EngineInterface, line: string): Promise<void> {
  let data: BridgeLine
  try {
    data = JSON.parse(line) as BridgeLine
  } catch {
    return
  }

  if (data.type === 'ready') {
    failures = 0
    $.ui.toast(`${PLUGIN}: http://127.0.0.1:${hubPort} is open for this session.`)
    return
  }
  if (data.type === 'hub') {
    return
  }
  if (data.type === 'prompt') {
    void handlePrompt($, data)
  }
}

async function handlePrompt(
  $: EngineInterface,
  request: { id: string; text: string },
): Promise<void> {
  const reply = await deliver($, request)
  try {
    await $.fs.write(
      joinPath(registryDir, 'results', `${request.id}.json`),
      JSON.stringify(reply),
    )
  } catch (error) {
    $.ui.log(`[${PLUGIN}] the answer could not be written back: ${describe(error)}`, {
      to: 'debug',
    })
  }
}

/** Submits the prompt and waits for the turn it starts to end. */
function deliver(
  $: EngineInterface,
  request: { id: string; text: string },
): Promise<Reply> {
  return new Promise<Reply>((resolve) => {
    waiting.set(request.id, resolve)
    void (async () => {
      try {
        await $.prompt.submit({ text: request.text, asUser: true })
        submitted.push(request.id)
      } catch (error) {
        waiting.delete(request.id)
        resolve({ ok: false, error: describe(error) })
      }
    })()
  })
}

// ------------------------------------------------------------------ helpers

function describe(error: unknown): string {
  if (error instanceof Error) return error.message
  return String(error)
}

function readNumber(value: unknown, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return fallback
}

/** Joins path pieces with the separator the first one already uses. */
function joinPath(...pieces: string[]): string {
  const usable = pieces.filter((piece) => piece !== '')
  if (usable.length === 0) return ''
  const separator = usable.some((piece) => piece.includes('\\')) ? '\\' : '/'
  return usable
    .map((piece, index) =>
      index === 0
        ? piece.replace(/[\\/]+$/, '')
        : piece.replace(/^[\\/]+/, '').replace(/[\\/]+$/, ''),
    )
    .join(separator)
}

async function resolveRegistryDir($: EngineInterface): Promise<string> {
  const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE'))
  if (!home) return joinPath('.claude', 'session-bridge')
  return joinPath(home, '.claude', 'session-bridge')
}

/** The node the bridge runs on: on the PATH, or where the PATH says it is. */
async function findNode($: EngineInterface): Promise<string | undefined> {
  for (const candidate of ['node', 'nodejs']) {
    try {
      const { exitCode } = await $.process.run([candidate, '--version'])
      if (exitCode === 0) return candidate
    } catch {
      // not this one
    }
  }

  const path = await $.env.get('PATH')
  if (!path) return undefined
  const separator = path.includes(';') ? ';' : ':'
  for (const folder of path.split(separator)) {
    if (!folder) continue
    for (const name of ['node.exe', 'node']) {
      const candidate = joinPath(folder, name)
      try {
        if (!(await $.fs.exists(candidate))) continue
        const { exitCode } = await $.process.run([candidate, '--version'])
        if (exitCode === 0) return candidate
      } catch {
        // not this one
      }
    }
  }
  return undefined
}

/** What the registry holds of the sessions that are still alive. */
async function readRegistry($: EngineInterface): Promise<RegistryEntry[]> {
  const folder = joinPath(registryDir, 'sessions')
  let names: { name: string; kind: string }[]
  try {
    names = await $.fs.list(folder)
  } catch {
    return []
  }
  const entries: RegistryEntry[] = []
  for (const entry of names) {
    if (entry.kind !== 'file' || !entry.name.endsWith('.json')) continue
    try {
      const text = await $.fs.read(joinPath(folder, entry.name))
      const parsed = JSON.parse(text) as RegistryEntry
      if (parsed && typeof parsed.cwd === 'string') entries.push(parsed)
    } catch {
      // a file the bridge is writing, or one that is gone
    }
  }
  return entries
}
