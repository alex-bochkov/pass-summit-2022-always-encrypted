$DatabaseServerTarget = "targetServer"
$DatabaseTarget = "targetDatabase"

$ConnectionString = "Data Source=$DatabaseServerTarget;Initial Catalog=$DatabaseTarget;Trusted_Connection=True;Column Encryption Setting=Enabled;"

$connTarget = New-Object System.Data.SqlClient.SqlConnection
$connTarget.ConnectionString = $ConnectionString;
$connTarget.open()	

$SelectQuery = "

SELECT TOP 10000 
    [user_id], 
    [email_address]
FROM [dbo].[site_users]
WHERE [email_address_encrypted] IS NULL

"

$cmdEncryptData = New-Object System.Data.SqlClient.SqlCommand
$cmdEncryptData.connection = $connTarget
$cmdEncryptData.commandtext = "

UPDATE [dbo].[site_users]
SET [email_address_encrypted] = @emailAddressEncrypted
WHERE user_id = @userId

"

While ($True) {

    Write-Host "($(Get-Date)): Getting new batch of records to decrypt"

    $RecordsToEncrypt = Invoke-Sqlcmd $SelectQuery -ConnectionString $ConnectionString -QueryTimeout 0

    ForEach ($Record in $RecordsToEncrypt) {

        $cmdEncryptData.Parameters.Clear();
        $cmdEncryptData.Parameters.AddWithValue("userId", $Record.user_id) | Out-Null

        $addressLine1Encrypted = $cmdEncryptData.Parameters.Add("emailAddressEncrypted", [Data.SQLDBType]::NVarChar, 200);
        $addressLine1Encrypted.Value = $Record.email_address

        $Result = $cmdEncryptData.ExecuteNonQuery();

    }
    
    if ($RecordsToEncrypt.Count -eq 0) {

        $cmdCutover = New-Object System.Data.SqlClient.SqlCommand
        $cmdCutover.connection = $connTarget
        $cmdCutover.commandtext = "

BEGIN TRAN;

EXEC sp_rename 'dbo.site_users.email_address', 'email_address_decrypted', 'COLUMN';
EXEC sp_rename 'dbo.site_users.email_address_encrypted', 'email_address', 'COLUMN';

COMMIT;

        "
        $cmdCutover.ExecuteNonQuery();
        Write-Host "Encryption has been completed"
        break;
         


    } elseif ($RecordsToEncrypt.Count -lt 100) {
        Write-Host "waiting 1 second.."
        Start-Sleep -Seconds 1
    }   
    
}

$connTarget.Close();
