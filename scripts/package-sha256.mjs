// SHA-256 of the macOS package for the CI artifact (DAN-1075, parts 1075-3a and 3a-2).
//   node scripts/package-sha256.mjs --verify  exit 0 equal, 1 differs, 2 not usable
// dist/Ductura-macOS.dmg.sha256 is one line in the `shasum -a 256` form, so
// `shasum -a 256 -c` also works in the unpacked artifact. Paths are relative to
// the working folder (the repository root in CI). Writing the line is part
// 1075-3b; until then any other arguments, none included, exit 2. Every error
// other than a different hash exits 2.
import { createHash } from 'node:crypto';
import { closeSync, constants, fstatSync, openSync, readSync } from 'node:fs';

const NAME = 'Ductura-macOS.dmg';
const PACKAGE = `dist/${NAME}`;
const SIDECAR = `${PACKAGE}.sha256`;
const LINE = /^([0-9a-f]{64}) {2}Ductura-macOS\.dmg\n$/;
const LINE_BYTES = 64 + 2 + NAME.length + 1;
const { O_RDONLY, O_NOFOLLOW, O_NONBLOCK } = constants;

// Opens a path for reading once, never through a symbolic link (O_NOFOLLOW)
// and never waiting on a FIFO (O_NONBLOCK). The descriptor must be a regular
// file and `check` may refuse its size. `read` reads only through that
// descriptor, at most one byte past the checked size, and returns the bytes it
// took. Then a second fstat of the same descriptor, always taken, must show
// the same size, mtime and ctime to the nanosecond (bigint: a double loses
// nanoseconds), inode and device, and the bytes taken must be that size, so a
// file changed while it was read is refused. `settle` judges the bytes after
// that second fstat (an emptied package is "empty", which wins over "changed").
function use(path, check, read, settle = () => {}) {
  let fd;
  try {
    fd = openSync(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  } catch (error) {
    throw new Error(`${path}: ${error.code === 'ENOENT' ? 'missing' : error.code ?? error.message}`);
  }
  try {
    const before = fstatSync(fd, { bigint: true });
    if (!before.isFile()) throw new Error(`${path} is not a regular file`);
    const size = Number(before.size);
    check(size);
    const bytes = read(fd, size + 1);
    const after = fstatSync(fd, { bigint: true });
    settle(bytes);
    if (bytes !== size || ['size', 'mtimeNs', 'ctimeNs', 'ino', 'dev'].some((key) => after[key] !== before[key])) {
      throw new Error(`${path} changed while being read`);
    }
  } finally {
    closeSync(fd);
  }
}

// Reads from the start to EOF, or to `limit` bytes, in blocks of 64 KiB.
function readAll(fd, limit, take) {
  const buffer = Buffer.alloc(Math.min(limit, 65536));
  let bytes = 0;
  for (let n; bytes < limit && (n = readSync(fd, buffer, 0, Math.min(buffer.length, limit - bytes), bytes)) > 0; bytes += n) {
    take(buffer.subarray(0, n));
  }
  return bytes;
}

function packageHash() {
  const refuseEmpty = (size) => { if (size === 0) throw new Error(`${PACKAGE} is empty`); };
  const hash = createHash('sha256');
  // Emptied after the check: "empty", not the hash of no bytes.
  use(PACKAGE, refuseEmpty, (fd, limit) => readAll(fd, limit, (chunk) => hash.update(chunk)), refuseEmpty);
  return hash.digest('hex');
}

// The hash from the .sha256 file, which must be exactly `<hex>  <name>\n`.
// Like the package, it is read to EOF but at most one byte past the checked
// size, which oneLine fixed at the line, so growth is seen.
function recordedHash() {
  const oneLine = (size) => {
    if (size !== LINE_BYTES) throw new Error(`${SIDECAR} is not one line of ${LINE_BYTES} bytes`);
  };
  const chunks = [];
  use(SIDECAR, oneLine, (fd, limit) => readAll(fd, limit, (chunk) => chunks.push(Buffer.from(chunk))));
  // latin1 maps each byte to one character; LINE accepts only ASCII.
  const match = LINE.exec(Buffer.concat(chunks).toString('latin1'));
  if (!match) throw new Error(`${SIDECAR} is not "<64 lowercase hex>  ${NAME}"`);
  return match[1];
}

async function main(args) {
  if (args.length !== 1 || args[0] !== '--verify') throw new Error('usage: package-sha256.mjs --verify');
  const want = recordedHash();
  const got = packageHash();
  if (got !== want) {
    console.error(`${PACKAGE}: SHA-256 differs from ${SIDECAR} (${got}, recorded ${want})`);
    return 1;
  }
  console.log(`${PACKAGE}: SHA-256 matches ${SIDECAR}`);
  return 0;
}

main(process.argv.slice(2)).then(
  (code) => { process.exitCode = code; },
  (error) => { console.error(`package-sha256: ${error.message}`); process.exitCode = 2; },
);
