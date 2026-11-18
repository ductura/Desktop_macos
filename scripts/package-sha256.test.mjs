// SHA-256 of the macOS package next to it in the CI artifact (DAN-1075).
// Run with node --test scripts/package-sha256.test.mjs from the repository root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { closeSync, constants, existsSync, linkSync, lstatSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
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
  const r = spawnSync(process.execPath, [SCRIPT, ...args], { cwd: dir, encoding: 'utf8', timeout: 20_000 });
  return { code: r.status, out: r.stdout + r.stderr };
};
const sidecar = (dir) => join(dir, 'dist', `${NAME}.sha256`);
// Buffer.equals, not deepEqual: a failing deepEqual on 1 MB builds a huge diff.
const unchanged = (path) => assert.ok(readFileSync(path).equals(BYTES), `${path} changed`);
// Writing leaves only the package and its .sha256: no other file anywhere.
const distPair = (dir) => assert.deepEqual(readdirSync(join(dir, 'dist')).sort(), [NAME, `${NAME}.sha256`]);
const onlyPair = (dir) => {
  assert.deepEqual(readdirSync(dir), ['dist']);
  distPair(dir);
};
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
  onlyPair(dir);
  assert.equal(run(dir, '--verify').code, 0);
  onlyPair(dir);
}));

