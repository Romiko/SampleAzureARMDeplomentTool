[bool]$Global:EventLogEnabled = $true

function PrepareToLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $folderPath,

        [Parameter(Mandatory=$true)]
        [string]
        $logFileName,
    
        [Parameter(Mandatory=$false)]
        [switch]
        $noEventLog
    )
    if ($noEventLog) {
        $Global:EventLogEnabled = $false 
    }
    else {
        CreateEventLogSource -eventLogName "Application" -eventLogSourceName "DevopsPowerShell"
    }
    $timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."} 
    $fileName = "$timestamp$logFileName"
    $filePath = [System.IO.Path]::Combine($folderPath, $fileName)
    [System.IO.Directory]::CreateDirectory($folderPath) | Out-Null
    return $filePath
}

function CreateEventLogSource {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $eventLogName,

        [Parameter(Mandatory=$true)]
        [string]
        $eventLogSourceName
    )
    if ([System.Diagnostics.EventLog]::SourceExists($eventLogSourceName) -eq $false) {
        [System.Diagnostics.EventLog]::CreateEventSource($eventLogSourceName, $eventLogName)
    } else {
        Write-Warning "Failed to add event source $eventLogSourceName - already exists in $eventLogName"
    }
}

function RemoveOldLogs {
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $folderPath,
        [Parameter(Mandatory=$true)]
        $daysToKeepLogs
    )
    $limit = (Get-Date).AddDays( 0 - $daysToKeepLogs )
    #Delete any old reports
    Get-ChildItem $folderPath -Recurse | ? {
        -not $_.PSIsContainer -and $_.CreationTime -lt $limit
    } | Remove-Item
}

function LogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $message,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Information", "Warning", "Error", "FailureAudit", "SuccessAudit")]
        [String]
        $messageType,

        [Parameter(Mandatory = $false)]
        [String]
        $filePath = "",

        [Parameter(Mandatory = $false)]
        [switch]
        $isFatal
    )
	$timestamp = Get-Date -Format G
    $timeStampMessage = "$timestamp : $message"
    if ($messageType -eq "Information") {
        if ($Global:EventLogEnabled) {
            LogToEventLog -message $message -entryType $messageType -entryId 1
        }
        LogToScreen -msg $timeStampMessage
        LogToFile -message $timeStampMessage -fileName $filePath 
    } elseif ($messageType -eq "Warning") {
        if ($Global:EventLogEnabled) {
            LogToEventLog -message $message -entryType $messageType -entryId 1
        }
        LogToScreen -msg $timeStampMessage -color "Yellow"
        LogToFile -message $timeStampMessage -fileName $filePath
    } elseif ($messageType -eq "Error") {
        if ($Global:EventLogEnabled) {
            LogToEventLog -message $message -entryType $messageType -entryId 1
        }
        LogToScreen -msg $timeStampMessage -color "Red"
        LogToFile -message $timeStampMessage -fileName $filePath
        if ($isFatal) {
            $msg = "Fatal Error in Devops PowerShell - Exit"
            if ($Global:EventLogEnabled) {
                LogToEventLog -message $msg -entryType $messageType -entryId 1
            }
            LogToScreen -msg $msg -color "Red"
            LogToFile -message $msg -fileName $filePath
            exit 1
        }
    }
}

function LogToFile {
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $message, 

        [Parameter(Mandatory = $false)]
        [String]
        $fileName = ""
    )
    if ($fileName -eq "") {
        return
    } else {
        $message >> $fileName
    }
}

function LogToEventLog {
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $message,

        [Parameter(Mandatory = $true)]
        [String]
        $entryType,

        [Parameter(Mandatory = $true)]
        [String]
        $entryId
    )
    Write-EventLog -LogName "Application" -Source "DevopsPowerShell" -EventID $entryId -EntryType $entryType -Message $message -ErrorAction SilentlyContinue
}

function LogToScreen {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $msg,

        [Parameter(Mandatory = $false)]
        [string]
        $color
    )
	if ($color -eq $null -or $color -eq "") {
		$color = "Green"
	}
	Write-Host $message -ForegroundColor $color
	return $message
}

function LogInfoMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $msg,

        [Parameter(Mandatory = $false)]
        [string]
        $filePath
    )
    LogMessage -message $msg -messageType "Information" -filePath $filePath
}

function LogWarningMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $msg,

        [Parameter(Mandatory = $false)]
        [string]
        $filePath
    )
    LogMessage -message $msg -messageType "Warning" -filePath $filePath
}

function LogErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $msg,

        [Parameter(Mandatory = $false)]
        [string]
        $filePath,

		[Parameter(Mandatory = $false)]
        [bool]
        $fatal = $false 
    )
    if ($fatal) {
        LogMessage -message $msg -messageType "Error" -filePath $filePath -isFatal
    } else {
        LogMessage -message $msg -messageType "Error" -filePath $filePath
    }
} 

function ExportToCSV {
    param(
        [Parameter(Mandatory = $true)]
        $objectArray,

        [Parameter(Mandatory = $true)]
        [string]
        $filePath
    )
    $objectArray | Select-Object * | Export-Csv -Path $filePath -NoTypeInformation -Append
}


Function Remove-InvalidFileNameChars {
  param(
    [Parameter(Mandatory=$true,
      Position=0,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$true)]
    [String]$Name
  )

  $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
  $re = "[{0}]" -f [RegEx]::Escape($invalidChars)
  return ($Name -replace $re)
}