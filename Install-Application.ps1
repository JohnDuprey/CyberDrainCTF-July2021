#requires -RunAsAdministrator
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Write-LogMessage {
    <#
    .SYNOPSIS
        Write to event log and write-host
    .DESCRIPTION
        Take message and write event log / output via write-host
    .PARAMETER Message
        Message to write to event log
    .PARAMETER Category
        Event type to write (Info, Warn or Error)
    .PARAMETER EventId
        Custom Event ID (default 10001)
    .PARAMETER Silent
        Suppress Write-Host output
    #>
    Param (
        [Parameter(Mandatory = $true)]
        $Message,
        [ValidateSet('Info', 'Error', 'Warn')]
        $Category = "Info",
        $EventId = 1001,
        [switch]$Silent
    )
    switch ($Category) {
        'Error' { $etype = 1; break }
        'Warn' { $etype = 2; break }
        'Info' { $etype = 4; break }
    }
    $sysLogName = "CyberDrain CTF"
    If (-not([System.Diagnostics.EventLog]::SourceExists($sysLogName))) { New-EventLog -LogName Application -Source $sysLogName }
    Write-EventLog -Message $message -LogName Application -Source $sysLogName -EntryType $etype -EventId $EventId
    if (!($Silent)) {
        Write-Host $message
    } 
    Return
}

function Get-FileFromUrl {
    <#
    .SYNOPSIS
        Takes url and downloads file to specified directory
    .DESCRIPTION
        Download file from url using BITS, fail back to net.webclient
    .PARAMETER Url
        Message to write to event log
    .PARAMETER DestDir
        Destination Directory
    .PARAMETER FileName
        Downloaded file name
    #>
    Param (
        [string]$Url,
        [string]$DestDir,
        [string]$FileName
    )
    If (!(Test-Path -Path $DestDir)) {
        Write-LogMessage -category "Info" -message "Creating local destination directory $DestDir"
        Try {
            New-Item -Path $DestDir -ItemType Directory | Out-Null
        }
        Catch {
            Write-LogMessage -category "Error" -message ">> Failed to create the destination directory $DestDir with the following error: $($_.Exception.Message)." 
            break
        }
    }
    else {
        Remove-Item -Path "$DestDir\$FileName" -Force -ErrorAction SilentlyContinue
    }
    Write-LogMessage -category "Info" -message "Downloading $Url to $DestDir."

    If (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-LogMessage -category "Info" -message "Attempting to use BITS to download files."
        Try {
            Start-BitsTransfer -Source $url -Destination "$DestDir\$FileName" -Priority High -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-LogMessage -category "Error" -message "Failed to download $Url using BITS with the following error: $($_.Exception.Message)." 
            Write-LogMessage -category "Info" -message "Attempting to use WebClient to download files."
            $webclient = New-Object System.Net.WebClient
            Try {
                $webclient.DownloadFile($Url, "$DestDir\$FileName")
            }
            Catch {
                Write-LogMessage -category "Error" -message "Failed to download $Url with the following error: $($_.Exception.Message)." 
            }
        }
    }
    else {
        Write-LogMessage -category "Info" -message "Attempting to use WebClient to download files."
        $webclient = New-Object System.Net.WebClient
        Try {
            $webclient.DownloadFile($url, "$DestDir\$FileName")
        }
        Catch {
            Write-LogMessage -category "Error" -message "Failed to download $Url with the following error: $($_.Exception.Message)." 
        }
    }
}

Function Get-InstalledApps {
    <#
    .SYNOPSIS
        Get list of Software from HKLM
    .DESCRIPTION
        Gets list of installed software packages
    #>
    $RegPath = New-Object System.Collections.ArrayList
    $RegPath.Add('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') | Out-Null
    $RegPath64 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    If ( (Test-Path -Path $RegPath64) ) {
        $RegPath.Add($RegPath64) | Out-Null
    }

    $Apps = ForEach ($Path in $RegPath) {
        Try {
            $SelObjParams = $null
            $SelObjParams = @{
                Property = @(
                    @{n = 'DisplayName'; e = { ($_.DisplayName -replace '[^\u001F-\u007F]', '') } },
                    @{n = 'DisplayVersion'; e = { ($_.DisplayVersion -replace '[^\u001F-\u007F]', '') } },
                    'InstallDate',
                    'InstallLocation',
                    'UninstallString',
                    'QuietUninstallString',
                    'SystemComponent',
                    'NoRemove',
                    'NoRepair',
                    'PSChildName',
                    'PSPath',
                    'PSParentPath',
                    @{n = 'UserProfile'; e = { ($null) } } 
                )
            }
            Get-ItemProperty -Path $Path -ErrorAction 'SilentlyContinue' | Select-Object @SelObjParams
        }
        Catch {}
    }
    $Apps
}

