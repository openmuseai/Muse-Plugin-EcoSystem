import test from 'node:test'
import assert from 'node:assert/strict'
import {createHash} from 'node:crypto'
import {mkdtemp, rm, writeFile} from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import {createPlan, loadStack, parseOptions, verifyE2eAttestation} from '../scripts/stack.mjs'

test('stack versions and product API policy agree', async () => {
  const stack = await loadStack()
  assert.equal(stack.versions.plugin, stack.product.version)
  assert.equal(stack.policy.wordApiMajor, stack.product.requires.wordApiMajor)
})

test('plans keep build and e2e gates distinct', () => {
  const build = createPlan(parseOptions(['--gate', 'build']))
  const e2e = createPlan(parseOptions(['--gate', 'e2e']))
  assert.ok(build.some(task => task.name === 'ffi-build'))
  assert.ok(build.some(task => task.name === 'plugin-source-audit'))
  assert.ok(build.some(task => task.name === 'plugin-wordart-audit'))
  assert.ok(build.some(task => task.name === 'word-editor-tests' && task.args.includes('test/word_menu_grid_test.dart')))
  assert.ok(build.some(task => task.name === 'word-editor-tests' && task.args.includes('test/word_wordart_gallery_test.dart')))
  assert.ok(build.some(task => task.name === 'host-desktop-build'))
  assert.ok(!build.some(task => task.name.endsWith('-e2e')))
  assert.ok(e2e.some(task => task.name === 'host-desktop-e2e'))
  const render = createPlan(parseOptions(['--scope', 'render']))
  assert.ok(!render.some(task => task.name === 'core-golden'))
  assert.throws(() => parseOptions(['--scope', 'render', '--platform', 'web']), /RENDER_SCOPE_DESKTOP_ONLY/u)
  assert.throws(() => parseOptions(['--mode', 'release']), /RELEASE_SIGNING_KEY_REQUIRED/u)
  assert.throws(() => parseOptions(['--platform', 'planet']), /INVALID_OPTIONS/u)
})

test('e2e attestation requires actual artifacts, source identities and all cases', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'word-stack-test-'))
  try {
    const hostPath = path.join(dir, 'host')
    const enginePath = path.join(dir, 'engine')
    await writeFile(hostPath, 'host binary')
    await writeFile(enginePath, 'engine binary')
    const digest = file => createHash('sha256').update(file).digest('hex')
    const expected = {target: 'desktop', bundleSha256: digest('bundle'),
      coreSourceDigest: digest('core'), coreLibsSourceDigest: digest('core libs'),
      editorSourceDigest: digest('editor'),
      hostSourceDigest: digest('host source'), engineSourceDigest: digest('engine source'),
      nativeEngineSha256: digest('engine binary')}
    const evidencePath = path.join(dir, 'evidence.json')
    await writeFile(evidencePath, '{"passed":true}')
    const attestation = {profile: 'openmuse-word-stack-e2e/1', ...expected,
      sourceNativeEngineSha256: expected.nativeEngineSha256,
      hostArtifact: {path: hostPath, sha256: digest('host binary')},
      engineArtifact: {path: enginePath, sha256: digest('engine binary')},
      cases: {install: {status: 'passed', evidence: [evidencePath]}}}
    assert.deepEqual((await verifyE2eAttestation(attestation, expected, ['install'])).passedCases, ['install'])
    await assert.rejects(verifyE2eAttestation(attestation, expected, ['install', 'edit']), /E2E_CASE_MISSING/u)
    await assert.rejects(verifyE2eAttestation({...attestation, bundleSha256: digest('other')}, expected, ['install']), /E2E_IDENTITY_MISMATCH/u)
    await writeFile(enginePath, 'tampered')
    await assert.rejects(verifyE2eAttestation(attestation, expected, ['install']), /E2E_ARTIFACT_INVALID/u)
  } finally {
    await rm(dir, {recursive: true, force: true})
  }
})
