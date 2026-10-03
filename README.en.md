# pencil-bridge

**English** | [中文](README.md)

Let AI harnesses (DSH / Claude Code / Codex CLI) connect through **pencil MCP** to **specific `.pen` files and nodes** in Pen.app — to restyle code from the design, extract assets from the design, and write code-side style changes back into the design.

## What problem it solves

A design file and a codebase are two things that drift apart on their own. A designer nudges a spacing value, swaps an icon, or adds a color token in Pen.app, and the code side usually has to chase it by eyeballing screenshots. In the other direction, styles changed in code slowly leave the design file out of date.

pencil-bridge hands that loop to the harness, but three real problems have to be solved first:

1. **Editing the right document.** When the target `.pen` is not open, pencil MCP **silently falls back to the last-focused document and raises no error** — you may be editing the wrong file without knowing. So every command first verifies document identity with a **sentinel**, and stops if it does not match.
2. **Addressing nodes.** Node names are not unique in a design file, so name matching is unreliable. The mapping table stores **node ids**.
3. **Being able to undo a bad write.** `.pen` files are not under version control (they are usually gitignored), so any reverse write (code → design) must build its own compensating backup first.

## What you get

Four commands plus one knowledge hub bundle, installed in a shared location so all three harnesses can use them.

| Command | Codex form | Responsibility | Default direction |
|---|---|---|---|
| `/pencil-init` | `$pencil-init` | Environment check: is Pen.app running, does the MCP binary exist, is MCP registered in each harness, is the socket reachable | Read-only diagnostics; asks before any write |
| `/pencil-map` | `$pencil-map` | Create / update `.pencil-bridge/design-map.yaml` | design → mapping table |
| `/pencil-sync` | `$pencil-sync` | Restyle code from the design; **reverse mode** edits the design file | both ways |
| `/pencil-assets` | `$pencil-assets` | Extract four kinds of assets: bitmaps, vector `path`s, icon references, design variable tokens | design → files |

`pencil-bridge` (the hub bundle) is invocable too, and acts as the control and diagnostic entry point: it explains the overall model, recommends which command to use, and runs stack detection when you have not specified one.

## Install

```bash
git clone https://github.com/LouXiaXiaoHei/pencil-bridge.git ~/Project/pencil-bridge
~/Project/pencil-bridge/bin/link
```

`bin/link` fans the five skills out to the three harness skill roots:

| harness | skill root | method |
|---|---|---|
| DSH | `~/.agents/skills/` | directory symlink |
| Claude Code | `~/.claude/skills/` | directory symlink |
| Codex CLI | `~/.codex/skills/` | copy (symlink following **unverified** — not gambling on it) |

The script is idempotent and safe to re-run. Preview with `--dry-run`, or target one root with `--only agents|claude|codex`.

> The two symlinked roots follow the repo automatically; **the Codex root is a copy, so re-run `bin/link --only codex` after updating the repo**, or its skills will stay on an older revision.

After fanning out, **restart the harness or open a new session** for the skill menu to refresh.

## Using the four commands

- `/pencil-init` — say "pencil won't connect", "the MCP isn't responding", "check the design connection".
- `/pencil-map` — say "build the mapping", "link the design file to pages", "which design file is this page in".
- `/pencil-sync` — say "restyle from the design", "the design changed, sync it"; for reverse, "write this color back into the design".
- `/pencil-assets` — say "export the icons", "extract the assets", "export the design variables to CSS/Dart/colors.xml".

**Codex syntax differs**: Codex CLI uses **`$`** instead of `/`, i.e. `$pencil-init`, `$pencil-map`, `$pencil-sync`, `$pencil-assets`. The skill contents are identical across all three; only the invocation prefix differs.

## Supported stacks

Stack detection covers three kinds and recognises **multi-stack monorepos** (the `stacks` field in the mapping table is a list):

- **Flutter** — `pubspec.yaml`
- **Android / Kotlin** — `build.gradle(.kts)` + `AndroidManifest.xml`
- **Web** — `package.json` plus a bundler config (Vite / Next.js / Nuxt, etc.)

Detection **excludes**: dependency directories (`node_modules/`, `.dart_tool/`, `Pods/`), build-output directories (`build/`, `dist/`, `.next/`, …), host-shell directories (Flutter's `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/` belong to the parent stack and are not separate stacks), and **toolchain / third-party SDK copies vendored inside the repo** (e.g. `tools/<sdk>/`).

## Prerequisites

- **Pen.app must be running** — the MCP reads and writes the design through the app's in-memory model, so with the app closed there is nothing to connect to.
- **The target `.pen` must already be open in Pen.app.** Otherwise the MCP silently falls back to the last-focused document (see "Editing the right document" above).
- pencil MCP must be registered in the relevant harness. `/pencil-init` diagnoses this read-only.

## Safety boundaries

- **Read-only by default**: `/pencil-init` is diagnostics only, and every command asks before writing.
- **Reverse writes carry a compensating backup**: before writing, reverse sync (code → design) `Get`s the target subtree into `.pencil-bridge/backups/<ISO8601>.json` with a rollback instruction, then verifies node-by-node afterwards.
- **A sentinel mismatch stops the run** — it does not retry.
- **Credential files are never read**: every flow explicitly skips `~/.pencil/session-desktop.json`, `~/.pencil/agent-auth`, `~/.dsh/.credentials.yaml`, `~/.claude/.credentials.json` and similar, and never writes them into logs or artifacts. The full seven-entry deny-list is in the credential section of [`skills/pencil-bridge/references/write-safety.md`](skills/pencil-bridge/references/write-safety.md).
- **Writes do not hit disk immediately**: after `execute` returns, changes are not on disk within seconds and require the user to save in Pen.app. Commands say so when they finish.

## Repository layout

```
bin/
  link            fan the five skills out to the three harness roots
  check           validate the skill package (frontmatter, references, no absolute paths, no dangling links)
skills/
  pencil-bridge/  hub bundle: control + 9 references
    references/   mcp-toolbox / document-routing / write-safety / design-map /
                  assets-extraction / init-and-mcp / stack-{flutter,kotlin,web}
  pencil-init/    thin shell pointing back at the hub
  pencil-map/     thin shell
  pencil-sync/    thin shell
  pencil-assets/  thin shell
tests/
  check.test.sh   tests for bin/check (25 cases)
  link.test.sh    tests for bin/link (56 cases, isolated HOME)
docs/
  reference/      pencil MCP write API manual, acceptance record
  superpowers/    design spec and implementation plan
```

## Development

```bash
bin/check                 # validate the skill package; non-zero on failure
tests/check.test.sh       # tests for bin/check
tests/link.test.sh        # tests for bin/link (isolated HOME, never touches real skill roots)
```

Re-run `bin/check` after editing skills; if you changed anything under `skills/`, remember `bin/link --only codex` to refresh the copy.

**Note**: the same stack-detection criterion is duplicated across three per-stack references (`stack-flutter.md`, `stack-kotlin.md`, `stack-web.md`), so wording changes must be applied to all three.

## Documentation

- [Design spec](docs/superpowers/specs/2026-10-01-pencil-bridge-design.md) — full design decisions and constraints
- [Implementation plan](docs/superpowers/plans/2026-10-01-pencil-bridge-implementation.md) — how the 15 tasks were carried out
- [pencil write API manual](docs/reference/pencil-write-api-manual.md) — measured behaviour of the MCP `execute` API
- [Acceptance record](docs/reference/acceptance-2026-10-01.md) — measured results for the six acceptance criteria, plus what remains uncovered

## License

Released under the **MIT License** — see [LICENSE](LICENSE). Copyright © 2026 eatmoreduck.
