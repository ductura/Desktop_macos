// SHA-256 of the macOS package for the CI artifact (DAN-1075).
//   node scripts/package-sha256.mjs           write dist/Ductura-macOS.dmg.sha256
//   node scripts/package-sha256.mjs --verify  exit 0 equal, 1 differs, 2 not usable
// The file is one line in the `shasum -a 256` form, so `shasum -a 256 -c` also
// works in the unpacked artifact. Paths are relative to the working folder
// (the repository root in CI). Every error other than a different hash exits 2.
import { createHash } from 'node:crypto';
import { createReadStream, lstatSync, readFileSync, writeFileSync } from 'node:fs';

const NAME = 'Ductura-macOS.dmg';
const PACKAGE = `dist/${NAME}`;
const SIDECAR = `${PACKAGE}.sha256`;
const LINE = /^([0-9a-f]{64}) {2}Ductura-macOS\.dmg\n$/;
const LINE_BYTES = 64 + 2 + NAME.length + 1;

// Size of a regular file; a missing path, folder or symbolic link is refused.
function regularFileSize(path) {
  let stat;
  try {
    stat = lstatSync(path);
  } catch {
    throw new Error(`${path} is missing`);
  }
  if (!stat.isFile()) throw new Error(`${path} is not a regular file`);
  return stat.size;
}

async function packageHash() {
  if (regularFileSize(PACKAGE) === 0) throw new Error(`${PACKAGE} is empty`);
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(PACKAGE)) hash.update(chunk);
  return hash.digest('hex');
}

// The hash from the .sha256 file, which must be exactly `<hex>  <name>\n`.
function recordedHash() {
  if (regularFileSize(SIDECAR) !== LINE_BYTES) throw new Error(`${SIDECAR} is not one line of ${LINE_BYTES} bytes`);
  // latin1 maps each byte to one character; LINE accepts only ASCII.
  const match = LINE.exec(readFileSync(SIDECAR, 'latin1'));
  if (!match) throw new Error(`${SIDECAR} is not "<64 lowercase hex>  ${NAME}"`);
  return match[1];
}

async function main(args) {
  if (args.length === 0) {
    const sha = await packageHash();
    writeFileSync(SIDECAR, `${sha}  ${NAME}\n`);
    console.log(`${SIDECAR}: ${sha}`);
    return 0;
  }
  if (args.length !== 1 || args[0] !== '--verify') throw new Error('usage: package-sha256.mjs [--verify]');
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
