/**
 * claude-session-bridge — the local HTTP bridge.
 *
 * One process per Claude Code session. It holds two servers on 127.0.0.1:
 *
 *   - a session server on an ephemeral port: it accepts a prompt for *this*
 *     session, hands it to the parent (the mod) on stdout as one JSON line,
 *     and waits for the answer the parent writes back into the results
 *     directory.
 *   - a hub server on the fixed port (default 8787): the one place a client
 *     talks to. It keeps a registry of the live sessions on disk and routes
 *     a request to the session whose working directory was named.
 *
 * Whichever session got the hub port first keeps it; every other session
 * retries every few seconds, so the hub survives the death of its first host.
 *
 * Arguments: --registry <dir> --cwd <dir> --root <dir> --session <id>
 *            --hub-port <n>
 */

import { createServer } from 'node:http'
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs'
import { join, resolve as resolvePath } from 'node:path'

// ---------------------------------------------------------------- arguments

const argv = process.argv.slice(2)

function arg(name, fallback = '') {
  const index = argv.indexOf(`--${name}`)
  return index >= 0 && index + 1 < argv.length ? argv[index + 1] : fallback
}

const registry = arg('registry')
const cwd = arg('cwd')
const root = arg('root', cwd)
const sessionId = arg('session') || randomUUID()
const hubPort = Number(arg('hub-port', '8787')) || 8787
const heartbeat = arg('heartbeat')
const defaultTimeoutMs = Number(arg('timeout-ms', '600000')) || 600000
const host = '127.0.0.1'

if (!registry || !cwd) {
  process.stderr.write('usage: server.mjs --registry <dir> --cwd <dir> [--root <dir>] [--session <id>] [--hub-port <n>]\n')
  process.exit(2)
}

const sessionsDir = join(registry, 'sessions')
const resultsDir = join(registry, 'results')
const tokenPath = join(registry, 'token')

mkdirSync(sessionsDir, { recursive: true })
mkdirSync(resultsDir, { recursive: true })

// ------------------------------------------------------------------- paths

/** One spelling of a path, so two spellings of the same folder match. */
function normalizePath(value) {
  if (typeof value !== 'string') return ''
  let text = value.trim()
  if (!text) return ''
  text = text.replace(/\\/g, '/')
  text = text.replace(/\/{2,}/g, '/')
  if (text.length > 1) text = text.replace(/\/+$/, '')
  // A Windows path is one whatever its case.
  return /^[A-Za-z]:/.test(text) ? text.toLowerCase() : text
}

/** A client may name a folder relatively; the bridge's own folder is the base. */
function absolutePath(value) {
  if (typeof value !== 'string') return ''
  const text = value.trim()
  if (!text) return ''
  return normalizePath(resolvePath(text))
}

const key = createHash('sha1').update(normalizePath(cwd)).digest('hex').slice(0, 12)
const entryFile = join(sessionsDir, `${key}-${sessionId}.json`)

// ------------------------------------------------------------------ token

function readToken() {
  try {
    const value = readFileSync(tokenPath, 'utf8').trim()
    return value
  } catch {
    return ''
  }
}

function ensureToken() {
  const existing = readToken()
  if (existing) return existing
  const value = randomBytes(32).toString('hex')
  try {
    writeFileSync(tokenPath, value, { flag: 'wx', mode: 0o600 })
    return value
  } catch (error) {
    if (error && error.code === 'EEXIST') return readToken()
    throw error
  }
}

ensureToken()

function authorized(request, body) {
  const token = readToken()
  if (!token) return false
  const header = request.headers['x-bridge-token']
  if (typeof header === 'string' && header === token) return true
  if (body && typeof body.token === 'string' && body.token === token) return true
  return false
}

// ------------------------------------------------------------------ output

function emit(payload) {
  try {
    process.stdout.write(`${JSON.stringify(payload)}\n`)
  } catch {
    // The parent is gone; nothing to say it to.
  }
}

function log(message) {
  try {
    process.stderr.write(`[session-bridge] ${message}\n`)
  } catch {
    // ignored
  }
}

// ---------------------------------------------------------------- registry

function isAlive(pid) {
  if (!pid) return false
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return Boolean(error) && error.code === 'EPERM'
  }
}

/** Every live session, the dead ones dropped and their files cleaned up. */
function listSessions() {
  const found = []
  let names = []
  try {
    names = readdirSync(sessionsDir)
  } catch {
    return found
  }
  for (const name of names) {
    if (!name.endsWith('.json')) continue
    const file = join(sessionsDir, name)
    let data
    try {
      data = JSON.parse(readFileSync(file, 'utf8'))
    } catch {
      continue
    }
    if (!isAlive(data.pid)) {
      try {
        unlinkSync(file)
      } catch {
        // ignored
      }
      continue
    }
    found.push(data)
  }
  return found
}

