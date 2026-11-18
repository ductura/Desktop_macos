// Swift contract client from the locked @ductura/contracts OpenAPI (DAN-959).
//   node scripts/contracts.mjs --write   regenerate SWIFT_FILE
//   node scripts/contracts.mjs --check   exit 0 equal, 1 differs, 2 tarball not usable
// The generator supports only what it needs and throws on everything else.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

export const SWIFT_FILE = 'Sources/DucturaCore/Contracts.generated.swift';
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const isObj = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
function fail(message) { throw new Error(message); }
function onlyKeys(o, allowed, where) {
  if (!isObj(o)) fail(`${where}: not an object`);
  for (const k of Object.keys(o)) if (!allowed.includes(k)) fail(`${where}: unsupported key ${JSON.stringify(k)}`);
}

export function parseLock(lock) {
  const keys = ['version', 'url', 'sha256', 'operations'];
  onlyKeys(lock, keys, 'lock');
  for (const k of keys) if (!own(lock, k)) fail(`lock: missing ${k}`);
  const { version, url, sha256, operations } = lock;
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) fail('lock: bad version');
  const want = `/ductura/Institution_server/releases/download/contracts-v${version}/ductura-contracts-${version}.tgz`;
  if (url !== `https://github.com${want}`) fail('lock: url is not the release tarball of version');
  if (!/^[0-9a-f]{64}$/.test(sha256)) fail('lock: sha256 must be 64 lowercase hex');
  if (!Array.isArray(operations) || operations.length === 0 || new Set(operations).size !== operations.length) {
    fail('lock: operations must be a non-empty list without duplicates');
  }
  return lock;
}

// Reads a .tgz in memory; every entry must be a regular file with a unique name.
export function readTar(tgz) {
  const tar = gunzipSync(tgz);
  const files = new Map();
  for (let at = 0; at + 512 <= tar.length; ) {
    const h = tar.subarray(at, at + 512);
    if (h.every((b) => b === 0)) return files;
    const field = (from, len) => h.subarray(from, from + len).toString('utf8').replace(/\0.*$/s, '');
    const prefix = field(345, 155);
    const name = prefix ? `${prefix}/${field(0, 100)}` : field(0, 100);
    const size = field(124, 12).trim();
    if (!['0', '\0'].includes(String.fromCharCode(h[156]))) fail(`tar: ${name} is not a regular file`);
    if (!/^[0-7]+$/.test(size) || files.has(name)) fail(`tar: bad or duplicate entry ${name}`);
    const end = at + 512 + parseInt(size, 8);
    if (end > tar.length) fail(`tar: ${name} is truncated`);
    files.set(name, tar.subarray(at + 512, end));
    at += 512 + Math.ceil((end - at - 512) / 512) * 512;
  }
  fail('tar: no end marker');
}

export function openapiFromTarball(tgz, lock) {
  const files = readTar(tgz);
  const pkg = JSON.parse(files.get('package/package.json') ?? fail('tar: no package.json'));
  if (pkg.name !== '@ductura/contracts' || pkg.version !== lock.version) fail('tar: package is not the locked version');
  return JSON.parse(files.get('package/openapi/v1.json') ?? fail('tar: no openapi/v1.json'));
}

const KEYWORDS = new Set(('associatedtype class deinit enum extension fileprivate func import init inout internal let open operator ' +
  'private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default ' +
  'defer do else fallthrough for guard if in repeat return throw switch where while as false is nil self super throws true try ' +
  'any some await async').split(' '));
const swiftName = (n) => (/^[a-z][A-Za-z0-9]*$/.test(n) && !KEYWORDS.has(n) ? n : fail(`unsupported name ${JSON.stringify(n)}`));

function isString(s, where) {
  onlyKeys(s, ['type', 'const', 'pattern', 'description', 'anyOf'], where);
  if (own(s, 'anyOf')) {
    if (own(s, 'type') && s.type !== 'string') fail(`${where}: not a string`);
    if (!Array.isArray(s.anyOf) || s.anyOf.length === 0) fail(`${where}: bad anyOf`);
    s.anyOf.forEach((a, i) => { onlyKeys(a, ['type', 'const'], `${where}.anyOf[${i}]`); if (a.type !== 'string' || typeof a.const !== 'string') fail(`${where}: anyOf of string constants only`); });
  } else if (s.type !== 'string') fail(`${where}: not a string`);
}

