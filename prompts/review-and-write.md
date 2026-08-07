# /review - Reply Daily Activity Monitor Review and Upload

You are running the review turn for a staged sweep. This is the ONLY path in the monitor that may upload to SharePoint. It runs after [prompts/sweep.md](sweep.md) has staged `sweep.md` and `sweep.docx` under `output/<timestamp>/`.

Never skip the approval gate. Scheduled Automation runs land here the same way as `/sweep`, and they must not auto-upload.

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

- Prompt: `"Ready to upload sweep.md and sweep.docx to <sharepoint_site_url>/<sharepoint_folder_path>?"`
- Options:
  - `upload` - "Yes, upload both files now"
  - `edit_first` - "Let me edit sweep.md in the editor first, then I'll say /review again"
  - `discard` - "Discard this sweep - do not upload"

Handle each response:

- **`edit_first`**: open `sweep.md` via `open_resource` and tell the user to save the file, then re-run `/review`. Set `run.json` `status` back to `"staged"` (unchanged) and stop.
- **`discard`**: update `run.json` `status` to `"discarded"`. Do not delete the local files. Stop.
- **`upload`**: continue to Step 4.

## Step 4 - Re-render sweep.docx if sweep.md changed

If the user promoted/demoted any items in Step 2, rewrite `sweep.md` to reflect the final bucket assignments first (preserve the exact section structure from [prompts/sweep.md](sweep.md#step-6---stage-the-markdown-output)).

Then re-invoke the docx renderer so the two files stay in sync:

```powershell
pwsh -File scripts/render-docx.ps1 -MarkdownPath "output/<timestamp>/sweep.md" -DocxPath "output/<timestamp>/sweep.docx"
```

If the renderer fails, stop before upload.

## Step 5 - Deliver approved outputs

Filename resolution uses the pattern from `config.output.filename_pattern` with `{yyyy}`, `{mm}`, `{dd}`, `{hhmm}` substituted from the run timestamp. Default pattern: `sweep-{yyyy}-{mm}-{dd}-{hhmm}`.

Branch on `config.output.mode`:

### Mode `local_sync` (default, recommended)

Copy `sweep.md` and `sweep.docx` from `output/<timestamp>/` into `config.output.upload_dir`, renaming to the resolved filename pattern. Use the PowerShell shell tool:

```powershell
Copy-Item -LiteralPath "output/<timestamp>/sweep.md" -Destination "<upload_dir>/<resolved-name>.md" -Force
Copy-Item -LiteralPath "output/<timestamp>/sweep.docx" -Destination "<upload_dir>/<resolved-name>.docx" -Force
```

The OneDrive/SharePoint sync client on the user's machine handles cloud upload. Verify both destination files exist after the copy. If `upload_dir` doesn't exist or is not writable, do NOT create parent directories silently - stop, tell the user which path failed, and leave `run.json` at `"staged"`.

### Mode `sharepoint_api`

Resolve the WorkIQ server via `GetMcpTools` with `{"pattern": "workiq"}` (`workiq`, `user-workiq`, etc.).

Discover the target document library path with `search_paths` and `get_schema` (e.g. search paths matching the site's driveItem collection). Then upload both files by calling `create_entity` against the resolved `driveItem` path with the file bytes base64-encoded. If the library exposes a dedicated upload action instead, use `do_action` with that action's schema.

Upload both files to `<sharepoint_site_url>/<sharepoint_folder_path>/<resolved-name>.md` and `.docx`. Upload sweep.md first, then sweep.docx. If either upload fails:

1. Do NOT retry silently. Tell the user which upload failed and what the WorkIQ error said.
2. Leave `run.json` `status` at `"staged"` so `/review` can be re-run after the underlying issue is fixed.
3. Common causes: user lacks Edit permission on the folder, folder path doesn't exist, WorkIQ token expired. Quote the relevant remediation from [SETUP.md](../SETUP.md#sharepoint-upload-fails-with-permission-denied).

### Mode `both`

Do the `local_sync` copy first, then the `sharepoint_api` upload. Report both destinations in Step 6. If the API upload fails after the local copy succeeded, mark the run as `"partially_uploaded"` in `run.json` and tell the user only the local sync landed.

## Step 6 - Confirm and finalize

On successful delivery:

1. Update `run.json` `status` to `"uploaded"` (or `"partially_uploaded"` per mode `both`) and record the destination paths / URLs.
2. Post a final chat message with the destination path(s) and a one-line reminder that the daily automation is armed for `<display_time>`. For `local_sync`, remind the user that OneDrive will sync the files up to the cloud - opening the file in File Explorer will show a sync status icon.
3. Update `run.json` `status` to `"done"`.

Do NOT delete the local `output/<timestamp>/` folder. It's the local audit trail; the user can prune it themselves.
