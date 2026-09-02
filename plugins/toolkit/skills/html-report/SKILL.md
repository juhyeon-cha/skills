---
name: html-report
description: Build a single HTML page for reporting or sharing inside a company, out of `template.html`. Pick a preset for the purpose (analysis, finance, status, proposal), then delete or duplicate sections and fill them in; what comes out is one self-contained file. Use for requests like "보고서 만들어줘", "발표자료 만들어줘", "주간보고 정리해줘", "이 논의 HTML로 뽑아줘". Subject-agnostic.
---

# Building an HTML page for reporting and sharing

**There is one template, `template.html`.** No substitution engine, no build step — read it, delete,
duplicate, fill. The output is one self-contained `.html` file that opens as it is and is shared as
it is. Printed, it becomes an A4 report.

**The report comes out in Korean.** `template.html` holds Korean throughout — marker names, preset
section headings, boilerplate — and Pretendard is the default font because the body text is Korean.
This document is in English; what it produces is not.

## 1. The procedure

1. **Settle the content.** If a file path came in as an argument, read it; otherwise take it from the
   conversation. What to write is §2. **If the department and author for the cover are not in the
   conversation, ask here** — the three fields in §4 cannot be guessed, and asking after the fact
   means the cover is already filled.
2. Read `template.html`. Read it whole — the presets and the component store are down at the bottom.
3. **Pick a preset.** §5. Paste the one you picked into the body section slot.
4. **Settle the sections and fill them.** Marker rules are §3. For more components, copy them out of
   the `PALETTE` region.
5. **Embed the font.** Pretendard by default. Three stored woff2 faces go into the draft as base64 —
   details in §6-2.

   ```bash
   python3 embed-font.py <draft>.html pretendard > <draft>-font.html
   ```

   **The order is embed, then finalize.** Reversed, `finalize.py` strips the injection-point comment
   and `embed-font.py` ends with rc=1.

6. **Run `finalize.py`.** Its input is the font-embedded file from the previous step. Comment and
   component-store removal and the §8 checks are this tool's work — they are not done by hand
   (§7, §8). `rc=0` and you are finished; on `rc=1`, read the lines on stderr and decide whether to
   fix them or pass them as body content (§8).

   ```bash
   python3 finalize.py <draft>-font.html > <YYYY-MM-DD>-<slug>.html
   ```

   **Write it where you were told to**, otherwise under `reports/` if the project has one, otherwise
   in the current working directory. The slug is letters, digits and hyphens taken from the title.

7. **Attach the §6-3 font notice to the completion report verbatim.** Every time.

### Where the three agents come in

| Agent | When you hand off | What comes back |
| :------- | :---------- | :---------- |
| `data-analyst` | When step 1 also brought **a pile of numbers** (tables, CSV, logs, pasted figures) | Settled values and tables. Every value carries its unit, as-of date and how it was computed |
| `worklog-structurer` | When step 1 brought **records in time order** (commits, issues, weekly logs, meeting notes) to build achievement or retrospective material | A list of entries. Achievements in [problem - solution - result], retrospectives in [cause - action - prevention] |
| `report-writer` | After the preset is picked in step 3, and **before sections are filled** in step 4 | Draft text for the subtitle, "at a glance", body, conclusion and next steps |

The first two handle raw material and `report-writer` turns the result into sentences. So **raw
material always goes first** — a request that arrived with data runs `data-analyst` → `report-writer`,
a request to write achievements or a retrospective out of records runs `worklog-structurer` →
`report-writer`, and records with numbers mixed in run all three, `worklog-structurer` →
`data-analyst` → `report-writer`: **stand the entries up first, then hand over their empty number
slots.** Until it is settled what counts as one entry, which values to compute is not settled either.
Handing over settled values and stood-up entries is what keeps the sentence side from inventing facts.
With no material and only a conversation, `report-writer` alone finishes it.

**None of the three assembles HTML, and none of them runs the font embed or `finalize.py`.** The
procedure above does that. **When `data-analyst` comes back unable to produce a value for want of a
tool, this procedure does that arithmetic itself in `python3` and leaves the expression it used in the
output's evidence slot** — delegation quietly turning into mental arithmetic is how this spot fails.

## 2. What to write

