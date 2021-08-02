#requires -version 7

<#

WARNING: Starting this challenge by using the link below starts a 30 minute timer that cannot be stopped. There are no retries. Click on the URL below to start the timer and receive your token. Remember to add your own e-mail address to the URL: https://cyberdrainctf.azurewebsites.net/api/StartFileTimer?email=YOUREMAILADDRESSHERE@EMAIL.COM

the website https://tempstorage00011.blob.core.windows.net/ctffiles?restype=container&comp=list contains a list files. Find actual file that contains your token.

The filename of the file that contains your token, is the second token.

Change the following URL to the correct values:

https://cyberdrainctf.azurewebsites.net/api/CheckFile?email=YOUREMAIL@EMAIL.COM&Token=SECONDTOKEN

You will then receive your flag.

Timer URLs
https://cyberdrainctf.azurewebsites.net/api/StartFileTimer?email=john.duprey@complete.network
https://cyberdrainctf.azurewebsites.net/api/CheckFile?email=john.duprey@complete.network&Token=5d500e0c-9a7a-4e45-ad95-07e3d0845fd2

#>

Function Get-CTFBlobStorageList {
    Param(
        [string]$Marker = ''
    )
    $uri = 'https://tempstorage00011.blob.core.windows.net/ctffiles?restype=container&comp=list'
    
    If ($Marker -ne '') {
        $uri = "$uri&marker=$Marker"
    }

    Write-Host "Getting blob list for $uri" -BackgroundColor DarkBlue
    $wr = Invoke-WebRequest -UseBasicParsing -Uri $uri
    $xmlbegin = '(<\?xml.+$)'

    if ($wr.Content -match $xmlbegin) {
        $xml = [xml]$Matches[1]
        return $xml.EnumerationResults
    }
    else {
        return $false
    }
}

Function Get-CTFBlobFiles {
    Param(
        $EnumerationResults
    )
    $BlobList = $EnumerationResults.Blobs.Blob
    $blobcount = ($BlobList | Measure-Object).Count
    Write-Host "$blobcount blobs to search, starting parallel jobs" -BackgroundColor Yellow -ForegroundColor Black

    $BlobList | ForEach-Object -AsJob -ThrottleLimit 500 -Parallel {
        $Name = $_.Name
        $Type = ''
        Try {
            $filewr = Invoke-WebRequest -UseBasicParsing -Uri $_.Url -ErrorAction Stop
            $Token = $filewr.Content

            $Type = $Token.GetType().Name

            If ($Type -eq 'Byte[]') {
                $Token = [System.Text.Encoding]::ASCII.GetString($Token)
            }

            New-Object PSObject -Property @{
                FileName = $Name
                Token    = $Token 
                Type     = $Type             
            }
        }
        Catch {

        }
    } | Receive-Job -Wait -AutoRemoveJob
}

Function Start-CTFBlobChallenge {
    Param(
        [switch]$All,
        [string]$TokenToFind = ''
    )
    $start = Get-Date
    Write-Host '=== Starting CTF ===' -BackgroundColor Red
    Write-Host $start
    $NextMarker = ''
    $HasMorePages = $true
    $FlagFound = $false
    $x = 0
    Do {
        $EnumerationResults = Get-CTFBlobStorageList -Marker $NextMarker
        If ($x -ge 0) {
            $Blobs = Get-CTFBlobFiles -EnumerationResults $EnumerationResults 
        
            Foreach ($Blob in $Blobs) {
                if (!($All)) {
                    if ($Blob.Token -contains $TokenToFind) {
                        Write-Host '!!!!!!!!!!! FLAG FOUND !!!!!!!!!!' -BackgroundColor Green -ForegroundColor Black
                        $FlagFound = $true
                        $Blob
                        break
                    }
                }
                else {
                    $Blob
                }
            }
        }

        if (!($FlagFound)) { 
            if ($EnumerationResults.NextMarker) {
                $NextMarker = $EnumerationResults.NextMarker
                Write-Host "$x - Next Marker $NextMarker" -BackgroundColor Blue
                $HasMorePages = $true
            }
            else {
                Write-Host '=== No more markers found ===' -BackgroundColor Red
                $HasMorePages = $false
            }
        }
        else {
            $HasMorePages = $false
        }
        $x++
    }
    While ( $HasMorePages ) 
    $end = Get-Date
    Write-Host "CTF Completed $end" -BackgroundColor Red
    $mins = (New-TimeSpan -Start $start -End $end).Minutes
    Write-Host "Elapsed time $mins mins"
}
