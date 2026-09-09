// POSIX legacy-fixture bridge only. Production uses fetch directly; the native
// suite injects a function and never launches this fake-curl compatibility path.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
if (process.env.FAKE_NATIVE_NOTION === '1') {
  globalThis.fetch = async () => new Response(JSON.stringify({id:'native-fixture',properties:{Name:{title:[]},Status:{select:{name:'open'}},Type:{select:{name:'task'}},Labels:{multi_select:[]},'Blocked by':{relation:[]}},results:[]}));
} else if (process.env.FAKE_CURL_LOG) {
  globalThis.fetch = async (url, options={}) => {
    if (!String(url).startsWith('https://api.notion.com/v1/')) throw new Error('fixture refuses unexpected endpoint');
    const executable = path.join(process.env.PATH.split(path.delimiter)[0],'curl');
    if (!fs.readFileSync(executable,'utf8').includes('FAKE_NOTION_401')) throw new Error('fixture refuses a real curl executable');
    const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ledger-fetch-fixture-'));
    try {
      const output=path.join(directory,'response'),args=['-sS','-o',output,'-w','%{http_code}','-X',options.method??'GET',String(url)];
      for (const [name,value] of Object.entries(options.headers??{}))args.push('-H',name+': '+value);
      if(options.body!==undefined){const input=path.join(directory,'request');fs.writeFileSync(input,options.body);args.push('--data-binary','@'+input);}
      const result=spawnSync(executable,args,{encoding:'utf8'});
      if(result.status!==0)throw new Error('fake curl failed: '+result.stderr);
      return new Response(fs.readFileSync(output),{status:Number(result.stdout)});
    } finally {fs.rmSync(directory,{recursive:true,force:true});}
  };
} else globalThis.fetch = async () => { throw new Error('fixture refuses unconfigured network transport'); };
