# Worker `ready_for_tasks` Flag

## Problem

Workers were being promoted to `active` status as soon as they sent a heartbeat, even though they were still initializing (apt installs, model loading, etc.). This caused them to be killed with "GPU ready but never claimed tasks" after 180s because the orchestrator expected them to be claiming tasks but they weren't ready yet.

## Solution

Workers now stay in `spawning` status until they explicitly signal `ready_for_tasks=true` in their metadata. Heartbeat alone means "I'm alive", not "I'm ready to work".

## Changes Made

### Orchestrator
- `gpu_orchestrator/worker_state.py`:
  - Added `ready_for_tasks` field to `DerivedWorkerState`
  - Changed `_determine_lifecycle()`: `ACTIVE_READY` now requires both VRAM AND `ready_for_tasks=true`
  - Changed promotion logic: only promote when `ready_for_tasks=true`

- `gpu_orchestrator/control_loop.py`:
  - Updated promotion log message
  - Removed fallback log-based promotion

## Worker Changes Required (Headless-Wan2GP)

The worker needs to set `metadata.ready_for_tasks = true` once the task queue is started.

### How to set it

The worker just needs to include `ready_for_tasks: true` in the metadata when updating. This can be done by merging it into existing metadata updates:

```python
# When updating worker metadata, include ready_for_tasks
current_metadata = worker_record.get('metadata', {})
current_metadata['ready_for_tasks'] = True

supabase.table('workers').update({
    'metadata': current_metadata
}).eq('id', worker_id).execute()
```

Or if the worker already does metadata updates (e.g., for VRAM), just add the flag there.

### When to set it

Set `ready_for_tasks=true` AFTER:
- Task queue/worker loop has started
- Models are loaded (if applicable)
- Worker is actually ready to call `claim_next_task`

Example location in worker code:
```python
# After task queue starts:
logger.info("QUEUE: Task queue started with N workers")
# Include ready_for_tasks=True in subsequent metadata updates
self.ready_for_tasks = True
```

## Deployment Order

1. Deploy orchestrator changes
2. Deploy worker changes

Workers without the flag will stay in `spawning` until they're updated. The longer `spawning_timeout_sec` (600s) will apply instead of `ready_not_claiming_timeout_sec` (180s), so workers won't get killed prematurely.
