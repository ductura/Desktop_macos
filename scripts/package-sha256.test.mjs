// --verify of the macOS package SHA-256 (DAN-1075, part 1075-3a).
// Run with node --test scripts/package-sha256.test.mjs from the repository root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { closeSync, constants, mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
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

// Review c.6968945689 (#17): each file is opened once and every read goes
// through that checked descriptor. A preload wraps fs.openSync (the script must
// open through it); right after it opens the target (inode taken with lstat
// when the preload loads) it renames the replacement over the path once. The
// answer must come from the file that was opened, so a script that opens or
// reads the path a second time, before or after the check, flips it.
const SWAPS = [
  ['the untouched package', 'package', BYTES, GOOD, flipped(), 0],
  ['a changed package', 'package', flipped(), GOOD, BYTES, 1],
  ['a .sha256 with the right hash', 'sidecar', BYTES, GOOD, OTHER, 0],
  ['a .sha256 with another hash', 'sidecar', BYTES, OTHER, GOOD, 1],
];
for (const [what, target, bytes, line, replacement, code] of SWAPS) {
  test(`--verify reads ${what} through the checked descriptor when the path is swapped (exit ${code})`, within((dir) => {
    const path = target === 'package' ? pkg(dir) : sidecar(dir);
    const next = join(dir, 'next');
    writeFileSync(next, replacement);
    const preload = join(dir, 'swap.mjs');
    writeFileSync(preload, `import fs from 'node:fs';\nimport { syncBuiltinESMExports } from 'node:module';\n`
      + `const path = ${JSON.stringify(path)}, ino = fs.lstatSync(path).ino, o = fs.openSync, f = fs.fstatSync;\nlet done = false;\n`
      + `fs.openSync = (...a) => { const fd = o(...a); if (!done && f(fd).ino === ino) { done = true; fs.renameSync(${JSON.stringify(next)}, path); } return fd; };\n`
      + 'syncBuiltinESMExports();\n');
    const r = run(dir, ['--verify'], ['--import', pathToFileURL(preload).href]);
    assert.equal(r.code, code, r.out);
    assert.ok(readFileSync(path).equals(Buffer.from(replacement)), 'the swap happened');
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
  ['binary mode marker', `${SHA} *${NAME}\n`], ['two tabs', `${SHA}\t\t${NAME}\n`],
  ['tab and space', `${SHA}\t ${NAME}\n`], ['space and tab', `${SHA} \t${NAME}\n`], ['one NBSP', `${SHA}\u00a0${NAME}\n`],
  ['two LF as separator', `${SHA}\n\n${NAME}\n`], ['CR instead of LF', `${SHA}  ${NAME}\r`],
  ['DEL instead of LF', `${SHA}  ${NAME}\u007f`], ['NUL instead of LF', `${SHA}  ${NAME}\0`], ['space instead of LF', `${SHA}  ${NAME} `],
];
// Rows of another length stop at the size check, rows of 84 bytes at the line
// pattern; each asserts its own message, so neither check stands in for the other.
const SIZE = /not one line of 84 bytes/, PATTERN = /is not "<64 lowercase hex>  Ductura-macOS\.dmg"/;
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

// The tests run in CI: ci-ok-test has exactly one step running them, with only
// a name and the command (no if, continue-on-error or shell to quiet it).
test('ci-ok-test runs these tests in one plain step', () => {
  const steps = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8')).jobs['ci-ok-test'].steps;
  const ours = steps.filter((s) => JSON.stringify(s).includes('package-sha256'));
  assert.equal(ours.length, 1);
  assert.deepEqual(Object.keys(ours[0]).sort(), ['name', 'run']);
  assert.equal(ours[0].run, 'node --test scripts/package-sha256.test.mjs');
});
