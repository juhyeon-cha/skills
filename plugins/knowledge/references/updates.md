# Editing constraints

`prepare` validates decisions and current documents, then stores an immutable packet containing
before/after text, original bindings, source snapshots and next bindings. It does not edit documents.
For new claims/documents, consolidation or an index used as current evidence, read
[impact and structural changes](maintenance.md) before preparing the packet.

- `keep` preserves the exact excerpt but supplies valid after-snapshot evidence. A renamed path
  can be updated here without changing prose.
- `replace` supplies different nonblank prose and nonempty after-snapshot evidence.
- `remove` supplies empty text and evidence. Only the excerpt is removed; its surrounding Markdown
  and document file remain. Review the complete final prose for broken structure.

Edited excerpts must be unique and nonoverlapping. All retained claims, including unchanged ones,
are checked for literal presence and existing source paths after the proposed edits. These checks
cannot establish semantic correctness. Each new preparation clears any previous review selection;
the newly returned packet must be independently reviewed.

Application preflights every document against expected original or exact planned bytes. Known
conflicts fail before any write. Files are replaced individually through sibling temporary files;
permission bits are preserved, but ownership, ACLs, extended attributes, timestamps and inode
identity are not. Symlinks, multiply linked files and special files are rejected during apply.
Use ordinary text files in an exclusively owned workspace. See [recovery](workflow.md) for partial
application. All-removed claims yield null next bindings; further starts fail until a separate
project is initialized with a new reviewed baseline. Files are not deleted automatically.
