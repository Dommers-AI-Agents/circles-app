# Ops scripts

One-off operational shell scripts (env updates, migrations, diagnostics).
Run them from `backend/` — they read `.env` and `scripts/` relative to it:

    tools/ops/update-env-vars.sh

Deploy scripts stay at the backend root: `deploy.sh`, `quick-deploy.sh`,
`deploy-indexes.sh`, `setup-cloud-scheduler.sh`.
