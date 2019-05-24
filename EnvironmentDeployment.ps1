<#
.SYNOPSIS
    Script used to deploy all of infrastructure which is defined in EnvironmentDeployment.json. 
    
.DESCRIPTION
    This script allows you deploy or update all cloud infrastructure pieces which are necessary to host an environment. You can specify certain resources to be deployed with the resources array parameter.

.PARAMETER configFile
    The json configuration file which contains the deployment info for each environment such as ip address spaces and infrastructure resources that makes up an environment

.PARAMETER environment
    The environment to which you will deploy to, specified in EnvironmentDeployment.json

.PARAMETER baseDir
    This parameter is your base directory to your Code Repo e.g. C:\code

.PARAMETER resources
    Array of resources that can be specified in order to deploy only certain resources. If this parameter is left blank, all resources will be deployed or updated. The naming convention for the resource is 
    the ResourceGroupSuffix tag found in the EnvironmentDeployment.json file (i.e. VirtualMachines, VNet, etc).

.EXAMPLE
    ./EnvironmentDeployment.ps1 -configFile .\EnvironmentDeployment.json -environment pcac -baseDir C:\Repos -resources ServiceFabric,PostgreSQL
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$configFile,
    [Parameter(Mandatory = $true)]
    [string]$environment,
    [Parameter(Mandatory = $false)]
    [string]$baseDir = 'C:\Repos\',
    [Parameter(Mandatory = $false)]
    [array]$resources = @(),
    [Parameter(Mandatory = $false)]
    [string]$logFolder = "C:\Logs\",
    [Parameter(Mandatory = $false)]
    [string]$logFileName = "DeploymentLogs.log"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\Shared\UploadArtifacts\UploadArtifacts.psm1 -Force
Import-Module $ScriptDir\Shared\Logging\Logging.psm1 -Force
Import-Module $ScriptDir\Shared\AzureHelpers\AzureHelpers.psm1 -Force

$logFilePath = PrepareToLog $logFolder $logFileName
$conf = (Get-Content $configFile) -join "`n" | ConvertFrom-Json
$environmentConfiguration = $conf.$environment

if (!$environmentConfiguration) {
    LogErrorMessage "No Environment Configuration for $environment - please create your configuration in file $configFile" $logFilePath
    exit 1
}

if($environment.Length -gt 14) {
    LogErrorMessage "Environment name is too long. Maximum length is 12 characters" $logFilePath
    exit 1
}

if($environment -cmatch '[A-Z]') {
    LogErrorMessage "Environment name must be lowercase" $logFilePath
    exit 1
}

Select-Subscription -SubscriptionName $environmentConfiguration.Subscription
$subscriptionId = (Get-AzureRmContext).Subscription.Id
$location = $environmentConfiguration.location
$ipbase = $environmentConfiguration.ipbase
$pdns = $environmentConfiguration.primarydns
$sdns =  $environmentConfiguration.secondarydns
$monitoripbase = $environmentConfiguration.monitoripbase
$gatewayipbase = $environmentConfiguration.gatewayipbase
$puppetipbase = $environmentConfiguration.puppetipbase
$clientipbase = $environmentConfiguration.clientipbase
$baseDir = Join-Path $baseDir \
foreach ($deployment in $environmentConfiguration.deployments) {
    $resourceGroup = $environment + "-" + $deployment.resourceGroupSuffix
    # we want to skip anything not contained in the array
    if ($resources.Length -gt 0) { 
        if (!$resources.contains($deployment.resourceGroupSuffix)) {
            continue
        }
    }
    if($deployment.overrideResourceGroup.length -gt 0){
        $resourceGroup = $deployment.overrideResourceGroup
    }
    $tf = $deployment.templateFile
    $pf = $deployment.paramsFile -replace '==ENVIRONMENTNAME==', $environment
    $folder = Split-Path -Path $pf
    $fileName = Split-Path -Path $pf -Leaf -Resolve
    $outfile = $folder + "\tmp_deployment_" + $fileName
    (Get-Content $pf) | Set-Content $outfile

    LogInfoMessage "Deployment. Group: $resourceGroup TemplateFile: $tf Parameters File: $pf" $logFilePath
    if ($deployment.UploadDirectory) {
        $artifactsResources = GetArtifactsResourceNames -resourceName "Supporting" -environmentName $environment
        $artifactResourceGroup = $artifactsResources[0]
        $artifactStorageAccountName = $artifactsResources[1]
        $artifactsLocationSasToken = "_artifactsLocationSasToken"
        $artifactsLocation = "_artifactsLocation"
        LogInfoMessage "Uploading artifacts to Resource Group [$artifactResourceGroup] and Storage Account [$artifactStorageAccountName]" $logFilePath

        if($deployment.UploadDirectory -like "*longExpireTime*") {
            $artifactsHash = UploadArtifacts -storageAccountName $artifactStorageAccountName `
            -resourceGroupLocation $environmentConfiguration.location `
            -resourceGroupName $artifactResourceGroup `
            -artifactStagingDirectory $deployment.UploadDirectory.Replace('==BASEDIR==', $baseDir) `
            -artifactsLocationName $artifactsLocation `
            -artifactsLocationSasTokenName $artifactsLocationSasToken `
            -expireTimeHours 87600
        } else {
            $artifactsHash = UploadArtifacts -storageAccountName $artifactStorageAccountName `
            -resourceGroupLocation $environmentConfiguration.location `
            -resourceGroupName $artifactResourceGroup `
            -artifactStagingDirectory $deployment.UploadDirectory.Replace('==BASEDIR==', $baseDir) `
            -artifactsLocationName $artifactsLocation `
            -artifactsLocationSasTokenName $artifactsLocationSasToken 
        }

        LogInfoMessage "Uploaded Artifacts" $logFilePath
       
        (Get-Content -Path $outfile) | Foreach-Object {
            $_ -Replace '==ARTIFACTSASTOKEN==', $artifactsHash[$artifactsLocationSasToken] `
               -Replace '==ARTIFACTLOCATION==', $artifactsHash[$artifactsLocation]
            } | Set-Content -Path $outfile
    }
    (Get-Content -Path $outfile) | Foreach-Object {
        $_ -Replace '==SUBSCRIPTIONID==', $subscriptionId `
           -Replace '==ENVIRONMENTNAME==', $environment `
           -Replace '==LOCATION==', $location `
           -Replace '==IPBASE==', $ipbase `
           -Replace '==PDNS==', $pdns `
           -Replace '==SDNS==', $sdns `
           -replace '==MONITORIPBASE==', $monitoripbase `
           -replace '==GATEWAYIPBASE==', $gatewayipbase `
           -replace '==PUPPETIPBASE==', $puppetipbase `
           -replace '==CLIENTIPBASE==', $clientipbase
        } | Set-Content -Path $outfile
    AzureResourceGroupDeployment -templateFile $tf -templateParametersFile $outfile -resourceGroupName $resourceGroup -resourceGroupLocation $environmentConfiguration.location
}