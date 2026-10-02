# Step 9.2 — enrich the completed-feature entry

Read only when `update_task(status="done")` returned `timeline_events` with more than this task's `task_completed`/`task_deployed`. Otherwise step 9.2 is a no-op.

1. **Confirm the `feature_completed`:**

   ```
   mcp__meridian__list_timeline(project, event_type="feature_completed", limit=1)
   ```

   If the returned event's `id` is in `timeline_events` and its `enrichment` is `null`, that's the entry. No match → end here.

2. **One `question` issue per open question or action of the feature** — what stayed open on closing the feature, not on closing this task:

   ```
   mcp__meridian__create_issue(project, title="<the question or action>", type="question")
   ```

   Keep each `id`. **Don't recreate 9.1's issues**: if one is also a feature-level question, reuse its id. None → no refs.

3. **Write it:**

   ```
   mcp__meridian__enrich_timeline(
       project,
       event_id="<id of the feature_completed>",
       enrichment="<2-4 line recap>",
       refs=[{"ref_type": "issue", "ref_id": "<issue id>"}, ...],
   )
   ```

   **2 to 4 lines**: what the feature did (not the last task), why, and what stayed open. Shorter than 9.1 on purpose — each task's detail is already in its own entry.

Write-once by default: if this never runs (task marked done by hand, dead session), the entry keeps its mechanical summary. The feed has no gaps, only less rich entries.
