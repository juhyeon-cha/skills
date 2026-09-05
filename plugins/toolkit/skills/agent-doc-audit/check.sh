#!/usr/bin/env bash
# agent-doc-audit 의 기계 탐지. 인자로 받은 디렉토리 아래 *.md 전수(CHANGELOG.md 는 뺀다)를 훑어 SKILL.md 의
# 기계로 잡히는 후보를 stdout 에 낸다 — 판정은 사람과 에이전트의 읽기 단계 몫이고 이 스크립트는
# 후보만 낸다(rc 0 은 "탐지를 돌렸다" 이지 "후보 0건" 이 아니다).
#
#   check.sh <디렉토리> [<디렉토리>…] [--root <디렉토리>]…
#
# <디렉토리> 는 훑는 자리이고 --root 는 훑지 않되 경로 실재만 대조하는 자리다 — 플러그인 문서가
# 하네스 루트의 docs/ 를 가리키면 그 루트를 --root 로 준다(그 트리의 투영까지 훑지 않으려고).
#
# 출력 한 줄 = 파일:줄:기준:문장. 기준 표지는 SKILL.md 의 번호를 앞에 단다:
#   4-date          YYYY-MM-DD 날짜
#   4-line-pointer  파일 경로 뒤의 :<줄 번호>
#   1-correction    정정 어휘 (종전 · 이전에는 · 바로잡 · 정정)
#   6-dead-path     백틱 안 경로가 실재하지 않는다 — 파일의 디렉토리 · 인자로 받은 디렉토리 전부 · CWD
#                   어디서도 test -e 가 거짓. 자리표시자(<…> ${…} * ~ 공백)와 URL 은 보지 않고, 경로로
#                   읽는 것은 마지막 조각에 점이 있거나 / 로 끝나거나 ./ 또는 / 로 시작하는 것뿐이다.
#                   문서가 다른 트리를 가리키면 그 트리를 --root 로 넘겨라 — 그러면 살아 있는 경로로 읽는다.
#   7-korean        한글이 든 줄 — 백틱·따옴표("…" '…' “…” 「…」) 안과 마크다운 제목 줄, 펜스 코드 블록은 뺀다
#
# 입력 디렉토리가 없거나 인자가 없으면 rc≠0 + stderr. 대상 *.md 가 0개여도 rc≠0 — 빈 집합의 탐지는
# 탐지가 아니다.

set -uo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

SCAN=""; ROOTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ -n "${2:-}" ] || fail "--root 뒤에 디렉토리가 없다"; ROOTS="$ROOTS $2"; shift 2 ;;
    -*) fail "모르는 옵션: $1 (사용: check.sh <디렉토리> [<디렉토리>…] [--root <디렉토리>]…)" ;;
    *) SCAN="$SCAN $1"; shift ;;
  esac
done
[ -n "$SCAN" ] || fail "사용: check.sh <디렉토리> [<디렉토리>…] [--root <디렉토리>]…"
for d in $SCAN $ROOTS; do
  [ -d "$d" ] || fail "디렉토리가 없다: $d"
done

# CHANGELOG.md 는 뺀다 — 이력은 호출 자리가 아니므로 옛 경로·날짜가 그대로 맞다.
# shellcheck disable=SC2086
FILES=$(find $SCAN -type f -name '*.md' -not -name CHANGELOG.md | sort)
[ -n "$FILES" ] || fail "대상 *.md 가 0개다:$SCAN"

# 한 파일을 훑는 탐지기. 정규식과 UTF-8 처리를 한 곳에 두려고 perl 하나로 한다(macOS 기본 탑재).
PROG='
use utf8; use strict; use warnings;
use File::Basename qw(dirname);
binmode STDOUT, ":encoding(UTF-8)";
my ($file, @roots) = @ARGV;
open my $fh, "<:encoding(UTF-8)", $file or die "open $file: $!";
my $dir = dirname($file);
my $fence = 0; my $n = 0;
sub alive { my $p = shift; for my $b ($dir, @roots, ".") { return 1 if -e "$b/$p" } return -e $p ? 1 : 0 }
while (my $line = <$fh>) {
  $n++; chomp $line;
  if ($line =~ /^\s*(```|~~~)/) { $fence = !$fence; next; }
  my @hits;
  push @hits, "4-date"         if $line =~ /(?<![\d.])\d{4}-\d{2}-\d{2}(?![\d.])/;
  push @hits, "4-line-pointer" if $line =~ /[\w.\/-]+\.[A-Za-z]+:\d+/;
  push @hits, "1-correction"   if $line =~ /종전|이전에는|바로잡|정정/;
  my $dead = 0;
  while ($line =~ /`([^`]+)`/g) {
    my $p = $1;
    next if $p =~ /[\s<>\$\*~|]/ || $p =~ /^https?:/ || $p =~ /^\//;
    $p =~ s/:\d+$//; $p =~ s/[.,;:)]+$//;
    next unless $p =~ m{/};
    my ($last) = $p =~ m{([^/]*)$};
    next unless $p =~ m{/$} || $p =~ m{^\./} || $last =~ /\./;
    $dead = 1 unless alive($p);
  }
  push @hits, "6-dead-path" if $dead;
  unless ($fence || $line =~ /^\s*#/) {
    my $s = $line;
    $s =~ s/`[^`]*`//g; $s =~ s/"[^"]*"//g; $s =~ s/“[^”]*”//g; $s =~ s/「[^」]*」//g;
    $s =~ s/\x27[^\x27]*[가-힣][^\x27]*\x27//g;
    push @hits, "7-korean" if $s =~ /[가-힣]/;
  }
  print "$file:$n:$_:$line\n" for @hits;
}
'

rc=0
for f in $FILES; do
  # shellcheck disable=SC2086
  perl -e "$PROG" "$f" $SCAN $ROOTS || rc=1
done
[ "$rc" -eq 0 ] || fail "탐지기가 죽은 파일이 있다 — 위 stderr"
exit 0
