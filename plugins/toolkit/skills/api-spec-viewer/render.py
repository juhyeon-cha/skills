#!/usr/bin/env python3
"""스냅샷 JSON 하나를 받아 자체 포함 HTML 카탈로그를 stdout 으로 낸다.

입력은 extract-spring.py · extract-fastapi.py 가 내는 스냅샷이고,
그 형태는 같은 폴더의 snapshot-schema.md 가 정의한다.

사용법: render.py <스냅샷.json> > out.html

화면은 playground 스킬의 data-explorer 를 출발점으로 한다. 다른 점 하나 —
playground 의 "프롬프트 출력 + 복사 버튼" 자리는 선택한 엔드포인트의
요청/응답 JSON 샘플 복사로 쓴다 (사용자 결정 2026-08-29).

ponytail: 타입 이름 → 모델 연결은 타입 문자열에서 식별자를 뽑아 모델 이름과
맞춰 보는 것까지다. 제네릭 인자가 여럿인 타입(Map<K,V>)은 첫 모델만 펼친다.
동명 모델은 첫 항목을 펼치고 개수만 알린다 — 모듈 경로까지 담으려면 스냅샷
스키마가 먼저 바뀌어야 한다.
"""

import html
import json
import sys

TOP_KEYS = ("framework", "endpoints", "models", "enums")
ITEM_KEYS = {
    "endpoints": ("method", "path", "request", "response"),
    "models": ("name", "fields"),
    "enums": ("name", "values"),
}


def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def load_snapshot(path):
    """읽고 스키마를 단언한다. 없는 키는 이름을 stderr 에 찍는다."""
    try:
        with open(path, encoding="utf-8") as f:
            snap = json.load(f)
    except OSError as e:
        die(f"스냅샷을 열 수 없다: {path} ({e.strerror})")
    except json.JSONDecodeError as e:
        die(f"스냅샷이 JSON 이 아니다: {path} ({e})")
    if not isinstance(snap, dict):
        die(f"{path}: 최상위가 객체가 아니다")
    absent = [k for k in TOP_KEYS if k not in snap]
    if absent:
        die(f"{path}: 최상위 키가 없다 — {', '.join(absent)}")
    if not isinstance(snap["framework"], str):
        die(f"{path}: framework 가 문자열이 아니다")
    for key, required in ITEM_KEYS.items():
        if not isinstance(snap[key], list):
            die(f"{path}: {key} 가 배열이 아니다")
        for i, item in enumerate(snap[key]):
            if not isinstance(item, dict):
                die(f"{path}: {key}[{i}] 가 객체가 아니다")
            missing = [k for k in required if k not in item]
            if missing:
                die(f"{path}: {key}[{i}] 에 키가 없다 — {', '.join(missing)}")
    # 빈 결과를 성공으로 내면 "추출이 실패했다" 와 "볼 것이 없다" 가 구분되지 않는다.
    if not snap["endpoints"]:
        die(f"{path}: endpoints 가 0건이다 — 빈 화면을 성공으로 내지 않는다")
    if not snap["models"]:
        die(f"{path}: models 가 0건이다")
    return snap


def embed(snap):
    """<script type=application/json> 안에 넣을 문자열. '<' 를 막아 태그 탈출을 없앤다."""
    return json.dumps(snap, ensure_ascii=False, sort_keys=True).replace("<", "\\u003c")


