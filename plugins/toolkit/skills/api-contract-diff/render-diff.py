#!/usr/bin/env python3
"""스냅샷 JSON 두 개(이전, 이후)를 받아 계약 변경 HTML 을 stdout 으로 낸다.

받는 것은 **스냅샷 파일**이지 커밋이 아니다. 커밋에서 스냅샷을 뽑는 것은
api-spec-viewer 스킬의 일이고, 이 파일은 그 산출물 둘만 본다.

사용법: render-diff.py <이전.json> <이후.json> > diff.html

ponytail: 모델은 이름으로 맞춘다. 스냅샷 스키마가 모듈 경로를 담지 않아
동명 모델은 한 항목으로 합쳐 비교한다(필드는 합집합). 모듈까지 가르려면
스냅샷 스키마가 먼저 바뀌어야 한다.
"""

import html
import json
import re
import sys

TOP_KEYS = ("framework", "endpoints", "models", "enums")
ITEM_KEYS = {
    "endpoints": ("method", "path", "request", "response"),
    "models": ("name", "fields"),
    "enums": ("name", "values"),
}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


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
    if not snap["endpoints"]:
        die(f"{path}: endpoints 가 0건이다")
    if not snap["models"]:
        die(f"{path}: models 가 0건이다")
    return snap


def models_by_name(snap):
    """동명 모델은 필드를 합집합으로 합친다. 스냅샷이 모듈을 구분하지 않기 때문이다."""
    out = {}
    for m in snap["models"]:
        bucket = out.setdefault(m["name"], [])
        for f in m["fields"]:
            if f not in bucket:
                bucket.append(f)
    return out


def type_models(type_str, known):
    return [n for n in IDENT.findall(type_str or "") if n in known]


def reachable(type_str, known):
    """타입에서 닿는 모델 이름 전부. 필드 타입을 따라 닫힐 때까지 넓힌다."""
    seen, stack = set(), type_models(type_str, known)
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        stack += [n for f in known[name] for n in type_models(f["type"], known)]
    return seen


def affected(model_name, snap, known):
    hits = []
    for ep in snap["endpoints"]:
        touched = reachable(ep["request"], known) | reachable(ep["response"], known)
        if model_name in touched:
            hits.append({"method": ep["method"], "path": ep["path"]})
    return hits


def diff_endpoints(before, after):
    def keyed(snap):
        return {(e["method"], e["path"]): e for e in snap["endpoints"]}

    b, a = keyed(before), keyed(after)
    added = [a[k] for k in sorted(a.keys() - b.keys())]
    removed = [b[k] for k in sorted(b.keys() - a.keys())]
    changed = []
    for k in sorted(a.keys() & b.keys()):
        if b[k]["request"] != a[k]["request"] or b[k]["response"] != a[k]["response"]:
            changed.append({
                "method": k[0], "path": k[1],
                "before": {"request": b[k]["request"], "response": b[k]["response"]},
                "after": {"request": a[k]["request"], "response": a[k]["response"]},
            })
    return {"added": added, "removed": removed, "changed": changed}


def diff_models(before, after):
    b, a = models_by_name(before), models_by_name(after)
    out = {
        "added": [{"name": n, "fields": a[n], "affected": affected(n, after, a)}
                  for n in sorted(a.keys() - b.keys())],
        "removed": [{"name": n, "fields": b[n], "affected": affected(n, before, b)}
                    for n in sorted(b.keys() - a.keys())],
        "changed": [],
    }
    for name in sorted(a.keys() & b.keys()):
        bf = {f["name"]: f["type"] for f in b[name]}
        af = {f["name"]: f["type"] for f in a[name]}
        added = [{"name": n, "type": af[n]} for n in sorted(af.keys() - bf.keys())]
        removed = [{"name": n, "type": bf[n]} for n in sorted(bf.keys() - af.keys())]
        retyped = [{"name": n, "before": bf[n], "after": af[n]}
                   for n in sorted(af.keys() & bf.keys()) if bf[n] != af[n]]
        if added or removed or retyped:
            out["changed"].append({
                "name": name, "added": added, "removed": removed, "retyped": retyped,
                "affected": affected(name, after, a),
            })
    return out


def build_diff(before, after):
    d = {"endpoints": diff_endpoints(before, after), "models": diff_models(before, after)}
    d["empty"] = not any(v for group in d.values() for v in group.values())
    return d


def embed(obj):
    """<script type=application/json> 안에 넣을 문자열. '<' 를 막아 태그 탈출을 없앤다."""
    return json.dumps(obj, ensure_ascii=False, sort_keys=True).replace("<", "\\u003c")


