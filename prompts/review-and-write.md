# /review - Reply Daily Activity Monitor Review and Upload

You are running the review turn for a staged sweep. This is the ONLY path in the monitor that may write to the delivery destination. It runs after [prompts/sweep.md](sweep.md) has staged `sweep.md` and `sweep.docx` under `output/<timestamp>/`.

Never skip the approval gate. Scheduled Automation runs land here the same way as `/sweep`, and they must not auto-write.

## Step 0 - Locate the staged run

1. If invoked from `/sweep`, the run folder is already known - use it.
2. If invoked as `/review`, list every subdirectory of `output/` sorted descending by name. Pick the newest whose `run.json` `status` is `"staged"`. If none exist, tell the user there is nothing to review and stop.
3. Read `run.json` to recover the config snapshot and paths. Read `sweep.md` to recover the buckets. Do not re-parse the docx.

## Step 1 - Post the review summary

Post a concise chat message like:

> **Sweep ready for review: <monitor_name>, <YYYY-MM-DD HH:MM>**
> Window: <since ...>
> - Included: N (Meetings X | Email X | Teams X | Files X | Copilot X)
> - Needs Your Call: N
> - Excluded: N
>
> Staged: `output/<timestamp>/sweep.md` and `sweep.docx`.

Do NOT paste the full sweep contents inline. If the user asks to see it, use the `Read` tool to show sections on demand.

## Step 2 - Walk the "Needs Your Call" bucket

For each item in the Needs Your Call section (cap at 20 per turn; if more, tell the user and iterate in batches):

Use `AskQuestion` with a single question per item:

- Prompt: `"[Needs Your Call | <surface>] <title> - <one-line why>"`
- Options:
  - `include` - "Promote to Included"
  - `exclude` - "Drop from this sweep"
  - `keep_borderline` - "Keep in Needs Your Call section"

Update the in-memory bucket assignments as answers come in. Do not edit `sweep.md` yet.

If there are zero Needs Your Call items, skip this step entirely - do not ask a filler question.

## Step 3 - Offer a final quick edit pass

Use `AskQuestion` with one final question:

- Prompt: `"Ready to write sweep.md and sweep.docx to <upload_dir>?"`
- Options:
  - `write` - "Yes, write both files now"
  - `edit_first` - "Let me edit sweep.md in the editor first, then I'll say /review again"
  - `discard` - "Discard this sweep - do not write"

Handle each response:

- **`edit_first`**: open `sweep.md` via `open_resource` and tell the user to save the file, then re-run `/review`. Set `run.json` `status` back to `"staged"` (unchanged) and stop.
- **`discard`**: update `run.json` `status` to `"discarded"`. Do not delete the local files. Stop.
- **`write`**: continue to Step 4.

## Step 4 - Re-render sweep.docx if sweep.md changed

If the user promoted/demoted any items in Step 2, rewrite `sweep.md` to reflect the final bucket assignments first (preserve the exact section structure from [prompts/sweep.md](sweep.md#step-6---stage-the-markdown-output)).

Then re-invoke the docx renderer so the two files stay in sync:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/render-docx.ps1 -MarkdownPath "output/<timestamp>/sweep.md" -DocxPath "output/<timestamp>/sweep.docx"
```

If the renderer fails, stop before writing anything to the destination.

## Step 5 - Deliver approved outputs

Filename resolution uses the pattern from `config.output.filename_pattern` with `{yyyy}`, `{mm}`, `{dd}`, `{hhmm}` substituted from the run timestamp. Default pattern: `sweep-{yyyy}-{mm}-{dd}-{hhmm}`.

Branch on `config.output.mode`:

### Mode `local_sync` (the only implemented mode)

Copy `sweep.md` and `sweep.docx` from `output/<timestamp>/` into `config.output.upload_dir`, renaming to the resolved filename pattern. Use the PowerShell shell tool:

```powershell
Copy-Item -LiteralPath "output/<timestamp>/sweep.md" -Destination "<upload_dir>/<resolved-name>.md" -Force
Copy-Item -LiteralPath "output/<timestamp>/sweep.docx" -Destination "<upload_dir>/<resolved-name>.docx" -Force
```

The OneDrive/SharePoint sync client on the user's machine handles cloud upload. Verify both destination files exist after the copy, and confirm their sizes are non-zero. If `upload_dir` doesn't exist or is not writable, do NOT create parent directories silently - stop, tell the user which path failed, and leave `run.json` at `"staged"`.

### Modes `sharepoint_api` and `both` - not available

Neither mode is implemented, because WorkIQ cannot upload files. Microsoft documents `upload_blob` as "not released in the current WorkIQ MCP surface" and directs callers to OneDrive/SharePoint for uploads. The other write tools (`create_entity`, `do_action`) act on mail and calendar entities, not document-library bytes, and this monitor is forbidden from calling them.

If `config.output.mode` is either of these, stop and tell the user:

> Your config asks for a direct SharePoint API upload, but WorkIQ has no released file-upload tool, so I can't do that. Your sweep is staged at `output/<timestamp>/` and nothing was lost. Set `output.mode` to `local_sync` and `output.upload_dir` to a OneDrive-synced folder - or re-run `/setup` - and then `/review` again.

Leave `run.json` `status` at `"staged"`. Do not silently fall back to `local_sync`: the user asked for a specific destination and deserves to know it didn't happen.

## Step 6 - Confirm and finalize

On successful delivery:

1. Update `run.json` `status` to `"delivered"` and record the destination paths.
2. Post a final chat message with the destination paths and a one-line reminder that the daily automation is armed for `<display_time>`. Remind the user that OneDrive does the actual upload to SharePoint - opening the folder in File Explorer will show a sync status icon on each file, and a green checkmark means it landed.
3. Update `run.json` `status` to `"done"`.

Do NOT delete the local `output/<timestamp>/` folder. It's the local audit trail; the user can prune it themselves.