This is writing a report, not filling in a template. The five below hold across every preset.

1. **Lead with the conclusion.** Title, subtitle and "at a glance" alone have to be enough to decide
   on. The body is the grounds for that decision, not a place to defer it to.
2. **Put a unit and an as-of date on every number.** An amount without a unit and a change without an
   as-of date each produce exactly one question in the meeting. Say where the number came from too.
3. **Keep fact and judgement apart.** "Revenue rose 3.2%" is a fact; "growth is solid" is a
   judgement. Write the judgement in the same paragraph as the fact it came from.
4. **Say what the reader has to do.** Approve, decide, or note. "Please review" asks for nothing.
   Write the deadline and the person along with it.
5. **Write what you do not know as not known.** Do not fill a blank with `N/A`, and write down what
   you could not answer as unanswered. A filled blank reads as reviewed.

Length stays within **3–5 lines of "at a glance" and 4–7 body sections.** Longer and the reader takes
the summary and drops the rest — do not spend time writing what will be dropped.

**Each preset carries narrower criteria in the comments of `template.html`.** That is why you read it
whole.

## 3. Markers — these three are all of them

```
<!-- SECTION: <name> | <flag> -->  …  <!-- /SECTION: <name> -->
```

Names and flags are written in Korean inside `template.html`; there are three flags and this is what
each does.

| Flag         | What it means                                                                   |
| :----------- | :------------------------------------------------------------------------------ |
| **Required** | It stays. Only three are required: cover, "at a glance", conclusion.             |
| **Optional** | With nothing to put in it, **delete it whole, opening comment through closing.** |
| **Repeat**   | Duplicate as many as you need. Delete it when you need none.                     |

## 4. Document structure

The skeleton runs in this order. The bold ones are required; the rest are deleted when there is
nothing to put in them.

```
cover → at a glance → body (preset) → conclusion → next steps → references → footer
  ▲          ▲                            ▲
required  required                     required
```

**The cover and the footer are colour bands.** Five things go on the cover:

| Slot | What goes in it |
| :--- | :---------- |
| Document kind | The genre of the document — "quarterly results report", "weekly status". It does not repeat the title |
| Title | What the document is about. Period and subject belong in it |
| Classification | The badge at top right. **Confidential is the default. Delete `<span class="classification">` only when the user says the document is public** |
| Subtitle | **The conclusion, in one sentence.** Not an elaboration of the title |
| Department, date, author | **These three fields are fixed.** Do not rename them, do not drop one to slot another in, and do not add a fourth. In particular, "shared with", recipients and distribution scope do not go here — put that in the body or the footer if it is needed. The author is **the user who asked for the material** — this slot names the person accountable rather than the tool that built it, so a model name (`Claude` and the like) does not go in it. When one of the three cannot be filled, do not invent it and do not drop the field: **ask the user** (§1 step 1) |

**Fill `<title>` in `<head>` at the same time.** It is not one of the five visible on the cover — it
is what shows in the browser tab, in bookmarks and in share previews — so it is not in the table
above, but it gets filled when the cover does. Usually the same sentence as the title. Miss it and
the tab shows the raw title placeholder — the §8 check catches it, but this is the spot where it gets
filled before that.

The footer holds the confidentiality line (left) and the same badge (right), plus copyright and a
contact. The badge is an inline element, so it works inside body paragraphs too.

**Body sections are numbered automatically from `01`** — "at a glance", the footer and the references
get no number. References are the grounds for the body rather than body, so they take no slot in the
table of contents.

## 5. Presets — a body that fits the purpose

The `PRESET` region holds four finished section sets. Pick one, paste it into the body section slot,
and inside the preset delete any part you have nothing to put in.

| Preset                  | When to use it                    | Body structure                                                     |
| :---------------------- | :-------------------------------- | :----------------------------------------------------------------- |
| **A. Analysis report**  | What you looked at, why, what now | Background → data and method → findings → implications → limitations |
| **B. Finance**          | The numbers are the subject       | Financial summary → P&L → reasons for change → exceptions           |
| **C. Status report**    | Weekly or monthly progress        | Progress → issues and risks → plan for the next period              |
| **D. Proposal**         | Going in for approval             | Problem → proposal and alternatives → cost and schedule → the ask   |

