import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {installDistribution, diagnoseInstallation, installationPlan} from '../../plugins/harness/lib/runtime/parity-install.mjs';
import {inspectDistribution, generateDistribution, digest} from '../../plugins/harness/lib/distribution.mjs';
import {verifyRegistration, registerRoles, loadRole} from '../../plugins/harness/lib/runtime/roles.mjs';
import {createChallenge, recordHook, diagnose} from '../../plugins/harness/lib/runtime/doctor.mjs';
import {formatStateContext} from '../../plugins/harness/lib/runtime/state.mjs';

const source = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'parity-install-')));
const read = file => fs.readFileSync(file, 'utf8');
const put = (file, text) => {fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, text);};
try {
  const newer = path.join(scratch, 'newer');
  fs.cpSync(source, newer, {recursive:true});
  const manifest = path.join(newer, '.claude-plugin/plugin.json');
  const changed = JSON.parse(read(manifest)); changed.version = '99.0.0';
  put(manifest, JSON.stringify(changed));
  put(path.join(newer, 'hooks/session-context.md'), read(path.join(newer, 'hooks/session-context.md')) + '\nFixture updated context.\n');
  generateDistribution(newer);
  const markerSource = path.join(scratch, 'marker-source');
  fs.cpSync(source, markerSource, {recursive:true});
  put(path.join(markerSource, '.in_use/12345'), '{"pid":');
  const markerInstall = installDistribution({source:markerSource, destination:path.join(scratch, 'marker-install'), surface:'claude-cli'});
  assert.equal(markerInstall.receipt.sourceHash, inspectDistribution(source).hash);
  assert(!fs.existsSync(path.join(markerInstall.receipt.installedRoot, '.in_use')));
  assert(!Object.keys(markerInstall.receipt.files).some(file => file.includes('/.in_use/')));
  assert.deepEqual(inspectDistribution(markerInstall.receipt.installedRoot).files, inspectDistribution(source).files);
  const baseline = inspectDistribution(source);
  for (const surface of ['claude-cli','codex-cli','codex-desktop','antigravity-cli']) {
    const destination = path.join(scratch, surface, 'plugin');
    const options = {source, destination, surface,
      ...(surface.startsWith('codex') ? {agentsDestination:path.join(scratch,surface,'agents')} : {})};
    const user = path.join(destination, 'user-notes.txt');
    const policy = path.join(scratch, surface, 'managed-settings.json');
    put(user, 'user-owned'); put(policy, '{"deny":["remote"]}');
    const result = installDistribution(options);
    assert.equal(result.status, 'STAGED');
    assert.equal(result.loaded, 'UNREACHED');
    assert.equal(result.receipt.sourceHash, baseline.hash);
    assert.equal(result.receipt.contextHash, baseline.contextHash);
    assert.deepEqual(result.receipt.skills, baseline.skills);
    assert.equal(diagnoseInstallation(options).static, 'PASS');
    assert.equal(diagnoseInstallation(options).loaded, 'UNREACHED');
    assert.equal(read(user), 'user-owned'); assert.equal(read(policy), '{"deny":["remote"]}');
    const installedRoot = result.receipt.installedRoot;
    assert.equal(inspectDistribution(installedRoot).contextHash, baseline.contextHash);
    assert.equal(fs.statSync(path.join(installedRoot,'scripts/ledger.sh')).mode & 0o777,
      fs.statSync(path.join(source,'scripts/ledger.sh')).mode & 0o777);
    if (surface.startsWith('codex')) {
      // The lifecycle writes exactly the existing role registration's bytes.
      verifyRegistration(registerRoles('codex', options.agentsDestination, installedRoot));
    }
    if (surface === 'antigravity-cli') {
      const skill = result.receipt.components.skills[0];
      assert.equal(path.dirname(skill), path.join(destination, 'skills'));
      assert(!read(skill).includes('${CLAUDE_PLUGIN_ROOT}'));
      assert(read(skill).includes(installedRoot));
      const hook = JSON.parse(read(path.join(destination,'hooks.json'))).harness.PreInvocation[0];
      assert(hook.command.includes(path.join(installedRoot,'scripts/hook.mjs')));
      const run = spawnSync('node', [path.join(installedRoot,'scripts/hook.mjs'),'context','--runtime','antigravity'], {input:'{}',encoding:'utf8',env:{...process.env,HARNESS_RUNTIME:''}});
      // A staged adapter must reject malformed context; staged bytes are not loading evidence.
      assert.equal(run.status, 2); assert.match(run.stderr, /absolute workspace and conversationId/);
    }
    installDistribution(options); // idempotent owned install
    const managed = result.receipt.components.skills[0];
    const original = read(managed);
    put(managed, original + '\nUSER EDIT\n');
    assert.throws(() => installDistribution({...options,source:newer}), /edited/);
    assert.equal(read(managed), original + '\nUSER EDIT\n');
    assert.equal(read(user), 'user-owned');
    put(managed, original);
    const duplicate = path.join(path.dirname(result.receipt.components.roles[0]), 'duplicate' + path.extname(result.receipt.components.roles[0]));
    put(duplicate, read(result.receipt.components.roles[0]));
    assert.match(diagnoseInstallation(options).reasons.join(' '), /duplicate/);
    fs.unlinkSync(duplicate);
    fs.unlinkSync(managed);
    assert.match(diagnoseInstallation(options).reasons.join(' '), /missing/);
    assert.throws(() => installDistribution(options), /missing/);
    put(managed, original);
    const originalWrite = fs.writeFileSync;
    let injected = false;
    fs.writeFileSync = function(file, ...args) {
      if (!injected && file === managed) {
        injected = true;
        originalWrite(file, 'partial write');
        throw new Error('fixture interrupted write');
      }
      return originalWrite(file, ...args);
    };
    try { assert.throws(() => installDistribution({...options,source:newer}), /interrupted write/); }
    finally { fs.writeFileSync = originalWrite; }
    assert(injected);
    assert.equal(read(managed), original);
    assert.equal(diagnoseInstallation(options).static, 'PASS');
    // Persistent failure at the same file must not prevent restoration of an
    // earlier updated manifest. Report both the operation and recovery errors.
    for (const partial of [false, true]) {
      fs.writeFileSync = function(file, ...args) {
        if (file === managed) {
          if (partial) originalWrite(file, 'persistent partial write');
          throw new Error('persistent target write failure');
        }
        return originalWrite(file, ...args);
      };
      try {
        assert.throws(() => installDistribution({...options,source:newer}), error => {
          assert(error instanceof AggregateError);
          assert.equal(error.cause.message, 'persistent target write failure');
          assert.equal(error.errors.length, 2);
          assert.match(error.message, /installation failed: persistent target write failure; restore failed:/);
          return true;
        });
      } finally { fs.writeFileSync = originalWrite; }
      assert.equal(JSON.parse(read(path.join(installedRoot,'.claude-plugin/plugin.json'))).version, baseline.version);
      assert.equal(read(managed), partial ? 'persistent partial write' : original);
      assert.equal(diagnoseInstallation(options).static, partial ? 'UNREACHED' : 'PASS');
      put(managed, original);
    }
    installDistribution({...options,source:newer});
    assert.equal(diagnoseInstallation({...options,source:newer}).static,'PASS');
    assert.equal(diagnoseInstallation(options).static,'UNREACHED');
    assert.equal(read(user),'user-owned'); assert.equal(read(policy),'{"deny":["remote"]}');
    installDistribution(options); // rollback from canonical old bytes
    assert.equal(diagnoseInstallation(options).static,'PASS');
    assert.equal(digest(read(managed)),digest(original));
    const symlink = path.join(destination,'skills','symlink.md');
    fs.symlinkSync(user,symlink);
    assert.match(diagnoseInstallation(options).reasons.join(' '),/symlink/);
    fs.unlinkSync(symlink);
    console.log(`PASS ${surface}: bytes, ownership, conflicts, missing/duplicate, update/rollback; loading remains UNREACHED`);
  }
  const collision = path.join(scratch,'collision');
  put(path.join(collision,'.claude-plugin/plugin.json'),'USER');
  assert.throws(() => installDistribution({source,destination:collision,surface:'claude-cli'}),/unowned/);
  assert.equal(read(path.join(collision,'.claude-plugin/plugin.json')),'USER');
  assert.throws(() => installationPlan({source,destination:path.join(source,'nested'),surface:'claude-cli'}),/disjoint/);
  const symlinkRoot = path.join(scratch,'linked'); fs.symlinkSync(collision,symlinkRoot);
  assert.throws(() => installationPlan({source,destination:path.join(symlinkRoot,'nested'),surface:'claude-cli'}),/symlink/);
  const liveFixture = {source,destination:path.join(scratch,'doctor-plugin'),surface:'claude-cli'};
  installDistribution(liveFixture);
  const registration = registerRoles('claude',undefined,liveFixture.destination);
  const doctorDirectory = path.join(scratch,'challenge');
  createChallenge(doctorDirectory,'claude',liveFixture.destination,registration,source);
  const observation = {...liveFixture,doctorDirectory,sessionId:'fixture-session'};
  assert.equal(diagnoseInstallation(observation).loaded,'UNREACHED'); // no executing hook/trust evidence
  for (let i = 0; i < 2; i++) {
    const run = spawnSync('node',[path.join(liveFixture.destination,'scripts/hook.mjs'),'context','--runtime','claude'],{
      input:JSON.stringify({hook_event_name:'SessionStart',session_id:'fixture-session',cwd:scratch}),encoding:'utf8',
      env:{...process.env,CLAUDE_PLUGIN_ROOT:liveFixture.destination,HARNESS_RUNTIME:'claude',HARNESS_DOCTOR_DIR:doctorDirectory,HARNESS_DATA_DIR:path.join(scratch,'state')},
    });
    assert.equal(run.status,0,run.stderr);
  }
  const duplicateHooks = diagnoseInstallation(observation);
  assert.equal(duplicateHooks.loaded,'UNREACHED');
  assert.match(duplicateHooks.reasons.join(' '),/context hook not observed exactly once/);
  // Synthetic signed hook observations exercise the diagnostic boundary only.
  // They are not claims that a provider actually launched these roles.
  for (const surface of ['claude-cli', 'codex-cli', 'codex-desktop']) {
    const target = {source, destination:path.join(scratch,`scope-${surface}`), surface,
      ...(surface.startsWith('codex') ? {agentsDestination:path.join(scratch,`scope-agents-${surface}`)} : {})};
    installDistribution(target);
    for (const runtime of ['claude', 'codex']) {
      for (const withContext of [false, true]) {
        const registration = registerRoles(runtime, runtime === 'codex' ? path.join(scratch,`roles-${surface}-${withContext}`) : undefined,target.destination);
        const directory = path.join(scratch,`scope-${surface}-${runtime}-${withContext}`);
        createChallenge(directory,runtime,target.destination,registration,source);
        const stateContext = withContext ? {runtime,repository:scratch,sessionId:'scope-session',data:path.join(scratch,'data')} : undefined;
        const record = (hook,event,stdout='') => recordHook(directory,target.destination,
          {session_id:'scope-session',...event},hook,{code:0,stdout,...(hook === 'context' ? {stateContext} : {})});
        record('context',{hook_event_name:'SessionStart'},JSON.stringify({hookSpecificOutput:{additionalContext:
          read(path.join(source,'hooks/session-context.md')) + (stateContext ? formatStateContext(stateContext) : '')}}));
        for (const entry of registration.roles) {
          const who = {agent_id:`child-${entry.role}`,agent_type:entry.identifier};
          record('role-start',{hook_event_name:'SubagentStart',...who});
          record('guard',{hook_event_name:'PreToolUse',tool_name:'Bash',...who});
          record('role-stop',{hook_event_name:'SubagentStop',last_assistant_message:`SIGNAL: ${loadRole(entry.role).signals[0]}`,...who});
        }
        record('stop',{hook_event_name:'Stop'});
        assert.equal(diagnose(target.destination,directory,'scope-session',source).live,'PASS');
        const result = diagnoseInstallation({...target,doctorDirectory:directory,sessionId:'scope-session',observedSurface:surface});
        const valid = surface === 'claude-cli' && runtime === 'claude' && withContext;
        assert.equal(result.loaded,valid ? 'PASS' : 'UNREACHED');
        assert.equal(result.live,valid ? 'PASS' : 'UNREACHED');
        if (!valid) assert.match(result.reasons.join(' '), /observed runtime missing or differs|surface identity unobserved/);
      }
    }
  }
  console.log('PASS lifecycle boundary negatives; no provider profile or trust settings changed');
} finally { fs.rmSync(scratch,{recursive:true,force:true}); }
