// --verify of the macOS package SHA-256 (DAN-1075, part 1075-3a).
// Run with node --test scripts/package-sha256.test.mjs from the repository root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { closeSync, constants, mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parse } from 'yaml';

const SCRIPT = fileURLToPath(new URL('package-sha256.mjs', import.meta.url));
const NAME = 'Ductura-macOS.dmg';
// NIST vector: one million 'a', written here and not computed by the script.
// Longer than three 64 KiB reads, so the first, middle and last byte below sit
// in different reads.
const BYTES = Buffer.alloc(1_000_000, 'a');
const SHA = 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0';
const GOOD = `${SHA}  ${NAME}\n`;
const OTHER = `${'0'.repeat(64)}  ${NAME}\n`;
const flipped = (at = 500_000) => { const b = Buffer.from(BYTES); b[at] ^= 0x01; return b; };

const pkg = (dir) => join(dir, 'dist', NAME);
const sidecar = (dir) => join(dir, 'dist', `${NAME}.sha256`);
// A fresh folder with the package and the .sha256 line the test writes itself.
function within(fn, bytes = BYTES, line = GOOD) {
  return () => {
    const dir = mkdtempSync(join(tmpdir(), 'pkg-sha-'));
    mkdirSync(join(dir, 'dist'));
    writeFileSync(pkg(dir), bytes);
    writeFileSync(sidecar(dir), line);
    try { fn(dir); } finally { rmSync(dir, { recursive: true, force: true }); }
  };
}
const run = (dir, args = ['--verify'], node = []) => {
  const r = spawnSync(process.execPath, [...node, SCRIPT, ...args], { cwd: dir, encoding: 'utf8', timeout: 20_000 });
  return { code: r.status, out: r.stdout + r.stderr };
};

for (const [where, at] of [['first', 0], ['middle', 500_000], ['last', 999_999]]) {
  test(`--verify exits 1 when the ${where} byte changed after the hash was written`, within((dir) => {
    writeFileSync(pkg(dir), flipped(at));
    const r = run(dir);
    assert.equal(r.code, 1, r.out);
    assert.match(r.out, /differs/);
  }));
}

for (const [what, bytes, code] of [['one byte shorter', BYTES.subarray(1), 1],
  ['one byte longer', Buffer.concat([BYTES, Buffer.of(0x61)]), 1], ['emptied', Buffer.alloc(0), 2]]) {
  test(`--verify exits ${code} when the package is ${what} after the hash was written`, within((dir) => {
    writeFileSync(pkg(dir), bytes);
    const r = run(dir);
    assert.equal(r.code, code, r.out);
    assert.match(r.out, code === 1 ? /differs/ : /empty/);
  }));
}

test('--verify exits 0 on the untouched package', within((dir) => {
  const r = run(dir);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /matches/);
}));

// The whole hash is compared: a recorded hash off in any one of its 64 hex
// digits fails, so comparing only some digits (the ends, a prefix) fails here.
test('--verify exits 1 when any one hex digit of the recorded hash differs', within((dir) => {
  for (let at = 0; at < 64; at++) {
    const line = `${SHA.slice(0, at)}${SHA[at] === '0' ? '1' : '0'}${SHA.slice(at + 1)}  ${NAME}\n`;
    writeFileSync(sidecar(dir), line);
    const r = run(dir);
    assert.equal(r.code, 1, `digit ${at}: ${r.out}`);
    assert.match(r.out, /differs/);
  }
}));

// Rows of another length stop at the size check, rows of 84 bytes at the line
// pattern; each asserts its own message, so neither check stands in for the other.
const SIZE = /not one line of 84 bytes/, PATTERN = /is not "<64 lowercase hex>  Ductura-macOS\.dmg"/;

