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


$vUserName = "xxxxxxx"
$vPassword = "xxxx"
$vTentant = "xxxx"
$subscription = "SubscriptionName"

$elasticName = "ElasticAgent"
$elasticGroup = "dev-DataBase"
$elasticServer = "dev2-ElasticServer"
$elasticServerUser = $vUserName
$elasticServerPassword = $vPassword
$tenantId = $vTentant
$powershellAzureUser = $vUserName
$powershellAzureUserPass = $vPassword
$initialCatalog = "example"


$dacPacPath = "./example_base.dacpac"


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



$passwd = ConvertTo-SecureString $vPassword -AsPlainText -Force
$pscredential = New-Object System.Management.Automation.PSCredential($vUserName, $passwd)
#Login as Service Principal
az login --service-principal -u $vUserName -p $vPassword --tenant $vTentant | Out-null
#Set Subscription
az account set --subscription $subscription

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

$elasticDatabases = az sql elastic-pool list-dbs --resource-group $elasticGroup --server $elasticServer --name $elasticName --query "[].{name:name}" -o table



foreach ($elasticDatabase in $elasticDatabases ) { 
    if($elasticDatabase.StartsWith($initialCatalog+"_")) {
      
        try
        {	
            $fileExe = $sqlPackageFileExe_name 
            & $fileExe /Action:Publish /SourceFile:$dacPacPath /TargetConnectionString:"Server=tcp:$sqlServer;Initial Catalog=$elasticDatabase;Persist Security Info=False;User ID=$elasticServerUser;Password=$elasticServerPassword;MultipleActiveResultSets=False;" 
            
            
            $logsSqlExe = $fileExe
            foreach($logSqlExe in $logsSqlExe){
                Write-Host ($logSqlExe)
            }
        }
        catch
        {
            $Error | format-list -force		
            Write-Host ($Error[0].Exception.ParentContainsErrorRecordException)
        }
    }
}


Remove-Item function:\WriteLog
Remove-Variable dacPacPath
Remove-Variable release




