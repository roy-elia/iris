---
owner: roy-elia
status: active
last_updated: 2026-11-24
source_of_truth: local
tags: [index]
---
# docs index

Purpose: shared, durable context for iris. Read this before placing or finding a file.

| File | Summary (one line) | Read when | Owner |
|---|---|---|---|
| `README.md` (repo root) | Download, build from source, develop commands, licence | Building or releasing | roy-elia |

No other docs exist yet.

## Where does X go
| I am producing | Put it in | Owning skill | Tracked |
|---|---|---|---|
| File-operation logic | `Sources/DropCore/` | manual | Yes |
| App, wheel, panel and window UI | `Sources/FileDropUtility/` | manual | Yes |
| Unit tests | `Tests/DropCoreTests/` | manual | Yes |
| Icon and sound resources | `Resources/` | manual | Yes |
| Build, install, lint and test scripts | `scripts/` | manual | Yes |
| A decision and its reasoning | `docs/decisions/YYYY-MM-DD-<topic>.md` (created on first use) | manual | Yes |
| Session handoff | `state/iris/HANDOFF.md` (created on first use) | session-handoff | Yes |
| Exploratory draft | `output/` (created on first use) | any | No |
| Scratch or pulled copy of an external page | `temp/` (created on first use) | any | No |

## Sources of truth
| Content | System of record | Role of this repo | Link recorded in |
|---|---|---|---|
| Code, docs, decisions | This repository | Owner record | none |
| Releases | GitHub Releases on roy-elia/iris (per `README.md`) | Link only | `README.md` |
| Tickets and bugs | Not recorded (owner question in `AGENTS.md`) | Unknown | none |

## Rules for this folder
- Every Markdown file here starts with front matter (`templates/front-matter.md` in ai-standards).
- Summaries come before raw sources; raw files go in a `sources/` folder beside their summary.
