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
# 폰트 임베드 — 있어야 할 것의 존재를 단언한다. 없어야 할 것의 부재로는 못 잡는다:
# main() 의 COMMENT_ANY 가 주석을 전부 지운 뒤에 잔존 검사가 돌아, 그 시점에는
# <!-- FONT:EMBED --> 가 이미 없다. LEFTOVER 에 'FONT:' 를 더해도 rc 는 0 그대로였다
# (실측 2026-08-22). 지우기 전의 draft 에서 마커를 찾는 길도 있으나, 그러면 마커를
# 손으로 지운 초안과 애초에 마커가 없는 초안이 통과한다 — 막으려는 것은 마커의
# 잔존이 아니라 폰트 없는 산출물이므로, 마커가 아니라 결과물을 본다.
#
# 두 번 좁힌다. ①키워드가 아니라 embed-font.py 의 FACE 가 내는 페이로드 형식을 보고
# ②그것도 <style> 요소의 텍스트 안에서만 본다(Balance 가 걷어온다). 판정 문자열이
# 사용자가 채우는 본문에 닿아 있으면 그 주제를 다루는 보고서 한 장이 검사를 꺼버린다 —
# '@font-face' 를 보던 판에서 <pre><code>@font-face …</code></pre> 를 본문에 한 번
# 넣은 사본이 폰트 0벌로 rc=0 을 받았다(실측 2026-08-22). 위의 창고 검사가 이름이
# 아니라 요소로 잡는 것과 같은 방향이고, <style> 안은 본문과 다른 문자열 공간이다.
EMBEDDED_FONT = re.compile(r'url\(data:font/woff2;base64,')

VOID = {'meta', 'link', 'br', 'hr', 'img', 'input', 'source', 'area', 'base', 'col',
        'embed', 'param', 'track', 'wbr', 'polyline', 'path', 'circle', 'rect', 'line'}


class Balance(HTMLParser):
    """태그 균형을 세면서 <style> 요소의 텍스트를 함께 걷는다.

    두 벌 파싱하지 않으려고 한 파서에 얹었다 — 심은 산출물은 1MB 를 넘는다.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []
        self.style_css = []

    def handle_data(self, data):
        # <style> 안은 HTMLParser 가 CDATA 로 넘긴다. 본문의 <pre><code> 나
        # 이스케이프된 &lt;style&gt; 텍스트는 여기 들어오지 않는다(실측 2026-08-22).
        if self.stack and self.stack[-1][0] == 'style':
            self.style_css.append(data)

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
    fontless = [] if EMBEDDED_FONT.search(''.join(balance.style_css)) else [
        '<style> 에 심긴 폰트가 없다 — embed-font.py 를 finalize.py 보다 먼저 돌려라']

    for name, found in (('잔존 마커·못 채운 자리', leftover),
                        ('외부 참조', external),
                        ('폰트 임베드', fontless),
                        ('태그 균형', problems)):
        say(f'{name}: {len(found)}건' + (' ✓' if not found else ''))
        for line in found:
            say(f'  {line}')

    sys.stdout.write(out)
    return 1 if (leftover or external or fontless or problems) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
