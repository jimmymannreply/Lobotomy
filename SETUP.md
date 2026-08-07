# Reply Daily Activity Monitor - Setup Guide

This is the recipient-facing guide. Follow it top-to-bottom on a fresh machine.

## 1. Prerequisites

Install these once. All are one-time installs; the monitor itself doesn't need re-install between runs.

| Tool | Why | Windows install |
|------|-----|-----------------|
| **Cursor** | Runs the agent + Automations that drive the monitor. | https://cursor.com/download |
| **Node.js 18+** | Runs the WorkIQ MCP server via `npx`. | `winget install OpenJS.NodeJS.LTS` |
| **pandoc** | Converts the generated Markdown into Word (`.docx`). | `winget install --id JohnMacFarlane.Pandoc` |
| **Microsoft Entra ID account** | Signs in to WorkIQ. Must have access to the SharePoint destination site. | Provided by your Reply/Valorem admin |

Verify each of these from PowerShell after install:

```powershell
node --version   # >= 18
npx --version
pandoc --version
```

## 2. Get the monitor

You have two options; both leave you with the same files.

**Option A - clone the repo (recommended for ongoing updates):**

```powershell
git clone <this-repo-url> "$HOME\.cursor\agents\Reply_Daily_Activity_Monitor"
```

**Option B - unzip the shareable bundle** you received (`reply-daily-activity-monitor.zip`):

```powershell
Expand-Archive -Path .\reply-daily-activity-monitor.zip -DestinationPath "$HOME\.cursor\agents\Reply_Daily_Activity_Monitor"
```

Then open the folder in Cursor: **File -> Open Folder** and pick the `Reply_Daily_Activity_Monitor` folder.

## 3. First-run setup

In Cursor, open a chat inside the workspace and type:

```
/setup
```

The agent will:

1. Walk you through the setup wizard defined in [prompts/setup.md](prompts/setup.md) - it will ask for your monitor name, seed terms, workflow stages, meetings/people/emails scope, SharePoint destination, and daily schedule.
2. Verify the WorkIQ MCP server is registered and prompt you to sign in with your Entra ID account.
3. Verify `pandoc` is on your PATH.
4. Write `config/monitor.config.json` and validate it against [schemas/monitor.config.schema.json](schemas/monitor.config.schema.json).
5. Offer to open the Cursor Automations editor with a prefilled daily schedule based on [automations/daily-sweep.json](automations/daily-sweep.json).

## 4. Running a sweep

On-demand:

```
/sweep
```

The agent will query WorkIQ across your configured surfaces, stage `sweep.md` and `sweep.docx` under `output/YYYY-MM-DD-HHMM/`, and post a summary in chat with Included / Needs-Your-Call / Excluded buckets. After you approve, it uploads both files to the SharePoint folder you configured and returns the SharePoint URLs.

Scheduled runs work the same way but the trigger is your cron. They also stop at review - nothing is uploaded until you say so in chat.

## 5. Sharing the monitor with someone else

From Cursor chat:

```
/export
```

That runs [scripts/export-package.ps1](scripts/export-package.ps1), which produces `dist/reply-daily-activity-monitor.zip` with:

- All prompts, rules, schemas, scripts, and the automation template.
- The `config/monitor.config.example.json` (a template with no user data).
- **No** `config/monitor.config.json` (your local config is stripped).
- **No** `output/` contents (your swept data is stripped).
- **No** `.git/` history.

Send the resulting zip to anyone at Reply. They repeat this SETUP.md from step 2, Option B.

## 6. Troubleshooting

### WorkIQ MCP is not registered

The monitor registers `workiq` and `workiq-preview` in [.cursor/mcp.json](.cursor/mcp.json). If Cursor doesn't pick them up:

1. **Fully quit Cursor** (Task Manager -> End Task, or right-click the tray icon -> Quit). A **Reload Window** is not enough - project MCP servers are only loaded during Cursor startup.
2. Relaunch Cursor and reopen the `Reply_Daily_Activity_Monitor_v1` folder.
3. Open **Cursor Settings -> MCP** (or press `Ctrl+,` and search "MCP"). You should see `workiq` and `workiq-preview` listed. If either shows a **Not enabled** / **Approve** state, click to enable/approve - Cursor gates project-level MCP servers behind explicit user approval for security.
4. Wait ~30 seconds after enabling - on first run, `npx` downloads the `@microsoft/workiq*` packages before the server responds.
5. Retry `/setup` in chat.

If the servers appear but show a red error, open the Output panel and pick the WorkIQ server from the dropdown to see the startup log. Common causes: `npx` not on the machine PATH that Cursor inherited (reinstall Node.js and restart Cursor), or the EULA hasn't been accepted yet (`npx.cmd -y @microsoft/workiq@latest accept-eula` from a normal PowerShell).

### WorkIQ sign-in loops or fails

Run this once from PowerShell to accept the EULA and complete an interactive sign-in outside of Cursor, then reopen Cursor:

```powershell
npx -y @microsoft/workiq@latest accept-eula
npx -y @microsoft/workiq@latest ask -q "Hello"
```

The second command triggers the Entra device-code flow the first time it's run. The question must be passed via the `-q` (or `--question`) flag - positional arguments are not accepted. On Windows PowerShell, use `npx.cmd` instead of `npx` if execution policy blocks the `.ps1` wrapper (see next section).

### PowerShell blocks npx with "running scripts is disabled on this system"

Fresh Windows installs default the PowerShell execution policy to `Restricted`, which blocks `npx.ps1`. You'll see:

```
npx : File C:\Program Files\nodejs\npx.ps1 cannot be loaded because running scripts is disabled on this system.
```

One-time fix (recommended - still blocks unsigned downloaded scripts, but lets npm/npx wrapper scripts run):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Answer `Y` when prompted, then re-run the failing `npx ...` command.

Alternative one-off: invoke the `.cmd` variant instead of `.ps1` - it bypasses the policy entirely for that call:

```powershell
npx.cmd -y @microsoft/workiq@latest accept-eula
```

### pandoc not found

The monitor calls pandoc from [scripts/render-docx.ps1](scripts/render-docx.ps1). Verify:

```powershell
Get-Command pandoc
```

If missing, re-run the winget install and reopen your terminal (PATH changes need a new shell).

### SharePoint upload fails with permission denied

The Entra ID account you signed WorkIQ into must have **Edit** permission on the SharePoint folder in `output.sharepoint_folder_path`. Ask the site owner to grant access, then retry the review flow with `/review`.

### The daily automation didn't fire

Open Cursor's Automations panel and confirm the automation created by `/setup` is enabled. If it isn't there, re-run `/setup` and answer "yes" when it asks about installing the automation.
