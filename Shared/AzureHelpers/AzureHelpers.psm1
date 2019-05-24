function Login-Azure {
    Try {
        Get-AzureRmSubscription | Out-Null
    } 
    Catch {
        if ($_ -like "*Login-AzureRmAccount to login*") {
            Login-AzureRmAccount
        }
        elseif ($_ -like "*Connect-AzureRmAccount to login*") {
            Connect-AzureRmAccount
        }
    }
}

function Select-Subscription {
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $subscriptionName
    )
    Login-Azure
    Select-AzureRmSubscription -SubscriptionName $subscriptionName | out-null -ErrorAction Stop
}

function New-ResourceGroup {
    param(
        [parameter(mandatory = $true)]
        [string]
        $resourceGroupName,
        [parameter(mandatory = $true)]
        [string]
        $resourceGroupLocation
    )
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
    $groupFound = $false
    while ($groupFound -eq $false) {
        try {
            Get-AzureRmResourceGroup -ResourceGroupName $resourceGroupName
            $groupFound = $true
        }
        catch {
            Write-Host "Not Found"
        }
    }
}

function Create-StorageAccountName {
    param(
        [parameter(Mandatory = $true)]
        [string]
        $accountName,

        [parameter(Mandatory = $false)]
        [switch]
        $littleEndian
    )
    $accountName = $accountName.ToLower() -replace "[^a-z0-9]", ""
    $nameLength = $accountName.Length
    if ($nameLength -gt 24) {
        Write-Host "Name was longer than 24 characters, reducing length to 24"
        $storageAccountNameLength = 23
        if ($littleEndian) {
            $accountName = $accountName.Substring(0, $storageAccountNameLength)
        } else {
            $accountName = $accountName.Substring($accountName.Length-$storageAccountNameLength,$storageAccountNameLength)
        }
    }
    return $accountName
}

function New-StorageAccount {
    param(
        [parameter(mandatory = $true)]
        [string]
        $resourceGroupName,
        [parameter(mandatory = $true)]
        [string]
        $accountName,
        [parameter(mandatory = $true)]
        [string]
        $location,
        [parameter(mandatory = $true)]
        [string]
        $skuName,
        [parameter(mandatory = $true)]
        [string]
        $Kind,
        [parameter(mandatory = $true)]
        [string]
        $accessTier,
        [parameter(mandatory = $false)]
        [switch]
        $littleEndian
    )
    $accountName = Create-StorageAccountName $accountName
    try {
        $storageAccount = Get-AzureRMStorageAccount -ResourceGroupName $resourceGroupName -StorageAccountName $accountName -ErrorAction Stop
    }
    catch {
        Write-Host "Creating new Storage account $accountName"
        New-AzureRMStorageAccount -ResourceGroupName $resourceGroupName -StorageAccountName $accountName -Location $location -SkuName $skuName -Kind $Kind -AccessTier $accessTier
    }
    $groupFound = $false
    while ($groupFound -eq $false) {
        try {
            $key = (Get-AzureRMStorageAccountKey -ResourceGroupName $resourceGroupName -StorageAccountName $accountName).Value[0]
            $groupFound = $true
        }
        catch {
            Start-Sleep -s 2
            Write-Host "Not Found"
        }
    }
    $hash = @{"AccountKey" = $key; "Name" = $accountName}
    return $hash
}

function AzureResourceGroupDeployment {
    param(
        [string] 
        [parameter(mandatory = $true)] 
        $resourceGroupLocation,
        [string] 
        [parameter(mandatory = $true)] 
        $resourceGroupName,
        [string] 
        [parameter(mandatory = $true)] 
        $templateFile,
        [string] 
        [parameter(mandatory = $true)] 
        $templateparametersfile
    )
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation -Verbose -Force
    New-AzureRMResourceGroupDeployment -Name ((get-childitem $templatefile).basename + '-' + ((get-date).touniversaltime()).tostring('mmdd-hhmm')) `
        -Mode "Incremental" `
        -Resourcegroupname $resourcegroupname `
        -Templatefile $templatefile `
        -Templateparameterfile $templateparametersfile `
        -Force -verbose `
        -Errorvariable errorMessages
    if ($errorMessages) {
        write-output '', 'template deployment returned the following errors:', @(@($errormessages) | foreach-object { $_.exception.message.trimend("`r`n") })
    }
}
