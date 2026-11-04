import {spawn, execFileSync} from 'node:child_process'
import {createHash, generateKeyPairSync} from 'node:crypto'
import {mkdtemp, mkdir, readFile, rm, writeFile, stat} from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {createWriteStream, existsSync} from 'node:fs'
import {root as pluginRoot} from './validate.mjs'
import {verifyPackage} from './verify.mjs'

const workspace = path.resolve(pluginRoot, '../../..')
const ecosystem = path.join(workspace, 'Muse-Plugin-Ecosystem')
const office = path.join(workspace, 'ioffice')
const host = path.join(workspace, 'Muse-Client')
const outputRoot = path.join(ecosystem, '.word-stack-runs')
const policyPath = path.join(pluginRoot, 'stack/compatibility.json')

function semver(value) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/u.exec(value)
  if (!match) throw new Error(`INVALID_SEMVER:${value}`)
  return {parts: match.slice(1, 4).map(Number), prerelease: match[4] ?? null}
}
function atLeast(actual, minimum) {
  const left = semver(actual), right = semver(minimum)
  for (let i = 0; i < 3; i++) {
    if (left.parts[i] > right.parts[i]) return true
    if (left.parts[i] < right.parts[i]) return false
  }
  if (left.prerelease === null) return true
  if (right.prerelease === null) return false
  const a = left.prerelease.split('.'), b = right.prerelease.split('.')
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] === undefined) return false
    if (b[i] === undefined) return true
    const aNumeric = /^\d+$/u.test(a[i]), bNumeric = /^\d+$/u.test(b[i])
    if (aNumeric && bNumeric && Number(a[i]) !== Number(b[i])) return Number(a[i]) > Number(b[i])
    if (aNumeric !== bNumeric) return !aNumeric
    if (a[i] !== b[i]) return a[i] > b[i]
  }
  return true
}
function readVersion(text, filename) {
  if (filename.endsWith('.json')) return JSON.parse(text).version
  const match = /^version\s*[:=]\s*["']?([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)/mu.exec(text)
  if (!match) throw new Error(`VERSION_NOT_FOUND:${filename}`)
  return match[1]
}
function git(cwd, args) {
  return execFileSync('git', args, {cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024}).trim()
}
async function untrackedSourcePaths(cwd) {
  const child = spawn('git', ['ls-files', '--others', '--exclude-standard', '-z'],
    {cwd, stdio: ['ignore', 'pipe', 'inherit']})
  const completion = new Promise((resolve, reject) => {
    child.on('error', reject)
    child.on('close', resolve)
  })
  const filenames = []
  let pending = Buffer.alloc(0)
  for await (const chunk of child.stdout) {
    pending = Buffer.concat([pending, chunk])
    let end
    while ((end = pending.indexOf(0)) !== -1) {
      const filename = pending.subarray(0, end).toString('utf8')
      pending = pending.subarray(end + 1)
      if (!filename.split('/').some(segment =>
        ['~', '.gradle', 'build', 'target', '.dart_tool', 'node_modules', 'dist', '.word-stack-runs'].includes(segment))) {
        filenames.push(filename)
      }
    }
  }
  const code = await completion
  if (code !== 0 || pending.length) throw new Error(`UNTRACKED_LIST_FAILED:${cwd}`)
  return filenames.sort()
}
async function sourceState(cwd) {
  const head = git(cwd, ['rev-parse', 'HEAD'])
  const status = git(cwd, ['status', '--porcelain'])
  const diff = execFileSync('git', ['diff', '--binary', 'HEAD'], {cwd, maxBuffer: 128 * 1024 * 1024})
  const untracked = await untrackedSourcePaths(cwd)
  const hash = createHash('sha256').update(head).update(diff)
  for (const filename of untracked) {
    const file = path.join(cwd, filename)
    const info = await stat(file).catch(() => null)
    if (info?.isFile()) hash.update(filename).update(await readFile(file))
  }
  return {head, dirty: status.length > 0, changedEntries: status ? status.split('\n').length : 0,
    sourceDigest: hash.digest('hex')}
}

export async function loadStack() {
  const policy = JSON.parse(await readFile(policyPath, 'utf8'))
  const product = JSON.parse(await readFile(path.join(pluginRoot, 'product/product.json'), 'utf8'))
  if (policy.profile !== 'openmuse-word-stack-policy/1' ||
      policy.wordApiMajor !== product.requires.wordApiMajor ||
      policy.editorSurfaceMajor !== product.requires.editorSurfaceMajor ||
      policy.productProfile !== product.profile) throw new Error('STACK_POLICY_API_MISMATCH')
  const versions = {}
  for (const [name, component] of Object.entries(policy.components)) {
    const file = path.join(workspace, component.path)
    const content = await readFile(file, 'utf8')
    const version = readVersion(content, file)
    if (!atLeast(version, component.minimum)) throw new Error(`COMPONENT_VERSION_TOO_OLD:${name}:${version}`)
    if (file.endsWith('.json') && JSON.parse(content).name !== component.package) throw new Error(`PACKAGE_NAME_MISMATCH:${name}`)
    if (file.endsWith('.yaml') && !new RegExp(`^name: ${component.package}$`, 'm').test(content)) throw new Error(`PACKAGE_NAME_MISMATCH:${name}`)
    if (file.endsWith('.toml') && !new RegExp(`^name = "${component.package}"$`, 'm').test(content)) throw new Error(`PACKAGE_NAME_MISMATCH:${name}`)
    versions[name] = version
  }
  if (versions.plugin !== product.version) throw new Error('PLUGIN_VERSION_MISMATCH')
  return {policy, versions, product}
}

export function parseOptions(argv) {
  const result = {platform: 'desktop', gate: 'e2e', suite: 'quick', scope: 'edit', mode: 'dev', dryRun: false,
    privateKey: null, publicKey: null, keyId: null}
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i]
    if (item === '--dry-run') result.dryRun = true
    else if (['--platform', '--gate', '--suite', '--scope', '--mode', '--private-key', '--public-key', '--key-id'].includes(item)) {
      if (!argv[i + 1]) throw new Error(`MISSING_VALUE:${item}`)
      result[item.slice(2).replace(/-([a-z])/gu, (_, letter) => letter.toUpperCase())] = argv[++i]
    } else throw new Error(`UNKNOWN_OPTION:${item}`)
  }
  if (!['desktop', 'android', 'ios', 'web', 'all'].includes(result.platform) ||
      !['build', 'e2e'].includes(result.gate) || !['quick', 'full'].includes(result.suite) ||
      !['render', 'edit'].includes(result.scope) ||
      !['dev', 'release'].includes(result.mode)) throw new Error('INVALID_OPTIONS')
  if (result.scope === 'render' && result.platform !== 'desktop') {
    throw new Error('RENDER_SCOPE_DESKTOP_ONLY')
  }
  if (result.mode === 'release' && (!result.privateKey || !result.publicKey || !result.keyId)) {
    throw new Error('RELEASE_SIGNING_KEY_REQUIRED')
  }
  return result
}

