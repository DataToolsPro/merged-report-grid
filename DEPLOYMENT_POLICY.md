# Deployment Policy

## Do NOT Deploy to Production

**NEVER, EVER attempt to deploy to production.**

- Do not run `sf project deploy start` targeting a production org
- Do not use `-o prod` or any production org alias in deploy commands
- Production deployment is performed by the user via change sets or their own processes

## Default Deployment Target: cardiff--datatools Sandbox

When deploying, use the **cardiff--datatools** sandbox (alias: `sandbox`):

- **URL:** https://cardiff--datatools.sandbox.lightning.force.com/
- **CLI alias:** `sandbox`
- **Username:** ryan@goodmangroupllc.co.datatools

```bash
sf project deploy start -o sandbox --test-level NoTestRun
```

This is the QA sandbox. When the user says "deploy," target this org.

## Production Path

Production deployments are the user's responsibility:

1. Deploy to sandbox first (CLI or VS Code)
2. Create outbound change set in sandbox
3. Upload to production
4. Deploy inbound change set in production (user-initiated)

See [CHANGE_SET_INVENTORY.md](CHANGE_SET_INVENTORY.md) and [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for details.