# api-spec-viewer/render.py 의 JSON 샘플 조작을 옮겨 온 것이다 — 두 화면의 복사
# 결과가 어긋나면 안 된다. 이 화면 고유의 것: 스냅샷 둘을 오가므로 useSnapshot 으로
# 문맥을 바꾸고, MODELS 는 위 models_by_name 과 같은 규칙으로 동명 모델의 필드를
# 합집합으로 담는다 — 카드의 필드 목록이 그 합집합에서 나오므로 샘플도 같아야 한다
# (뷰어는 첫 항목만 펼치되 "동명 N건" 배지로 그 사실을 알리고, 이 화면에는 그 배지가
# 없다). 복사 버튼은 pre 블록 없이 버튼만 낸다.
SHARED_JS = r"""
let MODELS = {}, ENUMS = {};
function useSnapshot(snap) {
  MODELS = {}; ENUMS = {};
  snap.models.forEach(m => {
    const bucket = MODELS[m.name] = MODELS[m.name] || [];
    m.fields.forEach(f => {
      const k = JSON.stringify(f);
      if (!bucket.some(x => JSON.stringify(x) === k)) bucket.push(f);
    });
  });
  snap.enums.forEach(e => { ENUMS[e.name] = e.values; });
}
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
function modelName(type) {
  const ids = String(type || '').match(/[A-Za-z_][A-Za-z0-9_]*/g) || [];
  return ids.find(n => MODELS[n]) || null;
}
function fieldsOf(name) { return MODELS[name] || []; }
function isList(type) {
  const t = String(type || '');
  return /\[\]\s*$/.test(t) ||
    /(^|[^A-Za-z0-9_])(List|list|Set|set|Collection|Iterable|Sequence|tuple|Tuple|Array|Flux|Page)\s*[<[]/.test(t);
}
function scalar(type) {
  const t = String(type || '').toLowerCase();
  if (/^\s*(void|none|null|nonetype)\s*$/.test(t)) return null;
  if (/\b(int|integer|long|short|byte|number)\b/.test(t)) return 0;
  if (/\b(float|double|decimal|bigdecimal)\b/.test(t)) return 0.0;
  if (/\b(bool|boolean)\b/.test(t)) return true;
  if (/\b(uuid)\b/.test(t)) return '00000000-0000-0000-0000-000000000000';
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
function copyButton(label, type) {
  const text = sampleText(type);
  const btn = document.createElement('button');
  btn.className = 'copy';
  if (text === null) { btn.disabled = true; btn.textContent = label + ' 없음'; return btn; }
  btn.textContent = label + ' JSON 샘플 복사';
  btn.onclick = () => copyText(text, btn);
  return btn;
}
"""

CSS = r"""
:root {
  --bg: #0d1117; --panel: #161b22; --line: #30363d; --fg: #c9d1d9; --dim: #8b949e;
  --accent: #58a6ff; --add: #7ee787; --add-bg: rgba(46,160,67,.15);
  --del: #f85149; --del-bg: rgba(248,81,73,.15);
  --chg: #d29922; --chg-bg: rgba(210,153,34,.13);
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 0 0 60px; background: var(--bg); color: var(--fg);
  font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", "Apple SD Gothic Neo", sans-serif;
}
code, pre, .path, .type { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
header { padding: 16px 22px; border-bottom: 1px solid var(--line); }
header h1 { margin: 0; font-size: 16px; font-weight: 600; }
.summary { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
.tag {
  border-radius: 999px; padding: 3px 11px; font-size: 12px; border: 1px solid var(--line);
}
.tag.add { color: var(--add); background: var(--add-bg); border-color: var(--add); }
.tag.del { color: var(--del); background: var(--del-bg); border-color: var(--del); }
.tag.chg { color: var(--chg); background: var(--chg-bg); border-color: var(--chg); }
.tag.zero { color: var(--dim); background: none; border-color: var(--line); }
main { padding: 18px 22px; max-width: 1000px; }
h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .06em; color: var(--dim); margin: 26px 0 10px; }
.card { border: 1px solid var(--line); border-left-width: 3px; border-radius: 8px; background: var(--panel); padding: 11px 14px; margin-bottom: 10px; }
.card.add { border-left-color: var(--add); }
.card.del { border-left-color: var(--del); }
.card.chg { border-left-color: var(--chg); }
.card-head { display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap; }
.badge { font-size: 11px; font-weight: 700; border-radius: 4px; padding: 1px 7px; }
.badge.add { color: var(--add); background: var(--add-bg); }
.badge.del { color: var(--del); background: var(--del-bg); }
.badge.chg { color: var(--chg); background: var(--chg-bg); }
.m { font-size: 11px; font-weight: 700; letter-spacing: .04em; }
.path { font-size: 13px; word-break: break-all; }
.name { font-size: 14px; font-weight: 600; }
.rows { margin-top: 8px; }
.row { padding: 2px 8px; border-radius: 4px; font-size: 12.5px; display: flex; gap: 8px; }
.row.add { background: var(--add-bg); color: var(--add); }
.row.del { background: var(--del-bg); color: var(--del); }
.row.chg { background: var(--chg-bg); color: var(--chg); }
.row .sign { width: 10px; font-weight: 700; }
.type { color: inherit; opacity: .8; }
.affected { margin-top: 9px; font-size: 12px; color: var(--dim); }
.affected .chip {
  display: inline-block; border: 1px solid var(--line); border-radius: 5px;
  padding: 1px 7px; margin: 3px 5px 0 0; color: var(--fg); font-size: 11.5px;
}
.buttons { margin-top: 10px; display: flex; gap: 8px; flex-wrap: wrap; }
.copy {
  border: 1px solid var(--line); background: var(--bg); color: var(--fg);
  border-radius: 6px; padding: 4px 10px; font-size: 11.5px; cursor: pointer;
}
.copy:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
.copy:disabled { color: var(--dim); cursor: default; }
.none { text-align: center; padding: 70px 20px; color: var(--dim); }
.none strong { display: block; font-size: 20px; color: var(--fg); margin-bottom: 8px; }
"""

