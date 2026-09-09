// Run in a detached child: inject a file replacement at the config-read boundary
// while executing the real preparation module and a harmless local bootstrap.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [plugin, top] = process.argv.slice(2);
const {inspectWorkspace} = await import(pathToFileURL(path.join(plugin, 'lib/workspace.mjs')));
const {runPreparation, preparationStatus} = await import(pathToFileURL(path.join(plugin, 'lib/preparation.mjs')));
const identity = await inspectWorkspace(top);
const file = path.join(top, '.harness.json');
const replacement = JSON.parse(await fs.readFile(file, 'utf8'));
replacement.bootstrap.argv[replacement.bootstrap.argv.length - 1] = 'new';
const readFile = fs.readFile;
let reads = 0, injected = false, error;
fs.readFile = async function(location, ...args) {
  const configRead = location === file && new Error().stack.includes('loadConfig');
  const bytes = await readFile.call(this, location, ...args);
  if (configRead && ++reads === 2) {
    await fs.writeFile(file, JSON.stringify(replacement)); injected = true;
  }
  return bytes;
};
try { await runPreparation(identity); } catch (caught) { error = caught.message; }
finally { fs.readFile = readFile; }
const status = await preparationStatus(identity);
const executed = await fs.readFile(path.join(top, 'executed'), 'utf8');
console.log(JSON.stringify({injected, executed, error, ...status}));
