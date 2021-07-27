[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Write-SysLog {
    Param (
        [Parameter(Mandatory = $true)]$message,
        $category = "INFO"
    )
    switch ($category) {
        'ERROR' { $etype = 1; break }
        'WARN' { $etype = 2; break }
        default { $etype = 4; break }
    }
    $sysLogName = "$script:application Installation"
    If (-not([System.Diagnostics.EventLog]::SourceExists($sysLogName))) { New-EventLog -LogName Application -Source $sysLogName }
    Write-EventLog -Message $message -LogName Application -Source $sysLogName -EntryType $etype -EventId 1001
    Write-Host $message 
    Return
}

function Get-FileFromUrl {
    Param (
        [string]$url,
		[string]$destdir,
        [string]$filename
    )
    If (!(Test-Path -Path $destdir)) {
        Write-Syslog -category "INFO" -message "Creating local destination directory $destdir"
        Try {
            New-Item -Path $destdir -ItemType Directory | Out-Null
        }
        Catch {
            Write-Syslog -category "ERROR" -message ">> Failed to create the destination directory $destdir with the following error: $($_.Exception.Message)." 
            break
        }
    }
    else {
        Remove-Item -Path "$destdir\$filename" -Force -ErrorAction SilentlyContinue
    }
    Write-Syslog -category "INFO" -message "Downloading $url to $destdir."

    If (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-Syslog -category "INFO" -message "Attempting to use BITS to download files."
        Try {
            Start-BitsTransfer -Source $url -Destination "$destdir\$filename" -Priority High -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Syslog -category "ERROR" -message "Failed to download $url using BITS with the following error: $($_.Exception.Message)." 
            Write-Syslog -category "INFO" -message "Attempting to use WebClient to download files."
            $webclient = New-Object System.Net.WebClient
            Try {
                $webclient.DownloadFile($url, "$destdir\$filename")
            }
            Catch {
                Write-Syslog -category "ERROR" -message "Failed to download $url with the following error: $($_.Exception.Message)." 
            }
        }
    }
    else {
        Write-Syslog -category "INFO" -message "Attempting to use WebClient to download files."
        $webclient = New-Object System.Net.WebClient
        Try {
            $webclient.DownloadFile($url, "$destdir\$filename")
        }
        Catch {
            Write-Syslog -category "ERROR" -message "Failed to download $url with the following error: $($_.Exception.Message)." 
        }
    }
}

Function Install-Application {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Chrome', 'Firefox', 'Reader', 'Slack')]
        [string[]]$Applications
    )
    
    $TempDir = "$env:windir\temp"
    $AppInstallParams = @{ 
        'Chrome'  = @{
            'Url'              = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'
            'Destdir'          = $TempDir
            'Filename'         = "chrome.msi"
            'InstallCommand'   = "$env:windir\system32\msiexec.exe"
            'InstallArguments' = @("/i", "'$TempDir\chrome.msi'", "/qn", "/L*v $TempDir\chrome-install.log")
        }
        'Firefox' = @{
            'Url'              = 'https://download-installer.cdn.mozilla.net/pub/firefox/releases/90.0.2/win64/en-US/Firefox%20Setup%2090.0.2.msi'
            'Destdir'          = $TempDir
            'Filename'         = "firefox.msi"
            'InstallCommand'   = "$env:windir\system32\msiexec.exe"
            'InstallArguments' = @("/i", "'$TempDir\firefox.msi'", "/qn", "/L*v $TempDir\firefox-install.log")
        }
        'Reader'  = @{
            'Url'              = 'https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/1901020064/AcroRdrDC1901020064_MUI.exe'
            'Filename'         = 'reader.exe'
            'Destdir'          = $TempDir
            'InstallCommand'   = 'reader.exe'
            'InstallArguments' = @("/sAll", "/msi", "/norestart", "/quiet", "/L*v $TempDir\reader-install.log", "ALLUSERS=1", "EULA_ACCEPT=YES")
        }
        'Slack'   = @{
            'Url'              = 'https://slack.com/ssb/download-win64-msi-legacy'
            'Destdir'          = $TempDir
            'Filename'         = "slack.msi"
            'InstallCommand'   = "$env:windir\system32\msiexec.exe"
            'InstallArguments' = @("/i", "'$TempDir\slack.msi'", "/qn", "/L*v", "$TempDir\slack-install.log")
        }
    }

    Foreach ($Application in $Applications) {
        $app = (New-Object PSObject -Property $AppInstallParams.$Application)

        $DownloadParams
        Get-FileFromUrl -url $app.Url -destdir $app.Destdir -filename $app.filename
        $filepath = "{0}\{1}" -f $app.destdir, $app.filename
        if (Test-Path $filepath) {

            $message = "Running installation {0} - {1}" -f $app.InstallCommand, ($app.InstallArguments -join " ")

            Write-SysLog -category "INFO" -message $message
            #$Result = Invoke-Command -FilePath $filepath -ArgumentList $app.InstallArguments
            $results = Start-Process -FilePath $filepath -ArgumentList $app.InstallArguments -NoNewWindow -Wait
            $results
            #if ($Result.ExitCode -eq 0) {
            #    Write-SysLog -category INFO -message "Installation of $Application completed successfully"
            #}
            #else {
            #    Write-Syslog -category ERROR "Installation of $App failed with exit code $($Result.ExitCode)"
            #}
        }

    }

}