// Review c.6968945689 (#17): each file is opened once and every read goes
// through that checked descriptor. A preload wraps fs.openSync (the script must
// open through it); right after it opens the target (inode taken with lstat
// when the preload loads) it renames the replacement over the path once. The
// answer must come from the file that was opened, so a script that opens or
// reads the path a second time, in either order, before or after the check,
// flips it. The last three rows open a file that fails the check and swap in
// one that passes, so the check must also fall on the file that is read.
const SWAPS = [
  ['the untouched package', 'package', BYTES, GOOD, flipped(), 0, /matches/],
  ['a changed package', 'package', flipped(), GOOD, BYTES, 1, /differs/],
  ['a .sha256 with the right hash', 'sidecar', BYTES, GOOD, OTHER, 0, /matches/],
  ['a .sha256 with another hash', 'sidecar', BYTES, OTHER, GOOD, 1, /differs/],
  ['an empty package', 'package', Buffer.alloc(0), GOOD, BYTES, 2, /is empty/],
  ['an 85-byte .sha256', 'sidecar', BYTES, `${GOOD} `, GOOD, 2, SIZE],
  ['an 84-byte .sha256 in capitals', 'sidecar', BYTES, `${SHA.toUpperCase()}  ${NAME}\n`, GOOD, 2, PATTERN],
];
const preloaded = (dir, path, hook, action) => {
  const preload = join(dir, 'hook.mjs');
  writeFileSync(preload, `import fs from 'node:fs';\nimport { syncBuiltinESMExports } from 'node:module';\n`
    + `const path = ${JSON.stringify(path)}, ino = fs.lstatSync(path).ino, h = fs.${hook}, f = fs.fstatSync;\nlet done = false;\n`
    + `fs.${hook} = (...a) => { const r = h(...a), fd = typeof r === 'number' ? r : a[0];\n`
    + `  if (!done && f(fd).ino === ino) { done = true; ${action} } return r; };\nsyncBuiltinESMExports();\n`);
  return run(dir, ['--verify'], ['--import', pathToFileURL(preload).href]);
};
for (const [what, target, bytes, line, replacement, code, message] of SWAPS) {
  test(`--verify reads ${what} through the checked descriptor when the path is swapped (exit ${code})`, within((dir) => {
    const path = target === 'package' ? pkg(dir) : sidecar(dir);
    const next = join(dir, 'next');
    writeFileSync(next, replacement);
    const r = preloaded(dir, path, 'openSync', `fs.renameSync(${JSON.stringify(next)}, path);`);
    assert.equal(r.code, code, r.out);
    assert.match(r.out, message);
    assert.ok(readFileSync(path).equals(Buffer.from(replacement)), 'the swap happened');
  }, bytes, line));
}

// A file that changes while it is read is not usable (2), whatever it now
// hashes to (reviews c.6970912826 and c.6971110273, QA c.6971128595 on #19).
// A preload wraps fstatSync and readSync and, on the target's descriptor
// (matched by inode), changes the file once at one phase of the read: right
// after the first fstat, after the first block, after the block that reaches
// the checked size (before EOF), or after EOF (before the second fstat). The
// script must notice by a second fstat of the same descriptor. Each row checks
// that the change happened.
const CHANGED = /changed while being read/;
const phased = (dir, path, phase, action) => {
  const preload = join(dir, 'phase.mjs');
  writeFileSync(preload, `import fs from 'node:fs';\nimport { syncBuiltinESMExports } from 'node:module';\n`
    + `const path = ${JSON.stringify(path)}, phase = ${JSON.stringify(phase)}, f = fs.fstatSync, rs = fs.readSync;\n`
    + `const { ino, size } = fs.lstatSync(path); let stats = 0, reads = 0, total = 0, done = false;\n`
    + `const fire = () => { if (!done) { done = true; ${action} } };\n`
    + `fs.fstatSync = (fd, ...a) => { const s = f(fd, ...a); if (s.ino === ino && ++stats === 1 && phase === 'check') fire(); return s; };\n`
    + `fs.readSync = (fd, ...a) => { const n = rs(fd, ...a); if (f(fd).ino === ino) { reads++; total += n;\n`
    + `  if ((phase === 'first' && reads === 1) || (phase === 'last' && n > 0 && total === size) || (phase === 'eof' && n === 0)) fire(); }\n`
    + `  return n; };\nsyncBuiltinESMExports();\n`);
  const ctime = statSync(path, { bigint: true }).ctimeNs;
  const r = run(dir, ['--verify'], ['--import', pathToFileURL(preload).href]);
  // Precondition: the clock moved ctime, so a row cannot pass on a change the
  // file system did not record.
  assert.notEqual(statSync(path, { bigint: true }).ctimeNs, ctime, 'ctime moved');
  return r;
};

