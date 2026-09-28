# satori

A systemd-free desktop respin of Devuan Excalibur: herbstluftwm on X11, a gum TUI
installer, built with live-build. This is a spec-driven project, so the docs are
the source of truth.

## Read first
- [SPEC.md](SPEC.md): what we're building, the phases, and the acceptance criteria.
- [DECISIONS.md](DECISIONS.md): decided (D-), proposed (P-), and open (O-) decisions, with rationale.
- [docs/desktop-stack.md](docs/desktop-stack.md) and [docs/installer.md](docs/installer.md): detailed designs.

`devuan-custom-distro-spec.md` is the original rough draft. It's been superseded by the files above. Don't treat it as current.

## Working rules
- **Keep the docs in sync.** When a decision changes, update DECISIONS.md (edit the entry and add a dated History line) and every doc that references it, in the same commit. Cross-check SPEC.md, docs/*, and DECISIONS.md for consistency.
- **Don't silently change Decided (D-) entries.** Propose the change to the maintainer first. Proposed (P-) entries are safe defaults to build on, but flag them when they matter.
- **Work phase by phase** (SPEC.md §7). A phase is done only when all its ✅ criteria pass. Prefer small commits per phase step.
- **Before adding any package,** check that it exists in Devuan Excalibur and passes the no-systemd rule (SPEC.md §4).
- **Pin every external build input** by checksum or container digest.
- **Don't add loose config to `includes.chroot/`** unless it's live-session-only. Anything an installed system keeps belongs in a `packages/satori-*` package.
- The maintainer may edit docs directly between sessions. Re-read files rather than relying on memory of earlier sessions.