test('writing again replaces a longer old .sha256 whole', within((dir) => {
  writeFileSync(sidecar(dir), `${'0'.repeat(64)}  ${NAME}\r\n${'x'.repeat(100)}`);
  assert.equal(run(dir).code, 0);
  assert.equal(readFileSync(sidecar(dir), 'utf8'), `${SHA}  ${NAME}\n`);
  onlyPair(dir);
  assert.equal(run(dir, '--verify').code, 0);
  onlyPair(dir);
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
  ['two NBSP', `${SHA}\u00a0\u00a0${NAME}\n`],
  ['DEL at the end', `${SHA}  ${NAME}\u007f\n`],
  ['BOM', `\ufeff${SHA}  ${NAME}\n`],
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
  // Exactly 84 bytes, so these reach the line pattern, not only the size check.
  ['two tabs', `${SHA}\t\t${NAME}\n`],
  ['tab and space', `${SHA}\t ${NAME}\n`],
  ['space and tab', `${SHA} \t${NAME}\n`],
  ['one NBSP', `${SHA}\u00a0${NAME}\n`],
  ['two LF as separator', `${SHA}\n\n${NAME}\n`],
  ['CR instead of LF', `${SHA}  ${NAME}\r`],
  ['DEL instead of LF', `${SHA}  ${NAME}\u007f`],
  ['NUL instead of LF', `${SHA}  ${NAME}\0`],
  ['space instead of LF', `${SHA}  ${NAME} `],
];
const EXACT_SIZE = new Set(['two tabs', 'tab and space', 'space and tab', 'one NBSP', 'two LF as separator',
  'CR instead of LF', 'DEL instead of LF', 'NUL instead of LF', 'space instead of LF']);
for (const [name, line] of BAD_LINES) {
  test(`--verify refuses a .sha256 line (exit 2): ${name}`, within((dir) => {
    writeFileSync(sidecar(dir), line);
    assert.notEqual(line, `${SHA}  ${NAME}\n`);
    if (EXACT_SIZE.has(name)) assert.equal(Buffer.byteLength(line), 84);
    const r = run(dir, '--verify');
    assert.equal(r.code, 2, r.out);
  }));
}

// The good line with one byte given the high bit (0x80): an ASCII decoding that
// drops that bit would read it back as the good line.
const GOOD = `${SHA}  ${NAME}\n`;
for (const at of [0, SHA.indexOf('0'), 64, GOOD.indexOf('.'), 83]) {
  test(`--verify refuses a high-bit byte in a .sha256 of the right length (exit 2): offset ${at}`, within((dir) => {
    const line = Buffer.from(GOOD);
    line[at] |= 0x80;
    writeFileSync(sidecar(dir), line);
    assert.equal(run(dir, '--verify').code, 2);
  }));
}

test('--verify refuses a .sha256 that is a symbolic link to a good line (exit 2)', within((dir) => {
  writeFileSync(join(dir, 'good.sha256'), GOOD);
  symlinkSync(join(dir, 'good.sha256'), sidecar(dir));
  assert.equal(run(dir, '--verify').code, 2);
}));

// Checks with lstat before reading, so a regression that leaves a FIFO or a
// link at .sha256 fails here instead of blocking the test.
const isPlainSidecar = (dir) => {
  const st = lstatSync(sidecar(dir));
  assert.ok(st.isFile() && st.nlink === 1, '.sha256 is a regular file with one name');
  assert.equal(readFileSync(sidecar(dir), 'utf8'), `${SHA}  ${NAME}\n`);
};

// A FIFO in place of either file, with no other end, with a reader or with a
// writer that the test holds open: never a wait (the process has a 20 s
// limit). --verify refuses it (2); writing replaces a .sha256 FIFO by rename
// (0) and refuses a package FIFO (2). The script is the package's reader.
const FIFO_PEERS = [['no other end', null], ['a reader', constants.O_RDONLY | constants.O_NONBLOCK], ['a writer', constants.O_RDWR]];
for (const [what, at] of [['.sha256', sidecar], ['package', (dir) => join(dir, 'dist', NAME)]]) {
  for (const [peer, flags] of FIFO_PEERS) {
    if (what === 'package' && peer === 'a reader') continue;
    for (const args of [[], ['--verify']]) {
      const replaced = what === '.sha256' && args.length === 0;
      test(`a ${what} FIFO with ${peer} exits ${replaced ? 0 : 2} without waiting: ${args.join(' ') || 'write'}`, within((dir) => {
        if (what === 'package') writeFileSync(sidecar(dir), `${SHA}  ${NAME}\n`);
        rmSync(at(dir), { force: true });
        assert.equal(spawnSync('mkfifo', [at(dir)]).status, 0);
        const held = flags === null ? null : openSync(at(dir), flags);
        try {
          const r = run(dir, ...args);
          assert.equal(r.code, replaced ? 0 : 2, r.out);
          if (replaced) {
            isPlainSidecar(dir); // lstat first: reading a FIFO left in place would block
            onlyPair(dir);
          } else {
            assert.match(r.out, /is not a regular file/);
          }
        } finally {
          if (held !== null) closeSync(held);
        }
      }));
    }
  }
}

// Writing never goes through an existing .sha256 path: the line goes into a
// new temporary file in dist/ (opened wx) that is then renamed over it, so a
// link at .sha256 is replaced and whatever it named stays as it was.
test('writing over a .sha256 hard-linked to the package leaves the package as it was', within((dir) => {
  linkSync(join(dir, 'dist', NAME), sidecar(dir));
  assert.equal(run(dir).code, 0);
  unchanged(join(dir, 'dist', NAME));
  assert.equal(lstatSync(join(dir, 'dist', NAME)).nlink, 1);
  isPlainSidecar(dir);
  onlyPair(dir);
}));

test('writing over a .sha256 hard-linked to another file leaves that file as it was', within((dir) => {
  const other = join(dir, 'other.txt');
  writeFileSync(other, `${'0'.repeat(64)}  ${NAME}\r\nkeep`);
  linkSync(other, sidecar(dir));
  linkSync(other, join(dir, 'third.txt'));
  assert.equal(run(dir).code, 0);
  assert.equal(readFileSync(other, 'utf8'), `${'0'.repeat(64)}  ${NAME}\r\nkeep`);
  assert.equal(lstatSync(other).nlink, 2);
  isPlainSidecar(dir);
  distPair(dir);
}));

for (const [what, target] of [['the package', (dir) => join(dir, 'dist', NAME)], ['a file outside dist/', (dir) => join(dir, 'outside.txt')]]) {
  test(`writing over a .sha256 symbolic link to ${what} leaves it as it was`, within((dir) => {
    writeFileSync(join(dir, 'outside.txt'), 'keep');
    symlinkSync(target(dir), sidecar(dir));
    assert.equal(run(dir).code, 0);
    unchanged(join(dir, 'dist', NAME));
    assert.equal(readFileSync(join(dir, 'outside.txt'), 'utf8'), 'keep');
    isPlainSidecar(dir);
    distPair(dir);
  }));
}

test('writing over a dangling .sha256 link does not create its target', within((dir) => {
  const nowhere = join(dir, 'nowhere.txt');
  symlinkSync(nowhere, sidecar(dir));
  assert.equal(run(dir).code, 0);
  assert.equal(existsSync(nowhere), false);
  isPlainSidecar(dir);
  onlyPair(dir);
}));

// The temporary name is random; a preloaded module fixes randomBytes so the
// test knows it. With that name free, writing works and leaves no temp file.
const FIXED = `import crypto from 'node:crypto';\nimport { syncBuiltinESMExports } from 'node:module';\n`
  + `crypto.randomBytes = (n) => Buffer.alloc(n, 0xab);\nsyncBuiltinESMExports();\n`;
// Extra preload lines patch node:fs to make one step of the write fail.
const runFixed = (dir, ...args) => runPatched(dir, '', ...args);
const runPatched = (dir, patch, ...args) => {
  const preload = join(dirname(dir), `${basename(dir)}-fixed.mjs`);
  writeFileSync(preload, `${FIXED}import fs from 'node:fs';\n${patch}\nsyncBuiltinESMExports();\n`);
  try {
    const r = spawnSync(process.execPath, ['--import', pathToFileURL(preload).href, SCRIPT, ...args], { cwd: dir, encoding: 'utf8', timeout: 20_000 });
    return { code: r.status, out: r.stdout + r.stderr };
  } finally {
    rmSync(preload, { force: true });
  }
};
const temp = (dir) => join(dir, 'dist', `.${NAME}.sha256.${'ab'.repeat(8)}.tmp`);

test('with a free temporary name writing succeeds and leaves only the pair', within((dir) => {
  assert.equal(runFixed(dir).code, 0);
  isPlainSidecar(dir);
  onlyPair(dir);
}));

// Without the preload the name is random, so a file at the fixed name is
// neither hit nor changed: a hard-coded temporary name fails here.
test('the temporary name is not fixed: a file at the test name stays and writing succeeds', within((dir) => {
  writeFileSync(temp(dir), 'keep');
  assert.equal(run(dir).code, 0);
  assert.equal(readFileSync(temp(dir), 'utf8'), 'keep');
  isPlainSidecar(dir);
}));

// A failing step exits 2 with its own error, leaves the old .sha256 as it was
// and removes the temporary file; a failing clean-up does not hide the error.
// Each step of the write (open, write, close, rename) also fails alone, with
// every other step working: TEMP marks the temporary descriptor and counts the
// bytes written to it, so a close fault fires only after a full write.
const OLD = `${'0'.repeat(64)}  ${NAME}\n`;
const fake = (code) => `Object.assign(new Error('${code} fake'), { code: '${code}' })`;
const TEMP = "let tempFd = -1, wrote = 0; const o = fs.openSync, w = fs.writeSync;\n"
  + "fs.openSync = (p, ...a) => { const fd = o(p, ...a); if (String(p).endsWith('.tmp')) tempFd = fd; return fd; };\n"
  + "fs.writeSync = (fd, ...a) => { const n = w(fd, ...a); if (fd === tempFd) wrote += n; return n; };\n"
  + `const full = () => wrote === ${64 + 2 + NAME.length + 1};\n`;
const FAULTS = [
  ['a failing open of the temporary file alone', "const o = fs.openSync;\n"
    + `fs.openSync = (p, ...a) => { if (String(p).endsWith('.tmp')) throw ${fake('EACCES')}; return o(p, ...a); };`, /EACCES/, true],
  ['a failing close alone after a full write (descriptor closed)', `${TEMP}const c = fs.closeSync;\n`
    + `fs.closeSync = (fd) => { c(fd); if (fd === tempFd && full()) throw ${fake('EIO')}; };`, /EIO/, true],
  ['a failing close alone after a full write (descriptor left open)', `${TEMP}const c = fs.closeSync;\n`
    + `fs.closeSync = (fd) => { if (fd === tempFd && full()) throw ${fake('EIO')}; c(fd); };`, /EIO/, true],
  ['a failing rename alone', `fs.renameSync = () => { throw ${fake('EXDEV')}; };`, /EXDEV/, true],
  ['a short write', 'const w = fs.writeSync; fs.writeSync = (fd, s, p) => w(fd, String(s).slice(0, 10), p);', /short write/, true],
  ['a failing write', "fs.writeSync = () => { throw Object.assign(new Error('ENOSPC fake'), { code: 'ENOSPC' }); };", /ENOSPC/, true],
  ['a failing write and close', "let failed = false; const c = fs.closeSync;\n"
    + "fs.writeSync = () => { failed = true; throw Object.assign(new Error('ENOSPC fake'), { code: 'ENOSPC' }); };\n"
    + "fs.closeSync = (fd) => { c(fd); if (failed) throw Object.assign(new Error('EIO fake'), { code: 'EIO' }); };", /ENOSPC/, true],
  ['a failing rename and clean-up', "fs.renameSync = () => { throw Object.assign(new Error('EXDEV fake'), { code: 'EXDEV' }); };\n"
    + "fs.unlinkSync = () => { throw Object.assign(new Error('EACCES fake'), { code: 'EACCES' }); };", /EXDEV/, false],
];
for (const [what, patch, message, cleaned] of FAULTS) {
  test(`writing with ${what} exits 2 and keeps the old .sha256`, within((dir) => {
    writeFileSync(sidecar(dir), OLD);
    const r = runPatched(dir, patch);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, message);
    assert.equal(readFileSync(sidecar(dir), 'utf8'), OLD);
    unchanged(join(dir, 'dist', NAME));
    if (cleaned) distPair(dir);
  }));
}

// After the refusal the entry at the temporary path is still exactly what it was.
const TEMP_TAKEN = [
  ['a regular file', (dir) => writeFileSync(temp(dir), 'keep'), (dir) => {
    assert.ok(lstatSync(temp(dir)).isFile());
    assert.equal(readFileSync(temp(dir), 'utf8'), 'keep');
  }],
  ['a hard link to the package', (dir) => linkSync(join(dir, 'dist', NAME), temp(dir)), (dir) => {
    const [t, p] = [lstatSync(temp(dir)), lstatSync(join(dir, 'dist', NAME))];
    assert.ok(t.isFile() && t.ino === p.ino && p.nlink === 2);
  }],
  ['a symbolic link to the package', (dir) => symlinkSync(join(dir, 'dist', NAME), temp(dir)), (dir) => {
    assert.ok(lstatSync(temp(dir)).isSymbolicLink());
    assert.equal(readlinkSync(temp(dir)), join(dir, 'dist', NAME));
  }],
  ['a dangling symbolic link', (dir) => symlinkSync(join(dir, 'nowhere.txt'), temp(dir)), (dir) => {
    assert.ok(lstatSync(temp(dir)).isSymbolicLink());
    assert.equal(readlinkSync(temp(dir)), join(dir, 'nowhere.txt'));
    assert.equal(existsSync(join(dir, 'nowhere.txt')), false);
  }],
];
for (const [what, make, still] of TEMP_TAKEN) {
  test(`writing exits 2 when the temporary path is already ${what}, changing nothing`, within((dir) => {
    writeFileSync(sidecar(dir), `${'0'.repeat(64)}  ${NAME}\n`);
    make(dir);
    const r = runFixed(dir);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, /EEXIST/);
    unchanged(join(dir, 'dist', NAME));
    assert.equal(readFileSync(sidecar(dir), 'utf8'), `${'0'.repeat(64)}  ${NAME}\n`);
    still(dir);
    assert.deepEqual(readdirSync(join(dir, 'dist')).sort(), [`.${NAME}.sha256.${'ab'.repeat(8)}.tmp`, NAME, `${NAME}.sha256`]);
  }));
}