// Reads come back short (7 bytes at most each): the script still reads both
// files whole and exits 0, so a single read that assumes a full block fails.
test('--verify reads to EOF when every read returns at most 7 bytes (exit 0)', within((dir) => {
  const preload = join(dir, 'short.mjs');
  writeFileSync(preload, "import fs from 'node:fs';\nimport { syncBuiltinESMExports } from 'node:module';\n"
    + 'const rs = fs.readSync;\nfs.readSync = (fd, b, o, l, p) => rs(fd, b, o, Math.min(l, 7), p);\nsyncBuiltinESMExports();\n');
  const r = run(dir, ['--verify'], ['--import', pathToFileURL(preload).href]);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /matches/);
}));
// Hashes of the content after each change, from sha256sum, not from the script:
// with them a script that checks the size only when the hash differs exits 0.
const PACKAGE_CHANGES = [
  ['cut to 500 000 bytes', 'fs.truncateSync(path, 500000);', '0071c4a7e7200b572501284e9a46954580950d9a73d401869236e87ed2ce99f8',
    (b) => b.equals(BYTES.subarray(0, 500_000))],
  ['one byte longer', "fs.appendFileSync(path, 'a');", '9710f0882e9694259bf237c37b53b170f63b30b2addce6d498107ab6e4f9c3a5',
    (b) => b.equals(Buffer.alloc(1_000_001, 'a'))],
  ['one byte changed in place', "const w = fs.openSync(path, 'r+'); fs.writeSync(w, Buffer.of(0x60), 0, 1, 500000); fs.closeSync(w);",
    '515540187c193943f294dffe6368d2be62d0a4dd7f83e51c69f0e0d8668b83d1', (b) => b.equals(flipped())],
  // utimes puts back the whole-second mtime the test set; only ctime still shows the change.
  ['one byte changed in place with its mtime put back', "const w = fs.openSync(path, 'r+');\n"
    + 'fs.writeSync(w, Buffer.of(0x60), 0, 1, 500000); fs.closeSync(w); fs.utimesSync(path, 1e9, 1e9);',
    '515540187c193943f294dffe6368d2be62d0a4dd7f83e51c69f0e0d8668b83d1', (b) => b.equals(flipped())],
];
for (const phase of ['check', 'first', 'last', 'eof']) {
  for (const [what, action, hash, changed] of PACKAGE_CHANGES) {
    test(`--verify exits 2 when the package is ${what} at phase ${phase}`, within((dir) => {
      utimesSync(pkg(dir), 1e9, 1e9); // a whole second, so a row can put it back exactly
      const r = phased(dir, pkg(dir), phase, action);
      assert.equal(r.code, 2, r.out);
      assert.match(r.out, CHANGED);
      assert.ok(changed(readFileSync(pkg(dir))), 'the change happened');
    }, BYTES, `${hash}  ${NAME}\n`));
  }
}

// Emptied before the first read, next to the hash of no bytes: "empty", not 0.
test('--verify exits 2 when the package is emptied after the check', within((dir) => {
  const r = phased(dir, pkg(dir), 'check', 'fs.truncateSync(path, 0);');
  assert.equal(r.code, 2, r.out);
  assert.match(r.out, /is empty/);
  assert.equal(statSync(pkg(dir)).size, 0, 'the change happened');
}, BYTES, `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ${NAME}\n`));

// The .sha256 is read in a loop to EOF (at most 85 bytes) and checked again
// with fstat: a line added or rewritten between reads, or after EOF, is seen.
const SIDECAR_CHANGES = [
  ['grows after the check', 'check', `fs.appendFileSync(path, ${JSON.stringify(GOOD)});`, GOOD + GOOD],
  ['is emptied after the check', 'check', 'fs.truncateSync(path, 0);', ''],
  ['grows after the first read', 'first', `fs.appendFileSync(path, ${JSON.stringify(GOOD)});`, GOOD + GOOD],
  ['is rewritten in place after the first read', 'first', `fs.writeFileSync(path, ${JSON.stringify(OTHER)});`, OTHER],
  ['is rewritten with its mtime put back after the first read', 'first',
    `fs.writeFileSync(path, ${JSON.stringify(OTHER)}); fs.utimesSync(path, 1e9, 1e9);`, OTHER],
  ['grows after EOF', 'eof', `fs.appendFileSync(path, ${JSON.stringify(GOOD)});`, GOOD + GOOD],
];
for (const [what, phase, action, after] of SIDECAR_CHANGES) {
  test(`--verify exits 2 when the .sha256 ${what}`, within((dir) => {
    utimesSync(sidecar(dir), 1e9, 1e9);
    const r = phased(dir, sidecar(dir), phase, action);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, CHANGED);
    assert.equal(readFileSync(sidecar(dir), 'utf8'), after, 'the change happened');
  }));
}

