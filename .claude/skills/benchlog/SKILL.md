---
name: benchlog
description: Drive the BenchLog repair-bench app on this Mac from the shell with the `benchlog` command - list and show repairs, open a repair (or a warranty repair) for a device, move a repair's status, add notes, find customers, devices, and parts, and search. Use when the user asks about their repairs, customers, devices, or parts stock, or names BenchLog.
---

# BenchLog

`benchlog` runs commands in the BenchLog app. Changes show in its window at once and
can be undone there. If the app is closed, the command opens it in the background.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code`
  and `error.message`, and do what the message says.
- A repair goes by its ticket: `42`, `0042`, or `#0042`. Customers, devices, and parts
  go by an 8-character id from their `list` command.
- `repair status` refuses to start work the customer hasn't approved. Ask the user
  before adding `--force`.
- This is the shop's customer data: read only what the task needs, and never copy
  phone numbers, emails, or passcodes elsewhere.
- To try something without real data, put `APP_STORE=/tmp/benchlog-test.sqlite` in
  front of the command.

## Main commands

| Command | Does |
| --- | --- |
| `benchlog status --json` | Open repairs by status, low-stock parts, the open page |
| `benchlog repair list --open [--status ready] [--search T] --json` | Find repairs |
| `benchlog repair show 42 --json` | One repair with its notes and parts |
| `benchlog repair add --device <id> --complaint T [--warranty-of 42] --json` | Open a repair |
| `benchlog repair status 42 --to ready --json` | Move it: intake, diagnosing, awaitingApproval, waitingOnParts, inProgress, ready, pickedUp, cancelled |
| `benchlog repair note 42 --text T --json` | Add a note to its timeline |
| `benchlog device list --search T --json`, `customer list`, `part list --low` | Find the rest |
| `benchlog search T --json` | Search everything, as the search field does |
| `benchlog open repairs` or `benchlog open 42` | Show a page or a repair in the window |

Everything else: `benchlog help`, and `benchlog help <command>` for its options.
For Claude Desktop or another MCP client: `benchlog mcp` serves the same commands.
