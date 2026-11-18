// Contract client (DAN-959): the committed Swift must equal the generator's
// output over the locked @ductura/contracts tarball. No network: tarballs are
// built here and the download is an injected function.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { check, generateSwift, parseLock, readTar, SWIFT_FILE } from './contracts.mjs';

const sha = (b) => createHash('sha256').update(b).digest('hex');
const committedLock = JSON.parse(readFileSync(new URL('../contracts.lock.json', import.meta.url)));
const HEALTH = {
  additionalProperties: false, type: 'object', required: ['status'],
  properties: {
    status: { const: 'ok', type: 'string' },
    state: { anyOf: [{ const: 'ok', type: 'string' }, { const: 'degraded', type: 'string' }] },
    minClientVersion: { pattern: '^(0|[1-9]\\d*)$', description: 'x', type: 'string' },
  },
};
const op = (schema, operationId = 'platform.health.get') => ({
  operationId, responses: { 200: { description: 'ok', content: { 'application/json': { schema } } } },
});
const spec = (schema = HEALTH, extra = {}) => ({ info: { version: '1.18.0' }, paths: { '/api/v1/health': { get: op(schema) }, ...extra } });
const lockFor = (sha256, version = '2.2.0') => ({
  version, sha256, operations: ['platform.health.get'],
  url: `https://github.com/ductura/Institution_server/releases/download/contracts-v${version}/ductura-contracts-${version}.tgz`,
});

// Minimal ustar writer: entries are { name, data, type } with type '0' by default.
function tgz(entries) {
  const blocks = [];
  for (const { name, data = '', type = '0' } of entries) {
    const body = Buffer.from(data);
    const h = Buffer.alloc(512);
    h.write(name, 0, 'utf8');
    h.write(body.length.toString(8).padStart(11, '0'), 124);
    h.write(type, 156);
    h.write('ustar\u000000', 257, 'latin1');
    blocks.push(h, body, Buffer.alloc((512 - (body.length % 512)) % 512));
  }
  return gzipSync(Buffer.concat([...blocks, Buffer.alloc(1024)]));
}
const pkg = (version = '2.2.0') => JSON.stringify({ name: '@ductura/contracts', version });
const tarball = (s = spec(), more = []) =>
  tgz([{ name: 'package/package.json', data: pkg() }, { name: 'package/openapi/v1.json', data: JSON.stringify(s) }, ...more]);
async function run(t, committed, lockOver = {}) {
  const lock = { ...lockFor(sha(t)), ...lockOver };
  return check({ lock, download: async () => t, committed });
}
const good = (s = spec(), t = tarball(s)) => Buffer.from(generateSwift(s, lockFor(sha(t))));

test('drift: any byte difference or a missing file fails with exit 1', async () => {
  const t = tarball();
  const ok = good(spec(), t);
  const s = ok.toString();
  const variants = {
    'one character': s.replace('status', 'statuz'), CRLF: s.replace(/\n/g, '\r\n'), BOM: `﻿${s}`,
    'no final newline': s.slice(0, -1), 'two final newlines': `${s}\n`,
  };
  for (const [name, text] of Object.entries(variants)) {
    const r = await run(t, Buffer.from(text));
    assert.equal(r.code, 1, name);
    assert.match(r.message, /differs from line \d+/, name);
  }
  assert.equal((await run(t, null)).code, 1, 'missing file');
  const changed = spec({ ...HEALTH, properties: { ...HEALTH.properties, extra: { type: 'string' } } });
  const t2 = tarball(changed);
  assert.equal((await run(t2, good(spec(), t2))).code, 1, 'changed schema, old file');
  assert.deepEqual(await run(t, ok), { code: 0, message: 'ok' });
});

test('locked tarball: wrong hash, download failure or a bad archive exit 2', async () => {
  const t = tarball();
  const ok = good(spec(), t);
  assert.match((await run(t, ok, { sha256: '0'.repeat(64) })).message, /sha256 mismatch/);
  for (const download of [async () => { throw new Error('reset'); }, async () => { throw new Error('status 404'); }]) {
    const r = await check({ lock: lockFor(sha(t)), download, committed: ok });
    assert.equal(r.code, 2);
    assert.match(r.message, /download failed/);
  }
  const bad = {
    symlink: tarball(spec(), [{ name: 'package/x', type: '2' }]),
    pax: tarball(spec(), [{ name: 'package/x', type: 'x' }]),
    duplicate: tarball(spec(), [{ name: 'package/openapi/v1.json', data: '{}' }]),
    'other version': tgz([{ name: 'package/package.json', data: pkg('2.1.1') }, { name: 'package/openapi/v1.json', data: JSON.stringify(spec()) }]),
    'no openapi': tgz([{ name: 'package/package.json', data: pkg() }]),
  };
  for (const [name, b] of Object.entries(bad)) assert.equal((await run(b, ok)).code, 2, name);
  assert.throws(() => readTar(Buffer.from('not gzip')));
});

