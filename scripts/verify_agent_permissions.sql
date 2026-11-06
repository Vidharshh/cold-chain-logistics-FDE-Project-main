-- Run as USR_FDE_RO (the agent-fde-ro connection), one statement at a time.

-- Should work: returns 5 rows.
SELECT TOP 5 * FROM FDE_VIEWS.VW_ACTIVE_FLEET;

-- Should fail with "SELECT permission was denied".
SELECT TOP 5 * FROM dbo.TBL_SC_FLEET_HIST_RAW;

-- Should fail too: the agent can write to the audit log but not read it.
SELECT * FROM FDE_VIEWS.AgentAuditLog;
