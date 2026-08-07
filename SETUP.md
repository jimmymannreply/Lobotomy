# Reply Daily Activity Monitor - Setup Guide

This is the recipient-facing guide. Follow it top-to-bottom on a fresh machine.

## 1. Prerequisites

Install these once. All are one-time installs; the monitor itself doesn't need re-install between runs.

| Tool | Why | Windows install |
|------|-----|-----------------|
| **Cursor** | Runs the agent + Automations that drive the monitor. | https://cursor.com/download |
| **Node.js 18+** | Runs the WorkIQ MCP server via `npx`. | `winget install OpenJS.NodeJS.LTS` |
| **pandoc** | Converts the generated Markdown into Word (`.docx`). | `winget install --id JohnMacFarlane.Pandoc` |
| **Microsoft Entra ID account** | Signs in to WorkIQ. Must have access to the OneDrive/SharePoint destination folder. | Provided by your Reply/Valorem admin |
| **OneDrive sync client** | Carries approved sweeps from your local folder up to SharePoint. Ships with Windows; just make sure your destination folder is synced. | Built in |

Verify each of these from PowerShell after install:

```powershell
node --version   # >= 18
npx --version
pandoc --version
```

### Tenant admin consent

WorkIQ reads your Microsoft 365 data through a Microsoft-operated service, and that service needs **admin consent in your tenant** before anyone can use it. Microsoft's own documentation is explicit: "To access Microsoft 365 tenant data, the WorkIQ CLI and MCP Server need to be consented to permissions that require administrative rights on the tenant."

If nobody at your organization has consented yet, you will hit a consent wall on first sign-in and setup cannot continue. Send your tenant admin to Microsoft's [Tenant Administrator Enablement Guide](https://github.com/microsoft/work-iq/blob/main/ADMIN-INSTRUCTIONS.md), which includes a one-click consent URL. This is a one-time action for the whole tenant.

### Accept the WorkIQ EULA

One-time, per machine. The command itself is the acceptance:

```powershell
npx.cmd -y "@microsoft/workiq@latest" accept-eula
```

It should print `EULA has been accepted` and write `%USERPROFILE%\.work-iq-cli\.workiq.json`. Do this **before** opening the monitor in Cursor - if the MCP server starts first, it gets stuck in a loading state and won't recover without a Cursor restart.

### Sign in to WorkIQ

Also one-time per machine. On Windows this uses the Windows account broker, so it raises a **native account-picker dialog** - you must run it from a real terminal window you can see and click:

```powershell
npx.cmd -y "@microsoft/workiq@latest" ask -q "What meetings do I have today?"
```

Pick your work account when the dialog appears. When the command prints an answer about your calendar, you're signed in and Windows has cached the token. If it instead throws `MsalClientException` with `authentication_canceled`, the dialog was dismissed or never got a chance to show - see [troubleshooting](#workiq-sign-in-fails-with-authentication_canceled) below.

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

1. Walk you through the setup wizard defined in [prompts/setup.md](prompts/setup.md) - it will ask for your monitor name, seed terms, workflow stages, meetings/people/emails scope, destination folder, and daily schedule.
2. Verify the WorkIQ MCP server is registered, the EULA is accepted, and you're signed in.
3. Verify `pandoc` is on your PATH.
4. Write `config/monitor.config.json` and validate it against [schemas/monitor.config.schema.json](schemas/monitor.config.schema.json).
5. Offer to open the Cursor Automations editor with a prefilled daily schedule based on [automations/daily-sweep.json](automations/daily-sweep.json).

The wizard will never ask you for a password, a token, or a client secret. WorkIQ handles sign-in through Entra ID and Windows caches the token. If anything asks you to paste a credential into chat, something is wrong - stop and report it.

## 4. Running a sweep

On-demand:

```
/sweep
```

The agent will query WorkIQ across your configured surfaces, stage `sweep.md` and `sweep.docx` under `output/YYYY-MM-DD-HHMM/`, and post a summary in chat with Included / Needs-Your-Call / Excluded buckets. After you approve, it copies both files into the destination folder you configured.

Scheduled runs work the same way but the trigger is your cron. They also stop at review - nothing is written until you say so in chat.

### How files reach SharePoint

The monitor writes approved sweeps into a **local OneDrive-synced folder**, and the OneDrive client uploads them to SharePoint for you. It does not call the SharePoint API directly.

This isn't a shortcut - it's the only option today. WorkIQ can read your M365 data and can even send mail or create calendar events, but it has no released tool for pushing raw file bytes into a document library. Microsoft's own plugin documentation says `upload_blob` "is not released in the current WorkIQ MCP surface" and directs you to OneDrive/SharePoint for uploads.

Practically this means one thing for you: **pick a destination folder that is actually synced.** If you choose a plain local folder, your sweeps will never appear in SharePoint. After the first run, open the destination in File Explorer and confirm the files show a green sync checkmark.

The config keeps a `sharepoint_api` mode reserved for the day Microsoft ships upload support. Selecting it today makes the review step stop with a clear error rather than silently doing nothing.

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

The monitor registers two servers in [.cursor/mcp.json](.cursor/mcp.json), and they are configured **differently** - this trips people up:

