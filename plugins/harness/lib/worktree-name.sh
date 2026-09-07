#!/usr/bin/env bash
# 스토리 ID → 워크트리 이름. **이 변환의 유일한 자리다** — ID 에서 워크트리 이름을 순파생하는
# 곳은 전부 여기를 부른다.
#
# 사용: bash lib/worktree-name.sh <스토리 ID>   → 워크트리 이름 한 줄
#       브랜치는 그 이름 앞에 `worktree-` 를 붙인 것이다 (EnterWorktree 가 name 에서 만든다).
#
# 왜 변환이 필요한가: github 백엔드의 ID 는 `<repo>#<번호>` 인데 **EnterWorktree 의 `name` 은
# `#` 을 받지 않는다** — 허용 문자는 letters·digits·dots·underscores·dashes 다. 그래서 스토리
# `skills#105` 의 워크트리는 `skills-105` 로 서고 브랜치는 `worktree-skills-105` 가 된다.
# ID 를 그대로 경로에 넣는 자리는 그 워크트리를 영영 못 찾는다 — 정리 스크립트가 없는 경로를
# 뒤져 "이미 정리된 상태" 라고 rc 0 을 내고 실물은 남았다 (harness#79, 실측 2건).
# beads 의 ID(`harness-abc`)는 허용 문자만 쓰므로 변환이 **무해**하다 — 이 어긋남이 beads 에서
# 드러나지 않았던 이유가 그것이다.
#
# 규칙: 허용 문자 밖의 문자를 전부 `-` 로 바꾼다. `#` 하나만 바꾸지 않는 이유는, 그러면 다른
# 문자를 쓰는 백엔드가 붙을 때 같은 결함을 다시 밟기 때문이다.
#
# **hooks/enter-worktree.sh 는 이것을 부르지 않는다** — 그쪽은 이름을 cwd 에서 역파생하므로
# 이름이 무엇이든 동작한다. 부르는 자리는 ID 에서 순파생하는 곳뿐이다.
set -u
id="${1:?사용법: worktree-name.sh <스토리 ID>}"
printf '%s\n' "${id//[^A-Za-z0-9._-]/-}"
