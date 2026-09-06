---
name: release
description: Release one plugin of the skills marketplace — sweep the changes since its previous tag, settle the bump width, write the CHANGELOG entry, raise the version in plugin.json, validate, commit, and tag locally. Use on a "릴리스해줘" or "<plugin> 버전 올려줘" request. Tag push and a GitHub release stay out of it unless the user says so explicitly.
---

# Releasing a plugin

Input: the plugin name — `plugins/<name>/` in the skills repo. The version has exactly one source,
`plugins/<name>/.claude-plugin/plugin.json`, and the marketplace reads it from there; the
CHANGELOG is `plugins/<name>/CHANGELOG.md`; the tag is `<name>-v<version>`. Nothing else holds the
number.

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
`plugins/<name>/.claude-plugin/plugin.json`, runs `claude plugin validate --strict` on both the
marketplace and the plugin, commits, and puts a local tag `<name>-v<version>`. **Everything that
changes state comes after the preconditions**, so a refusal at that stage leaves nothing behind, and
a validate failure restores the original `plugin.json`.

**rc≠0: read what it printed and fix that.** Do not do the steps by hand instead — the script is
where the version, the CHANGELOG heading, and the tag name are held to one number.

The tag is local. **Pushing the tag and publishing a GitHub release (`gh release create`) happen
only on the user's explicit instruction**, and an instruction covers one release. The marketplace
carries the edition once the commit reaches `main`; installs pick it up with
`claude plugin marketplace update skills` + `claude plugin update <name>@skills`.

## Completion criterion

`git tag -l '<name>-v<version>'` prints the tag, `jq -r .version plugins/<name>/.claude-plugin/plugin.json`
prints the same number, and `head -3 plugins/<name>/CHANGELOG.md` shows the dated heading — all three
read back in this session.
