#!/usr/bin/env python3
"""성과 기록 축적·대시보드 드라이버.

    python3 brag.py add <항목.json>              한 건(또는 배열)을 홈 아래에 쌓는다
    python3 brag.py render [--team T] [--author A] > 초안.html

축적 자리는 **`~/.brag/entries.jsonl` 고정**이다. 프로젝트 디렉토리에는 아무것도 쓰지
않는다 — 성과는 여러 레포에 걸치고, 사내 레포에 개인 평가 기록이 커밋되면 안 된다.
쓸 수 없으면 다른 곳으로 흘리지 않고 그 사유로 끝난다.

render 는 html-report 의 template.html 을 채운 **초안**을 stdout 으로 낸다. 그 뒤는
그 스킬과 같은 경로이고 순서도 같다:

    python3 ../html-report/embed-font.py 초안.html pretendard > 초안-font.html
    python3 ../html-report/finalize.py 초안-font.html > 대시보드.html

종료 코드: 0 통과 / 1 쌓인 기록이 0건 / 2 인자·입력·축적 자리가 틀림

표준 라이브러리만 쓴다. 새 의존성을 들이지 않는다.
"""
import getpass
import html
import json
import os
import re
import sys
from datetime import date
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / 'html-report' / 'template.html'
STORE = ('.brag', 'entries.jsonl')  # 홈 아래 고정. SKILL.md 와 같은 값이다.
REQUIRED = ('date', 'project', 'title', 'problem', 'solution', 'result')
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
# 증감은 색만으로 구분하지 않는다(SKILL.md §9). 기호를 입력이 들고 오게 하고
# 여기서 강제한다 — 방향은 사실이고 pos/neg(좋아졌는가)는 판단이라 값이 둘이다.
ARROWS = '▲▼—'

esc = html.escape


def die(msg, code=2):
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def store():
    # 호출 시점에 읽는다 — HOME 을 바꿔 돌리는 검사가 그 값을 보게 하려고.
    return Path(os.path.expanduser('~')).joinpath(*STORE)


def check(e, where):
    if not isinstance(e, dict):
        die(f'{where}: 항목이 객체가 아니다')
    blank = [k for k in REQUIRED if not str(e.get(k) or '').strip()]
    if blank:
        die(f'{where}: 빈 칸이 있다 — {" · ".join(blank)}')
    if not DATE.match(e['date']):
        die(f'{where}: date 는 YYYY-MM-DD 여야 한다 — {e["date"]!r}')
    for i, m in enumerate(e.get('metrics') or []):
        at = f'{where} metrics[{i}]'
        if not isinstance(m, dict):
            die(f'{at}: 지표가 객체가 아니다')
        for k in ('label', 'to'):
            if not str(m.get(k) or '').strip():
                die(f'{at}: {k} 는 필수다')
        d = str(m.get('delta') or '')
        if d and d[0] not in ARROWS:
            die(f'{at}: delta 는 {" · ".join(ARROWS)} 중 하나로 시작해야 한다 '
                f'(색만으로 구분하지 않는다) — {d!r}')


def add(path):
    try:
        raw = json.load(open(path, encoding='utf-8'))
    except OSError as e:
        die(f'항목 파일을 읽지 못했다: {e}')
    except json.JSONDecodeError as e:
        die(f'항목 파일이 JSON 이 아니다 ({path}): {e}')

    items = raw if isinstance(raw, list) else [raw]
    if not items:
        die(f'항목이 0건이다: {path}')
    for i, e in enumerate(items):
        check(e, f'{path}[{i}]')

    target = store()
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, 'a', encoding='utf-8') as f:
            for e in items:
                f.write(json.dumps(e, ensure_ascii=False) + '\n')
    except OSError as e:
        die(f'축적 자리에 쓰지 못했다 ({target}): {e}')

    print(f'쌓음: {len(items)}건 → {target}', file=sys.stderr)
    return 0


def load():
    path = store()
    try:
        lines = [ln for ln in open(path, encoding='utf-8').read().splitlines() if ln.strip()]
    except FileNotFoundError:
        lines = []          # 아직 한 건도 안 쌓았다 — render 가 rc=1 로 알린다
    except OSError as e:
        die(f'축적 자리를 읽지 못했다 ({path}): {e}')  # 권한 등은 0건이 아니다
    entries = []
    for n, ln in enumerate(lines, 1):
        try:
            e = json.loads(ln)
        except json.JSONDecodeError as ex:
            die(f'{path}:{n} 이 JSON 이 아니다: {ex}')
        check(e, f'{path}:{n}')
        entries.append(e)
    return path, entries


def quarter(d):
    y, m = int(d[:4]), int(d[5:7])
    return f'{y}년 {(m - 1) // 3 + 1}분기'


def metric(m):
    val = esc(str(m['to']))
    if str(m.get('from') or '').strip():
        val = f'<span class="from">{esc(str(m["from"]))}</span> → {val}'
    out = [f'<span class="value">{val}</span>',
           f'<span class="label">{esc(str(m["label"]))}</span>']
    d = str(m.get('delta') or '').strip()
    if d:
        # 방향 없는 값(—)에 방향 색을 붙이지 않는다. template.html 의 .delta.flat.
        cls = 'flat' if d[0] == '—' else ('pos' if m.get('good', True) else 'neg')
        out.append(f'<span class="delta {cls}">{esc(d)}</span>')
    return '<div class="stat">' + ''.join(out) + '</div>'