// Each file is reached by path exactly once, by one openSync, whatever the
// exit. A preload wraps every public function of node:fs and node:fs/promises
// (constructors aside) and logs each call with an argument that names the
// package or the .sha256: a string, a URL or URL-like object (resolved with
// fileURLToPath, as fs resolves it), a Buffer or any other ArrayBufferView,
// matched by device and inode (lstat and stat), so another spelling of the
// same path (/proc/self/cwd/..., /proc/self/fd/N) counts too. Calls that bypass
// the public fs module, or reach the files only through their folder (cpSync,
// globSync on dist/) or from a worker thread or child process, are left to
// review.
const COUNTS = [
  ['the untouched package', BYTES, GOOD, 0, ['package openSync', 'sha256 openSync']],
  ['a changed package', flipped(), GOOD, 1, ['package openSync', 'sha256 openSync']],
  ['an 84-byte .sha256 in capitals', BYTES, `${SHA.toUpperCase()}  ${NAME}\n`, 2, ['sha256 openSync']],
  ['an empty package', Buffer.alloc(0), GOOD, 2, ['package openSync', 'sha256 openSync']],
];
for (const [what, bytes, line, code, calls] of COUNTS) {
  test(`--verify reaches each file by path once, with openSync, for ${what} (exit ${code})`, within((dir) => {
    const preload = join(dir, 'count.mjs'), log = join(dir, 'calls.log');
    writeFileSync(log, '');
    writeFileSync(preload, `import fs from 'node:fs';\nimport { fileURLToPath } from 'node:url';\nimport { syncBuiltinESMExports } from 'node:module';\n`
      + `const append = fs.appendFileSync, lstat = fs.lstatSync, log = ${JSON.stringify(log)};\n`
      + `const stat = fs.statSync, ids = (p) => [lstat, stat].map((f) => { const s = f(p, { throwIfNoEntry: false }); return s && s.dev + ':' + s.ino; });\n`
      + `const files = { [ids(${JSON.stringify(pkg(dir))})[0]]: 'package', [ids(${JSON.stringify(sidecar(dir))})[0]]: 'sha256' };\n`
      + `const named = (x) => { try { const p = ArrayBuffer.isView(x) ? Buffer.from(x.buffer, x.byteOffset, x.byteLength)\n`
      + `  : x !== null && typeof x === 'object' && x.href ? fileURLToPath(x) : typeof x === 'string' ? x : null;\n`
      + `  return p !== null && ids(p).map((i) => files[i]).find(Boolean); } catch { return undefined; } };\n`
      + `for (const [where, mod] of [['', fs], ['promises.', fs.promises]]) for (const k of Object.keys(mod)) {\n`
      + `  const f = mod[k]; if (typeof f !== 'function' || /^[A-Z]/.test(k)) continue;\n`
      + `  mod[k] = function (...a) { for (const x of a) { const n = named(x); if (n) append(log, n + ' ' + where + k + '\\n'); }\n`
      + `    return f.apply(this, a); }; }\nsyncBuiltinESMExports();\n`);
    const r = run(dir, ['--verify'], ['--import', pathToFileURL(preload).href]);
    assert.equal(r.code, code, r.out);
    assert.deepEqual(readFileSync(log, 'utf8').trim().split('\n').sort(), calls);
  }, bytes, line));
}

