# /setup - Reply Daily Activity Monitor Setup Wizard

You are running the interactive first-run setup for the Reply Daily Activity Monitor. Follow this prompt file exactly. Do not skip steps, do not batch multiple questions together, and do not write to disk until Step 5.

## Step 0 - Confirm prerequisites

Before asking any config questions, silently check the environment:

1. Read `.cursor/mcp.json` to confirm `workiq` and `workiq-preview` are registered. `workiq` must be a stdio server launched via `npx.cmd`; `workiq-preview` must be an HTTP server pointing at `https://workiq.svc.cloud.microsoft/mcp`. There is no `@microsoft/workiq-preview` npm package - if you see one configured as a `command`, that registration is wrong and will never start.
2. Call `GetMcpTools` with `{"pattern": "workiq"}` to confirm the MCP servers are usable in the current Cursor session. Cursor prefixes user-scoped servers, so expect names like `user-workiq` rather than a bare `workiq`.
3. Confirm the WorkIQ EULA has been accepted on this machine. State lives in `$env:USERPROFILE\.work-iq-cli\.workiq.json`, which should contain `{"I-accept-EULA": "true"}`. If the file is absent, accept it once:

   ```powershell
   npx.cmd -y "@microsoft/workiq@latest" accept-eula
   ```

   This command *is* the acceptance - it is non-interactive and prints `EULA has been accepted`. Only run it after telling the user you are accepting Microsoft's WorkIQ licence terms on their behalf.