- `workiq` is a **local stdio server** launched with `npx.cmd`.
- `workiq-preview` is a **hosted HTTP server** at `https://workiq.svc.cloud.microsoft/mcp` with OAuth.

There is no `@microsoft/workiq-preview` package on npm. If you find a config that tries to `npx` it, that config is wrong and the server will fail to start every time. The correct shape:

```json
{
  "mcpServers": {
    "workiq": {
      "command": "npx.cmd",
      "args": ["-y", "@microsoft/workiq@latest", "mcp"],
      "tools": ["*"]
    },
    "workiq-preview": {
      "type": "http",
      "url": "https://workiq.svc.cloud.microsoft/mcp",
      "oauthClientId": "ba081686-5d24-4bc6-a0d6-d034ecffed87",
      "oauthPublicClient": true,
      "auth": { "redirectPort": 12798 }
    }
  }
}
```

If Cursor doesn't pick them up:

1. **Fully quit Cursor** (Task Manager -> End Task, or right-click the tray icon -> Quit). A **Reload Window** is not enough - MCP servers are only loaded during Cursor startup.
2. Relaunch Cursor and reopen the monitor folder.
3. Open **Cursor Settings -> MCP** (or press `Ctrl+,` and search "MCP"). If either server shows a **Not enabled** / **Approve** state, click to enable/approve - Cursor gates MCP servers behind explicit user approval for security.
4. Wait ~30 seconds after enabling - on first run, `npx` downloads `@microsoft/workiq` before the server responds.
5. Retry `/setup` in chat. Note that Cursor renames user-scoped servers, so in chat they appear as `user-workiq` and `user-workiq-preview`.

If the servers appear but show a red error, open the Output panel and pick the WorkIQ server from the dropdown to see the startup log. Common causes: `npx` not on the machine PATH that Cursor inherited (reinstall Node.js and restart Cursor), or the EULA hasn't been accepted yet.

### Your global mcp.json is invalid JSON

If *no* MCP servers load at all - not just WorkIQ - your user-level config is probably malformed. Cursor fails silently here; there is no error toast. Validate it:

```powershell
Get-Content "$env:USERPROFILE\.cursor\mcp.json" -Raw | ConvertFrom-Json
```

If that throws, fix the file. A doubled brace or a nested duplicate `mcpServers` key is the usual culprit:

```json
{ "mcpServers": {{ "mcpServers": { ... } }} }
```

There should be exactly one `mcpServers` key and no doubled braces.

### WorkIQ MCP server is stuck "loading" forever

The server was almost certainly started before the EULA was accepted or before you had signed in. It does not recover on its own. Accept the EULA and complete the sign-in from a real terminal (see [prerequisites](#accept-the-workiq-eula)), then **fully quit and relaunch Cursor** so the server restarts against valid state.

### WorkIQ sign-in fails with authentication_canceled

You'll see a stack trace containing:

```
MsalClientException: ErrorCode: authentication_canceled
Microsoft.Identity.Client.Platforms.Features.RuntimeBroker...
```

On Windows, WorkIQ signs in through the Windows Web Account Manager (WAM) broker, which raises a **native account-picker dialog**. It does not use a device-code flow, despite what some docs suggest. That has one important consequence: the sign-in **cannot** be completed from a background or agent-driven shell, because there's no window to click, so MSAL reports it as cancelled instantly.

Run it yourself from a visible terminal:

```powershell
npx.cmd -y "@microsoft/workiq@latest" ask -q "What meetings do I have today?"
```

The question must be passed via the `-q` (or `--question`) flag; positional arguments are not accepted. On Windows PowerShell, use `npx.cmd` rather than `npx` if execution policy blocks the `.ps1` wrapper (see next section).

If the dialog never appears at all, your machine may not be Entra-joined or the broker may be disabled by policy - contact your IT admin. If you get a consent wall instead, see [tenant admin consent](#tenant-admin-consent).

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

### Files were written but never appeared in SharePoint

The monitor copies approved sweeps into `output.upload_dir` and relies on the OneDrive client to sync them up. If the files are on disk but not in SharePoint:

1. Confirm `upload_dir` is inside a synced location. Compare it against your synced roots:

   ```powershell
   $env:OneDrive; $env:OneDriveCommercial
   ```

   A path outside those roots will never sync.
2. Open the folder in File Explorer and check the sync status icon on the files. A green checkmark means synced; blue arrows mean in progress; a red X means the sync failed.
3. Check that OneDrive is actually running and signed in to the same account, and that the folder isn't paused or excluded.
4. Confirm you have **Edit** permission on the underlying SharePoint library. Ask the site owner to grant access if not.

### The review step says SharePoint API upload is not supported

Expected. `output.mode` is set to `sharepoint_api` or `both`, and neither is implemented - WorkIQ has no released file-upload tool. Set `output.mode` to `local_sync` in `config/monitor.config.json` and set `output.upload_dir` to a OneDrive-synced folder, or just re-run `/setup`.

### The daily automation didn't fire

Open Cursor's Automations panel and confirm the automation created by `/setup` is enabled. If it isn't there, re-run `/setup` and answer "yes" when it asks about installing the automation.
