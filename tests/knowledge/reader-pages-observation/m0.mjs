import {createRequire} from 'node:module';
import fs from 'node:fs';
import {performance} from 'node:perf_hooks';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url), modulePath='/private/tmp/wiki-relocation-runtime/node_modules/markdown-it';
const MarkdownIt=require(modulePath), started=performance.now();
const md=new MarkdownIt({html:false,linkify:false});
const input='# 결제 계약\n\n## 금액\n\n| 필드 | 의미 |\n| --- | --- |\n| total | 합계 |\n\n## 금액\n\n[동일](#금액) [설명](guide.md#호출) [미허용](private.md)\n\n<script>alert(1)</script>\n\n[x](javascript:alert(1)) [x](data:text/html,evil)\n\n```json\n{"total": 120}\n```';
const tokens=md.parse(input,{}), ids=new Set(), links=[];
for(let i=0;i<tokens.length;i++){if(tokens[i].type==='heading_open'){const base=tokens[i+1].content.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu,'').trim().replace(/\s+/g,'-')||'section';let id=base,n=1;while(ids.has(id))id=base+'-'+ ++n;ids.add(id);tokens[i].attrSet('id',id);}}
function visit(ts){for(const t of ts){if(t.type==='link_open'){const h=t.attrGet('href');links.push(h);if(h==='private.md'){t.tag='span';t.attrs=[];}else t.attrSet('href', h.startsWith('#')?h:'/documents/guide/#호출');}if(t.children)visit(t.children);}}
visit(tokens);const html=md.renderer.render(tokens,md.options,{});
assert(html.includes('<table>'));assert(html.includes('id="금액-2"'));assert(!html.includes('<script>'));assert(!html.includes('href="javascript:'));assert(!html.includes('href="data:'));assert(!html.includes('href="private.md'));
const result={runtime:process.version,markdownIt:require(modulePath+'/package.json').version,inputs:[input,'# 설명\n\n## 호출\n\n검증된 호출 설명'],html,links,headings:[...ids],elapsed_ms:performance.now()-started,scope:'throwaway token experiment; not production markup (matching link-close handling still required), not HTTP authorization or independent semantic judgment',questions:[true,true,'Node and explicitly selected existing markdown-it module required; subprocess failures must be fail-closed'],model_usage:null};
fs.writeFileSync('/private/tmp/knowledge-reader-pages-plan/m0-result.json',JSON.stringify(result,null,2));console.log(JSON.stringify({passed:true,elapsed_ms:result.elapsed_ms,version:result.markdownIt}));
