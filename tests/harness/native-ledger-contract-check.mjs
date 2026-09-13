import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {executeLedger, commands, beadsCommands} from '../../plugins/harness/lib/ledger.mjs';
import {runCommand} from '../../plugins/harness/lib/process.mjs';
import {fileArguments} from '../../plugins/harness/lib/ledger/common.mjs';
import {worktreeName} from '../../plugins/harness/lib/workspace/worktree-name.mjs';

assert.equal(process.platform,process.argv[2]||process.platform);
const root=await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(),'native-ledger 한글 space-')));
const config=backend=>({ledger:{backend,owner:'fixture',project:5,database_id:'database'},extension:{한글:'preserve'}});
let reached=0;
const check=async(name,fn)=>{await fn();reached++;console.log('PASS '+name);};
const save=backend=>fs.writeFile(path.join(root,'.harness.json'),JSON.stringify(config(backend)));
const must=async promise=>{const value=await promise;assert.equal(value.code,0,value.stderr);return value.stdout;};
const absent=async promise=>{const value=await promise;assert.notEqual(value.code,0);return value;};
const noProcess=async()=>{throw new Error('unexpected process/remote transport');};
try{
  await check('native CLI root and UI constants require no Bash/jq/Python/backend process',async()=>{
    const cli=fileURLToPath(new URL('../../plugins/harness/scripts/ledger.mjs',import.meta.url));
    const env={...process.env};for(const key of Object.keys(env))if(key.toUpperCase()==='PATH')delete env[key];env.PATH=root;
    for(const backend of ['github','notion','beads']){await save(backend);const value=await runCommand({argv:[process.execPath,cli,'--root',root,'has-ui']},{cwd:root,env});assert.equal(value.code,0,value.stderr.toString());assert.equal(Boolean(value.stdout.length),backend!=='beads');}
    await fs.writeFile(path.join(root,'.harness.json'),'{"ledger":{"backend":"unknown"}}');await absent(executeLedger(['has-ui'],{root,process:noProcess}));
    assert.deepEqual(JSON.parse(await must(executeLedger(['--commands']))),[...commands,...beadsCommands]);
    const discovery=fileURLToPath(new URL('../../plugins/harness/scripts/harness-root.mjs',import.meta.url));
    const nested=path.join(root,'nested','inside');await fs.mkdir(nested,{recursive:true});
    const discover=(cwd,explicit)=>runCommand({argv:[process.execPath,discovery]},{cwd,env:{...env,HARNESS_ROOT:explicit??''}});
    let discovered=await discover(nested);assert.equal(discovered.code,0,discovered.stderr.toString());assert.equal(discovered.stdout.toString().trim(),root,'discovery must not validate backend');
    await fs.writeFile(path.join(root,'nested','.harness.json'),'invalid JSON is still a discovery marker');
    discovered=await discover(nested);assert.equal(discovered.code,0);assert.equal(discovered.stdout.toString().trim(),path.join(root,'nested'),'nearest worktree marker wins');
    discovered=await discover(nested,'../..');assert.equal(discovered.code,0);assert.equal(discovered.stdout.toString().trim(),'../..','legacy explicit spelling remains unchanged');
    const invalidRoots=[nested,path.join(root,'missing')];
    for(const separator of new Set([path.sep,'/']))for(const component of ['missing','.harness.json','nested/../missing'])invalidRoots.push(`${root}${separator}${component.replaceAll('/',separator)}${separator}..`);
    for(const explicit of invalidRoots){discovered=await discover(nested,explicit);assert.equal(discovered.code,1,explicit);assert.equal(discovered.stdout.length,0);assert.equal(discovered.stderr.toString().trim().split('\n').length,1,'failed explicit root cannot fall back');}
    await fs.rm(path.join(root,'nested'),{recursive:true});
    assert.equal(worktreeName('skills#한글 /🙂'),'skills------');
    assert.throws(()=>worktreeName(''),/required/);
    const title=path.join(root,'한글 title.txt'),acceptance=path.join(root,'acceptance.txt');
    await fs.writeFile(title,'제목 $(touch never)\n');await fs.writeFile(acceptance,'first\nsecond & literal\n');
    const ctx={cwd:root,input:Buffer.alloc(0)};
    assert.deepEqual(await fileArguments(['create','--title-file',title,'--acceptance-file',acceptance,'--silent'],ctx),['create','제목 $(touch never)','--silent','--acceptance','first\nsecond & literal']);
    for (const args of [['create','inline','--title-file',title],['create','--title-file',title,'--title-file',title],['update','task','--acceptance','inline','--acceptance-file',acceptance],['create','--title-file',path.join(root,'missing')]]) await assert.rejects(fileArguments(args,ctx));
  });
  await check('common command transport preserves multiline binary stdin and nonzero',async()=>{
    const input=Buffer.from([0,1,10,13,255]);const value=await runCommand({argv:[process.execPath,'-e',"const x=[];process.stdin.on('data',v=>x.push(v));process.stdin.on('end',()=>{process.stdout.write(Buffer.concat(x));process.exitCode=7;});"]},{cwd:root,input});assert.equal(value.code,7);assert.deepEqual(value.stdout,input);
  });
  assert.equal(reached,2); console.log(`PASS native ledger I/O ${reached}; host=${process.platform}`);
}finally{await fs.rm(root,{recursive:true,force:true});}
