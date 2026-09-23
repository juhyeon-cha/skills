import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync, spawn } from "node:child_process";
const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const scripts = path.join(
  root,
  "plugins/knowledge/scripts/wiki",
);
const modulePath = process.env.WIKI_MARKDOWN_IT_MODULE;
assert(
  modulePath && path.isAbsolute(modulePath),
  "Set WIKI_MARKDOWN_IT_MODULE to an external absolute markdown-it module directory",
);
function fixture(
  ids = ["overview", "operations"],
  home = ids[0],
  evidencePage,
) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "knowledge-wiki-test-"));
  const input = path.join(temp, "content"),
    output = path.join(temp, "site");
  fs.mkdirSync(input);
  const manifest = {
    title: "Example knowledge",
    revision: "source-a",
    home,
    pages: ids.map((id, i) => ({
      id,
      title: "Page " + i,
      summary: "설명 " + i,
      path: id + ".md",
      kind: i === 1 ? "evidence" : "knowledge",
    })),
    ...(evidencePage ? { evidencePage } : {}),
  };
  for (const id of ids)
    fs.writeFileSync(
      path.join(input, id + ".md"),
      "# " + id + "\n\n## 확인\n\n검색 예제\n\n[Home](" + home + ".md#확인)\n",
    );
  fs.writeFileSync(path.join(input, "manifest.json"), JSON.stringify(manifest));
  return { temp, input, output, manifest };
}
function run(name, args, dir = scripts) {
  return spawnSync(process.execPath, [path.join(dir, name + ".mjs"), ...args], {
    encoding: "utf8",
    cwd: os.tmpdir(),
    timeout: 10000,
  });
}
const build = (f, dir = scripts) =>
  run("build", [f.input, f.output, modulePath], dir);
const check = (f, extra = []) =>
  run("check", [path.join(f.input, "manifest.json"), f.output, ...extra]);
function mutateManifest(f, fn) {
  fn(f.manifest);
  fs.writeFileSync(
    path.join(f.input, "manifest.json"),
    JSON.stringify(f.manifest),
  );
}
function append(file, text) {
  fs.appendFileSync(file, text);
}
for (const [ids, home, evidencePage] of [
  [["intro", "notes"], "notes"],
  [["guide", "release", "proof", "faq"], "guide", "proof"],
])
  test("arbitrary routes " + ids.join(","), () => {
    const f = fixture(ids, home, evidencePage);
    assert.equal(build(f).status, 0);
    assert.equal(check(f).status, 0);
    const search = JSON.parse(
      fs.readFileSync(path.join(f.output, "search-index.json")),
    );
    assert.equal(search.pages.length, ids.length);
    for (const p of search.pages) {
      assert.equal(
        p.body,
        fs.readFileSync(path.join(f.input, p.id + ".md"), "utf8"),
      );
      assert.equal(p.url, p.id === home ? "/" : "/" + p.id + "/");
    }
    const html = fs.readFileSync(path.join(f.output, "index.html"), "utf8");
    assert(html.includes("Example knowledge"));
    assert(!html.includes("SAP"));
    assert(html.includes('href="/#%ED%99%95%EC%9D%B8"'));
    assert.equal(html.includes("근거와 확인 범위 보기"), Boolean(evidencePage));
    assert.notEqual(build(f).status, 0);
    assert.equal(
      JSON.parse(check(f, ["--observed-revision", "new"]).stdout).status,
      "stale",
    );
  });
