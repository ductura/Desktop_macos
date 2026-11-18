// SHA-256 of the macOS package for the CI artifact (DAN-1075, part 1075-3a).
//   node scripts/package-sha256.mjs --verify  exit 0 equal, 1 differs, 2 not usable
// dist/Ductura-macOS.dmg.sha256 is one line in the `shasum -a 256` form, so
// `shasum -a 256 -c` also works in the unpacked artifact. Paths are relative to
// the working folder (the repository root in CI). Writing the line is part
// 1075-3b; until then any other arguments, none included, exit 2. Every error
// other than a different hash exits 2.
import { createHash } from 'node:crypto';
import { closeSync, constants, createReadStream, fstatSync, openSync, readFileSync } from 'node:fs';

const NAME = 'Ductura-macOS.dmg';
const PACKAGE = `dist/${NAME}`;
const SIDECAR = `${PACKAGE}.sha256`;
const LINE = /^([0-9a-f]{64}) {2}Ductura-macOS\.dmg\n$/;
const LINE_BYTES = 64 + 2 + NAME.length + 1;
const { O_RDONLY, O_NOFOLLOW, O_NONBLOCK } = constants;

// Opens a path for reading once, never through a symbolic link (O_NOFOLLOW)
// and never waiting on a FIFO (O_NONBLOCK). The descriptor must be a regular
// file and `check` may refuse it; everything after goes through that
// descriptor, so the path cannot be swapped between the check and the use.
function use(path, check, work) {
  let fd;
  try {
    fd = openSync(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  } catch (error) {
    throw new Error(`${path}: ${error.code === 'ENOENT' ? 'missing' : error.code ?? error.message}`);
  }
  const close = () => closeSync(fd);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile()) throw new Error(`${path} is not a regular file`);
    check(stat);
  } catch (error) {
    close();
    throw error;
  }
  return work(fd, close);
}

function packageHash() {
  const refuseEmpty = (stat) => { if (stat.size === 0) throw new Error(`${PACKAGE} is empty`); };
  return use(PACKAGE, refuseEmpty, async (fd) => {
    const hash = createHash('sha256');
    // The stream closes the descriptor when it ends or fails.
    for await (const chunk of createReadStream(null, { fd, start: 0 })) hash.update(chunk);
    return hash.digest('hex');
  });
}

// The hash from the .sha256 file, which must be exactly `<hex>  <name>\n`.
function recordedHash() {
  const oneLine = (stat) => {
    if (stat.size !== LINE_BYTES) throw new Error(`${SIDECAR} is not one line of ${LINE_BYTES} bytes`);
  };
  return use(SIDECAR, oneLine, (fd, close) => {
    let text;
    try {
      // latin1 maps each byte to one character; LINE accepts only ASCII.
      text = readFileSync(fd, 'latin1');
    } finally {
      close();
    }
    const match = LINE.exec(text);
    if (!match) throw new Error(`${SIDECAR} is not "<64 lowercase hex>  ${NAME}"`);
    return match[1];
  });
}

async function main(args) {
  if (args.length !== 1 || args[0] !== '--verify') throw new Error('usage: package-sha256.mjs --verify');
  const want = recordedHash();
  const got = await packageHash();
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
