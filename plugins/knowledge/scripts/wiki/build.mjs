/** Build reader pages and search from one pinned Markdown snapshot. */
import fs from "node:fs";
import { parseDocument } from "./markdown.mjs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const [inputArg, outputArg, moduleArg, ...extra] = process.argv.slice(2);
if (!inputArg || !outputArg || !moduleArg || extra.length)
  throw Error("Usage: node build.mjs CONTENT NEW_OUTPUT MARKDOWN_IT_MODULE");
if (!path.isAbsolute(moduleArg))
  throw Error("MARKDOWN_IT_MODULE must be an absolute module path");
const MarkdownIt = createRequire(import.meta.url)(moduleArg);
const input = path.resolve(inputArg),
  output = path.resolve(outputArg),
  md = new MarkdownIt({ html: false, linkify: false });
const hash = (x) => crypto.createHash("sha256").update(x).digest("hex"),
  esc = (x) =>
    String(x).replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
function need(x, message) {
  if (!x) throw Error(message);
}
function safe(file) {
  const abs = path.resolve(input, file);
  need(
    abs.startsWith(input + path.sep),
    "Source escapes content root: " + file,
  );
  let cursor = input;
  need(!fs.lstatSync(cursor).isSymbolicLink(), "Symlink content root");
  for (const part of path.relative(input, abs).split(path.sep)) {
    cursor = path.join(cursor, part);
    need(!fs.lstatSync(cursor).isSymbolicLink(), "Symlink source: " + file);
  }
  need(fs.statSync(abs).isFile(), "Not a source file: " + file);
  return abs;
}
need(!fs.existsSync(output), "Output must be a new directory");
const raw = fs.readFileSync(safe("manifest.json"), "utf8"),
  manifest = JSON.parse(raw);
need(
  typeof manifest.title === "string" &&
    manifest.title.trim() &&
    typeof manifest.revision === "string" &&
    manifest.revision.trim() &&
    typeof manifest.home === "string" &&
    Array.isArray(manifest.pages) &&
    manifest.pages.length > 0,
  "Incomplete manifest",
);
const basePath = manifest.basePath ?? "/";
need(
  typeof basePath === "string" &&
    /^\/(?:[A-Za-z0-9_%.-]+\/)*$/.test(basePath) &&
    basePath.split("/").filter(Boolean).every((part) => {
      const decoded = decodeURIComponent(part);
      return decoded !== "." && decoded !== ".." && !/[\/\\]/.test(decoded);
    }),
  "Invalid publication basePath",
);
const ids = new Set(),
  paths = new Set();
const pages = manifest.pages.map((p) => {
  need(
    /^[a-z][a-z0-9-]*$/.test(p.id) && !ids.has(p.id),
    "Invalid or duplicate id",
  );
  ids.add(p.id);
  need(
    typeof p.title === "string" &&
      p.title.trim() &&
      typeof p.summary === "string",
    "Missing title/summary",
  );
  need(
    typeof p.path === "string" &&
      p.path.endsWith(".md") &&
      !p.path.includes("\\") &&
      !p.path.includes(":") &&
      p.path.split("/").every((part) => part && part !== "." && part !== ".."),
    "Source path must be a canonical relative Markdown path: " + p.path,
  );
  if (p.evidence !== undefined) {
    need(
      p.evidence !== null &&
        typeof p.evidence === "object" &&
        !Array.isArray(p.evidence),
      "Evidence must be an object: " + p.id,
    );
    for (const key of ["reviewStatus", "liveStatus"]) {
      need(
        p.evidence[key] === undefined ||
          (typeof p.evidence[key] === "string" && p.evidence[key].trim()),
        "Evidence " + key + " must be a nonempty string: " + p.id,
      );
    }
  }
  const absolute = safe(p.path);
  need(!paths.has(absolute), "Duplicate source");
  paths.add(absolute);
  const body = fs.readFileSync(absolute, "utf8"),
    { tokens, headings, anchors } = parseDocument(md, body);
  return {
    ...p,
    absolute,
    body,
    tokens,
    headings,
    anchors,
    sha256: hash(body),
    url: p.id === manifest.home ? basePath : basePath + p.id + "/",
  };
});
need(ids.has(manifest.home), "Unknown home page");
need(
  manifest.evidencePage === undefined || ids.has(manifest.evidencePage),
  "Unknown evidence page",
);
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const f = path.join(dir, e.name);
    need(!e.isSymbolicLink(), "Symlink input: " + f);
    return e.isDirectory() ? walk(f) : [f];
  });
}
for (const file of walk(input).filter((p) => p.endsWith(".md")))
  need(paths.has(file), "Orphan Markdown: " + file);
