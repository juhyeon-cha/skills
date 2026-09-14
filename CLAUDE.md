# Working in the skills repository

This repository is a plugin marketplace. Follow these six rules when working here.

- **Edit `plugins/<name>/` in this repository, not the installed copy.** Changes to
  user-scoped copies (`~/.claude/plugins/…`) are overwritten by the next marketplace
  update. Fix issues found in installed copies here, then update the installation.
- **A file belongs in `plugins/<name>/` only if the installed copy executes or reads it.**
  Marketplace installation copies that entire directory without exclusions. Otherwise,
  fixture-based checks of plugin code belong in `tests/`, and documents read only by
  people or agents developing the harness belong in `docs/`. For the two boundary cases
  (checks of shipped artifacts are development checks; documents referenced by shipped
  code must ship), see `docs/development.md`, "What belongs in the plugin, and what belongs in this repo".
- **The commit gate is `bash scripts/check.sh` from the repository root.** Its exit
  code must be 0. The script's header comments are the source of truth for its checks.
- **Run development checks manually with `bash tests/run-all.sh`.** They are not wired
  into the commit gate; some are slow or access the network or ledger. Its `SKIP` entries
  define what is excluded and why. When changing plugin code, cite results from running
  the relevant checks for that commit.
- **Plugin descriptions must match in three places.** The `description` in
  `plugins/<name>/.claude-plugin/plugin.json` is canonical; the corresponding entry in
  `.claude-plugin/marketplace.json` and the text in `README.md` must match it exactly.
  Gate (c) checks this.
- **The release procedure belongs to `.claude/skills/release/SKILL.md` (`/release`).**
  Follow it when bumping versions or releasing. Release operations belong to this
  repository, not to a harness root; the harness plugin must not carry instructions
  or policies for the publisher, including descriptions of version provenance.
  This boundary applies only to text read by the publisher. Instructions needed by
  installed copies receiving a release must remain in the plugin, such as the update
  procedure in `setup`. The version policy is in the "버전" section of `README.md`.

For other harness development rules (adding hook rules, plugin boundaries, and the
check catalogue), see `docs/development.md`. Rules carried by a development cycle
across target repositories (proving a gate is alive, shell pitfalls, and document
placement) belong in the shipped `plugins/harness/docs/engineering.md`.
