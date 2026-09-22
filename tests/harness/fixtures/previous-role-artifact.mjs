import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
import {pathToFileURL} from 'node:url';

// Frozen verbatim plugins/harness Git blobs from this commit, including modes.
// Keeping the full artifact lets its original inspector/installer validate it;
// tests need neither installed caches, Git history, tar, nor network access.
export async function previousRoleArtifact(destination) {
  const compressed = fs.readFileSync(new URL('./roles-v2.4.0.json.gz', import.meta.url));
  assert.equal(createHash('sha256').update(compressed).digest('hex'),
    'c55fb6b043179091efcb9b48eb3bafed08c88150bd0cc7667f8290cf770397e5');
  const fixture = JSON.parse(gunzipSync(compressed));
  assert.equal(fixture.commit, 'efe8c962ab5c0835c2a32f1de8a0e563a11928a6');
  assert.equal(fixture.files.length, 131);
  for (const {path: relative, text, mode} of fixture.files) {
    assert(!path.isAbsolute(relative) && !relative.split('/').includes('..'));
    const file = path.join(destination, relative);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, text, {flag: 'wx', mode});
    fs.chmodSync(file, mode);
  }
  assert(!fs.existsSync(path.join(destination, 'roles')));
  assert(!fs.existsSync(path.join(destination, 'native')));
  const distribution = await import(pathToFileURL(path.join(destination, 'lib/distribution.mjs')));
  const artifact = distribution.inspectDistribution(destination);
  assert.equal(artifact.hash, fixture.artifactHash);
  return {
    artifact,
    distribution,
    roles: await import(pathToFileURL(path.join(destination, 'lib/runtime/roles.mjs'))),
    install: await import(pathToFileURL(path.join(destination, 'lib/runtime/parity-install.mjs'))),
    doctor: await import(pathToFileURL(path.join(destination, 'lib/runtime/doctor.mjs'))),
  };
}
