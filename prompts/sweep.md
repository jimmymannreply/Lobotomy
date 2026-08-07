# /sweep - Reply Daily Activity Monitor Sweep

You are running a single sweep of the user's configured M365 activity through the WorkIQ MCP. Follow this file exactly. Do not write anything to the delivery destination here - that happens in [prompts/review-and-write.md](review-and-write.md) after explicit chat approval.

This whole file is read-only against M365. Do not call `create_entity`, `update_entity`, `delete_entity`, or `do_action` at any point.

## Step 0 - Load and validate config

1. Read `config/monitor.config.json`. If it doesn't exist, tell the user to run `/setup` first and stop.
2. Validate it against [schemas/monitor.config.schema.json](../schemas/monitor.config.schema.json). If validation fails, print the failing field and stop.
3. Confirm WorkIQ MCP is authenticated (`GetMcpTools` with `{"pattern": "workiq"}`). If `needsAuth`, quote the sign-in remediation from [SETUP.md](../SETUP.md#workiq-sign-in-loops-or-fails) and stop.

## Step 1 - Create the run folder

Compute the run timestamp as `YYYY-MM-DD-HHMM` in the user's local time. Create `output/<timestamp>/`. Every artifact for this sweep lives inside that folder.

Write `output/<timestamp>/run.json` first, containing:

```json
{
  "monitor_name": "<from config>",
  "started_at": "<ISO 8601 local time>",
  "config_snapshot": { ...verbatim copy of monitor.config.json... },
  "status": "querying"
}
```

Update the `status` field as the run progresses (`querying` -> `classifying` -> `staged` -> `delivered` -> `done`).

## Step 2 - Query WorkIQ per seed term across all surfaces

Resolve the WorkIQ server names first via `GetMcpTools` with `{"pattern": "workiq"}`. Cursor prefixes user-scoped servers, so expect `user-workiq` and `user-workiq-preview`. Never hardcode a server name.

Use `ask` on the `workiq` server as the primary query tool. If a result is vague and you need the underlying entity, follow up with the read-only structured tools on `workiq-preview` (`search_paths`, `get_schema`, `fetch`, `fetch_blob`).

For each entry in `config.seed_terms`, query once per surface. Use a query template like these (adapt phrasing to the actual tool signature - do not send this literally as JSON):

| Surface | Query template |
|---------|----------------|
| Meetings | `Find meetings from the last 24 hours where "<seed_term>" appears in the title, agenda, recap, or transcript.` |
| Email | `Find emails from the last 24 hours where "<seed_term>" appears in the subject, body, or attachment metadata. Include sender, recipients, subject, and a 2-sentence excerpt.` |
| Teams | `Find Teams chats or channel messages from the last 24 hours where "<seed_term>" appears in message text or shared file names. Include channel/chat, author, and a 2-sentence excerpt.` |
| Files | `Find files I created, edited, shared, or received in the last 24 hours where "<seed_term>" appears in the filename or in the recent-activity summary.` |

### Copilot activity

Copilot prompt/response history is **not** part of the WorkIQ tool surface - that data lives in Purview audit logs and needs separate admin-granted access. Attempt one probe per sweep:

`Find Microsoft 365 Copilot activity from the last 24 hours where "<seed_term>" appears in a prompt, response, or cited source.`

If it returns nothing usable, record the surface as **unavailable** rather than empty, and say so once in the output. Do not retry it per seed term - a single probe is enough. Never fabricate Copilot activity to fill the section.

Widen the window from 24h to `since <last successful run timestamp from output/*/run.json>` when a prior run exists, so nothing is missed between runs.

Also apply the config's scope filters when the WorkIQ tool supports them:

- `config.scope.meetings` - if not `"all"`, restrict the meetings query to those titles/series ids.
- `config.scope.people_and_chats` - always fetch activity involving these people/chats even without a seed match (see Step 3).
- `config.scope.emails` - if it's an array, restrict to those folders/labels/senders.

Collect the raw responses into an in-memory map keyed by `(seed_term, surface)`.

## Step 3 - Query workflow-stage captures (no seed filter)

For each entry in `config.workflow_stages` (may be empty), issue a WorkIQ query per surface asking for items in the last 24h that reference that stage as a workflow phase (not as a taxonomy tag). Example: `Find meetings, emails, and Teams messages from the last 24 hours discussing the "Sign-off" workflow stage - agenda items, approvals, or explicit stage handoffs.`

Also fetch activity involving anyone/anything in `config.scope.people_and_chats` even when no seed or stage matches, so the user's declared "always watch" list is honored.

## Step 4 - Merge and dedupe

Combine all responses into a flat list of items. Each item must be normalized to:

```json
{
  "id": "<stable id, prefer the WorkIQ-returned id>",
  "surface": "meetings|email|teams|files|copilot",
  "title": "<subject / meeting title / chat topic / filename>",
  "author_or_organizer": "<display name>",
  "when": "<ISO 8601>",
  "url": "<deep link if WorkIQ returned one>",
  "excerpt": "<<= 2 sentences of context>",
  "matched_terms": ["<seed_term>", ...],
  "matched_stages": ["<workflow_stage>", ...],
  "signal_strength": "strong|weak|taxonomy_only",
  "signal_reasons": ["title contains seed", "seed appears only in category tag", ...]
}
```

Dedupe by `id` first; when `id` is absent or duplicated across surfaces, dedupe by `(surface, title, when)` tuple.

## Step 5 - Classify into buckets

Apply the ambiguity policy from the config (`ambiguity.borderline_policy`, `ambiguity.taxonomy_only_matches`):

- **Included** - `signal_strength == "strong"`. Strong = multiple `matched_terms`, OR one term matched in a high-value field (title, subject, meeting recap headline, transcript speaker turn), OR the item is in `config.scope.people_and_chats`, OR the item matched a `workflow_stages` entry with a clear workflow-phase context.
- **Needs Your Call** - `signal_strength == "weak"` AND `borderline_policy == "needs_your_call"`. Weak = single-term match in a low-context field (body-only, generic term, or ambiguous phrasing). Include a one-line `why_needs_call` explanation per item.
- **Excluded** - `signal_strength == "taxonomy_only"` AND `taxonomy_only_matches == "exclude"`. Also excluded: anything the borderline policy resolves as excluded.

Override cases from `borderline_policy == "auto_include"` and `"auto_exclude"` accordingly.

## Step 6 - Stage the Markdown output

Write `output/<timestamp>/sweep.md` with this exact section structure. Do not add sections that aren't in this list; do not omit any. Empty sections should still be present with the header and `_No items._` underneath.

```markdown
# <monitor_name> - Sweep <YYYY-MM-DD HH:MM local>

**Owner:** <owner.display_name> (<owner.upn>)
**Tenants swept:** <tenant names, comma-separated>
**Window:** <since last run or last 24h>
**Seed terms:** <comma-separated>
**Workflow stages:** <comma-separated or "None">

## Summary

| Bucket | Meetings | Email | Teams | Files | Copilot | Total |
|--------|---------:|------:|------:|------:|--------:|------:|
| Included | ... | ... | ... | ... | ... | ... |
| Needs Your Call | ... | ... | ... | ... | ... | ... |
| Excluded | ... | ... | ... | ... | ... | ... |

Use `n/a` rather than `0` in the Copilot column when that surface was unavailable, and add a footnote under the table: `_Copilot activity is not exposed by WorkIQ; this surface was not swept._` A zero and an unavailable surface mean different things to the reader.

## Included

### Meetings
- **<title>** - <organizer>, <when> - <excerpt> [matched: <terms/stages>] [link](<url>)
- ...

### Email
- ...

### Teams
- ...

### Files
- ...

### Copilot Activity
- ...

## Needs Your Call

Items where a single ambiguous seed term matched with weak context. Review each and either promote to Included or drop.

### Meetings
- **<title>** - <organizer>, <when> - <excerpt>
  - _Why this is borderline:_ <one-line reason>
  - _Matched:_ <term(s)/stage(s)>
  - [link](<url>)
- ...

### Email / Teams / Files / Copilot Activity (same structure)

## Excluded (for transparency)

Only the count and reason categories - do not enumerate every item. Format:

- **N items** excluded because seed term appeared only as a taxonomy field value.
- **N items** excluded per `ambiguity` policy.
- **N items** excluded as duplicates of Included items.

## Configuration snapshot

Include a fenced JSON block with the exact `config_snapshot` from `run.json` so the sweep is self-describing when reviewed later.
```

## Step 7 - Render the Word output

Invoke [scripts/render-docx.ps1](../scripts/render-docx.ps1) via the shell tool, passing the Markdown path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/render-docx.ps1 -MarkdownPath "output/<timestamp>/sweep.md" -DocxPath "output/<timestamp>/sweep.docx"
```

Use `powershell`, not `pwsh`. PowerShell 7 is not installed on a default Windows machine, and most recipients will only have Windows PowerShell 5.1. All scripts in this repo are 5.1-compatible.

If pandoc is missing or the conversion fails, quote the troubleshooting section from [SETUP.md](../SETUP.md#pandoc-not-found) and stop before review - do not proceed with only the Markdown file.

## Step 8 - Update run status and hand off to review

Update `run.json` `status` to `"staged"` and record the file paths. Then invoke the review flow from [prompts/review-and-write.md](review-and-write.md).

Do NOT write anything to `config.output.upload_dir` in this file. Delivery only happens after explicit chat approval in the review flow.
