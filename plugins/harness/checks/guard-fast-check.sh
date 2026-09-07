#!/usr/bin/env bash
# guard.sh 골격 게이트의 **빠른 자리**. checks/guard-check.sh 의 임계 아래 절만 돌린다.
#
# 이 자리가 존재하는 이유: 종전에는 guard.sh 를 보는 가장 정교한 검사가 전부-아니면-전무라
# check-all 의 면제였고, 그래서 커밋마다 아무도 안 봤다. 전수를 통째로 넣으면 그 게이트가
# 두 배가 되므로(실측 skills#223 — 전수 159.5초 vs check-all 의 나머지 10개 합계 163.3초),
# 임계 아래 절만 여기서 돈다. 임계와 어느 절이 어느 쪽인지는 checks/guard-check.sh 의
# 「절 범위」 주석이 단일 소유한다 — 여기에 절 목록을 복사하지 않는다.
#
# 전수 자리는 checks/guard-check.sh 이고, 훅 guard.sh 를 고치는 커밋에서 손으로 돌린다
# (scripts/check-all.sh 의 면제 사유가 그 자리를 적는다).
#
# 훅이 HOME 아래에 쓰는 상태 파일의 격리(guard-check ⑯ 이 요구하는 export 들)는 여기가
# 아니라 checks/guard-check.sh 가 한다 — 이 파일은 훅 경로를 알지 못하고 그것을 부르지도
# 않는다. 그래서 ⑯ 의 파생(훅 경로를 적은 checks/*.sh)에도 이 파일은 들지 않는다.
set -uo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export GUARD_CHECK_SCOPE=fast
exec bash "$DIR/guard-check.sh"