PAGE = r"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API 계약 변경 — __FRAMEWORK__</title>
<style>__CSS__</style>
</head>
<body>
<header>
  <h1>API 계약 변경 — __FRAMEWORK__</h1>
  <div class="summary" id="summary"></div>
</header>
<main id="main"></main>
<script id="before" type="application/json">__BEFORE__</script>
<script id="after" type="application/json">__AFTER__</script>
<script id="diff" type="application/json">__DIFF__</script>
<script>
const BEFORE = JSON.parse(document.getElementById('before').textContent);
const AFTER = JSON.parse(document.getElementById('after').textContent);
const DIFF = JSON.parse(document.getElementById('diff').textContent);
__SHARED__

const main = document.getElementById('main');
const summary = document.getElementById('summary');

function tag(label, n, kind) {
  const s = document.createElement('span');
  s.className = 'tag ' + (n ? kind : 'zero');
  s.textContent = label + ' ' + n;
  summary.appendChild(s);
}
tag('엔드포인트 추가', DIFF.endpoints.added.length, 'add');
tag('엔드포인트 삭제', DIFF.endpoints.removed.length, 'del');
tag('엔드포인트 타입 변경', DIFF.endpoints.changed.length, 'chg');
tag('모델 추가', DIFF.models.added.length, 'add');
tag('모델 삭제', DIFF.models.removed.length, 'del');
tag('모델 필드 변경', DIFF.models.changed.length, 'chg');

function section(title) {
  const h = document.createElement('h2');
  h.textContent = title;
  main.appendChild(h);
}
function affectedBlock(list) {
  if (!list.length) return null;
  const d = document.createElement('div');
  d.className = 'affected';
  d.innerHTML = '영향받는 엔드포인트 ' + list.length + '개' +
    list.map(e => '<span class="chip">' + esc(e.method) + ' ' + esc(e.path) + '</span>').join('');
  return d;
}
function epCard(ep, badge, kind, types) {
  const c = document.createElement('div');
  c.className = 'card ' + kind;
  c.innerHTML = '<div class="card-head"><span class="badge ' + kind + '">' + esc(badge) + '</span>' +
    '<span class="m">' + esc(ep.method) + '</span><span class="path">' + esc(ep.path) + '</span></div>';
  const rows = document.createElement('div');
  rows.className = 'rows';
  rows.innerHTML = types;
  c.appendChild(rows);
  const btns = document.createElement('div');
  btns.className = 'buttons';
  btns.appendChild(copyButton('요청', ep.request));
  btns.appendChild(copyButton('응답', ep.response));
  c.appendChild(btns);
  main.appendChild(c);
}
function typeRow(sign, kind, label, value) {
  return '<div class="row ' + kind + '"><span class="sign">' + sign + '</span>' +
    '<span>' + esc(label) + '</span><span class="type">' + esc(value == null ? '(없음)' : value) + '</span></div>';
}