**When no preset fits, do not force one in** — duplicate the empty body section and build it
yourself. Mixing two is fine (a status report followed by the proposal's "the ask", say).

Section names do not get renamed. **The limitations section in A and the ask in D especially do not
get deleted** — an analysis with no limitations and a proposal with no ask read as documents nobody
reviewed.

## 6. Colour and fonts

### 6-1. Changing the colours — four lines and no more

The `BRAND` block at the top of the file:

```css
:root {
  --brand: #3f3f46;      /* for light backgrounds. 4.5:1 or better against white */
  --brand-dark: #a1a1aa; /* for dark backgrounds. A lighter step of the same hue */
  --band: #26262b;       /* the cover and footer colour band */
  --band-fg: #ffffff;    /* text on that band. 4.5:1 or better against --band */
}
```

The default is achromatic (zinc). To switch to a company brand colour, replace **these four values**
and nothing else. Accent rules, tinted backgrounds, bars, links and band secondaries are all derived
from here through `color-mix()`, so they follow.

**Change `--band-fg` whenever you make `--band` light.** Once their contrast drops below 4.5:1 the
cover title stops being readable.

**The output opens in dark mode too.** A reader whose OS is set to dark gets the dark palette
automatically (`prefers-color-scheme`). When you change colours, **check both** — matched in light
only, the contrast collapses in dark. To pin one of them, put `data-theme="light"` or
`data-theme="dark"` on `<html>`. Printing is always on white, whatever the setting.

**The semantic colours (`--info` `--warn` `--pos` `--neg`) have nothing to do with the brand.** Change
and warning must not follow a company colour — a loss painted in brand colours is not a thing that
should happen. Leave them alone.

### 6-2. Fonts — Pretendard by default, embedded by `embed-font.py`

The output is self-contained down to the font. Stored woff2 faces go into the draft as base64, so no
external reference is created and it opens identically on a machine that does not have the font.

```bash
python3 embed-font.py <draft>.html pretendard > <draft>-font.html
```

- **The order is embed, then finalize.** The injection point is a single `<!-- FONT:EMBED -->`
  comment, so running `finalize.py` first strips it and `embed-font.py` ends with rc=1.
- **The CSS name is fixed at `'ReportSans'`, independent of the font key.** That name is the first
  entry of `--font`, so changing font leaves the draft's CSS untouched.
- Only two fonts are stored in the skill: `pretendard` and `paperlogy`. Licence and coverage notices
  are in `fonts/FONT-LICENSE.md`.
- **Leave the system font stack at the tail of `--font` in place.** The stored Pretendard is a subset
  and does not contain `▲` `▼` `△`. Those change markers are drawn glyph by glyph from the fallback
  fonts even after embedding. It carries no Han characters either.

#### Other fonts get offered, and are embedded after the user picks

The completion report carries the §6-3 text verbatim, which names five fonts. **Nothing is downloaded
before the user picks.**

The preview is `preview.html` in this folder — it draws one and the same finance report in five fonts
in turn. **All five are drawn from a CDN.** Pretendard is a full CDN copy in the preview even though a
stored copy exists, so do not describe it as "Pretendard alone is local" — the stored copy is a subset
and its glyph count differs (the `▲▼△` above).

- Picking `paperlogy` changes only the font key in the command above.
- The third to fifth (Noto Sans KR, MaruBuri, RIDIBatang) have no stored copy. Download them at that
  point and embed them with the method below.

| Font | Where to get it |
| :--- | :--- |
| MaruBuri | `https://cdn.jsdelivr.net/gh/fonts-archive/MaruBuri@main/MaruBuri-{Regular,SemiBold,Bold}.woff2` |
| RIDIBatang | `https://cdn.jsdelivr.net/gh/fonts-archive/RIDIBatang@main/RIDIBatang.woff2` — **it has one weight only, so the file is passed once** (one argument in the snippet below = one face at 400). Declaring the same file at 600 and 700 as well makes the browser believe it found an exact face and **turn synthetic bold off** — text that should be bold comes out the same as body. Say in the report that 600 and 700 are synthetic bold |
| Noto Sans KR | `https://cdn.jsdelivr.net/npm/@fontsource/noto-sans-kr@5.2.5/files/noto-sans-kr-korean-{400,600,700}-normal.woff2` — state the limit below first |

**Do not embed the full distribution of Noto Sans KR.** The Google Fonts CSS API hands out 372
`@font-face` rules split by Unicode range across the three weights, and the source OTF is 4.6MB,
which is not an embedding candidate. The slice above **holds only the 2,350 Hangul syllables of
KS X 1001 — the original has 11,172.** Every other syllable falls through to a system font and the
typeface splits inside a single sentence. **When Noto Sans KR is picked, state this limit and confirm
that it is still the choice.**

`embed-font.py` does not know about downloaded files (it looks only at stored names). All that is
needed is replacing the injection point with a `<style>` of the same shape, so embed with the snippet
below.

```bash
# Fetch the woff2 per weight into a temp folder. Argument order is 400 · 600 · 700, and
# a font with one weight only (RIDIBatang) takes a single argument — that is what keeps synthetic bold on.
curl -sSLO <URL>

python3 - <draft>.html <400>.woff2 [<600>.woff2 <700>.woff2] <<'PY' > <draft>-font.html
import base64, re, sys
draft = open(sys.argv[1], encoding='utf-8').read()
faces = ''.join(
    "      @font-face { font-family: 'ReportSans'; font-style: normal; font-weight: %d;\n"
    "        src: url(data:font/woff2;base64,%s) format('woff2'); }\n"
    % (w, base64.b64encode(open(f, 'rb').read()).decode())
    for w, f in zip((400, 600, 700), sys.argv[2:]))
out, n = re.subn(r'(?m)^[ \t]*<!--\s*FONT:EMBED\s*-->[ \t]*\n?',
                 "    <style>\n%s    </style>\n" % faces, draft)
if n != 1:
    sys.exit('found %d injection points — there must be exactly 1' % n)
sys.stdout.write(out)
PY
```

**Base64 is never pasted by hand.** One face runs to hundreds of thousands of characters — a script
embeds it, always. Run `finalize.py` after embedding and the §8 font check sees this payload and
passes it. **Check the licence notice at the source you downloaded from and put it in one line in the
output's references or footer** — `fonts/FONT-LICENSE.md` covers only the six stored files and does
not apply here.

### 6-3. The fixed notice that goes in the completion report

Every time you hand over an output, attach the following **verbatim.** Rewritten each time, the set
of fonts on offer changes from report to report.

> 폰트는 **Pretendard** 로 심었습니다. 파일 안에 들어 있어 받는 분 기기에 그 폰트가 없어도
> 같은 모양으로 열립니다.
> 다른 폰트로도 뽑을 수 있습니다 — **Paperlogy · 본고딕(Noto Sans KR) · 마루부리 · 리디바탕**.
> **프리뷰를 보시겠습니까?** `<스킬 폴더>/preview.html` 을 브라우저로 열면 같은 보고서를
> 다섯 폰트로 번갈아 볼 수 있습니다(프리뷰는 폰트를 인터넷에서 받아 그립니다).
> 고르시면 그 폰트로 다시 심어 드리겠습니다.

The skill-folder placeholder in that notice is replaced with the real path — the user has to open that
file themselves. If you embedded a font other than the default, change the font name on the first line
to that one, and for RIDIBatang or Noto Sans KR add one line with the limit from §6-2: RIDIBatang has
synthetic bold at 600 and 700, and with Noto Sans KR **what was seen in the preview is the full glyph
set (11,172) while what gets embedded is 2,350**, so every other syllable is drawn in a different
typeface.

## 7. What gets deleted from the output, and what stays

**`finalize.py` does the deleting.** Not by hand — a person deleting leaves the inconspicuous things
behind, like an instruction comment with no prefix.

| Target                             | Who                 | Treatment                                                       |
| :--------------------------------- | :------------------ | :-------------------------------------------------------------- |
| **Every** HTML comment              | `finalize.py`       | **Deleted.** All of them, not only the ones marked `SECTION:`. A comment is merely invisible on screen; it stays in the file and reads perfectly well to anyone who opens the source. |
| `PRESET` and `PALETTE` stores       | `finalize.py`       | **The marker comments and the `<template>` bodies go together.** A store is a `<template>` element rather than a comment, so deleting only the comment leaves the markup alive and takes away the very grounds the §8 leftover check would have caught it on. |
| `{{double braces}}`                 | a person            | **None are left.** What you cannot fill, you delete the section for. Which one to fill is a judgement no tool makes for you — anything left is caught by the check. |
| CSS of unused components            | a person            | **Stays.** Picking selectors to delete takes the styles of components you did use down with them. |
| `.classification` and the confidentiality line | a person | **Stays.** Delete only the unfilled copyright `<p>` and keep the footer. |

**Not one external reference is left.** No CDN, no web font, no remote image, no `fetch`. Images go
inline as `data:` URIs. Fonts likewise, which is why `embed-font.py` embeds them as base64 (§6-2).
Uploaded as an artifact later, it still opens.

**The one exception is `preview.html`.** That file is not an output but a shell for picking a font,
and it draws five fonts from a CDN. The user picks, then it is downloaded and embedded, so that CDN
reference never leaks into an output. The output side is caught by the external-reference check in §8.

## 8. Verification — do what you can, and write down what you could not

### Always run

```bash
python3 finalize.py <draft>-font.html > <output>.html; echo "rc=$?"
```

The cleaned file goes to stdout, what was deleted and what was flagged goes to stderr, and the
judgement is **the exit code**. The input file is only opened, so the draft survives even if the tool
dies.

| rc | What it means |
| :- | :- |
| 0  | All four passed: leftover markers, external references, font embedding, tag balance. Safe to share as is |
| 1  | A check flagged something. stderr names it by line number. Usually it is a leftover you did not delete, so treat stdout as a draft; **when it is body content that got flagged, a person judges and passes it** (below) |
| 2  | The input could not be read |

The four checks are these.

- **Leftover markers and unfilled slots** — `{{double braces}}` · `SECTION:` · `PRESET:` ·
  `PALETTE:` · `<template>`. The last is the store's only remaining trace, so it is caught as an
  element rather than by name.
  **Something flagged inside `<pre>`/`<code>` may be body content** — material explaining marker
  syntax or a substitution slot is supposed to be flagged. The tool does not tell inside a code block
  from outside (that would turn a regex into a parser), so a person makes that call. When you pass
  one, **write down which line you took as body content and why** — anything flagged outside a code
  block is a leftover you did not delete, and blurring the two blunts the check.
- **External references** — `src=` · `@import` · `url(http…)` · `<script>` · `<link>`. A body
  `<a href>` is fine; pulling something in is the violation.
- **Font embedding** — it looks for `url(data:font/woff2;base64,` inside `<style>`. Absent, it is
  `rc=1`, and the cause is one of two: the font was never embedded (§6-2), or `finalize.py` ran first
  and the injection-point comment was already gone. A code block in the body explaining `@font-face`
  does not trip it — the judgement is made only inside `<style>` elements.
- **Tag balance** — drop one `</tr>` while duplicating a table and everything below it collapses.

**The grounds for the judgement are the rc and the full stderr.** Read the flagged lines in full
rather than shortening them to a `head` or a count — the tool prints all of them, and the silence of a
truncated list is not evidence. The same holds when a person passes an `rc=1` as body content: read it
in full, and write down which line you passed and why.

### Confirm the render only when you can confirm it

**To write "I opened it" you have to have seen pixels.** Producing the file is not seeing the render.

- With a headless browser, take a screenshot and look at it. For example:
  `<browser> --headless=new --screenshot=/tmp/shot.png --window-size=1000,1500 <the file>`
- To see the printed result, produce it with `--print-to-pdf`. But **do not go digging through PDF
  bytes to decide whether a background colour made it in** — bands and text colour are recorded by
  the same operator and cannot be told apart. To look at print styling, render a copy with
  `@media print` changed to `@media all` and **`@media screen` changed to `@media not all`.** Miss the
  second and the dark palette bleeds in although it would never apply on paper — the dark palette
  lives inside `@media screen`.
- **This imitation fails to reproduce one thing Chromium does when printing.** Chromium forces
  `prefers-color-scheme` to light for print (measured on Edge 151). Run the imitation on a machine
  with OS dark mode on and it comes out darker than the real print. **That forcing reaches the media
  feature only** — a dark theme switched on by attribute, like `data-theme="dark"`, survives into
  print. When the palette is what is being judged, look at a real print from `--print-to-pdf`
  alongside, and **judge on text colour rather than background** — Chrome does not print backgrounds
  by default, so the ground comes out white either way. (Whether WebKit and Gecko force it was not
  measured.)
- With none of that available, stop at the grep and tag checks above and **write "the render was not
  confirmed" in the report.** Give the person the path so they can open it.

## 9. Components

Callouts (info, caution, emphasis) · tables · **number tables (right-aligned, subtotals, totals,
sub-accounts)** · **change markers** · **status badges** · statistic tiles · achievement metric cards
(before → after) · code · quotes · image with caption · vertical timeline · accordion · tabs · bar
chart with sparkline · page break. All of them exist as finished markup in the `PALETTE` region.

**Change and status are never distinguished by colour alone.** The `▲`/`▼`/`—` marks and a word
("done", "delayed") always go with them. In black-and-white print and for colour-vision deficiency,
colour is gone.

**Number tables carry their unit and as-of date in a `.table-note`.** An amount without a unit
produces exactly one question in the report.

## 10. Ceilings left in place

### What you run into while writing

- **Tabs are radios plus CSS.** There is no `role="tab"` and no arrow-key movement, and a hidden panel
  is not found by `Ctrl+F`. **When the content has to be searchable, use `h3` subheadings instead of
  tabs.** With more than one tab group on a page, change the `t1` in `name` and `id`. Four per group
  at most — going beyond means adding a CSS selector line each. (In print every panel is expanded.)
- **The only charts are bars and sparklines.** For lines, scatter or multi-series, read the `dataviz`
  skill and draw inline SVG. Do not start a second chart rule here.
- **There are no diagrams.** Draw inline SVG when you need one.
  ⚠️ **mermaid is unusable** — rendering a `mermaid` block is a feature of the artifact viewer, not of
  the browser. In a local `.html` it shows as a lump of code.
- **Page breaks bind small units only.** Do not put `break-inside: avoid` on a whole section — one
  long section shoved along whole leaves a large gap on the preceding page. Bind only what becomes
  unreadable when cut — table rows, statistic tiles, callouts, quotes — and hold paragraphs together
  with `orphans`/`widows`. **`orphans`/`widows` are honoured by Chrome, Edge and Safari. Firefox
  ignores them.** When a section must start on a fresh page, put `<div class="page-break"></div>`
  before it.

### What to know before you ship

- **It uses `color-mix()`.** Chrome 111, Safari 16.2, Firefox 113 or later. To ship to anything lower,
  replace the five derived tokens (`--accent-soft` `--info-soft` `--warn-soft` `--band-muted`
  `--band-line`) with literal colours.
- **Colour bands are for screen only.** In print the cover and footer bands become heavy rules.
  Flooding the top of an A4 eats toner, shows through the back and mangles text in black-and-white
  output. To keep bands on paper, delete that block from `@media print` and add
  `print-color-adjust: exact` — and then everything outside the page margin (`@page margin`) stays
  white.
- **There are no page numbers, headers or footers.** Browsers never implemented `@top-center` and
  `counter(page)` in CSS `@page`. Use the header/footer option in the browser's print dialog.
- **This is not a slide deck.** It is one scrolling document.

## 11. Changing the template

A one-off instruction given in words at call time ("skip the background this time", "a table instead
of tiles") does not touch the template. It applies to that output only. **When the same instruction
comes three times, that is when it goes into the template** — the line between a taste getting fixed
in place after one use, and repeating the same words every time.

A new preset takes the same bar. Once you have built the same kind of report three times, it goes into
`PRESET`.

**Where you change it depends on how this skill was installed.**

| Installed as | Where you change it |
| :-------- | :-------- |
| A plugin (`/plugin install toolkit@skills`) | Do not edit files in the cache — **the next update overwrites them.** Edit `plugins/toolkit/` in the source repo (`juhyeon-cha/skills`) and commit |
| Copied into a project (`.claude/skills/html-report/`) | Edit that file directly |

**A value that differs per project, like a company brand colour, does not get baked into the
template.** Write it in the project instructions (`CLAUDE.md` and the like) — "reports in this project
use `--brand: #003a70`" — and substitute that value when you build an output. The template's default
stays achromatic.
