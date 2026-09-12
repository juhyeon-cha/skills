---
name: release
description: Release a skills marketplace plugin through versioning, validation, commit, tag, push and a published GitHub Release with automatically generated notes. Use on a "릴리스해줘" or "<plugin> 버전 올려줘" request; an explicit release approval covers push and publication for that release.
---

# Releasing a plugin

Input: the plugin name — `plugins/<name>/` in the skills repo. The version has exactly one source,
`plugins/<name>/.claude-plugin/plugin.json`, and the marketplace reads it from there; the
CHANGELOG is `plugins/<name>/CHANGELOG.md`; the tag is `<name>-v<version>`. Nothing else holds the
number independently. Generated runtime manifests derive it from that source; never bump them by hand.

An explicit user request or approval to release covers the release commit and tag push to
`origin`'s default branch and GitHub Release publication for that release. Proceed without
asking again. A preparation-only request ends before push. Editing this skill is not itself
an instruction to publish a release.

Work in the assigned linked worktree. Before writing the entry, fetch the default branch
and inspect the commits that would be pushed; the approved release scope must cover them.
Check GitHub CLI authentication and resolve `origin` to its GitHub repository for `--repo`.

## 1. Sweep the changes since the previous tag

```bash
PREV=$(git tag -l '<name>-v*' --sort=-v:refname | head -1)
git log --oneline "${PREV:+$PREV..}HEAD" -- plugins/<name>
```

When no `<name>-v*` tag exists, the sweep starts at the first commit — say so in the output ("no
previous tag; swept from the first commit") and in the entry. Read every commit in the range,
not just the subjects: the width decision below needs the diff of anything that changes what an
install has to do by hand — for `harness`, the update section of
`plugins/harness/skills/setup/SKILL.md`.

## 2. Settle the width

The width is decided by **what an install has to do by hand**, never by the size of the diff — an
install must be able to tell from the number alone whether `claude plugin update` is all it takes.

| Width | When | Examples |
|---|---|---|
| PATCH | the plugin update is everything | fixes, wording, internal gate changes |
| MINOR | the plugin grew, an install touches nothing | a new skill, check, or subcommand |
| MAJOR | an install has hand work | a renamed or removed skill people call by name; a new context file an install must create; a shape change of a file the install owns; a removed subcommand |

**The setup-skill diff of step 1 looks one way — it is a pointer, not a judgment.** It catches hand
work only when the setup skill was updated to say so; hand work that appeared without that edit is
not caught, and an install that then updates on a narrow number has its gate break right after with
no procedure to follow. So read the range for hand work directly, and treat an empty diff as "not
found", never as "none". (No gate sees the width — the judgment is natural language, settled once
per release over the whole range, so there is nothing for a commit to be compared against.)

A plugin nobody has installed yet stays at its current number — raising it tells nobody anything.
When the rule says MAJOR and you decide not to widen, write that judgment into the entry in one
line; the next reader must not have to rediscover it.

## 3. Write the entry

`plugins/<name>/CHANGELOG.md`: a new entry at the top, heading `## <version> — YYYY-MM-DD` (today's
date; `<version>` is the number the width from step 2 produces), body = what an install receives in
this edition, grouped by what changed, with the width judgment as its first line. The entry is
filled once, here — never per commit.

**Write it before running step 4** — the script refuses to move while the top heading is not this
release's, so a version that rose without an entry cannot happen.

When the plugin gained or lost a skill, `plugin.json`'s `description` gets the matching phrase, and
`README.md` plus `.claude-plugin/marketplace.json` copy that sentence verbatim — `plugin.json` is
the original. Do that here too; step 4 commits those files along with the version.

## 4. Run the script

```bash
bash scripts/release.sh <name> <patch|minor|major>
```

It computes the next number, checks the preconditions, raises `version` in
`plugins/<name>/.claude-plugin/plugin.json`, regenerates harness runtime metadata from its common
distribution module, runs `claude plugin validate --strict` on both the marketplace and the plugin
and the repository gate, commits, tags `<name>-v<version>`, and pushes both. **Everything that
changes state comes after the preconditions**, so a refusal at that stage leaves nothing behind, and
a generation, validation or gate failure restores the original manifest and generated metadata.
Harness releases require Node and a consistent source artifact before the bump. The script
accepts the default branch or a linked worktree branch and requires `origin`'s default
branch to be an ancestor of HEAD. It pushes HEAD directly to that default branch.

**rc≠0: read what it printed and fix that.** Do not do the steps by hand instead — the script is
where the version, the CHANGELOG heading, and the tag name are held to one number.

The harness runs the script in the assigned linked worktree under the release approval.
The main checkout remains untouched. Read the printed outgoing commit list; the push carries
those commits and the release commit without a squash merge, keeping the tag reachable.

The push is atomic — the commit and the tag land together or neither does. **A tag alone on the
remote is the orphan this avoids**, so do not push one by hand after a partial failure; the script
prints what to rerun and what to undo.

## 5. Publish the GitHub Release

After the atomic push succeeds, publish the pushed tag in the repository resolved from `origin`:

```bash
gh release create <name>-v<version> --repo <origin-owner/repo> --verify-tag --generate-notes
```

Use GitHub's generated notes as-is; the repository CHANGELOG remains the versioned install
history from step 3. Release approval includes this step. If publication fails after push,
keep the pushed commit and tag and retry publication only. On an uncertain response, first
check `gh release view` for that tag to avoid creating a duplicate.

## Completion criterion

`git tag -l '<name>-v<version>'` prints the tag, `jq -r .version plugins/<name>/.claude-plugin/plugin.json`
prints the same number, and `head -3 plugins/<name>/CHANGELOG.md` shows the dated heading — all three
read back in this session.

**One more, because the push is what the release is for**: `git merge-base --is-ancestor <name>-v<version> origin/<default branch>`
returns 0. It is the assertion the orphan defect would fail, and it reads the remote rather than the
local tag.

Read `gh release view <name>-v<version> --repo <origin-owner/repo> --json tagName,isDraft,url`.
The tag must match and `isDraft` must be false. Report the published URL; a successful push
without a published GitHub Release is incomplete.
