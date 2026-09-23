/** Check local build bytes, never semantic correctness or live source freshness. */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import assert from "node:assert/strict";
const hash = (x) => crypto.createHash("sha256").update(x).digest("hex");
function check() {
  const args = process.argv.slice(2),
    manifestArg = args[0],
    receiptArg = args[1];
  if (!manifestArg || !receiptArg)
    throw Error(
      "Usage: node check.mjs CONTENT_MANIFEST SITE_DIRECTORY [--observed-revision REVISION]",
    );
  if (
    args.length !== 2 &&
    !(args.length === 4 && args[2] === "--observed-revision" && args[3])
  )
    throw Error("Unexpected arguments");
  const observed = args[3],
    manifestPath = path.resolve(manifestArg),
    receiptPath = path.resolve(receiptArg, "build-receipt.json"),
    input = path.dirname(manifestPath),
    output = path.dirname(receiptPath);
  function readConfined(root, file) {
    const absolute = path.resolve(root, file);
    assert(absolute.startsWith(root + path.sep), "Path escapes root: " + file);
    let cursor = root;
    assert(!fs.lstatSync(cursor).isSymbolicLink(), "Symlink root");
    for (const part of path.relative(root, absolute).split(path.sep)) {
      cursor = path.join(cursor, part);
      assert(!fs.lstatSync(cursor).isSymbolicLink(), "Symlink file: " + file);
    }
    assert(fs.statSync(absolute).isFile(), "Not file: " + file);
    return fs.readFileSync(absolute);
  }
  const manifestRaw = readConfined(input, path.basename(manifestPath)),
    receiptRaw = readConfined(output, path.basename(receiptPath)),
    manifest = JSON.parse(manifestRaw),
    receipt = JSON.parse(receiptRaw);
  assert.equal(receipt.schemaVersion, 1);
  assert.equal(receipt.kind, "local-build-integrity-receipt");
  assert.equal(
    receipt.revision,
    manifest.revision,
    "Receipt revision mismatch",
  );
  const expectedInputs = [
    path.basename(manifestPath),
    ...manifest.pages.map((p) => p.path),
  ].sort();
  assert.deepEqual(
    Object.keys(receipt.inputs).sort(),
    expectedInputs,
    "Receipt input inventory mismatch",
  );
  for (const [file, expected] of Object.entries(receipt.inputs))
    assert.equal(
      hash(readConfined(input, file)),
      expected,
      "Input hash mismatch: " + file,
    );
  function inventory(root) {
    return fs.readdirSync(root, { withFileTypes: true }).flatMap((e) => {
      assert(!e.isSymbolicLink(), "Symlink inventory: " + e.name);
      return e.isDirectory()
        ? inventory(path.join(root, e.name)).map((f) => e.name + "/" + f)
        : [e.name];
    });
  }
  assert.deepEqual(
    inventory(input)
      .filter((f) => f.endsWith(".md"))
      .sort(),
    manifest.pages.map((p) => p.path).sort(),
    "Markdown inventory mismatch",
  );
  const actualOutputs = inventory(output)
    .filter((f) => f !== path.basename(receiptPath))
    .sort();
  assert.deepEqual(
    Object.keys(receipt.outputs).sort(),
    actualOutputs,
    "Receipt output inventory mismatch",
  );
  const required = [
    "index.html",
    "404.html",
    "search.js",
    "style.css",
    "search-index.json",
    ...manifest.pages
      .filter((p) => p.id !== manifest.home)
      .map((p) => p.id + "/index.html"),
  ];
  for (const file of required)
    assert(actualOutputs.includes(file), "Missing required output: " + file);
  for (const [file, expected] of Object.entries(receipt.outputs))
    assert.equal(
      hash(readConfined(output, file)),
      expected,
      "Output hash mismatch: " + file,
    );
  const snapshotHash = hash(
    manifestRaw.toString() +
      manifest.pages.map((p) => receipt.inputs[p.path]).join(""),
  );
  assert.equal(
    receipt.snapshotHash,
    snapshotHash,
    "Snapshot identity mismatch",
  );
  const search = JSON.parse(readConfined(output, "search-index.json"));
  assert.equal(search.snapshotHash, snapshotHash);
  assert.equal(search.revision, manifest.revision);
  assert.equal(search.pages.length, manifest.pages.length);
  for (const p of manifest.pages) {
    const entry = search.pages.find((e) => e.id === p.id);
    assert(entry, "Missing search entry");
    assert.equal(entry.body, readConfined(input, p.path).toString());
    assert.equal(entry.sha256, receipt.inputs[p.path]);
  }
  if (observed && observed !== manifest.revision) {
    console.log(
      JSON.stringify(
        {
          ok: false,
          status: "stale",
          reason: "Explicitly supplied revision differs from content manifest",
          manifestRevision: manifest.revision,
          observedRevision: observed,
          scope:
            "Supplied-version comparison only; no live Git or live-system observation.",
        },
        null,
        2,
      ),
    );
    process.exitCode = 1;
    return;
  }
  console.log(
    JSON.stringify(
      {
        ok: true,
        status: "snapshot-consistent",
        inputFiles: expectedInputs.length,
        outputFiles: actualOutputs.length,
        revision: manifest.revision,
        observedRevision: observed || null,
        revisionComparison: observed
          ? "matches-explicitly-supplied-version"
          : "not-requested",
        scope:
          "Local byte integrity and optional supplied-version comparison only. No semantic review attestation, live Git observation, live-system verification, or currentness claim.",
      },
      null,
      2,
    ),
  );
}
try {
  check();
} catch (error) {
  console.log(
    JSON.stringify(
      { ok: false, status: "invalid", reason: error.message },
      null,
      2,
    ),
  );
  process.exitCode = 1;
}
