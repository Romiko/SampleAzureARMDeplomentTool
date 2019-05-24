#requires -version 3.0
#requires -module azurerm.resources
#requires -module azure.storage
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module $ScriptDir\..\Logging\Logging.psm1 -Force
Import-Module $ScriptDir\..\AzureHelpers\AzureHelpers.psm1 -Force

function Format-Validationoutput {
    param ($validationoutput, [int] $depth = 0)
    set-strictmode -off
    return @($validationoutput | where-object { $_ -ne $null } | foreach-object { @('  ' * $depth + ': ' + $_.message) + @(format-validationoutput @($_.details) ($depth + 1)) })
}

function GetArtifactsResourceNames {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $resourceName,

        [Parameter(Mandatory=$true)]
        [string]
        $environmentName
    )
    $artifactResourceGroup = $environmentName + "-$resourceName"
    $artifactStorageAccountName = $environmentName.ToLower() + $resourceName.ToLower()
    $artifactStorageAccountNameLength = $artifactStorageAccountName.Length - 23
    $startChar = 0
    if ($artifactStorageAccountNameLength -gt $startChar) {
        $startChar = $artifactStorageAccountNameLength
    }
    $artifactStorageAccountName = $artifactStorageAccountName.SubString($startChar)
    $artifactStorageAccountName = $artifactStorageAccountName.Replace("-", "")
    $returnArray = @($artifactResourceGroup, $artifactStorageAccountName)
    return $returnArray
}

function UploadArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string] 
        $storageaccountname,

        [Parameter(Mandatory = $true)]
        [string] 
        $resourcegrouplocation,

        [Parameter(Mandatory = $true)]
        [string]
        $resourcegroupname,

        [Parameter(Mandatory = $false)]
        [string] 
        $artifactstagingdirectory = '.',

        [Parameter(Mandatory = $false)]
        [string] 
        $storagecontainername = $resourcegroupname.tolowerinvariant() + '-stageartifacts',

        [Parameter(Mandatory = $false)]
        [string] 
        $artifactslocationname = '_artifactslocation',

        [Parameter(Mandatory = $false)]
        [string] 
        $artifactslocationsastokenname = '_artifactslocationsastoken',

        [Parameter(Mandatory = $false)]
        [int]
        $expireTimeHours = 4
    )

    $erroractionpreference = 'stop'
    set-strictmode -version 3

    $artifactstagingdirectory = [system.io.path]::getfullpath([system.io.path]::combine($psscriptroot, $artifactstagingdirectory))
    $optionalparameters = new-object -typename hashtable

    $storageaccount = (get-azurermstorageaccount | where-object {$_.storageaccountname -eq $storageaccountname.ToLower()})

    # create the storage account if it doesn't already exist
    if ($storageaccount -eq $null) {
        new-azurermresourcegroup -location "$resourcegrouplocation" -name $resourcegroupname -force | Out-Null
        $storageaccount = new-azurermstorageaccount -storageaccountname $storageaccountname.ToLower() -type 'standard_lrs' -resourcegroupname $resourcegroupname -location "$resourcegrouplocation"
    }

    # generate the value for artifacts location if it is not provided in the parameter file
    if ($optionalparameters[$artifactslocationname] -eq $null) {
        $optionalparameters[$artifactslocationname] = $storageaccount.context.blobendpoint + $storagecontainername
    }

    # copy files from the local storage staging location to the storage account container
    new-azurestoragecontainer -name $storagecontainername -context $storageaccount.context -erroraction silentlycontinue *>&1 | Out-Null

    $artifactfilepaths = get-childitem $artifactstagingdirectory -recurse -file | foreach-object -process {$_.fullname}
    foreach ($sourcepath in $artifactfilepaths) {
        set-azurestorageblobcontent -file $sourcepath -blob $sourcepath.substring($artifactstagingdirectory.length + 1) `
            -container $storagecontainername -context $storageaccount.context -force | Out-Null
    }

    # generate a 4 hour sas token for the artifacts location if one was not provided in the parameters file
    if ($optionalparameters[$artifactslocationsastokenname] -eq $null) {
        $optionalparameters[$artifactslocationsastokenname] = (new-azurestoragecontainersastoken -container $storagecontainername -context $storageaccount.context -permission r -expirytime (get-date).addhours($expireTimeHours))
    }
    
    Write-Host $optionalparameters[$artifactslocationname]
    Write-Host $optionalparameters[$artifactslocationsastokenname]
    return $optionalparameters 
}