Function Install-Application {
    <#
    .SYNOPSIS
        Install Applications from list
    .DESCRIPTION
        Cyberdrain CTF - Application install script
    .PARAMETER Applications
        Accepts list of applications - Options: Chrome,Firefox,Reader,Slack
    .PARAMETER DownloadDirectory
        Directory to download files to - default $env:windir\temp
    .OUTPUTS
        System.String - Results of installation
    .EXAMPLE
         Install-Application -Applications Chrome,Firefox,Slack,Reader 

         --- Cyberdrain CTF - Application install ---
        Selected Products: Chrome, Firefox, Slack, Reader
        Starting validation checks...
        Chrome is already installed
        Firefox is already installed
        Downloading https://slack.com/ssb/download-win64-msi-legacy to C:\Windows\temp.
        Attempting to use BITS to download files.
        Running installation: C:\Windows\system32\msiexec.exe /i C:\Windows\temp\slack.msi /qn /L*v C:\Windows\temp\slack-install.log
        Installation of Slack completed successfully
        Running secondary installer C:\Program Files\Slack Deployment\slack.exe
        Reader is already installed
        --- CyberDrain CTF - Application install completed ---
        Installed: 1 applications.
    .NOTES
        Author: John Duprey
        Date: 7/27/2021 
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Chrome', 'Firefox', 'Reader', 'Slack')]
        [string[]]$Applications,
        [string]$DownloadDirectory = "$env:windir\temp"
    )
    Begin {
        # List of applications and parameters for installation
        $AppInstallParams = @{ 
            'Chrome'  = @{
                'Url'              = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'
                'Destdir'          = $DownloadDirectory
                'Filename'         = "chrome.msi"
                'InstallCommand'   = "$env:windir\system32\msiexec.exe"
                'InstallArguments' = @("/i", "$DownloadDirectory\chrome.msi", "/qn", "/L*v $DownloadDirectory\chrome-install.log")
            }
            'Firefox' = @{
                'Url'              = 'https://download-installer.cdn.mozilla.net/pub/firefox/releases/90.0.2/win64/en-US/Firefox%20Setup%2090.0.2.msi'
                'Destdir'          = $DownloadDirectory
                'Filename'         = "firefox.msi"
                'InstallCommand'   = "$env:windir\system32\msiexec.exe"
                'InstallArguments' = @("/i", "$DownloadDirectory\firefox.msi", "/qn", "/L*v $TemPath\firefox-install.log")
            }
            'Reader'  = @{
                'Url'              = 'https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/1901020064/AcroRdrDC1901020064_MUI.exe'
                'Filename'         = 'reader.exe'
                'Destdir'          = $DownloadDirectory
                'InstallCommand'   = "$DownloadDirectory\reader.exe"
                'InstallArguments' = @("/sAll", "/msi", "/norestart", "/quiet", "ALLUSERS=1", "EULA_ACCEPT=YES")
            }
            'Slack'   = @{
                'Url'              = 'https://slack.com/ssb/download-win64-msi-legacy'
                'Destdir'          = $DownloadDirectory
                'Filename'         = "slack.msi"
                'InstallCommand'   = "$env:windir\system32\msiexec.exe"
                'InstallArguments' = @("/i", "$DownloadDirectory\slack.msi", "/qn", "/L*v", "$DownloadDirectory\slack-install.log")
                'SecondCommand'    = "$env:programfiles\Slack Deployment\slack.exe"
            }
        }
        $InstalledApps = Get-InstalledApps
        Write-LogMessage "--- Cyberdrain CTF - Application install ---`r`nSelected Products: $($Applications -join ', ')`r`nStarting validation checks..."
        $InstallCount = 0
    }
    Process {
        # Loop through each application in parameters
        Foreach ($Application in $Applications) {
            $app = (New-Object PSObject -Property $AppInstallParams.$Application)

            # Check installed programs and skip if already installed, write a warning to event logs
            $Installed = $InstalledApps | Where-Object { $_.DisplayName -match $Application }
            if ($Installed) {
                Write-LogMessage -Category Warn "$Application is already installed"
                continue
            }
            
            # Download file
            Get-FileFromUrl -url $app.Url -destdir $app.Destdir -filename $app.filename
            $filepath = "{0}\{1}" -f $app.destdir, $app.filename

            # Verify file exists
            if (Test-Path $filepath) {
                $message = "Running installation: {0} {1}" -f $app.InstallCommand, ($app.InstallArguments -join " ")

                Write-LogMessage -category "Info" -message $message
                Try {
                    # Try to install software and catch errors
                    $results = Start-Process -FilePath $app.installcommand -ArgumentList $app.InstallArguments -PassThru -Wait 
                    if ($results.ExitCode -eq 0 -or $results.ExitCode -eq 3010) {
                        if ($results.ExitCode -eq 3010) {
                            Write-LogMessage -category Info -message "Installation of $Application completed successfully`r`nA reboot is required to complete this install."
                        }
                        else {
                            Write-LogMessage -category Info -message "Installation of $Application completed successfully"
                        }
                        $InstallCount++

                        if ($app.SecondCommand) {
                            Write-LogMessage "Running secondary installer $($app.SecondCommand)"
                            Start-Process -FilePath $app.SecondCommand
                        }
                    }
                    else {
                        Write-LogMessage -category Error "Installation of $Application failed with exit code $($results.ExitCode)"
                    }
                }
                Catch {
                    Write-LogMessage -category Error "Installation of $Application failed with exception $($_.Exception.Message)"
                }
                # Clean up
                Remove-Item -Path $filepath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    End {
        # Log status
        Write-LogMessage "--- CyberDrain CTF - Application install completed ---`r`nInstalled: $InstallCount application(s)."
    }
}
