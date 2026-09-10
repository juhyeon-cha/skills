// A bounded diagnostic, not a preparation/product acceptance result.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {resolveExecutable} from '../../plugins/harness/lib/process.mjs';
const report = {host:process.platform, node:process.version, observations:[], verdict:'UNREACHED'};
const reportFile = process.argv[2] || 'windows-launch-canary.json';
if (process.platform !== 'win32') {
  fs.writeFileSync(reportFile, JSON.stringify(report,null,2)); console.log(JSON.stringify(report)); process.exit(0);
}
const directory = fs.mkdtempSync(path.join(os.tmpdir(),'harness-한글 launch-'));
try {
  const executable = await resolveExecutable('powershell.exe',{cwd:directory,env:process.env});
  report.executable = executable; report.cwdShape = 'temporary path with spaces and Korean';
  const script = path.join(directory,'한글 launch canary.ps1');
  fs.writeFileSync(script, `param([string]$Sentinel)
[IO.File]::WriteAllText($Sentinel, 'started')
[Console]::Out.WriteLine('CANARY_STDOUT')
[Console]::Error.WriteLine('CANARY_STDERR')
exit 7
`);
  for (const detached of [true,false]) for (const transport of ['pipe','file']) {
    const name = `${detached}-${transport}`, sentinel = path.join(directory,name+'.started');
    const outFile = path.join(directory,name+'.out'), errFile = path.join(directory,name+'.err');
    const handles = transport==='file'?[fs.openSync(outFile,'w'),fs.openSync(errFile,'w')]:[];
    let stdout='',stderr='';
    const child = spawn(executable,['-NoLogo','-NoProfile','-NonInteractive','-File',script,'-Sentinel',sentinel],{cwd:directory,env:process.env,detached,stdio:['ignore',...(transport==='pipe'?['pipe','pipe']:handles)]});
    child.stdout?.on('data',chunk=>stdout+=chunk);child.stderr?.on('data',chunk=>stderr+=chunk);
    let timedOut=false;
    const timer=setTimeout(()=>{timedOut=true;child.kill('SIGKILL');},15000);
    const result=await new Promise(resolve=>{child.once('error',error=>resolve({error:error.message}));child.once('close',(code,signal)=>resolve({code,signal}));});
    clearTimeout(timer);for(const handle of handles)fs.closeSync(handle);
    if(transport==='file'){stdout=fs.readFileSync(outFile,'utf8');stderr=fs.readFileSync(errFile,'utf8');}
    report.observations.push({detached,transport,...result,timedOut,started:fs.existsSync(sentinel),stdout,stderr});
  }
  report.supportedLaunch = 'attached; Job ownership is independent of console detachment';
  const supported = report.observations.filter(row=>!row.detached);
  report.verdict = supported.length===2&&supported.every(row=>row.started&&row.code===7&&row.stdout.includes('CANARY_STDOUT')&&row.stderr.includes('CANARY_STDERR'))?'PASS':'OBSERVED_MISMATCH';
} catch(error) {report.error=error.message;}
finally {fs.writeFileSync(reportFile,JSON.stringify(report,null,2));console.log(JSON.stringify(report));fs.rmSync(directory,{recursive:true,force:true});}
process.exitCode=report.verdict==='PASS'?0:1;
