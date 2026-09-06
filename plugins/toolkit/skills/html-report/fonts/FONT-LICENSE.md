# Font licence notice

The fonts in this directory are embedded into output HTML. Both are distributed under the **SIL Open
Font License 1.1**, which permits embedding and redistribution. The copyright holders, licences and
coverage figures below were read from the font files themselves with fontTools — coverage is the
number of code points in `cmap`.

> **Neither font has a single Han character.** A report containing Han characters renders those in
> the viewer's fallback font, not the embedded one. If Han characters are needed, change or add a
> font.

## Pretendard — subset build

- Files: `Pretendard-Regular.subset.woff2` · `Pretendard-SemiBold.subset.woff2` · `Pretendard-Bold.subset.woff2`
- Copyright: Copyright © 2023 길형진 (Kil Hyung-jin)
- Licence: SIL Open Font License 1.1 — https://scripts.sil.org/OFL
- Source: https://github.com/orioncactus/pretendard

**The stored copy is a subset, not the original.** It was taken from `dist/web/static/woff2-subset`
of the `pretendard@1.3.9` package. The three faces share one `cmap`, and this is its coverage.

- 3,728 code points (numGlyphs 4,381)
- 2,780 Hangul syllables — all 2,350 Hangul syllables of KS X 1001, plus 430 more (`갋·갣·걥·겂 …`).
  Not all 11,172 modern Hangul syllables
- **0 Han characters** — none of the 4,888 Han characters KS X 1001 specifies
- 228 Latin characters (U+0080–U+024F)

The distribution directory is named `woff2-subset`, which invites reading it as "the KS X 1001
subset". It is not: the Hangul is a superset of KS X 1001 and the Han is absent entirely.

## Paperlogy

- Files: `Paperlogy-4Regular.woff2` · `Paperlogy-6SemiBold.woff2` · `Paperlogy-7Bold.woff2`
- Copyright: Copyright © 2024 피티앤 (PT&)
- Licence: SIL Open Font License 1.1 — https://scripts.sil.org/OFL
- Source: https://noonnu.cc (distributed by Noonnu), repository `projectnoonnu/2408-3` tag `v1.0`

Stored as the original. The three faces share one `cmap`: 11,723 code points (numGlyphs 11,735), of
which 11,172 are Hangul syllables — the whole of the modern Hangul syllable block. **0 Han
characters.**

The Korean description in the `name` table (name ID 10, lang 1042) reads
`페이퍼로지 폰트는 프레젠테이션을 위한 파워포인트 전용 글꼴입니다`. That is a usage note; the licence
of this font is the OFL 1.1 in name ID 13 of the same table — embedding and redistribution stay
permitted.

---

OFL 1.1 full text: https://scripts.sil.org/OFL