export function targets(platform, system = process.platform) {
  if (platform === 'all') {
    if (system !== 'darwin') throw new Error('ALL_TARGETS_REQUIRE_MACOS')
    return ['desktop', 'android', 'ios', 'web']
  }
  if (platform === 'desktop' && !['darwin', 'linux', 'win32'].includes(system)) throw new Error('DESKTOP_PLATFORM_UNSUPPORTED')
  if (platform === 'ios' && system !== 'darwin') throw new Error('IOS_REQUIRES_MACOS')
  return [platform]
}

function hostBuild(target, mode, hostRoot = host) {
  if (mode === 'release') {
    if (target === 'desktop') {
      if (process.platform !== 'darwin') throw new Error('RELEASE_DESKTOP_BUILDER_MISSING_FOR_THIS_OS')
      return {cwd: hostRoot, cmd: 'bash', args: ['scripts/ci/build-macos.sh']}
    }
    return {cwd: hostRoot, cmd: 'bash', args: [`scripts/ci/build-${target}.sh`]}
  }
  if (target === 'desktop') {
    const kind = {darwin: 'macos', linux: 'linux', win32: 'windows'}[process.platform]
    return {cwd: path.join(hostRoot, 'app/openmuse_host'), cmd: 'flutter', args: ['build', kind, '--debug']}
  }
  const app = target === 'web' ? 'openmuse_web' : 'openmuse_mobile'
  const args = target === 'android' ? ['build', 'apk', '--debug'] :
    target === 'ios' ? ['build', 'ios', '--debug', '--no-codesign'] : ['build', 'web', '--release']
  return {cwd: path.join(hostRoot, `app/${app}`), cmd: 'flutter', args}
}