# 타입 → 모델 연결, JSON 샘플 생성, 복사 버튼. 두 스킬이 같은 조작을 내야 해서
# api-contract-diff/render-diff.py 도 같은 함수를 담는다.
SHARED_JS = r"""
const MODELS = {};
DATA.models.forEach(m => { (MODELS[m.name] = MODELS[m.name] || []).push(m); });
const ENUMS = {};
DATA.enums.forEach(e => { ENUMS[e.name] = e.values; });

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
function modelName(type) {
  const ids = String(type || '').match(/[A-Za-z_][A-Za-z0-9_]*/g) || [];
  return ids.find(n => MODELS[n]) || null;
}
function fieldsOf(name) { return MODELS[name] ? MODELS[name][0].fields : []; }
function isList(type) {
  const t = String(type || '');
  return /\[\]\s*$/.test(t) ||
    /(^|[^A-Za-z0-9_])(List|list|Set|set|Collection|Iterable|Sequence|tuple|Tuple|Array|Flux|Page)\s*[<[]/.test(t);
}
function scalar(type) {
  const t = String(type || '').toLowerCase();
  // 타입 전체가 없음일 때만 null 이다. 'str | None' 은 문자열이지 null 이 아니다.
  if (/^\s*(void|none|null|nonetype)\s*$/.test(t)) return null;
  if (/\b(int|integer|long|short|byte|number)\b/.test(t)) return 0;
  if (/\b(float|double|decimal|bigdecimal)\b/.test(t)) return 0.0;
  if (/\b(bool|boolean)\b/.test(t)) return true;
  if (/\b(uuid)\b/.test(t)) return '00000000-0000-0000-0000-000000000000';
  // 낱말 경계를 요구하지 않는다 — LocalDateTime · datetime 처럼 붙여 쓰는 표기가 흔하다.
  if (/(date|time|instant|timestamp)/.test(t)) return '2026-01-01T00:00:00Z';
  if (ENUMS[type] && ENUMS[type].length) return ENUMS[type][0];
  return 'string';
}
function sampleFor(type, seen) {
  if (!type) return null;
  const name = modelName(type);
  let value;
  if (name && !seen.has(name)) {
    const next = new Set(seen); next.add(name);
    value = {};
    fieldsOf(name).forEach(f => { value[f.name] = sampleFor(f.type, next); });
  } else if (name) {
    value = { '…': name + ' (순환 참조)' };
  } else {
    value = scalar(type);
  }
  return isList(type) ? [value] : value;
}
function sampleText(type) {
  if (!type) return null;
  return JSON.stringify(sampleFor(type, new Set()), null, 2);
}
function flash(btn, text) {
  const was = btn.textContent;
  btn.textContent = text;
  setTimeout(() => { btn.textContent = was; }, 1200);
}
function copyText(text, btn) {
  const fallback = () => {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    ta.remove();
    flash(btn, ok ? '복사됨' : '복사 실패 — 직접 선택해라');
  };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(() => flash(btn, '복사됨'), fallback);
  } else {
    fallback();
  }
}
function sampleBlock(label, type) {
  const box = document.createElement('div');
  box.className = 'sample';
  const head = document.createElement('div');
  head.className = 'sample-head';
  head.innerHTML = '<span>' + esc(label) + '</span>';
  const pre = document.createElement('pre');
  const text = sampleText(type);
  pre.textContent = text === null ? '(없음)' : text;
  if (text !== null) {
    const btn = document.createElement('button');
    btn.className = 'copy';
    btn.textContent = 'JSON 샘플 복사';
    btn.onclick = () => copyText(text, btn);
    head.appendChild(btn);
  }
  box.appendChild(head); box.appendChild(pre);
  return box;
}
function enumHint(type) {
  const vals = ENUMS[type];
  if (!vals || !vals.length) return '';
  return '<span class="enum">' + esc(vals.join(' · ')) + '</span>';
}
function buildTree(container, fields, seen, depth) {
  fields.forEach(f => {
    const name = modelName(f.type);
    const kids = (name && !seen.has(name) && depth < 8) ? fieldsOf(name) : [];
    const label = '<span class="fname">' + esc(f.name) + '</span>' +
      '<span class="ftype">' + esc(f.type) + '</span>' +
      (name && MODELS[name].length > 1 ? '<span class="dup">동명 ' + MODELS[name].length + '건</span>' : '');
    if (kids.length) {
      const d = document.createElement('details');
      const s = document.createElement('summary');
      s.innerHTML = label;
      d.appendChild(s);
      const box = document.createElement('div');
      box.className = 'kids';
      const next = new Set(seen); next.add(name);
      buildTree(box, kids, next, depth + 1);
      d.appendChild(box);
      container.appendChild(d);
    } else {
      const row = document.createElement('div');
      row.className = 'leaf';
      row.innerHTML = label + enumHint(f.type);
      container.appendChild(row);
    }
  });
}
function schemaBlock(label, type) {
  const box = document.createElement('div');
  box.className = 'schema';
  const head = document.createElement('div');
  head.className = 'schema-head';
  head.innerHTML = '<span>' + esc(label) + '</span><span class="ftype">' +
    esc(type == null ? '(없음)' : type) + '</span>';
  box.appendChild(head);
  const name = modelName(type);
  const tree = document.createElement('div');
  tree.className = 'tree';
  if (name && fieldsOf(name).length) {
    const seen = new Set([name]);
    buildTree(tree, fieldsOf(name), seen, 0);
  } else {
    tree.innerHTML = '<div class="leaf muted">' +
      (type == null ? '본문 없음' : '스냅샷에 이 타입의 모델이 없다') + '</div>';
  }
  box.appendChild(tree);
  return box;
}
"""