def put(doc, name, markup):
    """SECTION 블록 하나를 통째로 갈아 끼운다. markup 이 빈 문자열이면 그 섹션은 사라진다."""
    n = re.escape(name)
    pat = re.compile(r'[ \t]*<!--\s*SECTION:\s*%s\s*\|.*?<!--\s*/SECTION:\s*%s\s*-->[ \t]*\n?'
                     % (n, n), re.S)
    out, hit = pat.subn(lambda _: markup, doc)
    if hit != 1:
        die(f'템플릿의 SECTION: {name} 자리가 {hit}개다 — 1개여야 한다: {TEMPLATE}')
    return out


def render(team, author):
    path, entries = load()
    if not entries:
        die(f'쌓인 기록이 없다: {path} — 먼저 `brag.py add <항목.json>` 으로 쌓아라', 1)

    entries.sort(key=lambda e: e['date'], reverse=True)
    groups = {}
    for e in entries:
        groups.setdefault(quarter(e['date']), []).append(e)
    projects = sorted({e['project'] for e in entries})
    span = f'{entries[-1]["date"]} ~ {entries[0]["date"]}'
    metrics = sum(len(e.get('metrics') or []) for e in entries)

    try:
        doc = open(TEMPLATE, encoding='utf-8').read()
    except OSError as e:
        die(f'템플릿을 읽지 못했다: {e}')

    title = f'성과 기록 {span}'
    doc = doc.replace('<title>{{제목}}</title>', f'<title>{esc(title)}</title>')

    doc = put(doc, '표지',
              '      <header class="cover">\n'
              '        <p class="eyebrow">성과 기록</p>\n'
              '        <div class="cover-head">\n'
              f'          <h1>{esc(title)}</h1>\n'
              '          <span class="classification">대외비</span>\n'
              '        </div>\n'
              f'        <p class="lede">{len(entries)}건을 {len(groups)}개 분기에 걸쳐 '
              '문제 · 해결 · 성과 세 칸으로 세웠다.</p>\n'
              '        <dl class="docmeta">\n'
              f'          <div><dt>부서</dt><dd>{esc(team)}</dd></div>\n'
              f'          <div><dt>작성일</dt><dd>{date.today().isoformat()}</dd></div>\n'
              f'          <div><dt>작성자</dt><dd>{esc(author)}</dd></div>\n'
              '        </dl>\n'
              '      </header>\n')

    doc = put(doc, '한눈에',
              '      <section class="summary">\n        <ul>\n'
              f'          <li>기록 {len(entries)}건 · {len(groups)}개 분기 · {esc(span)}</li>\n'
              f'          <li>프로젝트 {len(projects)}개: {esc(" · ".join(projects))}</li>\n'
              f'          <li>전·후 값이 붙은 지표 {metrics}건</li>\n'
              '        </ul>\n      </section>\n')

    body = []
    for q, group in groups.items():
        body.append(f'      <section>\n        <h2>{esc(q)}</h2>\n')
        for e in group:
            body.append(f'        <h3>{esc(e["title"])}</h3>\n')
            body.append('        <p class="table-note">'
                        f'{esc(e["project"])} · {esc(e["date"])}</p>\n')
            ms = e.get('metrics') or []
            if ms:
                body.append('        <div class="stats">'
                            + ''.join(metric(m) for m in ms) + '</div>\n')
            for cls, label, key in (('warn', '문제', 'problem'),
                                    ('info', '해결', 'solution'),
                                    ('emph', '성과', 'result')):
                body.append(f'        <div class="callout {cls}">'
                            f'<span class="label">{label}</span>'
                            f'<p>{esc(str(e[key]))}</p></div>\n')
        body.append('      </section>\n')
    doc = put(doc, '본문', ''.join(body))

    doc = put(doc, '결론',
              '      <section>\n        <h2>결론</h2>\n'
              f'        <p>위 {len(entries)}건이 이 기간에 쌓인 기록의 전부다. 성과 칸은 '
              '기록에 적힌 값만 담는다 — 비어 있는 것은 아직 확인되지 않았다는 뜻이지 '
              '없다는 뜻이 아니다.</p>\n      </section>\n')

    doc = put(doc, '다음 단계', '')
    doc = put(doc, '참고', '')
    doc = put(doc, '꼬리말',
              '      <footer class="colophon">\n        <p class="notice">\n'
              '          <span>이 문서는 대외비입니다. 수신자 외 열람·배포를 금합니다.</span>\n'
              '          <span class="classification">대외비</span>\n'
              '        </p>\n      </footer>\n')

    print(f'초안: 기록 {len(entries)}건 · {len(groups)}개 분기 · 지표 {metrics}건 '
          f'({path})', file=sys.stderr)
    sys.stdout.write(doc)
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == 'add':
        return add(argv[2])
    if len(argv) >= 2 and argv[1] == 'render':
        try:
            author = getpass.getuser()
        except Exception:
            author = '미기재'
        team, rest = '미기재', argv[2:]
        while rest:
            if rest[0] in ('--team', '--author') and len(rest) > 1:
                team, author = (rest[1], author) if rest[0] == '--team' else (team, rest[1])
                rest = rest[2:]
            else:
                die(__doc__)
        return render(team, author)
    return die(__doc__)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
