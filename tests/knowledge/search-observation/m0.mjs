// Bounded premise probe; imports the existing production Markdown parser.
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {performance} from 'node:perf_hooks';
import {parseDocument} from '../../../plugins/knowledge/scripts/wiki/markdown.mjs';
const require = createRequire(import.meta.url);
const md = new (require(process.env.WIKI_MARKDOWN_IT_MODULE))({html:false,linkify:false});
const corpus = JSON.parse(fs.readFileSync(new URL('./corpus.json', import.meta.url)));
const docs = corpus.documents.map(d => ({...d,text:d.text.replace('{background}',corpus.background.repeat(corpus.repeat))}));
const queries = ['금액 단위','변경 total','운영 배포','재시도 상한','total 120','METADATA_ONLY_771','양자결제'];
function extract(d) {
  const {tokens,headings} = parseDocument(md,d.text);
  let section = {id:'',title:'',text:''}; const sections = [section];
  for (const token of tokens) {
    if (token.type === 'heading_open') {
      const h = headings.find(h => h.id === token.attrGet('id'));
      section = {...h,text:''}; sections.push(section);
    }
    if (['inline','fence','code_block'].includes(token.type)) section.text += token.content + ' ';
  }
  return sections.filter(s => s.text).map(s => ({...s,repository:d.repository,path:d.path}));
}
const timings=[]; let sections;
for(let i=0;i<10;i++){const start=performance.now();sections=docs.flatMap(extract);timings.push(performance.now()-start);}
const results=queries.map(q => ({query:q,
  baseline_repositories:docs.filter(d => JSON.stringify({...d,commit:'METADATA_ONLY_771'}).toLowerCase().includes(q.toLowerCase())).map(d=>d.repository),
  candidate_sections:sections.filter(s=>q.toLowerCase().split(/\s+/).every(t=>s.text.toLowerCase().includes(t))).map(s=>({repository:s.repository,path:s.path,id:s.id,text:s.text}))}));
const expected=['금액','변경-영향','검증','정책-2','예제'];
if(results.slice(0,5).some((r,i)=>r.candidate_sections.length!==1 || r.candidate_sections[0].id!==expected[i]) || results.slice(5).some(r=>r.candidate_sections.length) || Math.max(...timings)>1000)throw Error('M0 premise failed');
const hidden= [].flatMap(extract); if(hidden.length)throw Error('Hidden result');
console.log(JSON.stringify({runtime:process.version,corpus_bytes:Buffer.byteLength(JSON.stringify(docs)),timings_ms:timings,results,hidden_results:0,limits:'Pure parser/projection probe; live authorization, HTTP and actual model reading await implementation.'},null,2));
