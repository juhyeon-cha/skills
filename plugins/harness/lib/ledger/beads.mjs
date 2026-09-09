import fs from 'node:fs/promises';
import path from 'node:path';
import {parse,json,fail,replaceJSON} from './common.mjs';
const exists=file=>fs.stat(file).then(()=>true,error=>{if(error.code==='ENOENT')return false;throw error;});
export async function beadsLedger(argv,ctx){
  const [cmd,...args]=argv;
  const bd=(args,extra={})=>ctx.command('bd',['-C',ctx.root,...args],{input:ctx.inheritStdin?undefined:ctx.input,...extra});
  if(cmd==='has-ui')return;
  if(cmd==='wire-worktree'){
    const wt=args[0];if(!wt||!path.isAbsolute(wt)||!(await fs.stat(wt)).isDirectory())fail(`ledger-beads wire-worktree: 실재하는 <워크트리 절대 경로> 가 필요하다 ('${wt}')`);
    await fs.mkdir(path.join(wt,'.beads'),{recursive:true});await fs.writeFile(path.join(wt,'.beads/redirect'),path.join(ctx.root,'.beads')+'\n');ctx.out(`${path.join(wt,'.beads/redirect')} → ${path.join(ctx.root,'.beads')}\n`);return;
  }
  if(cmd==='rails'||cmd==='sprints'){
    if(args.some(arg=>arg!=='--json'))fail(`ledger-beads ${cmd}: 모르는 인자`);
    const file=path.join(ctx.root,cmd+'.json');let record;try{record=JSON.parse(await fs.readFile(file,'utf8'));}catch(error){fail(`ledger-beads ${cmd}: ${file} 를 읽지 못했다 — ${error.message}`);}
    if(!record[cmd]||typeof record[cmd]!=='object'||Array.isArray(record[cmd]))fail(`최상위 ${cmd} 키가 없다`);
    const rows=Object.entries(record[cmd]).map(([id,value])=>{if(cmd==='rails'){if(value.owner==null)fail(`레일 ${id} 에 owner 가 없다`);return{id,owner:value.owner};}if(!['active','closed'].includes(value.status))fail(`스프린트 ${id} 의 status 는 active|closed 둘뿐이다`);return{id,status:value.status};});ctx.out(json(rows));return;
  }
  if(cmd==='sprint-add'){
    const file=path.join(ctx.root,'sprints.json'),record=JSON.parse(await fs.readFile(file,'utf8'));record.sprints[args[0]]={status:'active'};await replaceJSON(file,record);ctx.out(`✓ 스프린트 등재: ${args[0]} (beads: ${file} 에 status=active)\n`);return;
  }
  if(cmd==='init'){
    const options=parse(args,{'--prefix':'prefix'});if(!options.prefix||options.positional.length)fail('ledger-beads init: --prefix <접두사> 가 필요하다');if(await exists(path.join(ctx.root,'.beads/embeddeddolt')))fail(`ledger-beads init: ${ctx.root}/.beads/embeddeddolt 가 이미 있다 — 다시 초기화하지 않는다`);
    const result=await bd(['init','--prefix',options.prefix],{allowFailure:true});return resultText(result);
  }
  if(cmd==='sync-check'){
    if(args.some(arg=>arg!=='--push'))fail('ledger-beads sync-check: 모르는 인자 (사용: sync-check [--push])');
    const warn=message=>ctx.err('⚠ 원장 게이트: '+message+'\n');let verdict='건너뜀';
    const where=await bd(['where'],{allowFailure:true});const database=/^\s*database:\s*(.*)$/m.exec(where.stdout.toString())?.[1];
    const dolt=async(args,cwd)=>ctx.command('dolt',args,{cwd,allowFailure:true});
    const available=await dolt(['version'],ctx.root);
    if(available.status==='spawn_error'){warn('dolt 미설치 — 원장 반영 여부를 판정할 수 없다');}
    else if(!database||!(await exists(database))){warn('임베디드 원장 없음(bd where 가 로컬 DB 경로를 내지 않았다)');}
    else{
      const directories=(await fs.readdir(database,{withFileTypes:true})).filter(row=>row.isDirectory()&&!row.name.startsWith('.')).map(row=>path.join(database,row.name));
      if(directories.length!==1)warn(`${database} 아래 DB 디렉토리가 ${directories.length}개다(1개를 기대) — 판정을 건너뛴다`);
      else{
        const dir=directories[0],remote=await dolt(['remote','-v'],dir);
        if(remote.code!==0||!remote.stdout.toString().trim())warn('원장에 Dolt 원격이 없다 — 이 원장은 이 머신에만 존재한다');
        else{
          if(!(await dolt(['branch','-a'],dir)).stdout.toString().includes('remotes/origin/main'))fail('원장이 원격에 한 번도 반영된 적이 없다 (remotes/origin/main 없음)');
          if((await dolt(['merge-base','main','remotes/origin/main'],dir)).code!==0)fail('원장 계보가 원격과 갈라졌다 — 공통 조상이 없다');
          const ahead=async()=>{const result=await dolt(['log','remotes/origin/main..main','--oneline'],dir);if(result.code!==0)fail('원장 ahead 판정 미도달');return result.stdout.toString().replace(/\x1b\[[0-9;]*m/g,'').split('\n').filter(line=>line.trim()).length;};
          let count=await ahead();
          if(!count)verdict='확인됨';
          else if(!args.includes('--push')){warn(`원장이 원격보다 ${count}개 커밋 앞서 있다 — 쓰기 모드가 아니라 반영하지 않는다`);verdict='앞서 있음(반영하지 않음 — 쓰기 모드 아님)';}
          else{const result=await ctx.command('bd',['dolt','push'],{cwd:ctx.root,allowFailure:true});ctx.err(result.stderr.toString()+result.stdout.toString());count=await ahead();if(count)fail(`원장이 여전히 원격보다 ${count}개 커밋 앞서 있다 — 자동 반영이 해소하지 못했다`);verdict='이번에 수행함';}
        }
      }
    }
    ctx.out(`✓ 원장 게이트 통과 — 원격 반영 ${verdict}\n`);return;
  }
  const result=await bd(argv,{allowFailure:true});
  if(['show','list','ready','blocked','children','search','query'].includes(cmd)&&args.includes('--json')){
    const parsed=JSON.parse(result.stdout.toString());if(Array.isArray(parsed))for(const row of parsed)if(!Object.hasOwn(row,'actor'))row.actor=row.assignee??null;
    return{code:result.code??1,stdout:json(parsed),stderr:result.stderr.toString()};
  }
  return resultText(result);
}
function resultText(result){return{code:result.code??1,stdout:result.stdout.toString(),stderr:result.stderr.toString()+(result.error?result.error.message+'\n':'')};}
