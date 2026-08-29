# 폰트 라이선스 고지

이 디렉토리의 폰트는 산출물 HTML 에 임베드된다. 두 폰트 모두 **SIL Open Font License 1.1** 로 배포되어 임베딩과 재배포가 허용된다. 아래 저작권자·라이선스 표기와 커버리지 숫자는 각 폰트 파일에서 실측한 값이다 (2026-08-22, fontTools 4.63.0 — 커버리지는 cmap 의 코드포인트 수).

> **두 폰트 다 한자가 0자다.** 한자가 든 보고서는 임베드 폰트가 아니라 뷰어의 폴백 폰트로 렌더된다. 한자가 필요하면 폰트를 바꾸거나 추가해야 한다.

## Pretendard — 서브셋본

- 파일: `Pretendard-Regular.subset.woff2` · `Pretendard-SemiBold.subset.woff2` · `Pretendard-Bold.subset.woff2`
- 저작권: Copyright © 2023 길형진 (Kil Hyung-jin)
- 라이선스: SIL Open Font License 1.1 — https://scripts.sil.org/OFL
- 원본: https://github.com/orioncactus/pretendard

**저장본은 원본이 아니라 서브셋본이다.** 배포처 `pretendard@1.3.9` 의 `dist/web/static/woff2-subset/` 에서 받았다. 3종의 cmap 이 동일하며 커버리지는 이렇다.

- 코드포인트 3,728자 (numGlyphs 4,381)
- 한글 음절 2,780자 — KS X 1001 의 한글 2,350자를 전부 포함하고, 그 밖의 음절 430자(갋·갣·걥·겂 …)를 더 담는다. 현대 한글 11,172자 전부는 아니다
- **한자 0자** — KS X 1001 이 규정하는 한자 4,888자가 하나도 없다
- 라틴 계열(U+0080–U+024F) 228자

배포 디렉토리 이름이 `woff2-subset` 이라 "KS X 1001 서브셋" 으로 읽기 쉬우나 그렇지 않다. 한글은 KS X 1001 의 상위집합이고 한자는 전무하다.

## Paperlogy

- 파일: `Paperlogy-4Regular.woff2` · `Paperlogy-6SemiBold.woff2` · `Paperlogy-7Bold.woff2`
- 저작권: Copyright © 2024 피티앤 (PT&)
- 라이선스: SIL Open Font License 1.1 — https://scripts.sil.org/OFL
- 원본: https://noonnu.cc (눈누 배포), 배포 저장소 `projectnoonnu/2408-3` 태그 `v1.0`

원본 그대로 저장했다. 3종의 cmap 이 동일하며 코드포인트 11,723자(numGlyphs 11,735), 그중 한글 음절 11,172자로 현대 한글 완성형 전부를 담는다. **한자는 0자다.**

name 테이블의 한국어 설명(name ID 10, lang 1042)에 `페이퍼로지 폰트는 프레젠테이션을 위한 파워포인트 전용 글꼴입니다` 가 들어 있다. 용도 안내 문구이고, 이 폰트의 라이선스는 같은 테이블 name ID 13 의 OFL 1.1 이다 — 임베딩·재배포 허용이라는 결론은 그대로다.

---

OFL 1.1 전문: https://scripts.sil.org/OFL
