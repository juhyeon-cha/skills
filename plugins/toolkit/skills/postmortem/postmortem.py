#!/usr/bin/env python3
"""사고 회고 드라이버 — 사고 기록 하나를 회고 초안 HTML 로 만든다.

    python3 postmortem.py <사고기록.json> > 초안.html

**축적하지 않는다.** 입력을 그때그때 받고 홈 아래에 아무것도 쓰지 않는다 — 회고는 그
사고 한 건의 문서라, 쌓아서 훑을 대상이 아니다(쌓는 쪽은 형제 스킬 brag 다).

초안은 stdout 으로 나온다. 그 뒤는 html-report 와 같은 경로이고 순서도 같다:

    python3 ../html-report/embed-font.py 초안.html pretendard > 초안-font.html
    python3 ../html-report/finalize.py 초안-font.html > 회고.html

**시각 정보가 없으면 경과 기록 섹션을 짓지 않는다.** `timeline` 이 비어 있으면 그
섹션을 통째로 빼고, 뺐다는 사실을 산출물에 한 줄로 적는다. 없는 시각을 그럴듯하게
채우는 것은 사고 기록에서 가장 비싼 거짓말이다.

종료 코드: 0 통과 / 2 인자·입력이 틀림

표준 라이브러리만 쓴다. 새 의존성을 들이지 않는다.
"""
import html
import json
import re
import sys
from datetime import date
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / 'html-report' / 'template.html'
DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')

esc = html.escape


def die(msg, code=2):
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def need(d, keys, where):
    if not isinstance(d, dict):
        die(f'{where}: 객체가 아니다')
    blank = [k for k in keys if not str(d.get(k) or '').strip()]
    if blank:
        die(f'{where}: 빈 칸이 있다 — {" · ".join(blank)}')


def load(path):
    try:
        rec = json.load(open(path, encoding='utf-8'))
    except OSError as e:
        die(f'사고 기록을 읽지 못했다: {path} — {e}')
    except json.JSONDecodeError as e:
        die(f'사고 기록이 JSON 이 아니다: {path} — {e}')

    need(rec, ('title', 'date', 'impact'), path)
    if not DATE.match(rec['date']):
        die(f'{path}: date 는 YYYY-MM-DD 여야 한다 — {rec["date"]!r}')

    causes = rec.get('causes') or []
    if not causes:
        die(f'{path}: causes 가 비었다 — 원인 없는 회고는 재발 방지도 없다')
    for i, c in enumerate(causes):
        need(c, ('cause', 'action', 'prevention'), f'{path} causes[{i}]')

    actions = rec.get('actions') or []
    if not actions:
        die(f'{path}: actions 가 비었다 — 남은 일이 없는 회고는 끝난 회고가 아니다')
    for i, a in enumerate(actions):
        need(a, ('todo', 'owner', 'due'), f'{path} actions[{i}]')

    for i, t in enumerate(rec.get('timeline') or []):
        need(t, ('when', 'what'), f'{path} timeline[{i}]')
    return rec


def put(doc, name, markup):
    """SECTION 블록 하나를 통째로 갈아 끼운다. markup 이 빈 문자열이면 그 섹션은 사라진다."""
    n = re.escape(name)
    pat = re.compile(r'[ \t]*<!--\s*SECTION:\s*%s\s*\|.*?<!--\s*/SECTION:\s*%s\s*-->[ \t]*\n?'
                     % (n, n), re.S)
    out, hit = pat.subn(lambda _: markup, doc)
    if hit != 1:
        die(f'템플릿의 SECTION: {name} 자리가 {hit}개다 — 1개여야 한다: {TEMPLATE}')
    return out


def callout(cls, label, text):
    return (f'        <div class="callout {cls}"><span class="label">{label}</span>'
            f'<p>{esc(str(text))}</p></div>\n')