test('--verify without a .sha256 file exits 2', within((dir) => {
  assert.equal(run(dir, '--verify').code, 2);
}));

for (const args of [[], ['--verify']]) {
  test(`a .sha256 that is a folder exits 2, not 1: ${args.join(' ') || 'write'}`, within((dir) => {
    mkdirSync(sidecar(dir));
    assert.equal(run(dir, ...args).code, 2);
    onlyPair(dir);
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
        writeFileSync(sidecar(dir), `${'0'.repeat(64)}  ${NAME}\n`);
        assert.equal(run(dir, ...args).code, 2);
        assert.equal(readFileSync(sidecar(dir), 'utf8'), `${'0'.repeat(64)}  ${NAME}\n`);
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
  const node = at((s) => /^actions\/setup-node@/.test(s?.uses ?? ''), 'setup-node');
  const build = at((s) => s?.run === './scripts/build-dmg.sh', 'build');
  const write = at((s) => s?.run === WRITE, 'write');
  const functional = at((s) => s?.run === './Tests/functional/install-and-launch.sh', 'functional');
  const hashSteps = steps.filter((s) => String(s?.run ?? '').includes('package-sha256')).length;
  if (hashSteps !== 2) problems.push(`hash steps: ${hashSteps}`);
  const verify = at((s) => s?.run === VERIFY, 'verify');
  // Any upload-artifact action (also /merge), in build-test exactly once.
  const uploads = (s) => /^actions\/upload-artifact[/@]/i.test(s?.uses ?? '');
  const upload = at(uploads, 'upload');
  // ... and that one is the plain action on a full SHA, not a sub-action such
  // as /merge, which takes no paths and would upload no pair.
  if (!/^actions\/upload-artifact@[0-9a-f]{40}$/.test(steps[upload]?.uses ?? '')) problems.push('upload action');
  // No other job uploads at all, so none can replace the pair, whatever the
  // spelling of the name (trailing space, expression).
  for (const [job, j] of Object.entries(wf?.jobs ?? {})) {
    if (job !== 'build-test' && (j?.steps ?? []).some(uploads)) problems.push(`${job} uploads an artifact`);
    // A local action or workflow could wrap an upload out of sight.
    for (const u of [j?.uses, ...(j?.steps ?? []).map((s) => s?.uses)]) {
      if (typeof u === 'string' && u.startsWith('./')) problems.push(`${job} uses a local action`);
    }
  }
  if (!(node < build && write === build + 1 && functional > write && verify > functional && upload === verify + 1)) {
    problems.push('order');
  }
  // Only these keys, so no if, continue-on-error, shell, env or working-directory.
  const keys = [[node, 'setup-node', ['uses', 'with']], [write, 'write', ['name', 'run']],
    [functional, 'functional', ['name', 'run']], [verify, 'verify', ['name', 'run']], [upload, 'upload', ['uses', 'with']]];
  for (const job of ['build-test', 'ci-ok-test']) {
    for (const k of Object.keys(wf?.jobs?.[job] ?? {})) {
      if (!['runs-on', 'timeout-minutes', 'permissions', 'steps'].includes(k)) problems.push(`${job} job key ${k}`);
    }
  }
  for (const [i, what, allowed] of keys) {
    for (const k of Object.keys(steps[i] ?? {})) if (!allowed.includes(k)) problems.push(`${what} key ${k}`);
  }
  // setup-node: the same full SHA as in ci-ok-test, Node 24.
  const pinned = (wf?.jobs?.['ci-ok-test']?.steps ?? []).find((s) => /^actions\/setup-node@[0-9a-f]{40}$/.test(s?.uses ?? ''));
  if (!pinned || steps[node]?.uses !== pinned.uses) problems.push('setup-node pin');
  if (JSON.stringify(steps[node]?.with) !== '{"node-version":24}') problems.push('setup-node version');
  const w = steps[upload]?.with ?? {};
  const paths = String(w.path ?? '').split('\n').map((p) => p.trim()).filter(Boolean).sort();
  if (w.name !== 'Ductura-macOS') problems.push('artifact name');
  if (JSON.stringify(paths) !== JSON.stringify([`dist/${NAME}`, `dist/${NAME}.sha256`])) problems.push('artifact paths');
  if (w['if-no-files-found'] !== 'error') problems.push('if-no-files-found');
  // Workflow or job env and defaults could change every run step at once.
  for (const [where, o] of [['workflow', wf], ['build-test', wf?.jobs?.['build-test']]]) {
    for (const k of ['env', 'defaults']) if (Object.hasOwn(o ?? {}, k)) problems.push(`${where} ${k}`);
  }
  const tests = wf?.jobs?.['ci-ok-test']?.steps ?? [];
  const testStep = tests.filter((s) => s?.run === 'node --test scripts/package-sha256.test.mjs');
  if (testStep.length !== 1) problems.push('ci-ok-test');
  for (const k of Object.keys(testStep[0] ?? {})) if (!['name', 'run'].includes(k)) problems.push(`ci-ok-test key ${k}`);
  return problems;
}

const ci = () => parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('ci.yml writes, verifies and uploads the hash with the package', () => {
  assert.deepEqual(ciProblems(ci()), []);
});

const steps = (wf) => wf.jobs['build-test'].steps;
const findRun = (wf, run) => steps(wf).findIndex((s) => s.run === run);
const setupNode = (wf) => steps(wf).find((s) => String(s.uses).startsWith('actions/setup-node@'));
const wf0 = () => ci();
const MUTATIONS = [
  ['upload without .sha256', 'artifact paths', (wf) => { steps(wf).at(-1).with.path = `dist/${NAME}`; }],
  ['upload with a glob', 'artifact paths', (wf) => { steps(wf).at(-1).with.path = 'dist/*'; }],
  ['upload may be skipped', 'upload key if', (wf) => { steps(wf).at(-1).if = 'always()'; }],
  ['--verify || true', 'verify: 0 steps', (wf) => { steps(wf)[findRun(wf, VERIFY)].run = `${VERIFY} || true`; }],
  ['if-no-files-found left at warn', 'if-no-files-found', (wf) => { delete steps(wf).at(-1).with['if-no-files-found']; }],
  ['--verify before the functional test', 'order', (wf) => {
    const [v] = steps(wf).splice(findRun(wf, VERIFY), 1);
    steps(wf).splice(findRun(wf, WRITE) + 1, 0, v);
  }],
  ['a step between --verify and upload', 'order', (wf) => { steps(wf).splice(findRun(wf, VERIFY) + 1, 0, { run: 'touch dist/x' }); }],
  ['--verify may be skipped', 'verify key continue-on-error', (wf) => { steps(wf)[findRun(wf, VERIFY)]['continue-on-error'] = true; }],
  ['--verify run by a shell that ignores it', 'verify key shell', (wf) => { steps(wf)[findRun(wf, VERIFY)].shell = 'sh -c "true" {0}'; }],
  ['write may be skipped', 'write key if', (wf) => { steps(wf)[findRun(wf, WRITE)].if = 'false'; }],
  ['another functional script', 'functional: 0 steps', (wf) => {
    steps(wf).find((s) => s.run === './Tests/functional/install-and-launch.sh').run = './Tests/functional/other.sh';
  }],
  ['functional test || true', 'functional: 0 steps', (wf) => {
    const step = steps(wf).find((s) => s.run === './Tests/functional/install-and-launch.sh');
    step.run = `${step.run} || true`;
  }],
  ['no write step', 'write: 0 steps', (wf) => { steps(wf).splice(findRun(wf, WRITE), 1); }],
  ['setup-node on another SHA', 'setup-node pin', (wf) => { setupNode(wf).uses = `actions/setup-node@${'0'.repeat(40)}`; }],
  ['setup-node on Node 18', 'setup-node version', (wf) => { setupNode(wf).with['node-version'] = 18; }],
  ['setup-node may be skipped', 'setup-node key if', (wf) => { setupNode(wf).if = 'false'; }],
  ['NODE_OPTIONS on the job', 'build-test env', (wf) => { wf.jobs['build-test'].env = { NODE_OPTIONS: '--import=x' }; }],
  ...[['the same name', steps(wf0()).at(-1).uses, 'Ductura-macOS'], ['a name with a trailing space', steps(wf0()).at(-1).uses, 'Ductura-macOS '],
    ['an expression for the name', steps(wf0()).at(-1).uses, "${{ 'Ductura-macOS' }}"], ['the merge sub-action', `actions/upload-artifact/merge@${'0'.repeat(40)}`, 'Ductura-macOS'],
  ].map(([what, uses, name]) => [`another job uploads with ${what}`, 'late uploads an artifact', (wf) => {
    wf.jobs.late = { 'runs-on': 'ubuntu-latest', needs: 'build-test', steps: [{ uses, with: { name, path: 'x', overwrite: true } }] };
  }]),
  ['another job uploads with another letter case', 'late uploads an artifact', (wf) => {
    wf.jobs.late = { 'runs-on': 'u', steps: [{ uses: steps(wf).at(-1).uses.replace('actions/upload-artifact', 'Actions/Upload-Artifact'), with: { name: 'x' } }] };
  }],
  ['a local reusable workflow', 'late uses a local action', (wf) => { wf.jobs.late = { uses: './.github/workflows/up.yml' }; }],
  ['a local composite action', 'late uses a local action', (wf) => { wf.jobs.late = { 'runs-on': 'u', steps: [{ uses: './.github/actions/up' }] }; }],
  ['the merge sub-action instead of the upload', 'upload action', (wf) => {
    const step = steps(wf).at(-1);
    step.uses = step.uses.replace('actions/upload-artifact@', 'actions/upload-artifact/merge@');
  }],
  ['a second upload in build-test', 'upload: 2 steps', (wf) => {
    steps(wf).push({ uses: `actions/upload-artifact/merge@${'0'.repeat(40)}`, with: { name: 'Ductura-macOS' } });
  }],
  ['env on ci-ok-test', 'ci-ok-test job key env', (wf) => { wf.jobs['ci-ok-test'].env = { NODE_OPTIONS: '--import=x' }; }],
  ['defaults on ci-ok-test', 'ci-ok-test job key defaults', (wf) => { wf.jobs['ci-ok-test'].defaults = { run: { shell: 'true {0}' } }; }],
  ...['build-test', 'ci-ok-test'].flatMap((job) => ['continue-on-error', 'if'].map((k) => [
    `${k} on the ${job} job`, `${job} job key ${k}`, (wf) => { wf.jobs[job][k] = k === 'if' ? 'false' : true; }])),
  ['a second write after the functional test', 'hash steps: 3', (wf) => {
    steps(wf).splice(findRun(wf, VERIFY), 0, { run: 'node  scripts/package-sha256.mjs' });
  }],
  ['functional test with continue-on-error', 'functional key continue-on-error', (wf) => {
    steps(wf).find((s) => s.run === './Tests/functional/install-and-launch.sh')['continue-on-error'] = true;
  }],
  ['defaults on the workflow', 'workflow defaults', (wf) => { wf.defaults = { run: { shell: 'sh' } }; }],
  ['tests not run in ci-ok-test', 'ci-ok-test', (wf) => { wf.jobs['ci-ok-test'].steps = []; }],
  ...['if', 'continue-on-error', 'shell'].map((k) => [`ci-ok-test step with ${k}`, `ci-ok-test key ${k}`, (wf) => {
    wf.jobs['ci-ok-test'].steps.find((s) => s.run === 'node --test scripts/package-sha256.test.mjs')[k] = k === 'shell' ? 'sh -c "true" {0}' : false;
  }]),
];
for (const [name, problem, mutate] of MUTATIONS) {
  test(`CI check fails: ${name}`, () => {
    const wf = ci();
    mutate(wf);
    assert.ok(ciProblems(wf).includes(problem), ciProblems(wf).join('; '));
  });
}
