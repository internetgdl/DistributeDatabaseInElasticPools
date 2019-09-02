# Despliegue de DACPAC a Azure Elastic Pools

[Sin categoría](http://eduardo.mx/category/sin-categoria/)

Despliegue de DACPAC a Azure Elastic Pools.

En un modelo de arquitectura de base de datos distribuida donde distribuimos los datos entre dos o más bases de datos y requerimos que estas bases de datos tengan el mismo esquema, puede representar un reto mantener la coherencia de los esquemas sobre todo cuando tenemos un modelo de integración y liberación continua; por lo cual la pregunta que nos podemos llegar a hacer es la siguiente: ¿Cuál es la mejor forma de implementar liberación continúa en proyectos de bases de datos con un modelo de base de datos distribuida?

Existen dos principales formas de hacerlo:

**La primera forma** es extrayendo el Query Script para actualizar los esquemas, comparando el esquema de la base de datos de desarrollo contra la productiva, tomar el Query y enviarlo a un Elastic Job con todo lo que implica.

Primero debemos de crear un Elastic Job Agent; este lo podemos crear directamente sobre nuestro portal Azure, debemos de seleccionar la base de datos al menos de tamaño S0 que se usara de base para nuestros Jobs.

![](http://eduardo.mx/wp-content/uploads/2019/09/image.png)

Debemos de crear las credenciales del Job, Nuestro target group, el Job como tal y finalmente los steps del Job; esto ya lo podemos hacer directamente sobre nuestro PowerShell usando los cmdlet de Az.Sql

Si no tenemos instalado el módulo lo podemos instalar de la siguiente forma:

```
Import-Module Az.Sql 
```

Necesitamos conectarnos con Azure, para esto usamos un usuario de aplicación con los permisos necesarios, lo definimos en variables.

```
$vUserName = "xxxxxxx" 

$vPassword = "xxxx" 

$vTentant = "xxxx" 

$subscription = "SubscriptionName" 
```

Obtenemos el objeto agente previamente creado sobre Azure (este agente también se puede crear desde el mismo PowerShell)

```
$JobAgent = Get-AzSqlElasticJobAgent -Name $AgentName -ResourceGroupName $resourceGroupName -ServerName $ServerName 
```

  
Ahora creamos las credenciales que usaremos para el ElasticJob, estas credenciales debe de ser el usuario y contraseña de algún acceso a la BD que tiene el Elastic Pool con suficientes privilegios

```
#SQL Credentials 

$AdminLogin = "SecureNotIntuitiveUserName" 

$AdminPassword = "xxxxxxxxxxxx" 
```

Tomamos el password y lo metemos dentro de un Secure String

```
$LoginPasswordSecure = (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force) 
```

Ahora creamos las credenciales:

```
$MasterCred = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $AdminLogin , $LoginPasswordSecure 

$MasterCred = $JobAgent | New-AzSqlElasticJobCredential -Name $AdminLogin -Credential $MasterCred 
```

Ahora creamos el TargetGroup, asi podemos agregar ciertas bases de datos, excluir ciertas bases de datos o trabajar con Elastic pools completos

En este ejemplo agregaremos todo un Elastic pool, cuando lancemos el Job afectará a todas las bases de datos de este Elastic Pool

```
$serverName = "devUser" 
$elasticName = "PocElasticAgent" 
$serverGroupName = "ServerGroup" 

$ServerGroup = $JobAgent | New-AzSqlElasticJobTargetGroup -Name $serverGroupName  

$ServerGroup | Add-AzSqlElasticJobTarget -ServerName $serverName -ElasticPoolName $elasticName -RefreshCredentialName $MasterCred.CredentialName 
```

Ahora creamos el Job con las credenciales previamente creadas

```
$Job = $JobAgent | New-AzSqlElasticJob -Name $JobName -RunOnce 
```

Ahora tiene el paso más importante, crear el step, antes de eso tenemos que obtener el Sql que se ejecutará, aquí lo obtenemos de un archivo:

```
$SqlText1 = Get-Content .\ContpaqiNube.Cti_Create.sql | Out-String 
```

ahora creamos el step:

```
$Job | Add-AzSqlElasticJobStep -Name $stepName -TargetGroupName $ServerGroup.TargetGroupName -CredentialName $MasterCred.CredentialName -CommandText $SqlText
```

Ahora iniciamos con la ejecución del Job.

```
$JobExecution = $Job | Start-AzSqlElasticJob 
```

De esta forma ya está ejecutando el Job y podemos consultar el estatus de la ejecución directamente sobre el portal de Azure, Sobre las tablas de job_executions en las tablas bajo el esquema jobs:internal de la base de datos que se definió como base de datos base

![](http://eduardo.mx/wp-content/uploads/2019/09/image-1-1024x426.png)

Si queremos monitorear sobre el mismo PowerShell podemos obtener los JobIds con estatus de finalización en null para posteriormente ver el estatus de la ejecución

```
Do 

{ 

$jobIDs= Get-AzSqlElasticJobExecution -Count 10 -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName | Where-Object {$_.EndTime -eq $null} | Select-Object JobExecutionId, JobName 

foreach($jobID in $jobIDs){ 

Clear 

Get-AzSqlElasticJobStepExecution -ResourceGroupName $resourceGroupName -ServerName $ServerName -AgentName $AgentName -JobExecutionId $jobID.JobExecutionId -JobName $jobID.JobName 

} 

Start-Sleep -s 1 

} While ($jobIDs.JobExecutionId.count-gt 0) 
```

De esta forma podemos distribuir un script de SQL entre todas las bases de datos de un mismo pool elástico en Azure; a continuación, describo los pros y contras que vemos trabajando en un modelo en el que tenemos que distribuir de forma constante los esquemas completos de base de datos.

Pros:

-   Al ejecutar solo el SQL con las diferencias de los esquemas puede llegar a ser rápida la distribución
-   La implementación de un sistema de monitoreo puede llegar a ser sencilla por el hecho de tener todos los registros en una base de datos.
-   Podemos detonar las actividades sobre los pipelines de nuestra liberación continua con PowerShell.

Cons:

-   Tenemos que garantizar que TODAS las BD tienen el esquema idéntico y no tenemos dependencia de algún dato; de otra forma el script que obtenemos no necesariamente serviría en algunas bases de datos y el homologarlas puede llegar a ser un dolor de cabeza
-   Tenemos que olvidarnos de sentencias de SQLCMD
-   No podemos definir el número de hilos que se ejecutan en paralelo.

**La segunda forma** de poder desplegar bases de datos entre una lista de bases de datos en un pool elástico es usando una máquina que tenga el paquete SqlPackage.exe, este paquete nos ayudará a evaluar en DACPAC Origen contra la base de datos destino, construir el script de ejecución e implementarlo mediante una conexión de SQL.

Este ejercicio lo vamos a trabajar solo con PowerShell, en el ejercicio adjunto al repositorio de GitHub viene configurado para que pueda recibir las variables del paso de ejecución definido en el pipeline de la liberación.

Primero nos conectamos a Azure:

```
$vUserName = "xxxxxxx" 

$vPassword = "xxxx" 

$vTentant = "xxxx" 

$subscription = "SubscriptionName" 

 

$passwd = ConvertTo-SecureString $vPassword -AsPlainText -Force 

$pscredential = New-Object System.Management.Automation.PSCredential($vUserName, $passwd) 

#Login as Service Principal 

az login --service-principal -u $vUserName -p $vPassword --tenant $vTentant | Out-null 

#Set Subscription 

az account set --subscription $subscription 
```

Posteriormente definimos los nombres de nuestro servidor de SQL

```
$sqlServerHostName = $elasticServer + ".database.windows.net" 
$sqlServer = $sqlServerHostName + ",1433" 
```

Ahora buscamos en todo el servidor el archivo SqlPackage.exe

```
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
```

  
Establecemos el path.  

```
$sqlPackageFileExe_name = "C:\Program Files (x86)\Microsoft SQL Server\" + $last_version + "\DAC\bin\SqlPackage.exe"; 
```

Ahora sacamos la lista de bases de datos que contiene nuestro pool elástico

```
$elasticDatabases = az sql elastic-pool list-dbs --resource-group $elasticGroup --server $elasticServer --name $elasticName --query "[].{name:name}" -o table 
```

Ahora viene lo importante, por cada una de nuestra base de datos, ejecutamos el comando de publicación de nuestro SqlPackage.exe

```
foreach ($elasticDatabase in $elasticDatabases ) {  

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
```

Una por una de nuestras bases de datos se comenzará a actualizar.

Pros:

-   Podemos ejecutar con múltiples hilos tanto como la maquina nos lo permita
-   Podemos escalar a ejecución por ServiceBus si nuestra demanda es demasiada.
-   Podemos detonar las actividades sobre los pipelines de nuestra liberación continua con PowerShell.

Cons:

-   Llega a ser lento por la evaluación que hace entre base y base de datos
-   Tenemos que construir todo un sistema de monitoreo, desde la generación de logs hasta las notificaciones.

Referencia:  [http://eduardo.mx/2019/09/02/despliegue-de-dacpac-a-azure-elastic-pools/](http://eduardo.mx/2019/09/02/despliegue-de-dacpac-a-azure-elastic-pools/)