for (const [name, mutate] of [
  [
    "missing source",
    (f) => mutateManifest(f, (m) => (m.pages[0].path = "missing.md")),
  ],
  ["missing home", (f) => mutateManifest(f, (m) => (m.home = "missing"))],
  [
    "missing evidence",
    (f) => mutateManifest(f, (m) => (m.evidencePage = "missing")),
  ],
  ["empty pages", (f) => mutateManifest(f, (m) => (m.pages = []))],
  [
    "duplicate id",
    (f) => mutateManifest(f, (m) => (m.pages[1].id = m.pages[0].id)),
  ],
  [
    "path escape",
    (f) => mutateManifest(f, (m) => (m.pages[0].path = "../outside.md")),
  ],
  [
    "broken link",
    (f) => append(path.join(f.input, "overview.md"), "\n[bad](absent.md)"),
  ],
  [
    "broken anchor",
    (f) =>
      append(
        path.join(f.input, "overview.md"),
        "\n[bad](operations.md#missing)",
      ),
  ],
  [
    "protocol relative",
    (f) =>
      append(path.join(f.input, "overview.md"), "\n[bad](//example.org/path)"),
  ],
  [
    "orphan",
    (f) => fs.writeFileSync(path.join(f.input, "orphan.md"), "orphan"),
  ],
  [
    "symlink",
    (f) =>
      fs.symlinkSync(
        path.join(f.input, "overview.md"),
        path.join(f.input, "alias.md"),
      ),
  ],
])
  test("reject " + name, () => {
    const f = fixture();
    mutate(f);
    assert.notEqual(build(f).status, 0);
    assert(!fs.existsSync(path.join(f.output, "build-receipt.json")));
  });
for (const sourcePath of [
  "./overview.md",
  "sub/../overview.md",
  "sub//one.md",
  "/overview.md",
  "C:\\one.md",
])
  test("reject noncanonical path " + sourcePath, () => {
    const f = fixture();
    mutateManifest(f, (m) => (m.pages[0].path = sourcePath));
    const result = build(f);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /canonical relative Markdown path/);
    assert(!fs.existsSync(f.output));
  });
for (const evidence of [
  true,
  null,
  [],
  { reviewStatus: true },
  { liveStatus: { pass: true } },
  { reviewStatus: " " },
  { liveStatus: "" },
])
  test("reject malformed evidence " + JSON.stringify(evidence), () => {
    const f = fixture();
    mutateManifest(f, (m) => (m.pages[0].evidence = evidence));
    const result = build(f);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Evidence/);
    assert(!fs.existsSync(f.output));
  });
test("canonical nested Markdown and textual status round trip", () => {
  const f = fixture();
  fs.mkdirSync(path.join(f.input, "nested"));
  fs.renameSync(
    path.join(f.input, "operations.md"),
    path.join(f.input, "nested/operations.md"),
  );
  fs.writeFileSync(
    path.join(f.input, "nested/operations.md"),
    "# Operations\n\n[Home](../overview.md)\n",
  );
  mutateManifest(f, (m) => {
    m.pages[1].path = "nested/operations.md";
    m.pages[0].evidence = { reviewStatus: "검토 완료", liveStatus: "미검증" };
  });
  assert.equal(build(f).status, 0);
  assert.equal(check(f).status, 0);
  assert(
    fs
      .readFileSync(path.join(f.output, "index.html"), "utf8")
      .includes("검토 완료"),
  );
});
test("raw HTML and dangerous links stay inert", () => {
  const f = fixture();
  append(
    path.join(f.input, "overview.md"),
    "\n<script>alert(1)</script>\n\n[x](javascript:alert(1))\n\n[x](data:text/html,boom)\n",
  );
  assert.equal(build(f).status, 0);
  const html = fs.readFileSync(path.join(f.output, "index.html"), "utf8");
  assert(!html.includes("<script>alert"));
  assert(!html.includes('href="javascript:'));
  assert(!html.includes('href="data:'));
});
for (const file of [
  "overview.md",
  "manifest.json",
  "index.html",
  "search-index.json",
])
  test("reject tamper " + file, () => {
    const f = fixture();
    assert.equal(build(f).status, 0);
    append(
      path.join(
        file.endsWith(".md") || file === "manifest.json" ? f.input : f.output,
        file,
      ),
      "\n ",
    );
    assert.notEqual(check(f).status, 0);
  });
