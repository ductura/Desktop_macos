// SHA-256 of the macOS package next to it in the CI artifact (DAN-1075).
// Run with node --test scripts/package-sha256.test.mjs from the repository root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const SCRIPT = fileURLToPath(new URL('package-sha256.mjs', import.meta.url));
const NAME = 'Ductura-macOS.dmg';
// NIST vector: one million 'a'. Longer than three 64 KiB reads, so the first,
// middle and last byte below sit in different reads.
const BYTES = Buffer.alloc(1_000_000, 'a');
const SHA = 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0';

// A fresh folder with dist/Ductura-macOS.dmg holding `bytes` (none when null).
function folder(bytes = BYTES) {
  const dir = mkdtempSync(join(tmpdir(), 'pkg-sha-'));
  mkdirSync(join(dir, 'dist'));
  if (bytes !== null) writeFileSync(join(dir, 'dist', NAME), bytes);
  return dir;
}
const run = (dir, ...args) => {
  const r = spawnSync(process.execPath, [SCRIPT, ...args], { cwd: dir, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
};
const sidecar = (dir) => join(dir, 'dist', `${NAME}.sha256`);
function within(fn) {
  return () => { const dir = folder(); try { fn(dir); } finally { rmSync(dir, { recursive: true, force: true }); } };
}

for (const [where, at] of [['first', 0], ['middle', 500_000], ['last', 999_999]]) {
  test(`--verify fails when the ${where} byte changes after the hash was written`, within((dir) => {
    assert.equal(run(dir).code, 0);
    const changed = Buffer.from(BYTES);
    changed[at] ^= 0x01;
    writeFileSync(join(dir, 'dist', NAME), changed);
    const r = run(dir, '--verify');
    assert.equal(r.code, 1, r.out);
    assert.match(r.out, /differs/);
  }));
}

const CHANGED = [['one byte shorter', BYTES.subarray(1), 1], ['one byte longer', Buffer.concat([BYTES, Buffer.of(0)]), 1], ['emptied', Buffer.alloc(0), 2]];
for (const [what, bytes, code] of CHANGED) {
  test(`--verify exits ${code} when the package is ${what} after the hash was written`, within((dir) => {
    assert.equal(run(dir).code, 0);
    writeFileSync(join(dir, 'dist', NAME), bytes);
    assert.equal(run(dir, '--verify').code, code);
  }));
}

test('writes one shasum line with the known hash and --verify passes on the untouched package', within((dir) => {
  const r = run(dir);
  assert.equal(r.code, 0, r.out);
  assert.equal(readFileSync(sidecar(dir), 'utf8'), `${SHA}  ${NAME}\n`);
  assert.equal(run(dir, '--verify').code, 0);
}));

test('writing again replaces an old .sha256', within((dir) => {
  writeFileSync(sidecar(dir), `${'0'.repeat(64)}  ${NAME}\n`);
  assert.equal(run(dir, '--verify').code, 1);
  assert.equal(run(dir).code, 0);
  assert.equal(run(dir, '--verify').code, 0);
}));

// Every line that is not exactly `<64 lowercase hex>  Ductura-macOS.dmg\n`.
const BAD_LINES = [
  ['CRLF', `${SHA}  ${NAME}\r\n`],
  ['no final LF', `${SHA}  ${NAME}`],
  ['two lines', `${SHA}  ${NAME}\n${SHA}  ${NAME}\n`],
  ['empty', ''],
  ['only LF', '\n'],
  ['tab', `${SHA}\t${NAME}\n`],
  ['one space', `${SHA} ${NAME}\n`],
  ['three spaces', `${SHA}   ${NAME}\n`],
  ['NBSP', `${SHA}  ${NAME}\n`],
  ['DEL at the end', `${SHA}  ${NAME}\u007f\n`],
  ['BOM', `﻿${SHA}  ${NAME}\n`],
  ['uppercase hex', `${SHA.toUpperCase()}  ${NAME}\n`],
  ['63 hex', `${SHA.slice(1)}  ${NAME}\n`],
  ['65 hex', `${SHA}0  ${NAME}\n`],
  ['non-hex letter', `${SHA.slice(0, 63)}g  ${NAME}\n`],
  ['binary mode marker', `${SHA} *${NAME}\n`],
  ['other name', `${SHA}  Ductura-macOS.dmg.old\n`],
  ['name with a path', `${SHA}  dist/${NAME}\n`],
  ['name with a Windows path', `${SHA}  dist\\${NAME}\n`],
  ['space after the name', `${SHA}  ${NAME} \n`],
  ['leading space', ` ${SHA}  ${NAME}\n`],
  ['NUL', `${SHA}  ${NAME}\0\n`],
  ['line after the line', `${SHA}  ${NAME}\n\n`],
  ['longer than 84 bytes', `${SHA}  ${NAME}\n${' '.repeat(1000)}`],
];
for (const [name, line] of BAD_LINES) {
  test(`--verify refuses a .sha256 line (exit 2): ${name}`, within((dir) => {
    writeFileSync(sidecar(dir), line);
    assert.notEqual(line, `${SHA}  ${NAME}\n`);
    const r = run(dir, '--verify');
    assert.equal(r.code, 2, r.out);
  }));
}

for (const byte of [0xc4, 0xe4]) {
  test(`--verify refuses a non-ASCII byte in a .sha256 of the right length (exit 2): ${byte.toString(16)}`, within((dir) => {
    const line = Buffer.from(`${SHA}  ${NAME}\n`);
    line[line.length - 5] = byte;
    writeFileSync(sidecar(dir), line);
    assert.equal(run(dir, '--verify').code, 2);
  }));
}

test('--verify without a .sha256 file exits 2', within((dir) => {
  assert.equal(run(dir, '--verify').code, 2);
}));

for (const args of [[], ['--verify']]) {
  test(`a .sha256 that is a folder exits 2, not 1: ${args.join(' ') || 'write'}`, within((dir) => {
    mkdirSync(sidecar(dir));
    assert.equal(run(dir, ...args).code, 2);
  }));
}

for (const args of [[], ['--verify']]) {
  test(`missing, empty, folder or symlink package exits 2: ${args.join(' ') || 'write'}`, () => {
    for (const make of [() => folder(null), () => folder(Buffer.alloc(0)), () => {
      const dir = folder(null); mkdirSync(join(dir, 'dist', NAME)); return dir;
    }, () => {
      const dir = folder(null); writeFileSync(join(dir, 'real.dmg'), BYTES);
      symlinkSync(join(dir, 'real.dmg'), join(dir, 'dist', NAME)); return dir;
    }]) {
      const dir = make();
      try {
        writeFileSync(sidecar(dir), `${SHA}  ${NAME}\n`);
        assert.equal(run(dir, ...args).code, 2);
      } finally { rmSync(dir, { recursive: true, force: true }); }
    }
  });
}

for (const args of [['--Verify'], ['--verify', 'extra'], ['--verify', '--verify'], ['--verify='], [''], [`dist/${NAME}`], ['--write']]) {
  // A well-formed but wrong hash: --verify would exit 1 and writing would replace it.
  test(`unknown arguments exit 2 and change nothing: ${JSON.stringify(args)}`, within((dir) => {
    const old = `${'0'.repeat(64)}  ${NAME}\n`;
    writeFileSync(sidecar(dir), old);
    assert.equal(run(dir, ...args).code, 2);
    assert.equal(readFileSync(sidecar(dir), 'utf8'), old);
  }));
}

// CI: the hash is written right after build-dmg.sh, checked after the last
// step that may touch dist/, and both files go into the Ductura-macOS artifact.
const WRITE = 'node scripts/package-sha256.mjs';
const VERIFY = `${WRITE} --verify`;
function ciProblems(wf) {
  const problems = [];
  const steps = wf?.jobs?.['build-test']?.steps ?? [];
  const at = (pred, what) => {
    const found = steps.flatMap((s, i) => (pred(s) ? [i] : []));
    if (found.length !== 1) problems.push(`${what}: ${found.length} steps`);
    return found[0] ?? -1;
  };
  const node = at((s) => /^actions\/setup-node@[0-9a-f]{40}$/.test(s?.uses ?? ''), 'setup-node');
  const build = at((s) => s?.run === './scripts/build-dmg.sh', 'build');
  const write = at((s) => s?.run === WRITE, 'write');
  const functional = at((s) => String(s?.run ?? '').startsWith('./Tests/functional/'), 'functional');
  const verify = at((s) => s?.run === VERIFY, 'verify');
  const upload = at((s) => /^actions\/upload-artifact@/.test(s?.uses ?? ''), 'upload');
  if (!(node < build && write === build + 1 && functional > write && verify > functional && upload === verify + 1)) {
    problems.push('order');
  }
  for (const [i, what] of [[write, 'write'], [verify, 'verify'], [upload, 'upload']]) {
    if (steps[i] && ('if' in steps[i] || 'continue-on-error' in steps[i])) problems.push(`${what} may be skipped`);
  }
  const w = steps[upload]?.with ?? {};
  const paths = String(w.path ?? '').split('\n').map((p) => p.trim()).filter(Boolean).sort();
  if (w.name !== 'Ductura-macOS') problems.push('artifact name');
  if (JSON.stringify(paths) !== JSON.stringify([`dist/${NAME}`, `dist/${NAME}.sha256`])) problems.push('artifact paths');
  if (w['if-no-files-found'] !== 'error') problems.push('if-no-files-found');
  const tests = wf?.jobs?.['ci-ok-test']?.steps ?? [];
  if (!tests.some((s) => s?.run === 'node --test scripts/package-sha256.test.mjs')) problems.push('ci-ok-test');
  return problems;
}

const ci = () => parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('ci.yml writes, verifies and uploads the hash with the package', () => {
  assert.deepEqual(ciProblems(ci()), []);
});

const steps = (wf) => wf.jobs['build-test'].steps;
const findRun = (wf, run) => steps(wf).findIndex((s) => s.run === run);
const MUTATIONS = [
  ['upload without .sha256', 'artifact paths', (wf) => { steps(wf).at(-1).with.path = `dist/${NAME}`; }],
  ['upload with a glob', 'artifact paths', (wf) => { steps(wf).at(-1).with.path = 'dist/*'; }],
  ['upload may be skipped', 'upload may be skipped', (wf) => { steps(wf).at(-1).if = 'always()'; }],
  ['--verify || true', 'verify: 0 steps', (wf) => { steps(wf)[findRun(wf, VERIFY)].run = `${VERIFY} || true`; }],
  ['if-no-files-found left at warn', 'if-no-files-found', (wf) => { delete steps(wf).at(-1).with['if-no-files-found']; }],
  ['--verify before the functional test', 'order', (wf) => {
    const [v] = steps(wf).splice(findRun(wf, VERIFY), 1);
    steps(wf).splice(findRun(wf, WRITE) + 1, 0, v);
  }],
  ['a step between --verify and upload', 'order', (wf) => { steps(wf).splice(findRun(wf, VERIFY) + 1, 0, { run: 'touch dist/x' }); }],
  ['--verify may be skipped', 'verify may be skipped', (wf) => { steps(wf)[findRun(wf, VERIFY)]['continue-on-error'] = true; }],
  ['no write step', 'write: 0 steps', (wf) => { steps(wf).splice(findRun(wf, WRITE), 1); }],
  ['tests not run in ci-ok-test', 'ci-ok-test', (wf) => { wf.jobs['ci-ok-test'].steps = []; }],
];
for (const [name, problem, mutate] of MUTATIONS) {
  test(`CI check fails: ${name}`, () => {
    const wf = ci();
    mutate(wf);
    assert.ok(ciProblems(wf).includes(problem), ciProblems(wf).join('; '));
  });
}