CSS = r"""
:root {
  --bg: #0d1117; --panel: #161b22; --line: #30363d; --fg: #c9d1d9;
  --dim: #8b949e; --accent: #58a6ff; --add: #7ee787; --del: #f85149; --warn: #d29922;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", "Apple SD Gothic Neo", sans-serif;
}
code, pre, .ftype, .path { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
header { padding: 14px 18px; border-bottom: 1px solid var(--line); }
header h1 { margin: 0; font-size: 16px; font-weight: 600; }
header .meta { color: var(--dim); font-size: 12px; margin-top: 4px; }
main { display: flex; align-items: stretch; height: calc(100vh - 62px); }
aside {
  width: 380px; min-width: 280px; border-right: 1px solid var(--line);
  display: flex; flex-direction: column;
}
.filters { padding: 12px; border-bottom: 1px solid var(--line); }
#q {
  width: 100%; padding: 7px 9px; border-radius: 6px; background: var(--bg);
  border: 1px solid var(--line); color: var(--fg); font-size: 13px;
}
#q:focus { outline: none; border-color: var(--accent); }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
.chip {
  border: 1px solid var(--line); background: var(--panel); color: var(--dim);
  border-radius: 999px; padding: 3px 10px; font-size: 11px; cursor: pointer;
}
.chip.on { color: var(--bg); background: var(--accent); border-color: var(--accent); font-weight: 600; }
.count { color: var(--dim); font-size: 11px; margin-top: 9px; }
#list { list-style: none; margin: 0; padding: 6px; overflow: auto; flex: 1; }
#list li {
  padding: 7px 9px; border-radius: 6px; cursor: pointer; display: flex; gap: 8px; align-items: baseline;
}
#list li:hover { background: var(--panel); }
#list li.on { background: #1f2937; }
.m { font-size: 10px; font-weight: 700; letter-spacing: .04em; min-width: 46px; }
.m.GET { color: var(--add); } .m.POST { color: var(--accent); }
.m.PUT, .m.PATCH { color: var(--warn); } .m.DELETE { color: var(--del); }
.path { font-size: 12px; word-break: break-all; }
section#detail { flex: 1; overflow: auto; padding: 18px 22px; }
.empty { color: var(--dim); padding-top: 40px; text-align: center; }
.ep-head { display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap; }
.ep-head .path { font-size: 15px; }
.schema, .sample { margin-top: 18px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }
.schema-head, .sample-head {
  display: flex; justify-content: space-between; align-items: center; gap: 10px;
  padding: 8px 12px; border-bottom: 1px solid var(--line); font-size: 12px; font-weight: 600;
}
.tree { padding: 6px 12px 10px; }
.kids { margin-left: 16px; border-left: 1px solid var(--line); padding-left: 10px; }
details > summary { cursor: pointer; padding: 2px 0; list-style-position: outside; }
.leaf { padding: 2px 0 2px 15px; }
.fname { margin-right: 8px; }
.ftype { color: var(--dim); font-size: 12px; }
.dup { color: var(--warn); font-size: 11px; margin-left: 8px; }
.enum { color: var(--add); font-size: 11px; margin-left: 8px; }
.muted { color: var(--dim); }
pre { margin: 0; padding: 10px 12px; overflow: auto; font-size: 12px; max-height: 320px; }
.copy {
  border: 1px solid var(--line); background: var(--bg); color: var(--fg);
  border-radius: 6px; padding: 3px 9px; font-size: 11px; cursor: pointer;
}
.copy:hover { border-color: var(--accent); color: var(--accent); }
"""