if (DIFF.empty) {
  main.innerHTML = '<div class="none"><strong>변경 없음</strong>' +
    '두 스냅샷의 엔드포인트와 모델이 같다. 빈 diff 는 오류가 아니다.</div>';
} else {
  if (DIFF.endpoints.removed.length) {
    section('삭제된 엔드포인트');
    useSnapshot(BEFORE);
    DIFF.endpoints.removed.forEach(ep => epCard(ep, '삭제', 'del',
      typeRow('-', 'del', '요청', ep.request) + typeRow('-', 'del', '응답', ep.response)));
  }
  useSnapshot(AFTER);
  if (DIFF.endpoints.added.length) {
    section('추가된 엔드포인트');
    DIFF.endpoints.added.forEach(ep => epCard(ep, '추가', 'add',
      typeRow('+', 'add', '요청', ep.request) + typeRow('+', 'add', '응답', ep.response)));
  }
  if (DIFF.endpoints.changed.length) {
    section('요청·응답 타입이 바뀐 엔드포인트');
    DIFF.endpoints.changed.forEach(ch => {
      let rows = '';
      ['request', 'response'].forEach(k => {
        if (ch.before[k] === ch.after[k]) return;
        const label = k === 'request' ? '요청' : '응답';
        rows += typeRow('-', 'del', label + ' (이전)', ch.before[k]);
        rows += typeRow('+', 'add', label + ' (이후)', ch.after[k]);
      });
      epCard({ method: ch.method, path: ch.path, request: ch.after.request, response: ch.after.response },
        '타입 변경', 'chg', rows);
    });
  }
  if (DIFF.models.changed.length) {
    section('필드가 바뀐 모델');
    DIFF.models.changed.forEach(m => {
      const c = document.createElement('div');
      c.className = 'card chg';
      c.innerHTML = '<div class="card-head"><span class="badge chg">필드 변경</span>' +
        '<span class="name">' + esc(m.name) + '</span></div>';
      const rows = document.createElement('div');
      rows.className = 'rows';
      rows.innerHTML =
        m.added.map(f => typeRow('+', 'add', f.name, f.type)).join('') +
        m.removed.map(f => typeRow('-', 'del', f.name, f.type)).join('') +
        m.retyped.map(f => typeRow('~', 'chg', f.name, f.before + ' → ' + f.after)).join('');
      c.appendChild(rows);
      const a = affectedBlock(m.affected);
      if (a) c.appendChild(a);
      main.appendChild(c);
    });
  }
  if (DIFF.models.added.length) {
    section('추가된 모델');
    DIFF.models.added.forEach(m => {
      const c = document.createElement('div');
      c.className = 'card add';
      c.innerHTML = '<div class="card-head"><span class="badge add">추가</span>' +
        '<span class="name">' + esc(m.name) + '</span></div>' +
        '<div class="rows">' + m.fields.map(f => typeRow('+', 'add', f.name, f.type)).join('') + '</div>';
      const a = affectedBlock(m.affected);
      if (a) c.appendChild(a);
      main.appendChild(c);
    });
  }
  if (DIFF.models.removed.length) {
    section('삭제된 모델');
    DIFF.models.removed.forEach(m => {
      const c = document.createElement('div');
      c.className = 'card del';
      c.innerHTML = '<div class="card-head"><span class="badge del">삭제</span>' +
        '<span class="name">' + esc(m.name) + '</span></div>' +
        '<div class="rows">' + m.fields.map(f => typeRow('-', 'del', f.name, f.type)).join('') + '</div>';
      const a = affectedBlock(m.affected);
      if (a) c.appendChild(a);
      main.appendChild(c);
    });
  }
}
</script>
</body>
</html>
"""


def render(before, after, diff):
    return (PAGE
            .replace("__CSS__", CSS)
            .replace("__SHARED__", SHARED_JS)
            .replace("__FRAMEWORK__", html.escape(after["framework"]))
            .replace("__BEFORE__", embed(before))
            .replace("__AFTER__", embed(after))
            .replace("__DIFF__", embed(diff)))


def main(argv):
    if len(argv) != 3:
        print("사용법: render-diff.py <이전.json> <이후.json> > diff.html", file=sys.stderr)
        return 2
    before = load_snapshot(argv[1])
    after = load_snapshot(argv[2])
    # 형태가 다른 것을 억지로 비교하지 않는다.
    if before["framework"] != after["framework"]:
        die(f"프레임워크가 다르다: {argv[1]}={before['framework']} · {argv[2]}={after['framework']}")
    sys.stdout.write(render(before, after, build_diff(before, after)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
