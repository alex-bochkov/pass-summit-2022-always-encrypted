-- the source table
CREATE TABLE [dbo].[site_users] (
    [user_id]       INT            NOT NULL,
    [email_address] NVARCHAR (200) NOT NULL
);

-- add new encrypted column:
ALTER TABLE [dbo].[site_users]
    ADD [email_address_encrypted] NVARCHAR (200) COLLATE Latin1_General_BIN2  
	ENCRYPTED WITH (
		COLUMN_ENCRYPTION_KEY = [cek],
		ENCRYPTION_TYPE = DETERMINISTIC,
		ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
	) NULL;

-- add a flag to track rows that require encryption
ALTER TABLE [dbo].[site_users] ADD [needsEncryption] INT;

CREATE INDEX temp_enc_site_users ON [dbo].[site_users] ([needsEncryption]) WITH (ONLINE = ON);

GO

CREATE OR ALTER TRIGGER [dbo].[site_users_Trg_dt] 
  ON [dbo].[site_users] AFTER UPDATE, INSERT 
  NOT FOR REPLICATION  
AS 
BEGIN

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 WHERE CONTEXT_INFO() = 0x01010101)
BEGIN
    UPDATE [dbo].[site_users]
    SET [needsEncryption]         = 1,
        [email_address_encrypted] = NULL
    WHERE [user_id] IN (SELECT [user_id] FROM inserted);
END

END
GO

-- ROLLBACK support
ALTER TABLE [dbo].[site_users] ADD [needsDecryption] INT;

CREATE INDEX temp_decr_site_users ON [dbo].[site_users] ([needsDecryption]) WITH (ONLINE = ON);
GO

-- run PowerShell script to encrypt all values and perform a cutover
...

-- run PowerShell script to decrypt new values and perform a rollback if needed
...
