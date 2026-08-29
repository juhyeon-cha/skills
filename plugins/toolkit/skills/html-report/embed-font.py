#!/usr/bin/env python3
"""폰트 임베드 드라이버 — 저장본 woff2 를 base64 로 초안에 심는다.

    python3 embed-font.py <초안.html> <폰트키> > <산출물.html>

폰트키는 pretendard 또는 paperlogy 다. 심은 본문은 stdout, 무엇을 몇 바이트로
심었는지는 stderr, 판정은 종료 코드다. finalize.py 와 같은 규칙으로,
입력 파일은 열기만 한다 — 도구가 죽어도 초안은 그대로 남는다.

주입 지점은 초안의 <!-- FONT:EMBED --> 주석 한 줄이고, 그 줄이 통째로
<style> 블록으로 바뀐다. 굵기는 400 / 600 / 700 세 벌이다 — template.html 이
쓰는 굵기가 600(6곳) · 700(5곳) 과 body 기본 400 뿐이고 italic 은 0건이라
세 벌이 정확히 덮는다(실측 2026-08-22, grep).

CSS 상의 이름은 폰트키와 무관하게 항상 'ReportSans' 다. 폰트키는 둘인데
CSS 이름을 하나로 묶어두면 초안의 --font 항목이 하나로 끝나고, 키를 바꿔도
초안의 CSS 를 손대지 않는다. 초안의 --font 는 'ReportSans' 를 첫 자리에
두면 두 키 모두 그대로 걸린다.

실행 순서는 embed → finalize 다. 뒤집으면 finalize.py 가 HTML 주석을 지우면서
주입 지점이 사라져 종료 코드 1 로 끝난다.

폴백은 없다. 폰트 파일이 없거나 키가 틀리면 심지 않고 그 사유로 끝난다.

종료 코드: 0 통과 / 1 주입 지점이 없거나 여러 개 / 2 인자·키·파일이 틀림

표준 라이브러리만 쓴다. 새 의존성을 들이지 않는다.
"""
import base64
import re
import sys
from pathlib import Path

# 저장본의 파일명 규칙이 두 폰트에서 서로 다르다(Pretendard 는 -SemiBold,
# Paperlogy 는 -6SemiBold). 상류에서 받은 이름이라 바꾸지 않고 그대로 적는다 —
# FONT-LICENSE.md 가 이 6개 파일명으로 배포처와 커버리지 숫자를 묶어두므로,
# 이름을 바꾸면 그 고지가 가리키는 대상이 없어진다.
FONTS = {
    'pretendard': {
        400: 'Pretendard-Regular.subset.woff2',
        600: 'Pretendard-SemiBold.subset.woff2',
        700: 'Pretendard-Bold.subset.woff2',
    },
    'paperlogy': {
        400: 'Paperlogy-4Regular.woff2',
        600: 'Paperlogy-6SemiBold.woff2',
        700: 'Paperlogy-7Bold.woff2',
    },
}
FAMILY = 'ReportSans'
FONT_DIR = Path(__file__).resolve().parent / 'fonts'

# 주입 지점. 마커 줄을 통째로 삼켜 <style> 로 바꾼다 — 주석이 남으면
# finalize.py 가 지우면서 심지 않은 초안과 심은 산출물이 구분되지 않는다.
MARKER = re.compile(r'(?m)^[ \t]*<!--\s*FONT:EMBED\s*-->[ \t]*\n?')

FACE = """      @font-face {{
        font-family: '{family}';
        font-style: normal;
        font-weight: {weight};
        src: url(data:font/woff2;base64,{b64}) format('woff2');
      }}
"""


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    draft_path, key = argv[1], argv[2]
    if key not in FONTS:
        print(f'모르는 폰트키: {key!r} — 쓸 수 있는 것은 '
              + ' · '.join(sorted(FONTS)), file=sys.stderr)
        return 2

    try:
        draft = open(draft_path, encoding='utf-8').read()
    except OSError as e:
        print(f'초안을 읽지 못했다: {e}', file=sys.stderr)
        return 2

    faces, raw = [], 0
    for weight, name in sorted(FONTS[key].items()):
        try:
            data = (FONT_DIR / name).read_bytes()
        except OSError as e:
            print(f'폰트 파일을 읽지 못했다: {e}', file=sys.stderr)
            return 2
        raw += len(data)
        faces.append(FACE.format(family=FAMILY, weight=weight,
                                 b64=base64.b64encode(data).decode('ascii')))

    block = (f'    <style>\n'
             f'      /* {key} — SIL Open Font License 1.1. '
             f'저작권·커버리지는 fonts/FONT-LICENSE.md */\n'
             + ''.join(faces) + '    </style>\n')

    out, planted = MARKER.subn(lambda _: block, draft)
    say = lambda s: print(s, file=sys.stderr)
    if planted != 1:
        say(f'주입 지점 <!-- FONT:EMBED --> 이 {planted}개다 — 정확히 1개여야 한다.')
        return 1

    say(f'심음: {key} {len(faces)}벌 · 원본 {raw:,}바이트 → '
        f'본문 {len(draft):,}자 → {len(out):,}자')
    sys.stdout.write(out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
