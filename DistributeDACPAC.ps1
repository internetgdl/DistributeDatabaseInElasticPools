Param
(
    [String]$dacPacPath,
    [String]$elasticName,
    [String]$elasticGroup,
    [String]$elasticServer,
    [String]$elasticServerUser,
    [String]$elasticServerPassword,
    [String]$tenantId,
    [String]$subscription,
    [String]$powershellAzureUserPass,
    [String]$powershellAzureUser,
    [String]$initialCatalog,
    [String]$storageAccountNameForLogs,
    [String]$sasTokenStorageAccount,
    [String]$tableNameStorageAccount,
    [String]$partitionKey,
    [String]$associateRepository,
	[String]$release,
    [String]$releaseNumber
)
if ([string]::IsNullOrEmpty($dacPacPath)) {
    throw "The Dac Pac are not privided"
}
$associateRepositorybool = 0
if($associateRepository -eq "true"){
	$associateRepositorybool = 1
}

Enable-AzureRmAlias

$sqlServerHostName = $elasticServer + ".database.windows.net"
$sqlServer = $sqlServerHostName + ",1433"

$global:dacPacPath = $dacPacPath
$global:release = $release
#FUNCTIONS
function global:WriteLog([String]$writeString) {
    
	
    $datetime = Get-Date -Format yMMdHmsfff
    $rowKey = $datetime
	
    $entity = New-Object -TypeName "Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity,$assemblySN" -ArgumentList $partitionKey, $rowKey

    $entity.Properties.Add("DacPAC", $global:dacPacPath) 
    $entity.Properties.Add("Releaseversion", $global:release)
    $entity.Properties.Add("Action", $writeString)
    
    $table.CloudTable.Execute((invoke-expression "[Microsoft.WindowsAzure.Storage.Table.TableOperation,$assemblySN]::InsertOrReplace(`$entity)")) | Out-null
	
    Write-Host $writeString
}


$password = ConvertTo-SecureString $powershellAzureUserPass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($powershellAzureUser, $password)

Login-AzureRmAccount -Credential $Credential -Subscription $subscription -Tenant $tenantId | Out-null
Set-AzureRmContext -SubscriptionId $subscription | Out-null

######################### los Logs


$storageCtx = New-AzureStorageContext -StorageAccountName $storageAccountNameForLogs -StorageAccountKey $sasTokenStorageAccount
$table = Get-AzureStorageTable -Name $tableNameStorageAccount -Context $storageCtx


$assemblySN = $table.CloudTable.GetType().Assembly.FullName

WriteLog ("Release " + $release)
WriteLog ("Release number " + $releaseNumber)

for ($i = 100; $i -le 190; $i += 10) {
    $sqlPackageFile_name = "C:\Program Files (x86)\Microsoft SQL Server\" + $i + "\DAC\bin\SqlPackage.exe";
    If (Test-Path $sqlPackageFile_name) {
        $last_version = $i;
    }
}

if ([string]::IsNullOrEmpty($last_version)) {
    throw "There are not Microsoft SQL DAC Installed
	More info: https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download?view=sql-server-2017"
}


$sqlPackageFileExe_name = "C:\Program Files (x86)\Microsoft SQL Server\" + $last_version + "\DAC\bin\SqlPackage.exe";
Write-Host $sqlPackageFileExe_name
WriteLog("`nStarting with " + $dacPacPath)

$elasticDatabases = (Get-AzureRmSqlElasticPoolDatabase -ResourceGroupName $elasticGroup -ServerName $elasticServer -ElasticPoolName $elasticName).DatabaseName

foreach ($elasticDatabase in $elasticDatabases ) { 
    if($elasticDatabase.StartsWith("cti_")) {
        WriteLog ("`nDeploying in " + $elasticDatabase)
        try
        {	
            #$dacService.deploy($dp,$elasticDatabase,$true,$deployOptions) 
            
            
            $fileExe = $sqlPackageFileExe_name
            & $fileExe /Action:Publish /SourceFile:$dacPacPath /TargetConnectionString:"Server=tcp:$sqlServer;Initial Catalog=$elasticDatabase;Persist Security Info=False;User ID=$elasticServerUser;Password=$elasticServerPassword;MultipleActiveResultSets=False;" /v:AssociateRepository=$associateRepositorybool /v:serverhostparam=$sqlServerHostName
            
            
            $logsSqlExe = $fileExe
            foreach($logSqlExe in $logsSqlExe){
                    WriteLog ($logSqlExe)
            }
        }
        catch
        {
            $Error | format-list -force		
            WriteLog ($Error[0].Exception.ParentContainsErrorRecordException)
        }
    }
}


Remove-Item function:\WriteLog
Remove-Variable dacPacPath
Remove-Variable release




