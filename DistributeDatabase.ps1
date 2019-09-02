#Import-Module Az.Sql

$vUserName = "xxxxxxx"
$vPassword = "xxxx"
$vTentant = "xxxx"
$subscription = "SubscriptionName"
$resourceGroupName = "dev-DataBase"
$serverName = "devUser"
$serverGroupName = "ServerGroup"
$elasticName = "PocElasticAgent"
$stepName ="step1"
$AgentName = "AgentExample"

$jobName = (get-date).ToString("MMddyyyyHHmmss")


#Login as Service Principal
az login --service-principal -u $vUserName -p $vPassword --tenant $vTentant | Out-null
#Set Subscription
az account set --subscription $subscription

#Get TargetDatabases


Write-Output "Getting job agent..."
$JobAgent = Get-AzSqlElasticJobAgent -Name $AgentName -ResourceGroupName $resourceGroupName -ServerName $ServerName


#SQL Credentials
$AdminLogin = "SecureNotIntuitiveUserName"
$AdminPassword = "xxxxxxxxxxxx"

# Create job credential in Job database for master user
Write-Output "Creating job credentials..."
$LoginPasswordSecure = (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force)


try {
    $MasterCred = Get-AzSqlElasticJobCredential -Name $AdminLogin -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName
} catch {
    $MasterCred = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $AdminLogin , $LoginPasswordSecure
    $MasterCred = $JobAgent | New-AzSqlElasticJobCredential -Name $AdminLogin -Credential $MasterCred
}


try {
    $ServerGroup = Get-AzSqlElasticJobTargetGroup -Name $serverGroupName -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName
} catch {
    # Create ServerGroup target group
    Write-Output "Creating test target groups..."
$ServerGroup = $JobAgent | New-AzSqlElasticJobTargetGroup -Name $serverGroupName 
$ServerGroup | Add-AzSqlElasticJobTarget -ServerName $serverName -ElasticPoolName $elasticName -RefreshCredentialName $MasterCred.CredentialName

}



Write-Output "Creating a new job"
$Job = $JobAgent | New-AzSqlElasticJob -Name $JobName -RunOnce
$Job

Write-Output "Creating job steps"
$SqlText1 = Get-Content .\ContpaqiNube.Cti_Create.sql | Out-String

$Job | Add-AzSqlElasticJobStep -Name $stepName -TargetGroupName $ServerGroup.TargetGroupName -CredentialName $MasterCred.CredentialName -CommandText $SqlText1

Write-Output "Start a new execution of the job..."
$JobExecution = $Job | Start-AzSqlElasticJob
$JobExecution

# Get the latest 10 executions run
$JobAgent | Get-AzSqlElasticJobExecution -Count 10

# Get the job step execution details
$JobExecution | Get-AzSqlElasticJobStepExecution

# Get the job target execution details
$JobExecution | Get-AzSqlElasticJobTargetExecution -Count 2

$jobID = Get-AzSqlElasticJobExecution -Count 10 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobName $JobName  | Select-Object JobExecutionId

#Get-AzSqlElasticJobExecution -Count 10 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobName $JobName | Where-Object {$_.EndTime -eq ""}


Do
{
    $jobIDs= Get-AzSqlElasticJobExecution -Count 10 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName | Where-Object {$_.EndTime -eq $null} | Select-Object JobExecutionId, JobName
    foreach($jobID in $jobIDs){
        Clear
        Get-AzSqlElasticJobStepExecution -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobExecutionId $jobID.JobExecutionId -JobName $jobID.JobName
        #Get-AzSqlElasticJobTargetExecution -Count 10 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobName $JobName -JobExecutionId $jobID.JobExecutionId
    }
    Start-Sleep -s 1
} While ($jobIDs.JobExecutionId.count-gt 0)


$jobIDProblem ="62e3e2c0-8aab-4076-a7a8-f4fbd1bdad7e"

Get-AzSqlElasticJobStepExecution -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobName $JobName -JobExecutionId $jobIDProblem
Get-AzSqlElasticJobTargetExecution -Count 2 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobName $JobName -JobExecutionId $jobIDProblem