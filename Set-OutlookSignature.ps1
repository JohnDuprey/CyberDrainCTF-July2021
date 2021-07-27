Function Set-OutlookSignature {
    <#
    .SYNOPSIS
        Cyberdrain CTF - Outlook Signature Generator
    .DESCRIPTION
        This script will connect to Outlook, pull Exchange details and profile information and generate an HTML signature. 
        Upon successful signature generation and registry changes, it will prompt for an Outlook restart.
    .PARAMETER SignatureName
        Base name for the Signature in Outlook (e.g. CyberdrainCTF)
    .PARAMETER PhoneNumberField
        Field to use from Exchange User details for phone number (Default: BusinessPhoneNumber)
    .PARAMETER HtmlTemplate
        Provide a string containing parameters for string format (e.g. {0})
        Variables: 0 = FirstName LastName, 1 = Phone number, 2 = Email Address
    .OUTPUTS
        System.String - Results for setting the signature
    .EXAMPLE
        Set-OutlookSignature -SignatureName CyberdrainCTF -HtmlTemplate (Get-Content -Raw SignatureTemplate.html)

        ===== Cyberdrain CTF Outlook Signature Generator ======
        Detected information from Outlook
        - Profile : Test
        - Account : test@test.com
        CyberdrainCTF-Test signature prepared
        Outlook 2016/2019/365 detected
        - Setting New to CyberdrainCTF-Test
        - Setting Reply/Forward to CyberdrainCTF-Test 
        SUCCESS: Signature has been updated
        Restart Outlook now? (y/N): y
    .NOTES
        Author: John Duprey
        Date: 7/25/2021
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$SignatureName,
        [Parameter(Mandatory = $true)]
        [string]$HtmlTemplate,
        [ValidateSet('BusinessPhoneNumber', 'MobileTelephoneNumber')]
        [string]$PhoneNumberField = 'BusinessPhoneNumber'
    )
    Write-Host "===== Cyberdrain CTF Outlook Signature Generator ======" -BackgroundColor Yellow -ForegroundColor Black

    # Verify Outlook Process
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE\'

    if (Test-Path $key) {
        Write-Verbose "Found Outlook.exe registry key"
        $OutlookExe = (Get-ItemProperty -Path $key).'(default)'
        If (-not(Test-Path $OutlookExe)) {
            Write-Host "ERROR: Outlook not found" -BackgroundColor Red
            return
        }
        else {
            Write-Verbose "Found Outlook.exe file"
            If (-not (Get-Process | Where-Object -Property Name -eq "Outlook")) {
                Write-Host "Outlook Found, launching now. If you do not have a default profile selected, please do so at this time." -BackgroundColor DarkBlue
                Start-Process -FilePath $OutlookExe
            }
        }
    }
    else {            
        Write-Host "ERROR: Outlook not found" -BackgroundColor Red
        return
    }    

    # Connect to open Outlook process and obtain profile and user information
    try { 
        $OutlookApplication = New-Object -ComObject 'Outlook.Application'
        $Session = $OutlookApplication.Session
        $ProfileName = $Session.CurrentProfileName
    }
    catch {
        Write-Host "ERROR Connecting to Outlook process, please try again after Outlook loads."
    }
    try {
        $User = $Session.CurrentUser.AddressEntry.GetExchangeUser()
        if ($User.PrimarySmtpAddress -eq "" -or $null -eq $User.PrimarySmtpAddress) {
            return
        }
    }
    catch {
        Write-Host "ERROR: Unable to obtain user information from this profile. Please make sure that the account is logged into Exchange." -BackgroundColor Red
        return
    }

    Write-Host "Detected information from Outlook"
    Write-Host "- Profile : $ProfileName"
    Write-Host "- Account : $($user.PrimarySmtpAddress)"

    # Generate Signature File
    $SignatureName = "$SignatureName-$ProfileName" 
    $LocalSignaturePath = (Get-Item Env:AppData).Value + '\Microsoft\Signatures'
    $HtmlPath = "{0}\{1}.htm" -f $LocalSignaturePath, $SignatureName

    # Validate phone number field
    if (-not($user.$PhoneNumberField)) {
        Write-Host "WARNING: No phone number detected for the selected Phone Number field ($PhoneNumberField)." -BackgroundColor Yellow -ForegroundColor Black
    }

    # Populate HTML Template
    $Name = "{0} {1}" -f $User.FirstName, $user.LastName
    $PreparedTemplate = $HtmlTemplate -f $Name, $user.$PhoneNumberField, $user.PrimarySmtpAddress
    $PreparedTemplate | Set-Content -Path $HtmlPath
    If (Test-Path $HtmlPath) {
        Write-Host "$SignatureName signature prepared" -BackgroundColor DarkGreen -ForegroundColor Black
        Write-Verbose "- Path : $HtmlPath"
    }
    else {
        Write-Host "ERROR: Signature file not found" -BackgroundColor Red
        return
    }

    # Target Outlook Versions 2013+
    $TargetVersions = @{
        "15.0" = "2013"
        "16.0" = "2016/2019/365"
    }

    $SignatureSet = $false
    $NewSignatureExists = $false
    $ReplySignatureExists = $false

    # Loop through profiles and update signature keys
    foreach ($Version in $TargetVersions.Keys) {
        $HKCU = "HKCU:\Software\Microsoft\Office\$Version\Outlook\Profiles\$ProfileName\9375CFF0413111d3B88A00104B2A6676"
        if (Test-Path $HKCU) {
            Write-Host "Outlook $($TargetVersions.$Version) detected" -BackgroundColor DarkBlue
            $ProfileKey = Get-ChildItem -Path $HKCU | Foreach-Object { if (($_ | Get-ItemProperty)."Account Name" -ne "Outlook Address Book") { $_.PSPath } }
            $Props = Get-ItemProperty $ProfileKey | Select-Object "New Signature", "Reply-Forward Signature"
            Write-Verbose "Registry : $ProfileKey"
            if ($Props."New Signature" -ne $SignatureName) {
                Write-Host "- Setting New to $SignatureName"
                Get-Item -Path $ProfileKey | New-Itemproperty -Name "New Signature" -value $SignatureName -Propertytype string -Force | Out-Null
            }
            else {
                Write-Host "- New Signature already set"
                $NewSignatureExists = $true
            }
            if ($Props."Reply-Forward Signature" -ne $SignatureName) {
                Write-Host "- Setting Reply-Forward to $SignatureName" 
                Get-Item -Path $ProfileKey | New-Itemproperty -Name "Reply-Forward Signature" -value $SignatureName -Propertytype string -Force | Out-Null    
            }
            else {
                Write-Host "- Reply/Forward Signature already set"
                $ReplySignatureExists = $true
            }
            $SignatureSet = $true
        }    
    }

    # Check to see if signature was set
    if ($SignatureSet) {
        if (-not ($ReplySignatureExists -and $NewSignatureExists)) {
            Write-Host "SUCCESS: Signature has been updated" -BackgroundColor DarkGreen -ForegroundColor Black
            $restart = Read-Host -Prompt "Restart Outlook now? (y/N)" 
            if ($restart -eq 'y') {
                Get-Process Outlook | Stop-Process | Out-Null
                Start-Process -FilePath $OutlookExe
            }
        }
        else {
            Write-Host "SUCCESS: Signature is already set, no changes to Outlook at this time." -BackgroundColor DarkGreen -ForegroundColor Black
        }
    }
    else {
        Write-Host "ERROR: Signature has not been updated" -BackgroundColor Red
    }
    
}

# Signature base name
$SignatureName = 'CyberdrainCTF'

# Html Template
$HtmlTemplate = @"
<html>
<head><Title>Signature</Title></head>
<body>
    <BR>
        <table> 
            <tr>
                <td>-- CyberdrainCTF --</td>
            </tr>
            <tr>
                <td>{0}</td>
            </tr>
            <tr>
                <td>p. {1}</td>
            </tr>
            <tr>
                <td>e. {2}</td>
            </tr>
        </table>
</body>
</html>
"@

# Run function to make signature
Set-OutlookSignature -SignatureName $SignatureName -HtmlTemplate $HtmlTemplate
#Get-OutlookSignature -SignatureName $SignatureName -HtmlTemplate (Get-Content -Raw .\SignatureTemplate.html)