export function createPlan(options, paths = {office, host, pluginRoot}) {
  const tasks = [
    {name: 'plugin-contract', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'validate']},
    {name: 'plugin-source-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:genoffice']},
    {name: 'plugin-icon-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:icons']},
    {name: 'plugin-cover-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:cover-previews']},
    {name: 'plugin-wordart-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:wordart-previews']},
    {name: 'plugin-quick-styles-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:quick-styles']},
    {name: 'plugin-shape-audit', cwd: paths.pluginRoot, cmd: 'npm', args: ['run', 'audit:shape-previews']},
    {name: 'plugin-tests', cwd: paths.pluginRoot, cmd: 'npm', args: ['test']},
    ...(options.scope === 'edit' ? [{name: 'core-golden', cwd: paths.office, cmd: 'cargo', args: ['test', '--manifest-path', 'libs/word-core/Cargo.toml', '--test', '04_function_stage3_golden']}] : []),
    {name: 'ffi-tests', cwd: paths.office, cmd: 'cargo', args: ['test', '--manifest-path', 'samples/docx-mvp-render/native/Cargo.toml', '--test', 'p2_ffi', ...(options.scope === 'edit' ? ['--test', 'p5_hash'] : ['f5_dump_json_stage3_shape'])]},
    {name: 'ffi-build', cwd: paths.office, cmd: 'cargo', args: ['build', '--release', '--manifest-path', 'samples/docx-mvp-render/native/Cargo.toml']},
    {name: 'word-render-pub', cwd: path.join(paths.office, 'samples/libs/word/word_render'), cmd: 'flutter', args: ['pub', 'get']},
    {name: 'word-render-tests', cwd: path.join(paths.office, 'samples/libs/word/word_render'), cmd: 'flutter', args: ['test', '--no-pub']},
    {name: 'word-editor-pub', cwd: path.join(paths.office, 'samples/libs/word/word_editor'), cmd: 'flutter', args: ['pub', 'get']},
    {name: 'word-editor-tests', cwd: path.join(paths.office, 'samples/libs/word/word_editor'), cmd: 'flutter', args: options.suite === 'full' ? ['test', '--no-pub'] : ['test', '--no-pub', 'test/word_product_shell_test.dart', 'test/word_menu_grid_test.dart', 'test/word_cover_gallery_test.dart', 'test/word_wordart_gallery_test.dart', 'test/word_quick_styles_test.dart', 'test/word_zoom_dialog_test.dart', 'test/word_go_to_panel_test.dart', 'test/word_ruler_test.dart']},
    {name: 'word-flutter-pub', cwd: path.join(paths.office, 'samples/docx-mvp-render/flutter'), cmd: 'flutter', args: ['pub', 'get']},
    {name: 'word-flutter-tests', cwd: path.join(paths.office, 'samples/docx-mvp-render/flutter'), cmd: 'flutter', args: options.suite === 'full' ? ['test'] : ['test', 'test/p2_engine_test.dart', 'test/render_command_test.dart']}
  ]
  for (const target of targets(options.platform)) {
    const build = hostBuild(target, options.mode, paths.host)
    if (options.mode === 'dev') tasks.push({name: `host-${target}-pub`, cwd: build.cwd, cmd: 'flutter', args: ['pub', 'get']})
    tasks.push({name: `host-${target}-build`, ...build})
    if (options.gate === 'e2e') tasks.push({name: `host-${target}-e2e`, cwd: paths.host,
      cmd: 'bash', args: [`scripts/word-product-e2e-${target}.sh`]})
  }
  return tasks
}