4. Confirm WorkIQ has a cached sign-in. See [Step 0a](#step-0a---workiq-sign-in) below - this is the single most common reason setup stalls.

5. From the shell, run `pandoc --version`. If that fails, also probe the standard winget install locations before declaring pandoc missing:

   ```powershell
   Get-Command pandoc -ErrorAction SilentlyContinue
   Test-Path "$env:LOCALAPPDATA\Pandoc\pandoc.exe"
   Test-Path "$env:ProgramFiles\Pandoc\pandoc.exe"
   ```

   If pandoc is on disk but not on PATH (common right after `winget install`), prepend the containing folder to `$env:PATH` for this shell session and treat the check as passing:

   ```powershell
   $env:PATH = "$env:LOCALAPPDATA\Pandoc;$env:PATH"
   ```

   Then tell the user pandoc was found on disk but their PATH is stale, and recommend they fully quit and relaunch Cursor after the wizard finishes so future terminals inherit the updated PATH.

If pandoc is genuinely missing from both PATH and the standard install locations, do NOT continue the wizard. Explain in chat exactly what is missing and quote the relevant remediation from [SETUP.md](../SETUP.md#1-prerequisites). Ask the user to install the missing prereq and re-run `/setup`.

Same rule for the WorkIQ MCP: if `.cursor/mcp.json` registers `workiq` / `workiq-preview` but `GetMcpTools` doesn't list them, the servers are registered but the Cursor MCP subsystem hasn't loaded them yet. Tell the user to click the MCP approval banner if one is showing (Cursor sometimes prompts before enabling project-level MCPs), or to fully quit and relaunch Cursor - a plain window reload is not always sufficient. Then re-run `/setup`.

## Step 0a - WorkIQ sign-in

WorkIQ authenticates through Entra ID. **The monitor never asks for, sees, or stores a password or token.** If the user offers to paste credentials into chat, decline and point them here.

On Windows, WorkIQ signs in through the Windows Web Account Manager (WAM) broker: it raises a **native Windows account-picker dialog**, not a device-code prompt. That has one critical consequence:

> A WAM sign-in cannot be completed from an agent-run background shell. There is no window to click, so MSAL fails immediately with `authentication_canceled` / `MsalClientException`.

So when sign-in is needed, launch a **visible** terminal and let the user complete it there:

```powershell
Start-Process -FilePath "powershell.exe" -ArgumentList '-NoExit','-NoProfile','-Command','npx.cmd -y "@microsoft/workiq@latest" ask -q "What meetings do I have today?"'
```

Tell the user to pick their work account in the dialog that appears, and to come back to chat when the command prints an answer. Tokens are cached by Windows itself (OneAuth / TokenBroker), not in the WorkIQ folder, so the only reliable proof of sign-in is that the `ask` command returned real data. Once it has, re-run the `GetMcpTools` check.

If the MCP server was started *before* the sign-in or EULA acceptance completed, it will be stuck in a `loading` state and will not recover on its own. Tell the user to fully quit and relaunch Cursor so the server restarts against the now-valid credentials.

Do not attempt to complete Entra sign-in from inside chat, and do not retry a failed WAM sign-in in a background shell - it will fail the same way every time.

## Step 1 - Detect existing config

Check whether `config/monitor.config.json` already exists.

- **If it does**: read it, summarize its current settings, and use `AskQuestion` to ask whether to (a) keep it and just re-install the automation, (b) update specific fields, or (c) start over. Only proceed to Step 2 if they pick (b) or (c).
- **If it does not**: proceed to Step 2.

## Step 2 - Capture configuration (one question per turn)

Walk through these questions in order. Use plain chat for freeform text answers and `AskQuestion` when there is a discrete set of options. Never batch two config questions in one turn - the recipient should see each choice clearly before answering.

Fields, in order:

1. **`monitor_name`** (plain chat) - "What do you want to call this monitor? For example, 'Contoso Migration Watch' or 'Northwind Platform Monitor'."
2. **`owner.display_name`** and **`owner.upn`** (plain chat, one turn each) - display name, then work email.
3. **`tenants`** - v1 supports exactly one tenant. Default to `[{ "name": "Reply", "workiq_profile": "default" }]` and confirm with the user via `AskQuestion` (options: "Reply" / "Enter a different tenant name"). Do not offer multi-tenant here even if the user asks - explain that multi-tenant is planned for a future release and tell them to file a request.
4. **`seed_terms`** (plain chat) - quote the working definition from the original spec:

   > A seed term is a curated trigger keyword that flags potentially in-scope content for capture, subject to relevance review when the match is weak or ambiguous.

   Ask: "List the seed terms/phrases you want the monitor to search for, comma-separated. Prefer specific multi-word phrases over generic single words (e.g. 'AEM asset ingest' over just 'security')."
5. **`workflow_stages`** (plain chat, optional) - "Are there end-to-end workflow stages you also want captured even when no seed term matches? Comma-separated, or type 'none'. Examples: Discovery, Design, Build, Test, Deploy, Sign-off."
6. **`scope.meetings`** (`AskQuestion` single-select):
   - "All meetings on my calendar/recap surface" -> `"all"`
   - "Just specific meetings" -> follow up with a plain chat turn asking for meeting titles or recurring-series identifiers (comma-separated).
7. **`scope.people_and_chats`** (plain chat, optional) - "Any specific people (UPNs), groups, or Teams chats you want monitored regardless of seed match? Comma-separated, or 'none'."
8. **`scope.emails`** (`AskQuestion` single-select):
   - "All email surfaces I have access to" -> `"all"`
   - "Only sent + received" -> `"sent_and_received"` (recommended)
   - "Specific folders / labels / senders" -> follow up with a plain chat turn.
9. **`output.mode`** - v1 supports exactly one working delivery mode: `"local_sync"`. Approved sweeps are written into a local OneDrive-synced folder and the OneDrive client carries them up to SharePoint.

   Set `output.mode` to `"local_sync"` without asking. If the user asks for a direct SharePoint API upload, explain why it isn't available yet:

   > WorkIQ can read your M365 data and can send mail or create calendar events, but it has no released tool for uploading raw file bytes into a document library - Microsoft documents `upload_blob` as "not released in the current WorkIQ MCP surface". So the monitor writes to your OneDrive-synced folder instead. The files still land in SharePoint; OneDrive does the upload. When Microsoft ships upload support, switching to `sharepoint_api` mode is a config change.

10. **`output.upload_dir`** (plain chat) - the folder approved sweeps are copied into. Before asking, detect the user's synced roots from the shell and offer them as concrete options:

    ```powershell
    $env:OneDrive; $env:OneDriveCommercial
    Get-ChildItem "$env:USERPROFILE" -Directory | Where-Object { $_.Name -like 'OneDrive*' -or $_.Name -like '*Reply*' -or $_.Name -like '*Valorem*' } | Select-Object -ExpandProperty FullName
    ```

    Ask: "Where should approved sweeps be written? This should be a folder inside your OneDrive/SharePoint-synced area so the files sync up automatically." Offer the detected roots via `AskQuestion` plus an "Enter a different path" option.

    Validate the answer before accepting it: the parent directory must already exist. If the leaf folder doesn't exist, ask whether to create it rather than creating it silently. Warn (but don't block) if the chosen path is not under a detected OneDrive root, since a non-synced folder means the files never reach SharePoint.

11. **`output.sharepoint_site_url`** and **`output.sharepoint_folder_path`** (plain chat, both optional) - not used for delivery in `local_sync` mode, but recorded in the config and printed in the sweep header so readers know which SharePoint site the synced folder maps to. Ask once: "Which SharePoint site does that folder sync to? (optional - used for the report header only, press enter to skip)."

12. **`output.local_staging_dir`** - set to `"./output"` without asking. This is the per-run staging area inside the repo, not a user-facing choice.

13. **`schedule.cron`** (`AskQuestion` single-select) with follow-up mapping to cron:
    - "Weekdays at 8:30 AM" -> `30 8 * * 1-5`
    - "Every day at 8:00 AM" -> `0 8 * * *`
    - "Every day at 5:00 PM" -> `0 17 * * *`
    - "Custom cron expression" -> follow-up plain chat asking for a valid 5-field cron string; validate that it has exactly 5 whitespace-separated fields.

    Also capture `schedule.display_time` as a human-readable rendering of the choice.

14. **`review.required_on_scheduled`** and **`review.required_on_ondemand`** - default both to `true`. Confirm with a single `AskQuestion`:
    - "Always pause for chat review before writing (recommended)"
    - "Auto-write scheduled runs, only review on-demand runs"
    - "Auto-write everything (not recommended)"

    Set both booleans accordingly.

15. **`ambiguity.borderline_policy`** - default `"needs_your_call"`. Confirm with `AskQuestion`:
    - "Send weak/single-term matches to a 'Needs Your Call' review bucket (recommended)"
    - "Auto-include them"
    - "Auto-exclude them"

## Step 3 - Show the summary

Print a compact Markdown table of every captured field and its resolved value. End with: "Type 'yes' to save this configuration, or tell me what to change."

Wait for confirmation. If they ask for a change, loop back to that specific question only.

## Step 4 - Validate the config

Write the assembled object to `config/monitor.config.json` first (Step 5's file), then validate it with the checker:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-config.ps1
```

Exit code 0 means valid. Exit code 1 means invalid - the script prints one failing field per line.

If validation fails, explain which field failed in plain language and re-prompt **only that field**, then re-run the checker. Do not proceed until it exits 0.

Warnings (printed separately from errors) do not block, but relay them to the user verbatim. The most important one to surface is a destination folder that isn't inside a OneDrive root - that silently means sweeps never reach SharePoint, and the user should know before they rely on it.

Use `powershell`, not `pwsh`: PowerShell 7 is not installed by default on Windows and most recipients will only have 5.1.

## Step 5 - Write the config file

Write `config/monitor.config.json` with the validated object. Include `"$schema": "../schemas/monitor.config.schema.json"` as the first key so IDEs pick up autocomplete.

Do not print the full file contents in chat after writing - just confirm the path and a one-line summary ("Saved config/monitor.config.json for monitor '<monitor_name>' with N seed terms and M workflow stages.").

## Step 6 - Offer to install the daily automation

Use `AskQuestion` to ask: "Install the daily automation now? It will trigger `/sweep` on your schedule (`<display_time>`) and stop at review."

- **If yes**: read [automations/daily-sweep.json](../automations/daily-sweep.json). Substitute the user's chosen cron into the `cron.cron` field. Then call the `cursor-app-control.open_automation` tool with the resulting object as `prefillWorkflowData`. Tell the user to click "Save" in the Automations editor that opens - explain that the editor is where scheduling and any deferred fields are finalized.
- **If no**: tell them they can install it later with `/setup` again or by opening the Automations editor manually and importing from `automations/daily-sweep.json`.

## Step 7 - Suggest a first run

End the wizard with: "Setup is complete. Type `/sweep` whenever you want to run your first sweep. I'll stage the results and pause for your review before anything is written to `<upload_dir>`."

Do NOT auto-run `/sweep` at the end of setup.