/** The live sessions whose working directory or project root is the folder. */
function findSessions(folder) {
  const wanted = absolutePath(folder)
  if (!wanted) return []
  return listSessions()
    .filter((entry) => normalizePath(entry.cwd) === wanted || normalizePath(entry.root) === wanted)
    .sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0))
}

/** The session a request names: by session id, else by folder. */
function findSession(folder, wantedSession) {
  const sessions = listSessions()
  if (wantedSession) {
    const exact = sessions.find((entry) => entry.sessionId === wantedSession)
    if (exact) return exact
  }
  return findSessions(folder)[0]
}

// ------------------------------------------------------------------ answer

/** The file the mod writes when the session's turn has ended. */
function waitForResult(id, timeoutMs) {
  const file = join(resultsDir, `${id}.json`)
  const limit = Date.now() + Math.min(Math.max(Number(timeoutMs) || 600000, 1000), 1800000)
  return new Promise((resolve) => {
    const timer = setInterval(() => {
      if (existsSync(file)) {
        clearInterval(timer)
        let parsed
        try {
          parsed = JSON.parse(readFileSync(file, 'utf8'))
        } catch {
          parsed = { ok: false, error: 'the result could not be read' }
        }
        try {
          unlinkSync(file)
        } catch {
          // ignored
        }
        resolve(parsed)
        return
      }
      if (Date.now() > limit) {
        clearInterval(timer)
        resolve({ ok: false, error: 'the session did not answer in time' })
      }
    }, 100)
  })
}

// ------------------------------------------------------------------ server

function readBody(request) {
  return new Promise((resolve) => {
    let data = ''
    request.on('data', (piece) => {
      data += piece
      if (data.length > 4 * 1024 * 1024) {
        request.destroy()
        resolve({})
      }
    })
    request.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {})
      } catch {
        resolve({})
      }
    })
    request.on('error', () => resolve({}))
  })
}

function sendJson(response, status, payload) {
  const body = JSON.stringify(payload)
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  })
  response.end(body)
}

/** The test console the hub serves, so it runs on the bridge's own origin. */
function sendConsole(response) {
  let page
  try {
    page = readFileSync(new URL('./index.html', import.meta.url))
  } catch {
    sendJson(response, 500, { ok: false, error: 'the console page is missing' })
    return
  }
  response.writeHead(200, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': page.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'content-security-policy':
      "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'",
  })
  response.end(page)
}

async function handleDeliver(request, response) {
  const body = await readBody(request)
  if (!authorized(request, body)) {
    sendJson(response, 401, { ok: false, error: 'the token is missing or wrong' })
    return
  }
  const text = typeof body.text === 'string' ? body.text : ''
  if (!text.trim()) {
    sendJson(response, 400, { ok: false, error: 'the prompt is empty' })
    return
  }
  const id = typeof body.id === 'string' && body.id ? body.id : randomUUID()
  emit({ type: 'prompt', id, text })
  const result = await waitForResult(id, body.timeoutMs ?? defaultTimeoutMs)
  sendJson(response, result && result.ok ? 200 : 202, { id, ...result })
}

function handleSessionRequest(request, response) {
  if (request.method === 'GET' && (request.url === '/health' || request.url === '/')) {
    sendJson(response, 200, {
      ok: true,
      role: 'session',
      cwd,
      root,
      sessionId,
      port: entry.port,
      hub: `http://${host}:${hubPort}/`,
    })
    return
  }
  if (request.method === 'GET' && request.url === '/favicon.ico') {
    response.writeHead(204)
    response.end()
    return
  }
  if (request.method === 'POST' && request.url === '/deliver') {
    void handleDeliver(request, response)
    return
  }
  sendJson(response, 404, { ok: false, error: 'no such route' })
}