async function runTask(task, logDir, env) {
  const commandLine = [task.cmd, ...task.args].join(' ')
  console.log(`\n==> ${task.name}: ${commandLine}`)
  const started = Date.now()
  const logPath = path.join(logDir, `${task.name}.log`)
  const log = createWriteStream(logPath)
  let tail = ''
  const child = spawn(task.cmd, task.args, {cwd: task.cwd, env: {...process.env, ...env}, stdio: ['inherit', 'pipe', 'pipe']})
  for (const stream of [child.stdout, child.stderr]) {
    stream.on('data', chunk => {
      log.write(chunk)
      tail = (tail + chunk.toString('utf8')).slice(-4096)
    })
  }
  const code = await new Promise((resolve, reject) => {
    child.on('error', reject)
    child.on('close', resolve)
  })
  log.end()
  await new Promise(resolve => log.on('finish', resolve))
  if (code === 0) console.log(`<== ${task.name}: passed (${Date.now() - started} ms)`)
  else console.error(`<== ${task.name}: failed (${code})\n${tail}`)
  return {name: task.name, command: commandLine, cwd: task.cwd, durationMs: Date.now() - started,
    exitCode: code, log: logPath}
}

function sha256(bytes) { return createHash('sha256').update(bytes).digest('hex') }

export async function verifyE2eAttestation(attestation, expected, requiredCases) {
  if (attestation?.profile !== 'openmuse-word-stack-e2e/1' ||
      attestation.target !== expected.target ||
      attestation.bundleSha256 !== expected.bundleSha256 ||
      attestation.coreSourceDigest !== expected.coreSourceDigest ||
      attestation.coreLibsSourceDigest !== expected.coreLibsSourceDigest ||
      attestation.editorSourceDigest !== expected.editorSourceDigest ||
      attestation.hostSourceDigest !== expected.hostSourceDigest ||
      attestation.engineSourceDigest !== expected.engineSourceDigest) {
    throw new Error(`E2E_IDENTITY_MISMATCH:${expected.target}`)
  }
  const artifact = attestation.hostArtifact
  const engine = attestation.engineArtifact
  for (const [label, item] of [['host', artifact], ['engine', engine]]) {
    if (!item || !path.isAbsolute(item.path) || !/^[a-f0-9]{64}$/u.test(item.sha256) ||
        sha256(await readFile(item.path)) !== item.sha256) {
      throw new Error(`E2E_ARTIFACT_INVALID:${expected.target}:${label}`)
    }
  }
  if (expected.nativeEngineSha256 &&
      attestation.sourceNativeEngineSha256 !== expected.nativeEngineSha256) {
    throw new Error(`E2E_ENGINE_MISMATCH:${expected.target}`)
  }
  for (const caseId of requiredCases) {
    const result = attestation.cases?.[caseId]
    if (result?.status !== 'passed' || !Array.isArray(result.evidence) || !result.evidence.length) {
      throw new Error(`E2E_CASE_MISSING:${expected.target}:${caseId}`)
    }
    for (const evidence of result.evidence) {
      if (typeof evidence !== 'string' || !path.isAbsolute(evidence) ||
          !(await stat(evidence).catch(() => null))?.isFile()) {
        throw new Error(`E2E_EVIDENCE_MISSING:${expected.target}:${caseId}`)
      }
    }
  }
  return {target: expected.target, hostArtifact: artifact, engineArtifact: engine,
    passedCases: requiredCases, attestedAt: attestation.completedAt}
}

