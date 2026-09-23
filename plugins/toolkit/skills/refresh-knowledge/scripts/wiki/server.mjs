/** Serve completed, explicitly selected wiki output on loopback only. */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
const [directory, portArg = "8766", ...extra] = process.argv.slice(2);
const port = Number(portArg);
if (
  !directory ||
  extra.length ||
  !Number.isInteger(port) ||
  port < 0 ||
  port > 65535
)
  throw Error("Usage: node server.mjs SITE_DIRECTORY [PORT]");
const root = path.resolve(directory);
if (!fs.statSync(root).isDirectory() || fs.lstatSync(root).isSymbolicLink())
  throw Error("Expected a real site directory");
const receipt = JSON.parse(
  fs.readFileSync(path.join(root, "build-receipt.json"), "utf8"),
);
if (
  receipt.kind !== "local-build-integrity-receipt" ||
  receipt.schemaVersion !== 1
)
  throw Error(
    "Expected a completed build receipt; run check.mjs before serving",
  );
const allowed = new Set(Object.keys(receipt.outputs));
const notFound = fs.readFileSync(path.join(root, "404.html"));
const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
};
function resolveFile(url) {
  let decoded;
  try {
    decoded = decodeURIComponent(new URL(url, "http://localhost").pathname);
  } catch (error) {
    if (error instanceof URIError || error instanceof TypeError) return null;
    throw error;
  }
  const file = path.resolve(
    root,
    "." + decoded + (decoded.endsWith("/") ? "index.html" : ""),
  );
  const relative = path.relative(root, file);
  if (!allowed.has(relative) || !file.startsWith(root + path.sep)) return null;
  let cursor = root;
  for (const part of relative.split(path.sep)) {
    cursor = path.join(cursor, part);
    if (fs.lstatSync(cursor).isSymbolicLink()) return null;
  }
  return file;
}
const server = http.createServer((req, res) => {
  try {
    const file = resolveFile(req.url),
      body = file ? fs.readFileSync(file) : notFound;
    res.writeHead(file ? 200 : 404, {
      "Content-Type": file
        ? mime[path.extname(file)] || "application/octet-stream"
        : mime[".html"],
      "Content-Security-Policy":
        "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      "X-Content-Type-Options": "nosniff",
    });
    res.end(body);
  } catch (error) {
    console.error(error);
    res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(
      "Local wiki file could not be read. Rebuild and check the snapshot.",
    );
  }
});
server.listen(port, "127.0.0.1", () =>
  console.log("http://127.0.0.1:" + server.address().port),
);