async function handleHubRequest(request, response) {
  if (request.method === 'GET' && request.url === '/') {
    sendConsole(response)
    return
  }
  if (request.method === 'GET' && request.url === '/favicon.ico') {
    response.writeHead(204)
    response.end()
    return
  }
  if (request.method === 'GET' && request.url === '/token') {
    // The console runs on this origin, so it can read the token here; no
    // cross-origin header is sent, so no other page can.
    sendJson(response, 200, { ok: true, token: readToken() })
    return
  }
  if (request.method === 'GET' && request.url === '/health') {
    sendJson(response, 200, { ok: true, role: 'hub', port: hubPort, sessions: listSessions().length })
    return
  }
  if (request.method === 'GET' && request.url?.split('?')[0] === '/sessions') {
    const url = new URL(request.url, `http://${host}:${hubPort}`)
    if (!authorized(request, undefined)) {
      sendJson(response, 401, { ok: false, error: 'the token is missing or wrong' })
      return
    }
    const cwd = url.searchParams.get('cwd')
    if (cwd !== null) {
      const sessions = findSessions(cwd)
      sendJson(response, 200, {
        ok: true,
        cwd,
        sessionIds: sessions.map((entry) => entry.sessionId),
      })
      return
    }
    sendJson(response, 200, { ok: true, sessions: listSessions() })
    return
  }
  if (request.method === 'POST' && request.url === '/prompt') {
    const body = await readBody(request)
    if (!authorized(request, body)) {
      sendJson(response, 401, { ok: false, error: 'the token is missing or wrong' })
      return
    }
    const contentType = String(request.headers['content-type'] ?? '')
    if (!contentType.includes('application/json')) {
      sendJson(response, 415, { ok: false, error: 'the body must be application/json' })
      return
    }
    const text = typeof body.prompt === 'string' ? body.prompt : typeof body.text === 'string' ? body.text : ''
    if (!text.trim()) {
      sendJson(response, 400, { ok: false, error: 'the prompt is empty' })
      return
    }
    const target = findSession(body.cwd ?? body.directory, body.session)
    if (!target) {
      sendJson(response, 404, {
        ok: false,
        error: 'no live session runs in that directory',
        sessions: listSessions().map((entry) => ({ cwd: entry.cwd, sessionId: entry.sessionId })),
      })
      return
    }
    try {
      const upstream = await fetch(`http://${host}:${target.port}/deliver`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-bridge-token': readToken(),
        },
        body: JSON.stringify({ id: randomUUID(), text, timeoutMs: body.timeoutMs ?? defaultTimeoutMs }),
      })
      const answer = await upstream.json()
      sendJson(response, upstream.status, { ...answer, cwd: target.cwd, sessionId: target.sessionId })
    } catch (error) {
      sendJson(response, 502, { ok: false, error: `the session could not be reached: ${error && error.message}` })
    }
    return
  }
  sendJson(response, 404, { ok: false, error: 'no such route' })
}

// ------------------------------------------------------------------- start

const entry = {
  cwd,
  root,
  sessionId,
  pid: process.pid,
  port: 0,
  startedAt: Date.now(),
  hubPort,
}

const sessionServer = createServer((request, response) => {
  void handleSessionRequest(request, response)
})

sessionServer.on('error', (error) => log(`the session server failed: ${error && error.message}`))

sessionServer.listen(0, host, () => {
  const address = sessionServer.address()
  entry.port = address && typeof address === 'object' ? address.port : 0
  try {
    writeFileSync(entryFile, JSON.stringify(entry, null, 2))
  } catch (error) {
    log(`the registry entry could not be written: ${error && error.message}`)
  }
  emit({ type: 'ready', port: entry.port, hubPort, cwd, root, sessionId, registry })
  tryHub()
})

let hubServer = null

function tryHub() {
  if (hubServer) return
  const server = createServer((request, response) => {
    void handleHubRequest(request, response)
  })
  server.on('error', (error) => {
    try {
      server.close()
    } catch {
      // ignored
    }
    if (!error || error.code !== 'EADDRINUSE') {
      log(`the hub failed: ${error && error.message}`)
    }
    setTimeout(tryHub, 5000)
  })
  server.listen(hubPort, host, () => {
    hubServer = server
    emit({ type: 'hub', port: hubPort })
  })
}

// --------------------------------------------------------------- life cycle

function cleanup() {
  try {
    unlinkSync(entryFile)
  } catch {
    // ignored
  }
}

process.on('exit', cleanup)
process.on('SIGINT', () => {
  cleanup()
  process.exit(0)
})
process.on('SIGTERM', () => {
  cleanup()
  process.exit(0)
})
process.on('uncaughtException', (error) => {
  log(`crashed: ${error && error.stack ? error.stack : error}`)
  cleanup()
  process.exit(1)
})
process.stdout.on('error', () => {
  cleanup()
  process.exit(0)
})

// The parent is the mod; when it goes, so does this bridge.
const parentPid = process.ppid
const startedAt = Date.now()

/** How long the mod may be quiet before this bridge leaves. */
const SILENCE_LIMIT = 30000

function heartbeatIsStale() {
  if (!heartbeat) return false
  let value = ''
  try {
    value = readFileSync(heartbeat, 'utf8').trim()
  } catch {
    // no beat yet: the mod may still be starting
    return Date.now() - startedAt > SILENCE_LIMIT
  }
  const beat = Number(value)
  if (!Number.isFinite(beat)) return Date.now() - startedAt > SILENCE_LIMIT
  return Date.now() - beat > SILENCE_LIMIT
}

setInterval(() => {
  if (!isAlive(parentPid) || heartbeatIsStale()) {
    cleanup()
    process.exit(0)
  }
}, 3000)
