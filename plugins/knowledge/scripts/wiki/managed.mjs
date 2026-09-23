/** Text-only bridge. Input contains only documents authorized for this request. */
import fs from "node:fs";
import path from "node:path";
import {createRequire} from "node:module";
import {parseDocument} from "./markdown.mjs";

const modulePath = process.argv[2];
if (!modulePath || !path.isAbsolute(modulePath)) throw Error("MARKDOWN_RUNTIME_REQUIRED");
const require = createRequire(import.meta.url);
if (require(path.join(modulePath, "package.json")).version !== "14.3.0")
  throw Error("MARKDOWN_RUNTIME_VERSION");
const MarkdownIt = require(modulePath);
const md = new MarkdownIt({html: false, linkify: false});
const input = JSON.parse(fs.readFileSync(0, "utf8"));
const pages = input.map(p => ({...p, ...parseDocument(md, p.text)}));

function resolve(href, page) {
  if (!href || /[\u0000-\u0020\\]/.test(href) || href.startsWith("//")) return null;
  if (/^https?:\/\//i.test(href) || /^mailto:/i.test(href)) return href;
  if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.includes("?")) return null;
  try {
    const at = href.indexOf("#");
    const rawFile = at < 0 ? href : href.slice(0, at);
    const file = decodeURIComponent(rawFile);
    const anchor = at < 0 ? "" : decodeURIComponent(href.slice(at + 1));
    if (/[\u0000-\u001f\\]/.test(file)) return null;
    const canonical = path.posix.normalize(path.posix.join(path.posix.dirname(page.path), file));
    const target = !file ? page : file.startsWith("/")
      ? pages.find(p => p.url === rawFile)
      : pages.find(p => p.repository === page.repository && p.path === canonical);
    if (!target || (anchor && !target.anchors.has(anchor))) return null;
    return target.url + (anchor ? "#" + encodeURIComponent("doc-" + anchor) : "");
  } catch { return null; }
}

for (const page of pages) {
  for (const token of page.tokens)
    if (token.type === "heading_open") token.attrSet("id", "doc-" + token.attrGet("id"));
  function visit(tokens) {
    const links = [];
    for (const token of tokens) {
      if (token.type === "image") {
        token.type = "text"; token.tag = "";
        token.content = "[이미지: " + token.content + "]";
        token.children = null; token.attrs = null;
      } else if (token.type === "link_open") {
        const href = resolve(token.attrGet("href"), page);
        links.push(Boolean(href));
        if (href) { token.attrSet("href", href); token.attrSet("rel", "noreferrer"); }
        else { token.tag = "span"; token.attrs = [["class", "unavailable-link"], ["title", "현재 허용된 문서 또는 제목을 확인할 수 없습니다."]]; }
      } else if (token.type === "link_close" && !links.pop()) token.tag = "span";
      if (token.children) visit(token.children);
    }
  }
  visit(page.tokens);
}
process.stdout.write(JSON.stringify(pages.map(p => ({
  url: p.url, title: p.headings[0]?.title || p.path,
  headings: p.headings.map(h => ({...h, id: "doc-" + h.id})), html: md.renderer.render(p.tokens, md.options, {}),
}))));