function nativeLibraryPath() {
  const extension = {darwin: 'dylib', linux: 'so', win32: 'dll'}[process.platform]
  if (!extension) throw new Error('NATIVE_FFI_PLATFORM_UNSUPPORTED')
  const filename = process.platform === 'win32' ? 'word_core_ffi.dll' : `libword_core_ffi.${extension}`
  return path.join(office, 'samples/docx-mvp-render/native/target/release', filename)
}

async function main() {
  const options = parseOptions(process.argv.slice(2))
  if (options.mode === 'release') {
    options.privateKey = path.resolve(options.privateKey)
    options.publicKey = path.resolve(options.publicKey)
  }
  const stack = await loadStack()
  const plan = createPlan(options)
  if (options.dryRun) {
    const shownPlan = [...plan.slice(0, 2),
      {name: 'plugin-pack-and-verify', cwd: pluginRoot, cmd: 'node', args: ['scripts/pack.mjs', '<signing-arguments>']},
      ...plan.slice(2)]
    console.log(JSON.stringify({options, versions: stack.versions,
      tasks: shownPlan.map(({name, cwd, cmd, args}) => ({name, cwd, command: [cmd, ...args]}))}, null, 2))
    return
  }
  const repositories = {
    ecosystem: await sourceState(ecosystem), host: await sourceState(host),
    core: await sourceState(path.join(office, 'libs/word-core')),
    coreLibs: await sourceState(path.join(office, 'libs/core-libs')),
    sample: await sourceState(path.join(office, 'samples/docx-mvp-render')),
    flutter: await sourceState(path.join(office, 'samples/libs/word'))
  }
  if (options.mode === 'release' && Object.values(repositories).some(item => item.dirty)) {
    throw new Error('RELEASE_REQUIRES_CLEAN_SOURCE_REVISIONS')
  }
  const selected = targets(options.platform)
  const runId = new Date().toISOString().replace(/[:.]/gu, '-') + '-' + repositories.ecosystem.head.slice(0, 8)
  const logDir = path.join(outputRoot, runId)
  await mkdir(logDir, {recursive: true})
  const report = {profile: 'openmuse-word-stack-run/1', runId, startedAt: new Date().toISOString(),
    options: {...options, privateKey: options.privateKey ? '<provided>' : null},
    versions: stack.versions, api: {word: stack.policy.wordApiMajor, editor: stack.policy.editorSurfaceMajor},
    policySha256: sha256(await readFile(policyPath)),
    repositories, stages: [], status: 'running'}
  const reportPath = path.join(logDir, 'report.json')
  const saveReport = async () => writeFile(reportPath, JSON.stringify(report, null, 2) + '\n')
  let tempKeys
  try {
    if (options.gate === 'e2e') {
      const missing = selected.filter(target => !plan.some(task => task.name === `host-${target}-e2e`) ||
        !existsSync(path.join(host, `scripts/word-product-e2e-${target}.sh`)))
      if (missing.length) throw new Error(`HOST_WORD_E2E_HOOK_MISSING:${missing.join(',')}`)
    }
    if (options.mode === 'dev') {
      tempKeys = await mkdtemp(path.join(os.tmpdir(), 'openmuse-word-stack-'))
      const keys = generateKeyPairSync('ed25519', {privateKeyEncoding: {type: 'pkcs8', format: 'pem'},
        publicKeyEncoding: {type: 'spki', format: 'pem'}})
      options.privateKey = path.join(tempKeys, 'private.pem')
      options.publicKey = path.join(logDir, 'test-public.pem')
      options.keyId = `dev-${runId}`
      await writeFile(options.privateKey, keys.privateKey, {mode: 0o600})
      await writeFile(options.publicKey, keys.publicKey)
    }
    for (const task of plan.slice(0, 2)) {
      const result = await runTask(task, logDir)
      report.stages.push(result)
      await saveReport()
      if (result.exitCode !== 0) throw new Error(`STAGE_FAILED:${task.name}`)
    }
    const pack = await runTask({name: 'plugin-pack', cwd: pluginRoot, cmd: 'node', args: [
      'scripts/pack.mjs', '--private-key', options.privateKey, '--key-id', options.keyId
    ]}, logDir)
    report.stages.push(pack)
    if (pack.exitCode !== 0) throw new Error('PLUGIN_PACK_FAILED')
    const bundle = path.join(pluginRoot, `dist/word-${stack.versions.plugin}.mcpb`)
    const bundleBytes = await readFile(bundle)
    report.bundle = {path: bundle, sha256: sha256(bundleBytes),
      verified: await verifyPackage(bundleBytes, await readFile(options.publicKey), options.keyId)}
    await saveReport()
    const env = {WORD_STACK_BUNDLE: bundle, WORD_STACK_PLUGIN_VERSION: stack.versions.plugin,
      WORD_STACK_PUBLIC_KEY: options.publicKey,
      WORD_STACK_KEY_ID: options.keyId, WORD_STACK_RUN_REPORT: reportPath,
      WORD_STACK_CORE_SOURCE_DIGEST: repositories.core.sourceDigest,
      WORD_STACK_CORE_LIBS_SOURCE_DIGEST: repositories.coreLibs.sourceDigest,
      WORD_STACK_EDITOR_SOURCE_DIGEST: repositories.flutter.sourceDigest,
      WORD_STACK_HOST_SOURCE_DIGEST: repositories.host.sourceDigest,
      WORD_STACK_ENGINE_SOURCE_DIGEST: repositories.sample.sourceDigest,
      WORD_STACK_BUNDLE_SHA256: report.bundle.sha256}
    for (const task of plan.slice(2)) {
      const target = task.name.startsWith('host-') && task.name.endsWith('-e2e') ?
        task.name.slice(5, -4) : null
      if (target) env.WORD_STACK_E2E_RESULT_PATH = path.join(logDir, `e2e-${target}.json`)
      const result = await runTask(task, logDir, env)
      report.stages.push(result)
      await saveReport()
      if (result.exitCode !== 0) throw new Error(`STAGE_FAILED:${task.name}`)
      if (task.name === 'ffi-build') {
        const nativePath = nativeLibraryPath()
        const nativeSha = sha256(await readFile(nativePath))
        report.nativeEngine = {path: nativePath, sha256: nativeSha}
        env.WORD_CORE_FFI = nativePath
        env.WORD_STACK_NATIVE_ENGINE_SHA256 = nativeSha
        await saveReport()
      }
      if (target) {
        const attestation = JSON.parse(await readFile(env.WORD_STACK_E2E_RESULT_PATH, 'utf8'))
        const requiredCases = options.scope === 'render'
          ? [...stack.policy.e2eCases.renderCommon,
            ...(target === 'desktop' ? stack.policy.e2eCases.renderDesktop : stack.policy.e2eCases[target])]
          : [...stack.policy.e2eCases.common, ...stack.policy.e2eCases[target],
            ...(options.suite === 'full' ? stack.policy.e2eCases.full : [])]
        report.stages[report.stages.length - 1].attestation = await verifyE2eAttestation(attestation, {
          target, bundleSha256: report.bundle.sha256,
          coreSourceDigest: repositories.core.sourceDigest,
          coreLibsSourceDigest: repositories.coreLibs.sourceDigest,
          editorSourceDigest: repositories.flutter.sourceDigest,
          hostSourceDigest: repositories.host.sourceDigest,
          engineSourceDigest: repositories.sample.sourceDigest,
          nativeEngineSha256: target === 'desktop' ? report.nativeEngine.sha256 : null
        }, requiredCases)
        await saveReport()
      }
    }
    report.status = options.gate === 'e2e' ? 'e2e-passed' : 'build-passed-not-e2e'
  } catch (error) {
    report.status = 'failed'
    report.error = String(error)
    throw error
  } finally {
    report.finishedAt = new Date().toISOString()
    await saveReport()
    if (tempKeys) await rm(tempKeys, {recursive: true, force: true})
    console.log(`\nWord stack report: ${reportPath}`)
  }
}

// Imported by tests without executing the build.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main()
}