test("partial output has no completion receipt and cannot serve", () => {
  const f = fixture();
  const dir = path.join(f.temp, "partial");
  fs.mkdirSync(dir);
  fs.copyFileSync(path.join(scripts, "build.mjs"), path.join(dir, "build.mjs"));
  fs.copyFileSync(path.join(scripts, "markdown.mjs"), path.join(dir, "markdown.mjs"));
  fs.copyFileSync(path.join(scripts, "visuals.mjs"), path.join(dir, "visuals.mjs"));
  assert.notEqual(build(f, dir).status, 0);
  assert(fs.existsSync(path.join(f.output, "index.html")));
  assert(!fs.existsSync(path.join(f.output, "build-receipt.json")));
  assert.notEqual(check(f).status, 0);
  assert.notEqual(run("server", [f.output, "0"]).status, 0);
});
test("copied plugin executes without repository dependencies", () => {
  const f = fixture(["welcome"]);
  const copy = path.join(f.temp, "installed-knowledge");
  fs.cpSync(scripts, copy, { recursive: true });
  assert.equal(build(f, copy).status, 0);
  assert.equal(
    run("check", [path.join(f.input, "manifest.json"), f.output], copy).status,
    0,
  );
});
test("loopback serves routes and custom 404, confines files", async () => {
  const f = fixture();
  assert.equal(build(f).status, 0);
  fs.writeFileSync(path.join(f.output, "secret.txt"), "hidden");
  const server = spawn(
    process.execPath,
    [path.join(scripts, "server.mjs"), f.output, "0"],
    { cwd: os.tmpdir(), stdio: ["ignore", "pipe", "pipe"] },
  );
  try {
    const url = await new Promise((resolve, reject) => {
      server.stdout.once("data", (data) => resolve(data.toString().trim()));
      server.once("error", reject);
      server.once("exit", (code) => reject(Error("server exit " + code)));
    });
    for (const [route, status] of [
      ["/", 200],
      ["/operations/", 200],
      ["/missing/", 404],
      ["/secret.txt", 404],
      ["/%ZZ", 404],
    ]) {
      const res = await fetch(url + route);
      assert.equal(res.status, status);
      assert(res.headers.get("content-security-policy"));
    }
  } finally {
    server.kill();
  }
});

