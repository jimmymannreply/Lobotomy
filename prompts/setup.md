# /setup - Reply Daily Activity Monitor Setup Wizard

You are running the interactive first-run setup for the Reply Daily Activity Monitor. Follow this prompt file exactly. Do not skip steps, do not batch multiple questions together, and do not write to disk until Step 5.

## Step 0 - Confirm prerequisites

Before asking any config questions, silently check the environment:

1. Read `.cursor/mcp.json` to confirm `workiq` and `workiq-preview` are registered.
2. Call `GetMcpTools` with `{"pattern": "workiq"}` to confirm both MCP servers are usable in the current Cursor session.
3. From the shell, run `pandoc --version`. If that fails, also probe the standard winget install locations before declaring pandoc missing:

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

If the WorkIQ servers are registered in `mcp.json` but `GetMcpTools` reports them as `needsAuth`, tell the user to run this once from PowerShell and then reopen Cursor:

```powershell
npx -y @microsoft/workiq@latest accept-eula
npx -y @microsoft/workiq@latest ask "Hello"
```

Do not attempt to complete Entra sign-in from inside chat.

## Step 1 - Detect existing config

Check whether `config/monitor.config.json` already exists.

- **If it does**: read it, summarize its current settings, and use `AskQuestion` to ask whether to (a) keep it and just re-install the automation, (b) update specific fields, or (c) start over. Only proceed to Step 2 if they pick (b) or (c).
- **If it does not**: proceed to Step 2.

## Step 2 - Capture configuration (one question per turn)

Walk through these questions in order. Use plain chat for freeform text answers and `AskQuestion` when there is a discrete set of options. Never batch two config questions in one turn - the recipient should see each choice clearly before answering.

Fields, in order:

1. **`monitor_name`** (plain chat) - "What do you want to call this monitor? For example, 'AEM/Juliette DAM Monitor' or 'Contoso Migration Watch'."
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
9. **`output.sharepoint_site_url`** (plain chat) - "Full SharePoint site URL where sweeps should be uploaded (e.g. https://valoremreply.sharepoint.com/sites/AEMDAM)."
10. **`output.sharepoint_folder_path`** (plain chat) - "Server-relative folder inside that site, e.g. 'Shared Documents/Daily Activity Monitor'."
11. **`schedule.cron`** (`AskQuestion` single-select) with follow-up mapping to cron:
    - "Weekdays at 8:30 AM" -> `30 8 * * 1-5`
    - "Every day at 8:00 AM" -> `0 8 * * *`
    - "Every day at 5:00 PM" -> `0 17 * * *`
    - "Custom cron expression" -> follow-up plain chat asking for a valid 5-field cron string; validate that it has exactly 5 whitespace-separated fields.

    Also capture `schedule.display_time` as a human-readable rendering of the choice.

12. **`review.required_on_scheduled`** and **`review.required_on_ondemand`** - default both to `true`. Confirm with a single `AskQuestion`:
    - "Always pause for chat review before uploading (recommended)"
    - "Auto-upload scheduled runs, only review on-demand runs"
    - "Auto-upload everything (not recommended)"

    Set both booleans accordingly.

13. **`ambiguity.borderline_policy`** - default `"needs_your_call"`. Confirm with `AskQuestion`:
    - "Send weak/single-term matches to a 'Needs Your Call' review bucket (recommended)"
    - "Auto-include them"
    - "Auto-exclude them"

## Step 3 - Show the summary

Print a compact Markdown table of every captured field and its resolved value. End with: "Type 'yes' to save this configuration, or tell me what to change."

Wait for confirmation. If they ask for a change, loop back to that specific question only.

## Step 4 - Validate against the schema

Before writing, validate the assembled object against [schemas/monitor.config.schema.json](../schemas/monitor.config.schema.json). If any required field is missing or malformed, explain which field failed and re-prompt only that field. Do not proceed to Step 5 until validation passes.

## Step 5 - Write the config file

Write `config/monitor.config.json` with the validated object. Include `"$schema": "../schemas/monitor.config.schema.json"` as the first key so IDEs pick up autocomplete.

Do not print the full file contents in chat after writing - just confirm the path and a one-line summary ("Saved config/monitor.config.json for monitor '<monitor_name>' with N seed terms and M workflow stages.").

## Step 6 - Offer to install the daily automation

Use `AskQuestion` to ask: "Install the daily automation now? It will trigger `/sweep` on your schedule (`<display_time>`) and stop at review."

- **If yes**: read [automations/daily-sweep.json](../automations/daily-sweep.json). Substitute the user's chosen cron into the `cron.cron` field. Then call the `cursor-app-control.open_automation` tool with the resulting object as `prefillWorkflowData`. Tell the user to click "Save" in the Automations editor that opens - explain that the editor is where scheduling and any deferred fields are finalized.
- **If no**: tell them they can install it later with `/setup` again or by opening the Automations editor manually and importing from `automations/daily-sweep.json`.

## Step 7 - Suggest a first run

End the wizard with: "Setup is complete. Type `/sweep` whenever you want to run your first sweep. I'll stage the results and pause for your review before anything is uploaded to SharePoint."

Do NOT auto-run `/sweep` at the end of setup.