let linkCount = 0;
for (const p of pages) {
  function visit(tokens) {
    for (const token of tokens) {
      need(
        token.type !== "image",
        "Images are not supported in this local preview",
      );
      if (token.type === "link_open") {
        const href = token.attrGet("href");
        need(!/^\/\//.test(href), "Protocol-relative links forbidden");
        if (href && !/^(https?:|mailto:)/.test(href)) {
          const targetUrl = new URL(href, "http://local" + p.url);
          const [file] = href.split("#");
          const target = href.startsWith("#")
            ? p
            : pages.find(
                (c) =>
                  c.absolute === path.resolve(path.dirname(p.absolute), file) ||
                  c.url === targetUrl.pathname,
              );
          need(target, "Missing reference: " + p.path + " -> " + href);
          const anchor = decodeURIComponent(targetUrl.hash.slice(1));
          need(
            !anchor || target.anchors.has(anchor),
            "Missing heading anchor: " + href,
          );
          token.attrSet(
            "href",
            target.url + (anchor ? "#" + encodeURIComponent(anchor) : ""),
          );
          linkCount++;
        }
      }
      if (token.children) visit(token.children);
    }
  }
  visit(p.tokens);
  p.html = md.renderer.render(p.tokens, md.options, {});
}
const snapshotHash = hash(raw + pages.map((p) => p.sha256).join(""));
const nav = (current) =>
  pages
    .map(
      (p, i) =>
        `<a href="${p.url}" ${p.id === current ? 'aria-current="page"' : ""}><span>${String(i + 1).padStart(2, "0")}</span>${esc(p.title)}</a>`,
    )
    .join("");
function shell(title, body, p) {
  const current = p?.id || "";
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)} · ${esc(manifest.title)}</title><link rel="stylesheet" href="${basePath}style.css"></head><body><a class="skip" href="#main">본문으로 건너뛰기</a><header><a class="brand" href="${basePath}">${esc(manifest.title)}</a><span class="edition">LOCAL KNOWLEDGE · 고정 스냅샷</span></header><div class="layout"><aside class="sidebar"><details class="menu" open><summary>페이지 탐색</summary><nav aria-label="페이지 탐색">${nav(current)}</nav></details><section class="search" aria-label="지식 검색"><label for="query">문서에서 찾기</label><input id="query" type="search" placeholder="검색어를 입력하세요…" autocomplete="off"><p id="search-status" role="status"></p><ul id="results"></ul></section></aside><main id="main" tabindex="-1"><div class="eyebrow">${p?.kind === "evidence" ? "근거와 확인 범위" : "작업 지식"}</div>${body}${p ? `<details class="provenance"><summary>이 문서의 근거와 스냅샷 정보</summary><p>문서 검토: ${esc(p.evidence?.reviewStatus || "미확인")} · 실환경 검증: ${esc(p.evidence?.liveStatus || "미확인")}</p><p>기준 revision: <code>${esc(manifest.revision)}</code></p><p>이 문서는 고정 스냅샷이며 이후 변경을 자동 감지하지 않습니다.</p><p>문서 해시: <code>${p.sha256}</code></p><p>스냅샷 해시: <code>${snapshotHash}</code></p>${manifest.evidencePage ? `<a href="${pages.find((entry) => entry.id === manifest.evidencePage).url}">근거와 확인 범위 보기</a>` : ""}</details>` : ""}<footer>읽고, 판단하고, 확인한 뒤 실행하세요.<span>${esc(manifest.title)}</span></footer></main><aside class="toc" aria-label="이 페이지에서"><p>이 페이지에서</p>${
    p
      ? p.headings
          .filter((h) => h.level === 2)
          .map(
            (h) => `<a href="#${encodeURIComponent(h.id)}">${esc(h.title)}</a>`,
          )
          .join("")
      : ""
  }</aside></div><script src="${basePath}search.js" defer></script></body></html>`;
}
fs.mkdirSync(output, { recursive: true });
for (const p of pages) {
  const dest = p.id === manifest.home ? output : path.join(output, p.id);
  fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(
    path.join(dest, "index.html"),
    shell(
      p.title,
      `<article data-source-sha256="${p.sha256}">${p.html}</article>`,
      p,
    ),
  );
}
fs.writeFileSync(
  path.join(output, "404.html"),
  shell(
    "페이지를 찾을 수 없습니다",
    `<h1>이 페이지를 찾지 못했습니다.</h1><p>주소가 바뀌었거나 존재하지 않는 페이지입니다. 탐색 메뉴에서 필요한 작업을 선택하세요.</p><a class="home-link" href="${basePath}">시작 페이지로 돌아가기 →</a>`,
  ),
);
fs.writeFileSync(
  path.join(output, "search-index.json"),
  JSON.stringify(
    {
      revision: manifest.revision,
      snapshotHash,
      pages: pages.map(({ id, title, summary, body, sha256, url }) => ({
        id,
        title,
        summary,
        body,
        sha256,
        url,
      })),
    },
    null,
    2,
  ),
);
for (const asset of ["search.js", "style.css"])
  fs.copyFileSync(path.join(__dirname, asset), path.join(output, asset));
fs.appendFileSync(path.join(output, "style.css"), "\n" + fs.readFileSync(path.join(__dirname, "visuals.css"), "utf8"));
const inputHashes = {
  "manifest.json": hash(raw),
  ...Object.fromEntries(pages.map((p) => [p.path, p.sha256])),
};
for (const [file, expected] of Object.entries(inputHashes))
  need(
    hash(fs.readFileSync(safe(file))) === expected,
    "Input changed during build: " + file,
  );
const outputHashes = Object.fromEntries(
  walk(output).map((file) => [
    path.relative(output, file),
    hash(fs.readFileSync(file)),
  ]),
);
const receipt = {
  schemaVersion: 1,
  kind: "local-build-integrity-receipt",
  scope:
    "Exact local input/output bytes only. Not semantic review, live Git observation, or live-system verification.",
  revision: manifest.revision,
  snapshotHash,
  inputs: inputHashes,
  outputs: outputHashes,
};
fs.writeFileSync(
  path.join(output, "build-receipt.json"),
  JSON.stringify(receipt, null, 2),
);
console.log(
  JSON.stringify(
    {
      ok: true,
      output,
      pages: pages.length,
      validatedBodyLinks: linkCount,
      snapshotHash,
      receipt: path.join(output, "build-receipt.json"),
    },
    null,
    2,
  ),
);