function structFields(schema, where) {
  onlyKeys(schema, ['type', 'additionalProperties', 'required', 'properties', 'description'], where);
  if (schema.type !== 'object' || schema.additionalProperties !== false || !isObj(schema.properties)) fail(`${where}: closed object only`);
  const required = schema.required ?? [];
  for (const r of required) if (!own(schema.properties, r)) fail(`${where}: required ${r} is not a property`);
  return Object.entries(schema.properties).map(([name, s]) => {
    isString(s, `${where}.${name}`);
    return `    public let ${swiftName(name)}: String${required.includes(name) ? '' : '?'}`;
  });
}

export function generateSwift(spec, lock) {
  const ops = new Map();
  for (const [path, item] of Object.entries(spec.paths ?? {})) {
    for (const [method, o] of Object.entries(item)) {
      if (ops.has(o.operationId)) fail(`duplicate operationId ${o.operationId}`);
      ops.set(o.operationId, { path, method, o });
    }
  }
  const parts = [`// Generated by scripts/contracts.mjs from @ductura/contracts ${lock.version} (API ${spec.info.version}).
// Tarball sha256 ${lock.sha256}.
// Do not edit: run node scripts/contracts.mjs --write.
import Foundation
`];
  for (const id of lock.operations) {
    const { path, method, o } = ops.get(id) ?? fail(`unknown operation ${id}`);
    if (!/^\/[a-z0-9/-]+$/.test(path)) fail(`${id}: unsupported path ${path}`);
    const type = id.split('.').map((p) => swiftName(p)[0].toUpperCase() + p.slice(1)).join('');
    const codes = Object.keys(o.responses ?? {});
    if (codes.length !== 1 || codes[0] !== '200') fail(`${id}: exactly one 200 response`);
    const content = o.responses['200'].content ?? {};
    if (Object.keys(content).join() !== 'application/json') fail(`${id}: application/json only`);
    parts.push(`
/// ${method.toUpperCase()} ${path} (${id})
public struct ${type}Response: Decodable, Equatable {
${structFields(content['application/json'].schema, id).join('\n')}
}

public enum ${type} {
    public static let method = "${method.toUpperCase()}"
    public static let relativePath = "${path.slice(1)}"

    public static func request(base: URL) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(relativePath))
        request.httpMethod = method
        return request
    }
}
`);
  }
  return parts.join('');
}

// { code, message }: 0 equal, 1 the committed file differs, 2 the tarball is not usable.
export async function check({ lock, download, committed }) {
  let tgz;
  try { tgz = await download(parseLock(lock).url); } catch (e) { return { code: 2, message: `download failed: ${e.message}` }; }
  if (createHash('sha256').update(tgz).digest('hex') !== lock.sha256) return { code: 2, message: 'sha256 mismatch' };
  let spec;
  try { spec = openapiFromTarball(tgz, lock); } catch (e) { return { code: 2, message: e.message }; }
  let want;
  try { want = Buffer.from(generateSwift(spec, lock)); } catch (e) { return { code: 1, message: `cannot generate: ${e.message}` }; }
  if (committed === null) return { code: 1, message: `${SWIFT_FILE} is missing` };
  if (Buffer.compare(want, committed) === 0) return { code: 0, message: 'ok' };
  const a = want.toString('latin1').split('\n');
  const b = committed.toString('latin1').split('\n');
  let line = 0;
  while (a[line] === b[line]) line += 1;
  return { code: 1, message: `${SWIFT_FILE} differs from line ${line + 1}; run node scripts/contracts.mjs --write` };
}

async function download(url) {
  const res = await fetch(url);
  if (res.status !== 200) throw new Error(`status ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const lock = parseLock(JSON.parse(readFileSync(`${root}contracts.lock.json`, 'utf8')));
  const file = `${root}${SWIFT_FILE}`;
  if (process.argv[2] === '--write') {
    const tgz = await download(lock.url);
    if (createHash('sha256').update(tgz).digest('hex') !== lock.sha256) fail('sha256 mismatch');
    writeFileSync(file, generateSwift(openapiFromTarball(tgz, lock), lock));
  } else if (process.argv[2] === '--check') {
    const r = await check({ lock, download, committed: existsSync(file) ? readFileSync(file) : null });
    console[r.code === 0 ? 'log' : 'error'](`contracts: ${r.message}`);
    process.exitCode = r.code;
  } else fail('usage: node scripts/contracts.mjs --write|--check');
}
