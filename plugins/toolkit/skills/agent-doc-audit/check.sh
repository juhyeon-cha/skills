#!/usr/bin/env bash
# agent-doc-audit 의 기계 탐지. 인자로 받은 디렉토리 아래 *.md 전수(CHANGELOG.md 는 뺀다)와 *.sh 전수를
# 훑어 기계로 잡히는 후보를 stdout 에 낸다 — 판정은 사람과 에이전트의 읽기 단계 몫이고 이 스크립트는
# 후보만 낸다(rc 0 은 "탐지를 돌렸다" 이지 "후보 0건" 이 아니다).
#
#   check.sh <디렉토리> [<디렉토리>…] [--root <디렉토리>]…
#
# <디렉토리> 는 훑는 자리이고 --root 는 훑지 않되 경로 실재만 대조하는 자리다 — 플러그인 문서가
# 하네스 루트의 docs/ 를 가리키면 그 루트를 --root 로 준다(그 트리의 투영까지 훑지 않으려고).
#
# 출력 한 줄 = 파일:줄:기준:문장. 기준 표지는 SKILL.md 의 번호를 앞에 단다:
#   4-date          YYYY-MM-DD 날짜 — 펜스 코드 블록 안은 뺀다(예시 JSON 의 날짜는 데이터이지 주장이 아니다)
#   4-line-pointer  파일 경로 뒤의 :<줄 번호> — 펜스 코드 블록 안은 뺀다
#   1-correction    `정정` 어휘가 든 줄 (`종전` · `이전에는` · `바로잡` · `정정` · `was removed` ·
#                   `were removed` · `went away` · `used to be`) — 7-korean 과 같은 제거본 위에서만
#                   본다: 백틱·따옴표 안, 펜스, 제목 줄은 뺀다.
#   6-dead-path     백틱 안 경로가 실재하지 않는다 — 파일의 디렉토리 · 인자로 받은 디렉토리 전부 · CWD
#                   어디서도 test -e 가 거짓. 자리표시자(<…> ${…} * ~ 공백)와 URL 은 보지 않고, 경로로
#                   읽는 것은 마지막 조각에 점이 있거나 / 로 끝나거나 ./ 또는 / 로 시작하는 것뿐이다.
#                   문서가 다른 트리를 가리키면 그 트리를 --root 로 넘겨라 — 그러면 살아 있는 경로로 읽는다.
#   7-korean        한글이 든 줄 — 백틱·따옴표("…" '…' “…” 「…」) 안과 마크다운 제목 줄, 펜스 코드 블록은 뺀다
#
# *.sh 는 기준 하나만 본다. 표지가 `1-correction` 이 아니라 `1-correction-sh` 라 *.md 후보와 섞이지 않는다:
#   1-correction-sh  주석 줄(`^\s*#`, 셔뱅은 뺀다)에 1-correction 과 **같은** 어휘가 든 줄. 제거본도
#                    같다(백틱·따옴표 안은 뺀다). 다만 등장 단위로 걸러 `종전대로`·`종전과 같`(현재
#                    동작 서술)과 `정정 보존`(규칙 이름)만 든 줄은 후보가 아니다 — 한 줄에 걸러낼
#                    등장과 남는 등장이 같이 있으면 후보다.
#                    코드 줄은 보지 않는다. 줄 끝에 붙은 주석도 보지 않는다 — 코드 안 문자열의 # 을
#                    주석 시작으로 잘못 읽느니 통째로 안 보는 쪽을 골랐다(사각지대이되 오탐이 없다).
#                    반대로 heredoc 안에서 # 로 시작하는 줄은 주석으로 읽는다 — 천장이다(현재 트리에 그 오탐은 0건이다).
#
# 입력 디렉토리가 없거나 인자가 없으면 rc≠0 + stderr. 대상 *.md 가 0개여도 rc≠0 — 빈 집합의 탐지는
# 탐지가 아니다. *.sh 는 0개여도 죽이지 않는다(문서만 있는 트리도 감사 대상이다) — 대신 부르는 쪽이
# 훑은 파일 수를 함께 보고해 "후보 0건" 과 "안 훑었다" 를 가른다.

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
# shellcheck disable=SC2086
FILES="$FILES $(find $SCAN -type f -name '*.sh' | sort)"

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
# *.md 와 *.sh 가 같이 쓰는 두 조각. 어휘가 한 곳에만 살아야 두 자리가 갈라지지 않는다.
my $CORR = qr/종전|이전에는|바로잡|정정|was removed|were removed|went away|used to be/;
sub strip {
  my $s = shift;
  $s =~ s/`[^`]*`//g; $s =~ s/"[^"]*"//g; $s =~ s/“[^”]*”//g; $s =~ s/「[^」]*」//g;
  $s =~ s/\x27[^\x27]*[가-힣][^\x27]*\x27//g;
  return $s;
}
if ($file =~ /\.sh$/) {
  while (my $line = <$fh>) {
    $n++; chomp $line;
    next if $line =~ /^#!/;
    next unless $line =~ /^\s*#/;
    my $s = strip($line);
    # 등장 단위 판정 — 걸러낼 형태를 먼저 두면 perl 의 leftmost 교대가 그 자리를 통째로 먹고 지나간다.
    # 조각을 지우고 다시 보는 식은 구분자마다 샌다(skills#239 가 세 수단으로 확인했다).
    my $hit = 0;
    while ($s =~ /종전대로|종전과 같|정정 보존|($CORR)/g) { $hit = 1 if defined $1 }
    print "$file:$n:1-correction-sh:$line\n" if $hit;
  }
  exit 0;
}
while (my $line = <$fh>) {
  $n++; chomp $line;
  if ($line =~ /^\s*(```|~~~)/) { $fence = !$fence; next; }
  my @hits;
  push @hits, "4-date"         if !$fence && $line =~ /(?<![\d.])\d{4}-\d{2}-\d{2}(?![\d.])/;
  push @hits, "4-line-pointer" if !$fence && $line =~ /[\w.\/-]+\.[A-Za-z]+:\d+/;
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
    my $s = strip($line);
    push @hits, "1-correction" if $s =~ $CORR;
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
