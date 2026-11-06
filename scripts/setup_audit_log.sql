-- Phase 4: create the audit log. Run as sa (the legacy-mssql connection).
CREATE TABLE FDE_VIEWS.AgentAuditLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    Timestamp DATETIME DEFAULT GETDATE(),
    SessionID VARCHAR(50),
    NodeExecuted VARCHAR(50),
    ToolName VARCHAR(100),
    Content NVARCHAR(MAX)
);
GO
GRANT INSERT ON FDE_VIEWS.AgentAuditLog TO USR_FDE_RO;
GO

-- Check (as sa): rows appear after you chat in the UI.
-- SELECT * FROM FDE_VIEWS.AgentAuditLog;