// Every .sha256 that is not exactly `<64 lowercase hex>  Ductura-macOS.dmg\n`.
const BAD_LINES = [
  ['CRLF', `${SHA}  ${NAME}\r\n`], ['no final LF', `${SHA}  ${NAME}`], ['two lines', GOOD + GOOD],
  ['empty', ''], ['only LF', '\n'], ['tab', `${SHA}\t${NAME}\n`], ['one space', `${SHA} ${NAME}\n`],
  ['three spaces', `${SHA}   ${NAME}\n`], ['two NBSP', `${SHA}\u00a0\u00a0${NAME}\n`], ['DEL at the end', `${SHA}  ${NAME}\u007f\n`],
  ['BOM', `\ufeff${GOOD}`], ['63 hex', GOOD.slice(1)],
  ['65 hex', `0${GOOD}`], ['other name', `${SHA}  Ductura-macOS.dmg.old\n`],
  ['name with a path', `${SHA}  dist/${NAME}\n`], ['name with a Windows path', `${SHA}  dist\\${NAME}\n`],
  ['space after the name', `${SHA}  ${NAME} \n`], ['leading space', ` ${GOOD}`], ['NUL', `${SHA}  ${NAME}\0\n`],
  ['empty line after the line', `${GOOD}\n`], ['longer than 84 bytes', GOOD + ' '.repeat(1000)],
  // Exactly 84 bytes, so these pass the size check and reach the line pattern.
  ['non-hex letter', `${SHA.slice(0, 63)}g  ${NAME}\n`], ['uppercase hex', `${SHA.toUpperCase()}  ${NAME}\n`],
  ['binary mode marker', `${SHA} *${NAME}\n`], ['other extension', `${SHA}  Ductura-macOS.zip\n`],
  ['other letter in the name', `${SHA}  Ductura-macOX.dmg\n`], ['lowercase name', `${SHA}  ductura-macOS.dmg\n`],
  ['other character for the dot', `${SHA}  Ductura-macOS-dmg\n`], ['underscore for the hyphen', `${SHA}  Ductura_macOS.dmg\n`], ['two tabs', `${SHA}\t\t${NAME}\n`],
  ['tab and space', `${SHA}\t ${NAME}\n`], ['space and tab', `${SHA} \t${NAME}\n`], ['one NBSP', `${SHA}\u00a0${NAME}\n`],
  ['two LF as separator', `${SHA}\n\n${NAME}\n`], ['CR instead of LF', `${SHA}  ${NAME}\r`],
  ['DEL instead of LF', `${SHA}  ${NAME}\u007f`], ['NUL instead of LF', `${SHA}  ${NAME}\0`], ['space instead of LF', `${SHA}  ${NAME} `],
];
const EXACT = BAD_LINES.findIndex(([name]) => name === 'non-hex letter');
BAD_LINES.forEach(([name, line], i) => {
  test(`--verify refuses a .sha256 line (exit 2): ${name}`, within((dir) => {
    assert.notEqual(line, GOOD);
    assert.equal(Buffer.byteLength(line) === 84, i >= EXACT);
    const r = run(dir);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, i >= EXACT ? PATTERN : SIZE);
  }, BYTES, line));
});

// The good line with the high bit set on one byte: a decoding that drops that
// bit would read it back as the good line.
for (const at of [0, SHA.indexOf('0'), 64, GOOD.indexOf('.'), 83]) {
  const line = Buffer.from(GOOD);
  line[at] |= 0x80;
  test(`--verify refuses a high-bit byte at offset ${at} (exit 2)`, within((dir) => {
    const r = run(dir);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, PATTERN);
  }, BYTES, line));
}

// Not a usable file: missing, a folder, a symbolic link to a good file, or a
// FIFO with no other end, a writer or a reader held by the test (never a wait).
// Each row asserts its own message: without the regular-file check a folder or
// FIFO would still exit 2, only for another reason (size, EISDIR, EAGAIN).
const NOT_FILE = /is not a regular file/;
const NOT_FILES = [
  ['missing', /: missing/, (path) => rmSync(path)],
  ['a folder', NOT_FILE, (path) => { rmSync(path); mkdirSync(path); }],
  ['a symbolic link to a good file', /: ELOOP/, (path) => { writeFileSync(`${path}.good`, readFileSync(path)); rmSync(path); symlinkSync(`${path}.good`, path); }],
  ...[['no other end', null], ['a writer', constants.O_RDWR], ['a reader', constants.O_RDONLY | constants.O_NONBLOCK]]
    .map(([peer, flags]) => [`a FIFO with ${peer}`, NOT_FILE, (path) => {
      rmSync(path);
      assert.equal(spawnSync('mkfifo', [path]).status, 0);
      return flags === null ? null : openSync(path, flags);
    }]),
];
for (const [file, at] of [['package', pkg], ['.sha256', sidecar]]) {
  for (const [what, message, make] of NOT_FILES) {
    test(`--verify exits 2 when the ${file} is ${what}`, within((dir) => {
      const held = make(at(dir));
      try {
        const r = run(dir);
        assert.equal(r.code, 2, r.out);
        assert.match(r.out, message);
      } finally {
        if (held) closeSync(held);
      }
    }));
  }
}

for (const args of [[], ['--Verify'], ['--verify', 'extra'], ['--verify', '--verify'], [''], ['dist/Ductura-macOS.dmg']]) {
  test(`exits 2 with usage for arguments ${JSON.stringify(args)}`, within((dir) => {
    const r = run(dir, args);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, /usage/);
  }));
}