PAGE = r"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API 카탈로그 — __FRAMEWORK__</title>
<style>__CSS__</style>
</head>
<body>
<header>
  <h1>API 카탈로그 — __FRAMEWORK__</h1>
  <div class="meta">엔드포인트 __N_EP__개 · 모델 __N_MODEL__개 · enum __N_ENUM__개 · 스냅샷 JSON 은 이 HTML 옆에 따로 있다</div>
</header>
<main>
  <aside>
    <div class="filters">
      <input id="q" type="search" placeholder="경로·타입 검색" autocomplete="off">
      <div class="chips" id="chips"></div>
      <div class="count" id="count"></div>
    </div>
    <ul id="list"></ul>
  </aside>
  <section id="detail"><div class="empty">왼쪽에서 엔드포인트를 고른다.</div></section>
</main>
<script id="snapshot" type="application/json">__SNAPSHOT__</script>
<script>
const DATA = JSON.parse(document.getElementById('snapshot').textContent);
__SHARED__

const listEl = document.getElementById('list');
const detailEl = document.getElementById('detail');
const countEl = document.getElementById('count');
const qEl = document.getElementById('q');
const methods = [...new Set(DATA.endpoints.map(e => e.method))].sort();
const active = new Set(methods);
let selected = null;

const chipsEl = document.getElementById('chips');
methods.forEach(m => {
  const b = document.createElement('button');
  b.className = 'chip on';
  b.textContent = m;
  b.onclick = () => {
    if (active.has(m)) { active.delete(m); b.classList.remove('on'); }
    else { active.add(m); b.classList.add('on'); }
    renderList();
  };
  chipsEl.appendChild(b);
});

function visible() {
  const q = qEl.value.trim().toLowerCase();
  return DATA.endpoints.filter(e => {
    if (!active.has(e.method)) return false;
    if (!q) return true;
    return [e.method, e.path, e.request, e.response].join(' ').toLowerCase().includes(q);
  });
}
function renderList() {
  const rows = visible();
  countEl.textContent = rows.length + ' / ' + DATA.endpoints.length + '개';
  listEl.innerHTML = '';
  rows.forEach(e => {
    const li = document.createElement('li');
    li.innerHTML = '<span class="m ' + esc(e.method) + '">' + esc(e.method) + '</span>' +
      '<span class="path">' + esc(e.path) + '</span>';
    if (selected === e) li.classList.add('on');
    li.onclick = () => { selected = e; renderList(); renderDetail(e); };
    listEl.appendChild(li);
  });
  if (!rows.length) {
    listEl.innerHTML = '<li class="muted">맞는 엔드포인트가 없다</li>';
  }
}
function renderDetail(e) {
  detailEl.innerHTML = '';
  const head = document.createElement('div');
  head.className = 'ep-head';
  head.innerHTML = '<span class="m ' + esc(e.method) + '">' + esc(e.method) + '</span>' +
    '<span class="path">' + esc(e.path) + '</span>';
  detailEl.appendChild(head);
  detailEl.appendChild(schemaBlock('요청 스키마', e.request));
  detailEl.appendChild(sampleBlock('요청 JSON 샘플', e.request));
  detailEl.appendChild(schemaBlock('응답 스키마', e.response));
  detailEl.appendChild(sampleBlock('응답 JSON 샘플', e.response));
}
qEl.oninput = renderList;
renderList();
</script>
</body>
</html>
"""


def render(snap):
    return (PAGE
            .replace("__CSS__", CSS)
            .replace("__SHARED__", SHARED_JS)
            .replace("__FRAMEWORK__", html.escape(snap["framework"]))
            .replace("__N_EP__", str(len(snap["endpoints"])))
            .replace("__N_MODEL__", str(len(snap["models"])))
            .replace("__N_ENUM__", str(len(snap["enums"])))
            .replace("__SNAPSHOT__", embed(snap)))


def main(argv):
    if len(argv) != 2:
        print("사용법: render.py <스냅샷.json> > out.html", file=sys.stderr)
        return 2
    sys.stdout.write(render(load_snapshot(argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
