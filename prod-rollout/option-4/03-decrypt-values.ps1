$DatabaseServerTarget = "SQL-SERVER-DATABASE" # there will be a lot of small queries so better use direct server enpoint (or AlwaysOn, but not NLB)
$DatabaseTarget = "db"

$ConnectionString = "Data Source=$DatabaseServerTarget;Initial Catalog=$DatabaseTarget;Trusted_Connection=True;Column Encryption Setting=Enabled;"

$connTarget = New-Object System.Data.SqlClient.SqlConnection
$connTarget.ConnectionString = $ConnectionString;
$connTarget.open()	

$SelectQuery = "

SELECT TOP 10000 
    [user_id],
    [email_address]
FROM [dbo].[site_users] WITH (FORCESEEK)
WHERE needsDecryption = 1
   
"

$cmdDecryptData = New-Object System.Data.SqlClient.SqlCommand
$cmdDecryptData.connection = $connTarget
$cmdDecryptData.commandtext = "

SET CONTEXT_INFO 0x01010101;

UPDATE [dbo].[site_users]
SET [needsDecryption]          = 0, 
    [email_address_decrypted]  = @email_address_plain_text,
WHERE user_id = @user_id 
    AND email_address = @email_address_encrypted -- (optimistic lock might be a good idea)

"

While ($True) {

    Write-Host "($(Get-Date)): Getting new batch of records to encrypt"

    $RecordsToDecrypt = Invoke-Sqlcmd $SelectQuery -ConnectionString $ConnectionString -QueryTimeout 0

    ForEach ($Record in $RecordsToDecrypt) {

        $cmdDecryptData.Parameters.Clear();
        $cmdDecryptData.Parameters.AddWithValue("user_id", $Record.user_id) | Out-Null
        $cmdDecryptData.Parameters.AddWithValue("email_address_plain_text", $Record.email_address) | Out-Null

        $EmailAddressEncryptedParamater = $cmdDecryptData.Parameters.Add("email_address_encrypted", [Data.SQLDBType]::NVarChar, 200);
        $EmailAddressEncryptedParamater.Value = $Record.email_address

        $Result = $cmdDecryptData.ExecuteNonQuery();

    }
    
    if ($RecordsToDecrypt.Count -eq 0) {

        $cmdRollback = New-Object System.Data.SqlClient.SqlCommand
        $cmdRollback.connection = $connTarget
        $cmdRollback.commandtext = "

BEGIN TRAN;

EXEC sp_rename 'dbo.site_users.email_address', 'email_address_encrypted', 'COLUMN';
EXEC sp_rename 'dbo.site_users.email_address_decrypted', 'email_address', 'COLUMN';

GO

ALTER TRIGGER [dbo].[site_users_Trg_dt]
    ON [dbo].[site_users]
    AFTER INSERT, UPDATE
    NOT FOR REPLICATION
AS 
BEGIN

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 WHERE CONTEXT_INFO() = 0x01010101)
BEGIN
    UPDATE [dbo].[site_users]
    SET [needsEncryption]         = 1,
        [email_address_encrypted] = NULL
    WHERE PK_id IN (SELECT PK_id FROM inserted);
END

END
GO

COMMIT;"

        $cmdRollback.ExecuteNonQuery();
        
        Write-Host "The rollback has completed!"
        break;
    }
    
    
}

$connTarget.Close();