// The tests run in CI and nothing quiets them: ci-ok-test has exactly one step
// running them, with only a name and the command; the workflow, the job and its
// steps carry no keys that could skip, soften or reconfigure them (env,
// defaults, if, continue-on-error, shell), and no step writes GITHUB_ENV or
// GITHUB_PATH or sets NODE_OPTIONS (by literal text: an obfuscated name such
// as "NODE_""OPTIONS" is left to review). Each change to a copy must be caught.
const WORKFLOW = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const extra = (keys, allowed) => Object.keys(keys ?? {}).filter((k) => !allowed.includes(k));
function ciProblems(wf) {
  const job = wf.jobs?.['ci-ok-test'] ?? {};
  const steps = Array.isArray(job.steps) ? job.steps : [];
  const ours = steps.filter((s) => JSON.stringify(s).includes('package-sha256'));
  return [
    ...extra(wf, ['name', 'on', 'permissions', 'jobs']).map((k) => `workflow key ${k}`),
    ...extra(job, ['runs-on', 'timeout-minutes', 'permissions', 'steps']).map((k) => `job key ${k}`),
    ...steps.flatMap((s) => extra(s, ['name', 'uses', 'with', 'run']).map((k) => `step key ${k}`)),
    ...['GITHUB_ENV', 'GITHUB_PATH', 'NODE_OPTIONS'].flatMap((name) => steps
      .filter((s) => JSON.stringify(s).includes(name)).map(() => `step names ${name}`)),
    ...(ours.length === 1 && extra(ours[0], ['name', 'run']).length === 0
      && ours[0].run === 'node --test scripts/package-sha256.test.mjs' ? [] : ['not one plain test step']),
  ];
}
test('ci-ok-test runs these tests in one plain step that nothing quiets', () => assert.deepEqual(ciProblems(WORKFLOW), []));
const OURS = (wf) => wf.jobs['ci-ok-test'].steps.find((s) => s.run === 'node --test scripts/package-sha256.test.mjs');
const SKIP = { NODE_OPTIONS: '--test-skip-pattern=.' };
for (const [what, change, problem] of [
  ['workflow env', (wf) => { wf.env = SKIP; }, 'workflow key env'],
  ['workflow defaults', (wf) => { wf.defaults = { run: { shell: 'bash' } }; }, 'workflow key defaults'],
  ['job env', (wf) => { wf.jobs['ci-ok-test'].env = SKIP; }, 'job key env'],
  ['job defaults', (wf) => { wf.jobs['ci-ok-test'].defaults = { run: { shell: 'true {0}' } }; }, 'job key defaults'],
  ['job continue-on-error', (wf) => { wf.jobs['ci-ok-test']['continue-on-error'] = true; }, 'job key continue-on-error'],
  ['step env', (wf) => { OURS(wf).env = SKIP; }, 'step key env'],
  ['step if', (wf) => { OURS(wf).if = 'false'; }, 'step key if'],
  ['step shell', (wf) => { OURS(wf).shell = 'true {0}'; }, 'step key shell'],
  ['a step writing GITHUB_ENV', (wf) => { wf.jobs['ci-ok-test'].steps.unshift({ run: 'echo "X=1" >> "$GITHUB_ENV"' }); }, 'step names GITHUB_ENV'],
  ['a step writing GITHUB_PATH', (wf) => { wf.jobs['ci-ok-test'].steps.unshift({ run: 'echo /tmp/bin >> "$GITHUB_PATH"' }); }, 'step names GITHUB_PATH'],
  ['a step setting NODE_OPTIONS', (wf) => { wf.jobs['ci-ok-test'].steps.unshift({ run: 'export NODE_OPTIONS=--test-skip-pattern=.' }); }, 'step names NODE_OPTIONS'],
  ['the step softened', (wf) => { OURS(wf).run += ' || true'; }, 'not one plain test step'],
  ['the step twice', (wf) => { wf.jobs['ci-ok-test'].steps.push({ ...OURS(wf) }); }, 'not one plain test step'],
  ['the step removed', (wf) => { wf.jobs['ci-ok-test'].steps = wf.jobs['ci-ok-test'].steps.filter((s) => s !== OURS(wf)); }, 'not one plain test step'],
]) {
  test(`the CI check catches ${what}`, () => {
    const wf = structuredClone(WORKFLOW);
    change(wf);
    assert.ok(ciProblems(wf).includes(problem), JSON.stringify(ciProblems(wf)));
  });
}
