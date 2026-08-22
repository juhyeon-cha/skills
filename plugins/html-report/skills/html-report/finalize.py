#!/usr/bin/env python3
"""산출물 정리 드라이버 — 주석과 부품 창고를 지우고 §8 검사를 돌린다.

    python3 finalize.py <초안.html> > <산출물.html>

정리본은 stdout, 무엇을 몇 개 지웠고 무엇이 걸렸는지는 stderr, 판정은 종료 코드다.
입력 파일은 열기만 한다 — 도구가 죽어도 초안은 그대로 남는다.

종료 코드: 0 통과 / 1 검사에 걸림 / 2 입력을 읽지 못함
검사에 걸려도 stdout 에는 정리된 본문이 나온다. 그것은 완성본이 아니라 초안이고,
무엇을 고쳐야 하는지는 stderr 가 줄 번호로 말한다.

표준 라이브러리만 쓴다. 새 의존성을 들이지 않는다.
"""
import re
import sys
from html.parser import HTMLParser

# 부품 창고. 마커는 주석이지만 창고 본체는 <template> 요소라, 주석만 지우면
# 창고 마크업이 살아남으면서 잔존 마커 검사가 잡을 근거까지 사라진다. 통째로 지운다.
WAREHOUSE = re.compile(
    r'[ \t]*<!--\s*(PRESET|PALETTE):START.*?<!--\s*\1:END\s*-->[ \t]*\n?',
    re.S,
)
COMMENT_LINE = re.compile(r'(?m)^[ \t]*<!--.*?-->[ \t]*\n', re.S)
COMMENT_ANY = re.compile(r'<!--.*?-->', re.S)

# 잔존 검사 — 못 채운 자리와 지워지지 않은 창고. <template> 는 마커가 사라진
# 창고의 유일한 흔적이라 이름이 아니라 요소로 잡는다.
LEFTOVER = re.compile(r'\{\{|SECTION:|PRESET:|PALETTE:|<template[\s>]')
# 외부 참조 — 링크(<a href>)는 정상이고 가져다 쓰는 것이 위반이다.
EXTERNAL = re.compile(r'\ssrc\s*=|@import|url\(\s*[\'"]?https?:|<script[\s>]|<link[\s>]')

VOID = {'meta', 'link', 'br', 'hr', 'img', 'input', 'source', 'area', 'base', 'col',
        'embed', 'param', 'track', 'wbr', 'polyline', 'path', 'circle', 'rect', 'line'}


class Balance(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []

    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append((tag, self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack:
            self.errors.append(f'{self.getpos()[0]}행: </{tag}> 짝 없음')
            return
        open_tag, line = self.stack.pop()
        if open_tag != tag:
            self.errors.append(f'{self.getpos()[0]}행: </{tag}> 인데 열린 것은 <{open_tag}> ({line}행)')


def hits(pattern, text):
    return [f'{n}행: {line.strip()}'
            for n, line in enumerate(text.splitlines(), 1) if pattern.search(line)]


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        draft = open(argv[1], encoding='utf-8').read()
    except OSError as e:
        print(f'입력을 읽지 못했다: {e}', file=sys.stderr)
        return 2

    out, warehouses = WAREHOUSE.subn('', draft)
    comments = len(COMMENT_ANY.findall(out))
    out = COMMENT_ANY.sub('', COMMENT_LINE.sub('', out))

    say = lambda s: print(s, file=sys.stderr)
    say(f'지움: 부품 창고 {warehouses}개 · 주석 {comments}개 '
        f'({len(draft)}자 → {len(out)}자)')

    leftover, external = hits(LEFTOVER, out), hits(EXTERNAL, out)
    balance = Balance()
    balance.feed(out)
    unclosed = [f'{line}행: <{tag}> 안 닫힘' for tag, line in balance.stack]
    problems = balance.errors + unclosed

    for name, found in (('잔존 마커·못 채운 자리', leftover),
                        ('외부 참조', external),
                        ('태그 균형', problems)):
        say(f'{name}: {len(found)}건' + (' ✓' if not found else ''))
        for line in found:
            say(f'  {line}')

    sys.stdout.write(out)
    return 1 if (leftover or external or problems) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
