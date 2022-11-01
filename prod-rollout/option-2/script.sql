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
            
-- add an index to quickly select data that needs to be encrypted
CREATE INDEX temp_enc_site_users ON [dbo].[site_users] ([email_address_encrypted]);

-- run PowerShell script to encrypt all values and perform a cutover

-- change NULL to NOT NULL as usual