test('lock: exact keys, exact release URL, lowercase sha256, operations', () => {
  const base = lockFor('a'.repeat(64));
  const url = base.url;
  const bad = [
    { ...base, extra: 1 }, { ...base, url: url.replace('https', 'http') }, { ...base, url: url.replace('github.com', 'evil.com') },
    { ...base, url: url.replace('download/', 'download/../') }, { ...base, url: `${url}?x=1` }, { ...base, version: '2.2.1' },
    { ...base, sha256: 'A'.repeat(64) }, { ...base, sha256: 'a'.repeat(63) }, { ...base, operations: [] },
    { ...base, operations: ['platform.health.get', 'platform.health.get'] }, { ...base, version: '2.2' },
    Object.assign(Object.create({ version: '2.2.0' }), { url, sha256: base.sha256, operations: base.operations }),
  ];
  for (const lock of bad) assert.throws(() => parseLock(lock), JSON.stringify(lock));
  assert.deepEqual(parseLock(base), base);
  assert.deepEqual(parseLock(committedLock), committedLock);
});

test('generator refuses every shape it does not support and writes nothing', () => {
  const props = (p) => spec({ ...HEALTH, properties: { ...HEALTH.properties, ...p } });
  const refused = {
    $ref: props({ x: { $ref: '#/x' } }), number: props({ x: { type: 'number' } }), 'type array': props({ x: { type: ['string', 'null'] } }),
    'nested object': props({ x: { type: 'object', properties: {} } }), 'anyOf non-const': props({ x: { anyOf: [{ type: 'string' }] } }),
    'open object': spec({ ...HEALTH, additionalProperties: true }), 'required unknown': spec({ ...HEALTH, required: ['status', 'nope'] }),
    'duplicate operationId': spec(HEALTH, { '/api/v1/other': { get: op(HEALTH) } }),
    'two responses': { ...spec(), paths: { '/api/v1/health': { get: { ...op(HEALTH), responses: { ...op(HEALTH).responses, 201: {} } } } } },
    'path parameter': { info: { version: '1.0.0' }, paths: { '/api/v1/{id}': { get: op(HEALTH) } } },
  };
  for (const name of ['a-b', 'class', 'Type', 'self', 'déjà', 'a b', 'a\r\nb', 'default', '_x', '1a']) {
    refused[`name ${JSON.stringify(name)}`] = props({ [name]: { type: 'string' } });
  }
  const lock = lockFor('a'.repeat(64));
  for (const [name, s] of Object.entries(refused)) assert.throws(() => generateSwift(s, lock), name);
  for (const id of ['toString', '__proto__', 'platform.other.get']) {
    assert.throws(() => generateSwift(spec(), { ...lock, operations: [id] }), id);
  }
});

test('health generates the expected Swift, deterministically', () => {
  const lock = lockFor('a'.repeat(64));
  const out = generateSwift(spec(), lock);
  assert.equal(out, generateSwift(spec(), lock));
  assert.equal(out, `// Generated by scripts/contracts.mjs from @ductura/contracts 2.2.0 (API 1.18.0).
// Tarball sha256 ${'a'.repeat(64)}.
// Do not edit: run node scripts/contracts.mjs --write.
import Foundation

/// GET /api/v1/health (platform.health.get)
public struct PlatformHealthGetResponse: Decodable, Equatable {
    public let status: String
    public let state: String?
    public let minClientVersion: String?
}

public enum PlatformHealthGet {
    public static let method = "GET"
    public static let relativePath = "api/v1/health"

    public static func request(base: URL) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(relativePath))
        request.httpMethod = method
        return request
    }
}
`);
  assert.equal(SWIFT_FILE, 'Sources/DucturaCore/Contracts.generated.swift');
});
