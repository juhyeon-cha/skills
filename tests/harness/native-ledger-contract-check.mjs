import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {executeLedger,commands,beadsCommands} from '../../plugins/harness/lib/ledger.mjs';
import {normalizeGithub} from '../../plugins/harness/lib/ledger/github.mjs';
import {richText} from '../../plugins/harness/lib/ledger/notion.mjs';
import {runCommand} from '../../plugins/harness/lib/process.mjs';
import {fileArguments} from '../../plugins/harness/lib/ledger/common.mjs';
import {worktreeName} from '../../plugins/harness/lib/worktree-name.mjs';

assert.equal(process.platform,process.argv[2]||process.platform);
const root=await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(),'native-ledger 한글 space-')));
const config=backend=>({ledger:{backend,owner:'fixture',project:5,database_id:'database'},extension:{한글:'preserve'}});
const result=(value='',code=0)=>({status:'exited',code,signal:null,stdout:Buffer.from(typeof value==='string'?value:JSON.stringify(value)),stderr:Buffer.alloc(0)});
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
  // Stateful Notion transport: requests/normalization are exercised without an
  // API-host override or a production fixture executable.
  const pages=new Map(),notes=new Map(),requests=[];let serial=0,failRequest=false,paginate=false;
  const plain=properties=>JSON.parse(JSON.stringify(properties),(key,value)=>key==='rich_text'||key==='title'?value.map(part=>({...part,plain_text:part.text?.content??part.plain_text??''})):value);
  const request=async(method,endpoint,body)=>{
    requests.push({method,endpoint,body});if(failRequest)throw new Error('HTTP 503 fixture unavailable');
    if(method==='POST'&&endpoint==='databases')return{id:'database'};
    if(method==='PATCH'&&endpoint.startsWith('databases/'))return{};
    if(method==='POST'&&endpoint.endsWith('/query')){const rows=[...pages.values()];return{results:paginate?(body.start_cursor?rows.slice(1):rows.slice(0,1)):rows,has_more:paginate&&!body.start_cursor,next_cursor:paginate&&!body.start_cursor?'next':null};}
    if(method==='POST'&&endpoint==='pages'){const id='page-'+(++serial),page={id,properties:plain(body.properties),created_time:'created',last_edited_time:'updated'};pages.set(id,page);return page;}
    const [kind,id]=endpoint.split('/');
    if(kind==='pages'){if(!pages.has(id))throw new Error('HTTP 404 object_not_found');if(method==='GET')return structuredClone(pages.get(id));Object.assign(pages.get(id).properties,plain(body.properties));return pages.get(id);}
    if(kind==='blocks'){if(method==='GET')return{results:(notes.get(id)??[]).map(text=>({type:'paragraph',paragraph:{rich_text:[{plain_text:text}]}}))};notes.set(id,[...(notes.get(id)??[]),...body.children.map(row=>row.paragraph.rich_text.map(part=>part.text.content).join(''))]);return{};}
    throw new Error('unexpected request '+method+' '+endpoint);
  };
  const n=args=>executeLedger(args,{root,cwd:root,env:{NOTION_TOKEN:'fixture-token'},request,process:noProcess});
  await save('notion');let epic,task;
  await check('Notion init preserves config extensions and creates relations',async()=>{await must(n(['init']));assert.equal(JSON.parse(await fs.readFile(path.join(root,'.harness.json'),'utf8')).extension.한글,'preserve');assert.ok(requests.at(-1).body.properties['Blocked by']);});
  await check('Notion create, inheritance, body files, empty fields and actor contract',async()=>{
    epic=(await must(n(['create','epic','-t','epic','-l','repo:a,repo:b,rail:r1,sprint:2026-S01,slug:r1-epic','--silent']))).trim();
    await must(n(['update',epic,'--assignee','owner']));await fs.writeFile(path.join(root,'한글 body.txt'),'description\nline2\n');
    task=(await must(n(['create','task','--parent',epic,'-l','repo:a','--body-file','한글 body.txt','--acceptance','조건','--silent']))).trim();
    let row=JSON.parse(await must(n(['show',task,'--json'])))[0];assert.deepEqual(row.labels,['rail:r1','repo:a','sprint:2026-S01']);assert.equal(row.description,'description\nline2');assert.equal(row.actor,null);
    await must(n(['update',task,'--claim','--actor','sess-A']));row=JSON.parse(await must(n(['show',task,'--json'])))[0];assert.equal(row.actor,'sess-A');assert.equal(row.status,'in_progress');assert.match(row.notes,/ACTOR: sess-A/);
    await absent(n(['update',task,'--claim','--assignee','other']));await must(n(['update',task,'--acceptance','','--assignee','']));row=JSON.parse(await must(n(['show',task,'--json'])))[0];assert.equal(row.acceptance_criteria,'');assert.equal(row.assignee,null);
    const literal=(await must(n(['create','literal','--description','-l','--acceptance','--labels','--silent']))).trim();
    const literalRow=JSON.parse(await must(n(['show',literal,'--json'])))[0];assert.equal(literalRow.description,'-l');assert.equal(literalRow.acceptance_criteria,'--labels');pages.delete(literal);
  });
  await check('Notion notes, label add/remove, children, ready and close contracts',async()=>{
    await must(n(['note',task,'text --json remains a body']));await must(n(['label','add',task,'custom']));await must(n(['label','remove',task,'custom']));
    await must(n(['update',task,'--status','open']));await must(n(['dep','add',task,epic]));assert.deepEqual(JSON.parse(await must(n(['ready','--json']))).map(row=>row.id),[epic]);
    await must(n(['close',epic,'--reason','closed reason']));assert.deepEqual(JSON.parse(await must(n(['ready','--json']))).map(row=>row.id),[task]);
    assert.deepEqual(JSON.parse(await must(n(['children',epic,'--json']))).map(row=>row.id),[task]);
    assert.match(await must(n(['show',task])),/ACCEPTANCE/);assert.match(await must(n(['list','--all'])),/\ttask\t/);
  });
  await check('Notion registries and all pagination/filter/failure boundaries',async()=>{
    assert.deepEqual(JSON.parse(await must(n(['rails','--json']))),[{id:'r1',owner:'owner'}]);
    await must(n(['sprint-add','2026-S01']));await absent(n(['sprint-add','2026-S01']));assert.deepEqual(JSON.parse(await must(n(['sprints','--json']))),[{id:'2026-S01',status:'active'}]);
    paginate=true;assert.ok(JSON.parse(await must(n(['list','--all','-n','0','--json']))).length>=3);paginate=false;
    failRequest=true;await absent(n(['ready','--json']));await absent(n(['list','--json']));failRequest=false;
    await absent(executeLedger(['show',task],{root,cwd:root,env:{},request,process:noProcess}));await absent(n(['show','missing','--json']));await absent(n(['delete',task]));
    const text='😀'.repeat(2001);const chunks=richText(text);assert.equal([...chunks[0].text.content].length,2000);assert.equal(chunks.map(part=>part.text.content).join(''),text);
  });
  await check('Notion stdin bodies and dependency JSONL retain command-looking text',async()=>{
    const body='line1\n--json\n한글';await must(executeLedger(['note',task,'--stdin'],{root,cwd:root,env:{NOTION_TOKEN:'fixture'},input:Buffer.from(body),request,process:noProcess}));assert.ok(notes.get(task).includes(body));
    await must(executeLedger(['dep','add','--file','-'],{root,cwd:root,env:{NOTION_TOKEN:'fixture'},input:Buffer.from(JSON.stringify({from:task,to:epic})+'\n'),request,process:noProcess}));
  });
  const ghCalls=[],nodes=new Map();let ghSerial=1,addFailure=false,membership=true,authFailure=false,patchFailure=false,truncate=false;
  const node=(number,title='issue')=>({number,id:'NODE'+number,databaseId:number,title,state:'OPEN',body:'description\n\n## Acceptance\n\ncriteria',repository:{name:'repo'},labels:{nodes:[{name:'repo:repo'},{name:'type:task'}]},comments:{nodes:[]},assignees:{nodes:[]},blockedBy:{totalCount:0,nodes:[]},projectItems:{nodes:[{project:{number:5}}]},parent:null,createdAt:'created',updatedAt:'updated',closedAt:null});nodes.set(1,node(1));
  const gh=async(command,options)=>{
    assert.equal(command.argv[0],'gh');const args=command.argv.slice(1);ghCalls.push({args,input:options.input?.toString()});const q=args.find(arg=>arg.startsWith('query='))?.slice(6),field=key=>args.find(arg=>arg.startsWith(key+'='))?.slice(key.length+1);
    if(args.join(' ')==='auth status')return result('',authFailure?1:0);
    if(args[0]==='label')return result('');
    if(args[0]==='project'){if(args[1]==='create')return result({number:5});if(args[1]==='view')return result({});if(args[1]==='item-add')return result('',addFailure?1:0);}
    if(args[0]==='issue'){
      const num=Number(args[2]);
      if(args[1]==='create'){const created=node(++ghSerial,args[args.indexOf('-t')+1]);created.body=await fs.readFile(args[args.indexOf('-F')+1],'utf8');created.labels.nodes=args[args.indexOf('-l')+1].split(',').map(name=>({name}));nodes.set(ghSerial,created);return result('https://github.com/fixture/repo/issues/'+ghSerial+'\n');}
      if(args[1]==='comment'){nodes.get(num).comments.nodes.push({body:args[args.indexOf('-b')+1]});return result('');}
      if(args[1]==='view')return result(nodes.get(num).labels.nodes.map(row=>row.name).join('\n'));
      if(args[1]==='close'){nodes.get(num).state='CLOSED';return result('');}if(args[1]==='reopen'){nodes.get(num).state='OPEN';return result('');}
      if(args[1]==='edit'){const raw=nodes.get(num);for(let i=3;i<args.length;i++){if(args[i]==='--add-label')raw.labels.nodes.push({name:args[++i]});else if(args[i]==='--remove-label'){const label=args[++i];raw.labels.nodes=raw.labels.nodes.filter(row=>row.name!==label);}else if(args[i]==='--add-assignee')raw.assignees.nodes=[{login:args[++i]}];else if(args[i]==='-F')raw.body=await fs.readFile(args[++i],'utf8');}return result('');}
    }
    if(args[0]==='api'){
      if(q){
        if(q.startsWith('mutation'))return result({data:{addSubIssue:{},createProjectV2Field:{}}});
        if(q.includes('fields(first:100)'))return result({data:{user:{projectV2:{id:'PROJECT',fields:{nodes:[{id:'FIELD',name:'Sprint',configuration:{duration:14,iterations:[],completedIterations:[]}}]}}}}});
        if(q.includes('items(first:100'))return result([{data:{user:{projectV2:{items:{nodes:[{content:{repository:{name:'repo'}}}]}}}}}]);
        if(q.includes('issues(first:100'))return result([{data:{repository:{issues:{nodes:[...nodes.values()].map(raw=>({...raw,blockedBy:truncate?{totalCount:51,nodes:[]}:raw.blockedBy,projectItems:{nodes:membership?[{project:{number:5}}]:[]}}))}}}}]);
        const raw=structuredClone(nodes.get(Number(field('n'))));if(!raw)return result({data:{repository:{issue:null}}});
        if(q.includes('subIssues'))raw.subIssues={nodes:[...nodes.values()].filter(row=>row.parent?.number===raw.number)};
        if(q.includes('projectItems'))raw.projectItems={nodes:membership?[{project:{number:5}}]:[]};return result({data:{repository:{issue:raw}}});
      }
      if(args.includes('--input')){
        const body=JSON.parse(options.input);if(args[1]==='graphql')return result({data:{updateProjectV2Field:{projectV2Field:{name:'Sprint'}}}});
        if(patchFailure)return result({message:'Not Found'},1);return result({assignees:(body.assignees??[]).map(login=>({login}))});
      }
      if(args.includes('--jq'))return result(args.at(-1)==='.node_id'?'NODE':'1');
      if(args.includes('POST'))return result({});
    }
    throw new Error('unexpected gh transport '+args.join(' '));
  };
  const g=args=>executeLedger(args,{root,cwd:root,env:{},process:gh});await save('github');
  await check('GitHub full normalized actor/dependency vocabulary and truncated dependencies refusal',async()=>{
    const raw=node(42);raw.comments.nodes=[{body:'ACTOR: first'},{body:'ACTOR: login sess-final\nmore'}];const row=normalizeGithub(raw);assert.equal(row.actor,'sess-final');assert.equal(row.acceptance_criteria,'criteria');assert.equal(row.assignee,null);
    truncate=true;await absent(g(['list','--json']));truncate=false;
    for (const field of ['labels','comments','assignees','blockedBy']) {
      const malformed=node(43);delete malformed[field];
      assert.throws(()=>normalizeGithub(malformed),/필수/,'missing '+field+' must not become an empty successful read');
    }
  });
  await check('GitHub create distinguishes item-add failure/reached membership from partial failure',async()=>{
    addFailure=true;membership=true;const created=(await must(g(['create','title','-l','repo:repo','--silent']))).trim();assert.match(created,/repo#/);
    membership=false;const failed=await absent(g(['create','partial','-l','repo:repo','--silent']));assert.match(failed.stderr,/만들었지만/);assert.ok(nodes.size>=3);
    addFailure=false;const before=ghCalls.length;await must(g(['create','reported success','-l','repo:repo','--silent']));assert.equal(ghCalls.slice(before).some(call=>call.args.some(arg=>arg.includes('projectItems'))),false);membership=true;
    await absent(g(['create','bad repo','--silent']));
  });
  await check('GitHub show/list/ready/children, update/note/label/close and HTTP failures',async()=>{
    await must(g(['show','repo#1','--json']));await must(g(['list','--all','--json']));await must(g(['ready','--json']));await must(g(['children','repo#1','--json']));
    await must(g(['update','repo#1','--claim','--actor','sess-native']));assert.equal(JSON.parse(await must(g(['show','repo#1','--json'])))[0].actor,'sess-native');
    await absent(g(['update','repo#1','--claim','--assignee','x']));await must(g(['update','repo#1','--assignee','']));patchFailure=true;await absent(g(['update','repo#1','--assignee','']));patchFailure=false;
    await must(g(['note','repo#1','note --json']));await must(g(['label','add','repo#1','extra']));await must(g(['label','remove','repo#1','extra']));await must(g(['update','repo#1','--status','open','--acceptance','updated']));await must(g(['dep','add','repo#1','repo#2']));await must(g(['close','repo#1','--reason','done']));
    authFailure=true;await absent(g(['show','repo#1','--json']));authFailure=false;await absent(g(['delete','repo#1']));
  });
  await check('GitHub registry/init/sprint replacement retains complete request contract',async()=>{await must(g(['init']));await must(g(['rails','--json']));assert.deepEqual(JSON.parse(await must(g(['sprints','--json']))),[]);await must(g(['sprint-add','2026-S02']));const payload=JSON.parse(ghCalls.findLast(call=>call.input?.includes('iterationConfiguration')).input);assert.equal(payload.variables.it[0].title,'2026-S02');assert.equal(payload.variables.d,14);});
  await save('beads');const bdCalls=[];let childLabels=['slug:parent','repo:wrong','rail:r1'],created=false;
  const beadProcess=async(command,options)=>{assert.equal(command.argv[0],'bd');assert.deepEqual(command.argv.slice(1,3),['-C',root]);const args=command.argv.slice(3);bdCalls.push({args,input:options.input});
    if(args[0]==='show')return result([{id:args[1],labels:args[1]==='parent'?['slug:parent','rail:r1','repo:wrong']:childLabels,assignee:'owner'}]);
    if(args[0]==='create'){created=true;childLabels=[...new Set([...childLabels,...args[args.indexOf('-l')+1].split(',')])];return result('child\n');}if(args[0]==='label'){childLabels=childLabels.filter(label=>label!==args.at(-1));return result('');}return result('raw output\n',args[0]==='delete'?7:0);};
  const b=args=>executeLedger(args,{root,cwd:root,process:beadProcess});
  await check('beads inherited extras are removed and read-only actor enrichment preserves passthrough',async()=>{
    assert.equal((await must(b(['create','child','--parent','parent','-l','repo:new','--silent']))).trim(),'child');assert.equal(created,true);assert.deepEqual(childLabels,['rail:r1','repo:new']);
    const row=JSON.parse(await must(b(['show','child','--json'])))[0];assert.equal(row.actor,'owner');assert.equal(await must(b(['note','child','text --json'])),'raw output\n');const failed=await b(['delete','child']);assert.equal(failed.code,7);assert.equal(failed.stdout,'raw output\n');
    for(const command of beadsCommands.filter(command=>!['delete','search','blocked','query'].includes(command)))await must(b([command]));
  });
  await check('beads registries have no absent-file fallback and sprint duplicates fail',async()=>{
    await absent(b(['rails','--json']));await fs.writeFile(path.join(root,'rails.json'),JSON.stringify({rails:{r1:{owner:'owner'}}}));assert.deepEqual(JSON.parse(await must(b(['rails','--json']))),[{id:'r1',owner:'owner'}]);
    await fs.writeFile(path.join(root,'sprints.json'),JSON.stringify({sprints:{}}));await must(b(['sprint-add','2026-S01']));await absent(b(['sprint-add','2026-S01']));assert.deepEqual(JSON.parse(await must(b(['sprints','--json']))),[{id:'2026-S01',status:'active'}]);
  });
  await check('beads sync read path never pushes and explicit push requires reread',async()=>{
    const database=path.join(root,'database');await fs.mkdir(path.join(database,'fixture-db'),{recursive:true});let ahead=1,pushes=0;
    const transport=async(command)=>{const [executable,...args]=command.argv;if(executable==='bd'){if(args.includes('where'))return result('database: '+database+'\n');assert.deepEqual(args,['dolt','push']);pushes++;ahead=0;return result('');}
      assert.equal(executable,'dolt');if(args[0]==='version')return result('dolt');if(args[0]==='remote')return result('origin fixture');if(args[0]==='branch')return result('remotes/origin/main');if(args[0]==='merge-base')return result('base');if(args[0]==='log')return result(ahead?'commit\n':'');throw new Error('unreached fixture');};
    const read=await executeLedger(['sync-check'],{root,cwd:root,process:transport});assert.equal(read.code,0,read.stderr);assert.equal(pushes,0);assert.match(read.stdout,/반영하지 않음/);
    await must(executeLedger(['sync-check','--push'],{root,cwd:root,process:transport}));assert.equal(pushes,1);assert.equal(ahead,0);
  });
  assert.equal(reached,14,'nonempty complete native judgment set');console.log(`PASS native ledger ${reached}; host=${process.platform}; offline transports, no remote writes`);
}finally{await fs.rm(root,{recursive:true,force:true});}