def render(rec):
    try:
        doc = open(TEMPLATE, encoding='utf-8').read()
    except OSError as e:
        die(f'템플릿을 읽지 못했다: {e}')

    causes, actions = rec['causes'], rec['actions']
    events = rec.get('timeline') or []
    title = str(rec['title'])
    doc = doc.replace('<title>{{제목}}</title>', f'<title>{esc(title)}</title>')

    doc = put(doc, '표지',
              '      <header class="cover">\n'
              '        <p class="eyebrow">사고 회고</p>\n'
              '        <div class="cover-head">\n'
              f'          <h1>{esc(title)}</h1>\n'
              '          <span class="classification">대외비</span>\n'
              '        </div>\n'
              f'        <p class="lede">{esc(str(rec["impact"]))}</p>\n'
              '        <dl class="docmeta">\n'
              f'          <div><dt>부서</dt><dd>{esc(str(rec.get("team") or "미기재"))}</dd></div>\n'
              f'          <div><dt>작성일</dt><dd>{date.today().isoformat()}</dd></div>\n'
              f'          <div><dt>작성자</dt><dd>{esc(str(rec.get("author") or "미기재"))}</dd></div>\n'
              '        </dl>\n'
              '      </header>\n')

    lines = [str(s) for s in (rec.get('summary') or [])]
    if not lines:
        lines = [f'{rec["date"]} 발생. {rec["impact"]}',
                 f'원인 {len(causes)}건을 세웠고 각각에 조치와 재발 방지를 붙였다.',
                 f'남은 일은 액션 아이템 {len(actions)}건이다.']
    doc = put(doc, '한눈에',
              '      <section class="summary">\n        <ul>\n'
              + ''.join(f'          <li>{esc(s)}</li>\n' for s in lines)
              + '        </ul>\n      </section>\n')

    body = []
    if events:
        body.append('      <section>\n        <h2>경과</h2>\n        <ol class="timeline">\n')
        for t in events:
            body.append(f'          <li><span class="when">{esc(str(t["when"]))}</span>'
                        f'<span class="what">{esc(str(t["what"]))}</span>')
            if str(t.get('detail') or '').strip():
                body.append(f'<p>{esc(str(t["detail"]))}</p>')
            body.append('</li>\n')
        body.append('        </ol>\n      </section>\n')
    else:
        # 시각이 없으면 지어내지 않는다. 뺐다는 사실만 한 줄로 남긴다.
        # 이 문구에 경과 섹션의 표시(ol.timeline · 그 한글 이름)를 쓰지 않는다 —
        # "섹션이 빠졌는가" 를 표시의 건수로 세는 판정을 이 안내가 되살리면 안 된다.
        body.append('      <div class="callout warn"><span class="label">경과 기록 없음</span>'
                    '<p>입력에 시각 정보가 한 건도 없어 경과 기록 섹션을 넣지 않았다. '
                    '사고가 어떤 순서로 진행됐는지는 이 문서로 확인되지 않는다.</p></div>\n')

    body.append('      <section>\n        <h2>원인 · 조치 · 재발 방지</h2>\n')
    for i, c in enumerate(causes, 1):
        body.append(f'        <h3>{i}. {esc(str(c.get("title") or c["cause"]))}</h3>\n')
        body.append(callout('warn', '원인', c['cause']))
        body.append(callout('info', '조치', c['action']))
        body.append(callout('emph', '재발 방지', c['prevention']))
    body.append('      </section>\n')
    doc = put(doc, '본문', ''.join(body))

    verdict = str(rec.get('conclusion') or '').strip() or (
        f'원인 {len(causes)}건에 대한 조치는 위와 같고, 아직 하지 않은 일은 다음 단계의 '
        f'액션 아이템 {len(actions)}건이다. 재발 방지 칸에 적힌 것 중 액션 아이템으로 '
        '내려오지 않은 것은 이미 끝난 것이다.')
    doc = put(doc, '결론',
              '      <section>\n        <h2>결론</h2>\n'
              f'        <p>{esc(verdict)}</p>\n      </section>\n')

    rows = ''.join(f'                <tr><td>{esc(str(a["todo"]))}</td>'
                   f'<td>{esc(str(a["owner"]))}</td>'
                   f'<td>{esc(str(a["due"]))}</td></tr>\n' for a in actions)
    doc = put(doc, '다음 단계',
              '      <section>\n        <h2>액션 아이템</h2>\n'
              '        <div class="table-wrap">\n          <table>\n'
              '            <thead>\n'
              '              <tr><th>할 일</th><th>담당</th><th>기한</th></tr>\n'
              '            </thead>\n            <tbody>\n' + rows
              + '            </tbody>\n          </table>\n        </div>\n      </section>\n')

    refs = [str(r) for r in (rec.get('refs') or [])]
    doc = put(doc, '참고',
              ('      <section class="refs">\n        <h2>참고</h2>\n        <ul>\n'
               + ''.join(f'          <li>{esc(r)}</li>\n' for r in refs)
               + '        </ul>\n      </section>\n') if refs else '')

    doc = put(doc, '꼬리말',
              '      <footer class="colophon">\n        <p class="notice">\n'
              '          <span>이 문서는 대외비입니다. 수신자 외 열람·배포를 금합니다.</span>\n'
              '          <span class="classification">대외비</span>\n'
              '        </p>\n      </footer>\n')

    print(f'초안: 경과 {len(events)}건'
          + (' (시각 정보가 없어 경과 기록 섹션을 뺐다)' if not events else '')
          + f' · 원인 {len(causes)}건 · 액션 아이템 {len(actions)}건', file=sys.stderr)
    sys.stdout.write(doc)
    return 0


def main(argv):
    if len(argv) != 2:
        die(__doc__)
    return render(load(argv[1]))


if __name__ == '__main__':
    sys.exit(main(sys.argv))
