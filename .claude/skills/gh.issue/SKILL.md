---
name: gh-issue
description: Operate GitHub issues with the `gh` CLI end-to-end. Use this skill whenever the user asks to create/list/view/search/update/comment/close/reopen/label/assign/triage issues, including Chinese requests like "提 issue", "查 issue", "关 issue", "加标签", or "批量处理 issue".
---

# GitHub `gh issue` Workflow Skill

Use this skill to turn natural language requests into safe, exact `gh issue` commands and execution steps.

## What this skill is responsible for

- Handle day-to-day issue operations using GitHub CLI.
- Resolve repository context before running commands.
- Prefer non-interactive command flags so automation is stable.
- Provide concise action summaries with issue links and command results.

## Trigger conditions

Activate this skill whenever the user asks for any of the following:

- Create an issue from bug notes, TODOs, meeting notes, or markdown content.
- List, search, or filter issues by state, label, assignee, author, or text.
- View issue details/comments or fetch issue fields in JSON.
- Edit title/body/labels/assignees/milestone.
- Comment, close, reopen, lock, or unlock issues.
- Triage stale issues or do batch issue maintenance.

Do not use this skill for pull-request-only tasks unless the user explicitly asks for both PR and issue workflows.

## Preflight checklist

Before issue operations, run these checks in order:

1. Verify CLI is available:
   - `gh --version`
2. Verify authentication:
   - `gh auth status`
3. Resolve repository context:
   - If user provided repo, use `--repo owner/repo` explicitly.
   - Else, if inside a git repo, use current remote context.
   - Else, request `owner/repo` from user.
4. Verify access:
   - `gh repo view --json nameWithOwner,viewerPermission`

If auth or permissions fail, stop and show exact remediation command.

## Core command templates

### 1) List and search issues

- List open issues:
  - `gh issue list --state open --limit 50`
- Search with query syntax:
  - `gh issue list --search "label:bug is:open sort:updated-desc" --limit 100`
- JSON output for automation:
  - `gh issue list --state all --json number,title,state,labels,assignees,url,updatedAt`

### 2) View issue details

- Basic details:
  - `gh issue view <number>`
- Include comments:
  - `gh issue view <number> --comments`
- Structured fields:
  - `gh issue view <number> --json number,title,body,state,labels,assignees,comments,url`

### 3) Create issue

- Fast create:
  - `gh issue create --title "<title>" --body "<body>"`
- With labels/assignees/milestone:
  - `gh issue create --title "<title>" --body-file <body.md> --label bug --assignee <user> --milestone "<milestone>"`
- Against a specific repo:
  - `gh issue create --repo owner/repo --title "<title>" --body "<body>"`

When body content is long, generate a temporary markdown file and use `--body-file`.

### 4) Edit issue

- Update title/body:
  - `gh issue edit <number> --title "<new-title>" --body-file <body.md>`
- Labels:
  - `gh issue edit <number> --add-label bug --remove-label needs-info`
- Assignees:
  - `gh issue edit <number> --add-assignee <user> --remove-assignee <user>`
- Milestone:
  - `gh issue edit <number> --milestone "<milestone>"`

### 5) Comment and state transitions

- Add comment:
  - `gh issue comment <number> --body "<comment>"`
- Close with reason comment:
  - `gh issue close <number> --comment "<why closing>"`
- Reopen with context:
  - `gh issue reopen <number> --comment "<why reopening>"`
- Lock/unlock:
  - `gh issue lock <number> --reason resolved`
  - `gh issue unlock <number>`

## Recommended workflows

### Workflow A: Create issue from user text

1. Extract title candidates and concise problem statement.
2. Build body template:
   - Background
   - Current behavior
   - Expected behavior
   - Repro steps
   - Scope/impact
   - Acceptance criteria
3. Choose labels/assignee/milestone from user intent.
4. Run `gh issue create ...`.
5. Return issue number + URL + next actions.

### Workflow B: Triage inbox

1. Pull target set with `gh issue list --search ... --json ...`.
2. Group by label/state/assignee.
3. Suggest edits before batch execution when impact is broad.
4. Apply edits with explicit commands.
5. Report changed issues in a compact table.

### Workflow C: Batch updates (safe mode)

1. Preview target list first.
2. Execute updates in a loop only after preview:
   - Example pattern:
     - `gh issue list --search "label:needs-triage" --json number --jq '.[].number'`
3. Apply one command per issue and capture failures.
4. Summarize success/failure counts.

Never run destructive or broad-scope batch operations without an explicit user request.

## Output format for final response

Use this structure after completing commands:

- Repo: `owner/repo`
- Actions executed: short bullet list of command intents
- Results:
  - `#123` <title> - <state> - <url>
  - `#456` <title> - <state> - <url>
- Failures (if any): reason + retry command
- Suggested next step: one practical follow-up

## Error handling playbook

- Not logged in:
  - `gh auth login`
- Wrong repo context:
  - add `--repo owner/repo`
- Permission denied:
  - show `viewerPermission` from `gh repo view` and explain limitation
- Missing issue number:
  - run filtered list first and let user pick target
- Validation/API errors:
  - rerun command with minimal flags, then add fields incrementally

## Practical examples

### Example 1: "Create a bug issue"

User intent: "帮我提一个 issue，描述登录后首页白屏。"

Action outline:

1. Draft title: `bug(web): blank home page after login`
2. Draft structured body from user context.
3. Run:
   - `gh issue create --title "bug(web): blank home page after login" --body-file /tmp/issue-body.md --label bug`

### Example 2: "Find stale issues and close them with comment"

1. Preview stale targets:
   - `gh issue list --search "is:open updated:<2025-12-01 label:needs-info" --json number,title,url`
2. After confirmation, close each issue with:
   - `gh issue close <number> --comment "Closing due to inactivity. Reopen if this is still relevant."`

## Quality bar

- Commands must be executable as-is.
- Repo context must be explicit when ambiguous.
- Use JSON output when parsing is needed.
- Responses must include URLs for all affected issues.
- Keep user-facing summaries concise and actionable.
