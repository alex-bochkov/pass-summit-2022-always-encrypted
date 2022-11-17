Param(
  [string]$ThreadCount
  [string]$ThreadId
)

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
WHERE [needsEncryption] = 1
   AND [user_id] % $ThreadCount = $ThreadId

UNION

SELECT TOP 10000 
    [user_id],
    [email_address]
FROM [dbo].[site_users]
WHERE [needsEncryption] IS NULL
   AND [user_id] % $ThreadCount = $ThreadId;
   
"

$cmdEncryptData = New-Object System.Data.SqlClient.SqlCommand
$cmdEncryptData.connection = $connTarget
$cmdEncryptData.commandtext = "

SET CONTEXT_INFO 0x01010101;

UPDATE [dbo].[site_users]
SET [needsEncryption]          = 0, 
    [email_address_encrypted]  = @email_address_encrypted,
WHERE [user_id] = @user_id 
    AND [email_address] = @email_address_plain_text -- ("optimistic" lock might be a good idea)

"

While ($True) {

    Write-Host "($(Get-Date)): Getting new batch of records to encrypt"

    $RecordsToEncrypt = Invoke-Sqlcmd $SelectQuery -ConnectionString $ConnectionString -QueryTimeout 0

    ForEach ($Record in $RecordsToEncrypt) {

        $cmdEncryptData.Parameters.Clear();
        $cmdEncryptData.Parameters.AddWithValue("user_id", $Record.user_id) | Out-Null
        $cmdEncryptData.Parameters.AddWithValue("email_address_plain_text", $Record.email_address) | Out-Null

        $EmailAddressEncryptedParamater = $cmdEncryptData.Parameters.Add("email_address_encrypted", [Data.SQLDBType]::NVarChar, 200);
        $EmailAddressEncryptedParamater.Value = $Record.email_address

        $Result = $cmdEncryptData.ExecuteNonQuery();

    }
    
    if ($RecordsToEncrypt.Count -eq 0) {

        $cmdCutover = New-Object System.Data.SqlClient.SqlCommand
        $cmdCutover.connection = $connTarget
        $cmdCutover.commandtext = "

BEGIN TRAN;

EXEC sp_rename 'dbo.site_users.email_address', 'email_address_decrypted', 'COLUMN';
EXEC sp_rename 'dbo.site_users.email_address_encrypted', 'email_address', 'COLUMN';

GO

ALTER TRIGGER [dbo].[site_users_Trg_dt]
    ON [dbo].[site_users]
    AFTER INSERT, UPDATE
    NOT FOR REPLICATION
AS 
BEGIN

IF NOT EXISTS (SELECT 1 WHERE CONTEXT_INFO() = 0x01010101)
BEGIN
    UPDATE [dbo].[site_users]
    SET [needsDecryption]         = 1,
        [email_address_decrypted] = NULL
    WHERE [user_id] IN (SELECT [user_id] FROM inserted);
END

END
GO

COMMIT;"
        $cmdCutover.ExecuteNonQuery();
        
        Write-Host "The encryption has completed!"
        break;
    }
    
    
}

$connTarget.Close();
