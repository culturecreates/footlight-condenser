# Archived Distillator Phase I Status

This file is retained as project history only.

Do not use it as the current operator workflow. Use these documents instead:

- `docs/distillator_migration.md` for the production transition playbook
- `docs/rollout_modes.md` for the current rollout glossary

Current rollout contract:

- operator-facing production states are `legacy`, `shadow`, and `active`
- `internal` remains a private compatibility alias only where older runtime callers still need it
- replay remains diagnostic-only and is not part of the production transition path

Historical phase language is intentionally archived here and should not be copied into operator UI or transition runbooks.
