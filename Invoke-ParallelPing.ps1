#requires -version 7
Function Invoke-ParallelPing {
    <#
    .SYNOPSIS
        Parallel ping checks
    .DESCRIPTION
        This script will accept a list of IP addresses or hostnames and perform ping checks in parallel. Requires PowerShell version 7. 
    .PARAMETER IPs
        List of IP addresses or hostnames to check
    .PARAMETER ThrottleLimit
        Number of parallel threads to process at a time (default 10) 
    .INPUTS
        System.String[] - List of IP Addresses/Hosts to ping
    .OUTPUTS
        System.Object - Ping results per address
    .EXAMPLE
        Invoke-ParallelPing -IPs @('1.1.1.1','8.8.8.8') -ThrottleLimit 5

        Address PingSucceeded RTT
        ------- ------------- ---
        8.8.8.8          True  12
        1.1.1.1          True  11
    .EXAMPLE
        @('8.8.8.8','8.8.4.4') | Invoke-ParallelPing    

        Address PingSucceeded RTT
        ------- ------------- ---
        8.8.8.8          True  11
        8.8.4.4          True  10
    .NOTES
        Author: John Duprey
        Date: 7/24/2021
    #>      
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true, ValuefromPipeline = $True)]
        [string[]]$IPs,
        [ValidateRange(1, 20)]
        $ThrottleLimit = 10
    )

    Begin {
        $StartTime = Get-Date
        Write-Verbose "-- Parallel ping test --"
        Write-Progress -Id 1 -Activity "Pinging..." 
        $AllIPs = New-Object System.Collections.ArrayList
    }

    Process {
        Foreach ($ip in $IPs) {
            $AllIPs.Add($ip) | Out-Null
        }
    }
    
    End {
        $AllIPs = $AllIPs | Sort-Object -Unique
        $IPCount = ($AllIPs | Measure-Object).Count

        $AllIPs | Foreach-Object -AsJob -ThrottleLimit $ThrottleLimit -Parallel {
            $p = Write-Progress -Activity "- $_"
            Test-NetConnection $_ -WarningAction Ignore
            $p | Write-Progress -Activity "- $_" -Completed
        } | Receive-Job -Wait -AutoRemoveJob | Select-Object @{name = "Address"; expression = { $_.ComputerName } }, PingSucceeded, @{name = "RTT"; expression = { $_.PingReplyDetails.RoundtripTime } }

        $EndTime = Get-Date
        $seconds = (New-Timespan -Start $StartTime -End $EndTime).TotalSeconds
        Write-Verbose "Pings finished for $IPCount IPs. Total time $($seconds)s"
        Write-Progress -Id 1 -Activity "Pinging Complete." -Completed
    }
}