const visualMarkdown = `# Visuals

> [!FLOW] 요청 처리
>
> 1. [요청](https://example.org/request)을 전송한다.
> 2. 결과를 확인한다.
>    - **성공** — 완료 결과
>    - **응답 유실** — 상태 재조회

> [!CARDS] 범위 판단
>
> - **확정** — <script>alert(1)</script> [위험](javascript:alert(1))
> - **미정** — [관련 문서](overview.md) ![설명](https://example.org/image.png)
`;
function managed(text) {
  return spawnSync(process.execPath, [path.join(scripts, 'managed.mjs'), modulePath], {
    encoding: 'utf8', input: JSON.stringify([{repository: 'r', path: 'overview.md', url: '/documents/r/overview.md/', text}]),
  });
}
test('bounded visuals share safe static and managed tokens and preserve canonical source', () => {
  const f = fixture(['overview']);
  const staticMarkdown = visualMarkdown.replace(' ![설명](https://example.org/image.png)', '');
  fs.writeFileSync(path.join(f.input, 'overview.md'), staticMarkdown);
  const built = build(f); assert.equal(built.status, 0, built.stderr);
  assert.equal(check(f).status, 0);
  const html = fs.readFileSync(path.join(f.output, 'index.html'), 'utf8');
  const result = managed(visualMarkdown); assert.equal(result.status, 0, result.stderr);
  const page = JSON.parse(result.stdout)[0];
  for (const rendered of [html, page.html]) {
    for (const name of ['wiki-flow', 'wiki-flow-step', 'wiki-flow-outcomes', 'wiki-cards', 'wiki-card']) assert(rendered.includes(name));
    assert(rendered.includes('<ol class="wiki-visual-items">'));
    assert(rendered.includes('aria-label="요청 처리"'));
    assert(rendered.includes('href="https://example.org/request"'));
    assert(!rendered.includes('[!FLOW]')); assert(!rendered.includes('[!CARDS]'));
    assert(!rendered.includes('<script>alert')); assert(!rendered.includes('href="javascript:'));
  }
  assert(!page.html.includes('<img')); assert(page.html.includes('[이미지: 설명]'));
  assert(page.html.includes('href="/documents/r/overview.md/"'));
  const text = page.sections.map(s => s.text).join(' ');
  assert(text.includes('응답 유실')); assert(text.includes('상태 재조회')); assert(text.includes('범위 판단'));
  assert(!text.includes('[!FLOW]')); assert(!text.includes('[!CARDS]')); assert(!text.includes('wiki-flow'));
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.output, 'search-index.json'))).pages[0].body, staticMarkdown);
  assert(fs.readFileSync(path.join(f.output, 'style.css'), 'utf8').endsWith(fs.readFileSync(path.join(scripts, 'visuals.css'), 'utf8')));
});
for (const [name, text] of [
  ['missing title', '> [!FLOW]\n>\n> 1. Step'],
  ['formatted title', '> [!FLOW] **Title**\n>\n> 1. Step'],
  ['title continuation', '> [!FLOW] Title\n> continued\n>\n> 1. Step'],
  ['wrong list', '> [!FLOW] Title\n>\n> - Step'],
  ['extra paragraph', '> [!FLOW] Title\n>\n> extra\n>\n> 1. Step'],
  ['early branch', '> [!FLOW] Title\n>\n> 1. Step\n>    - early\n> 2. End'],
  ['deep branch', '> [!FLOW] Title\n>\n> 1. Step\n>    - outcome\n>      - deep'],
  ['card without bold title', '> [!CARDS] Title\n>\n> - plain'],
  ['nested visual', '> Quote\n>\n> > [!FLOW] Nested\n> >\n> > 1. Step'],
]) test('reject visual ' + name + ' in both readers', () => {
  const f = fixture(['overview']); fs.writeFileSync(path.join(f.input, 'overview.md'), text);
  for (const result of [build(f), managed(text)]) {
    assert.notEqual(result.status, 0); assert.match(result.stderr, /VISUAL_BLOCK_INVALID/);
  }
  assert(!fs.existsSync(path.join(f.output, 'build-receipt.json')));
});
test('ordinary quotes, escaped markers and Mermaid examples retain ordinary Markdown rendering', () => {
  const text = '> Ordinary quote\n\n> \\[!FLOW] Literal marker\n\n```mermaid\nflowchart LR\n A --> B\n```\n\n```markdown\n> [!CARDS] Example\n```';
  const result = managed(text); assert.equal(result.status, 0, result.stderr);
  const html = JSON.parse(result.stdout)[0].html;
  assert(html.includes('<blockquote>')); assert(html.includes('[!FLOW] Literal marker'));
  assert(html.includes('class="language-mermaid"')); assert(!html.includes('wiki-visual'));
});
test('visual titles escape attribute payloads and card bodies keep safe Markdown structure', () => {
  const result = managed(`> [!CARDS] "><script>alert(1)</script>
>
> - **Title** — [Unavailable](absent.md) and \\*literal\\*
>
>   Detail paragraph with \`code\`.
>
>   - Nested detail
>
>   ~~~html
>   <img src=x onerror=alert(1)>
>   ~~~
`);
  assert.equal(result.status, 0, result.stderr);
  const page = JSON.parse(result.stdout)[0];
  assert(page.html.includes('aria-label="&quot;&gt;&lt;script&gt;'));
  assert(!page.html.includes('<script>')); assert(!page.html.includes('<img'));
  assert(page.html.includes('class="unavailable-link"')); assert(page.html.includes('<code>code</code>'));
  assert(page.html.includes('Nested detail')); assert(page.html.includes('&lt;img src=x onerror=alert(1)&gt;'));
  assert(page.sections[0].text.includes('Detail paragraph'));
  assert(page.sections[0].text.includes('Nested detail'));
});
