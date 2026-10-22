import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { createServer } from 'node:http'
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const bridge = fileURLToPath(new URL('./server.mjs', import.meta.url))

async function freePort() {
  const server = createServer()
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  const address = server.address()
  server.close()
  await once(server, 'close')
  return address.port
}

async function waitForSessions(registry, count) {
  const deadline = Date.now() + 5000
  while (Date.now() < deadline) {
    try {
      const files = readdirSync(join(registry, 'sessions')).filter((file) => file.endsWith('.json'))
      if (files.length >= count) return
    } catch {
      // bridge has not created the registry yet
    }
    await new Promise((resolve) => setTimeout(resolve, 50))
  }
  assert.fail(`expected ${count} live session registry entries`)
}

function startSession(registry, cwd, sessionId, hubPort) {
  return spawn(process.execPath, [
    bridge,
    '--registry', registry,
    '--cwd', cwd,
    '--root', cwd,
    '--session', sessionId,
    '--hub-port', String(hubPort),
  ], { stdio: 'ignore' })
}

test('GET /sessions?cwd returns matching session IDs and keeps the unfiltered response', async (t) => {
  const temporary = mkdtempSync(join(tmpdir(), 'session-bridge-test-'))
  const registry = join(temporary, 'registry')
  const project = join(temporary, 'project')
  const other = join(temporary, 'other')
  mkdirSync(project)
  mkdirSync(other)
  const hubPort = await freePort()
  const first = startSession(registry, project, 'project-session-a', hubPort)
  const second = startSession(registry, project, 'project-session-b', hubPort)
  const third = startSession(registry, other, 'other-session', hubPort)

  t.after(() => {
    for (const child of [first, second, third]) child.kill()
    rmSync(temporary, { recursive: true, force: true })
  })

  await waitForSessions(registry, 3)
  const token = readFileSync(join(registry, 'token'), 'utf8').trim()
  const headers = { 'x-bridge-token': token }

  const filteredResponse = await fetch(
    `http://127.0.0.1:${hubPort}/sessions?cwd=${encodeURIComponent(project)}`,
    { headers },
  )
  assert.equal(filteredResponse.status, 200)
  const filtered = await filteredResponse.json()
  assert.equal(filtered.ok, true)
  assert.deepEqual(new Set(filtered.sessionIds), new Set(['project-session-a', 'project-session-b']))

  const missingResponse = await fetch(
    `http://127.0.0.1:${hubPort}/sessions?cwd=${encodeURIComponent(join(temporary, 'missing'))}`,
    { headers },
  )
  assert.equal(missingResponse.status, 200)
  assert.deepEqual((await missingResponse.json()).sessionIds, [])

  const unfilteredResponse = await fetch(`http://127.0.0.1:${hubPort}/sessions`, { headers })
  const unfiltered = await unfilteredResponse.json()
  assert.equal(unfilteredResponse.status, 200)
  assert.equal(unfiltered.sessions.length, 3)
  assert.equal('sessionIds' in unfiltered, false)
})

test('the hub serves the test console and the token it needs', async (t) => {
  const temporary = mkdtempSync(join(tmpdir(), 'session-bridge-test-'))
  const registry = join(temporary, 'registry')
  const project = join(temporary, 'project')
  mkdirSync(project)
  const hubPort = await freePort()
  const child = startSession(registry, project, 'console-session', hubPort)

  t.after(() => {
    child.kill()
    rmSync(temporary, { recursive: true, force: true })
  })

  await waitForSessions(registry, 1)

  const page = await fetch(`http://127.0.0.1:${hubPort}/`)
  const html = await page.text()
  assert.equal(page.status, 200)
  assert.match(page.headers.get('content-type'), /text\/html/)
  assert.match(html, /<title>session-bridge/)
  assert.match(html, /\/sessions\?cwd=/)

  const token = await fetch(`http://127.0.0.1:${hubPort}/token`)
  const tokenBody = await token.json()
  assert.equal(token.status, 200)
  assert.equal(tokenBody.token, readFileSync(join(registry, 'token'), 'utf8').trim())

  const health = await fetch(`http://127.0.0.1:${hubPort}/health`)
  assert.equal(health.status, 200)
  assert.equal((await health.json()).role, 'hub')
})
