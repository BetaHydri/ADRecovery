<#
.SYNOPSIS
    Identifies the best candidate Domain Controller to serve as the authoritative SYSVOL source.

.DESCRIPTION
    Inspects all Domain Controllers in the domain and collects diagnostic data to help
    determine which DC should be marked as the authoritative SYSVOL source during a
    DFS-R authoritative restore:
      - PDC Emulator role holder
      - DFS Replication service status
      - SYSVOL share availability
      - SYSVOL content (policy/script file count and total size)
      - Newest file timestamp in the SYSVOL Policies folder

    Outputs a ranked summary table. The DC with the highest score is recommended.

    Corresponds to:
      - SYSVOL Recovery  Step 1

.PARAMETER DomainFQDN
    The FQDN of the domain. Auto-detected if omitted.

.PARAMETER Credential
    Optional credential for remote access to DCs.

.EXAMPLE
    .\Find-AuthoritativeDC.ps1

.EXAMPLE
    .\Find-AuthoritativeDC.ps1 -DomainFQDN "contoso.com"

.EXAMPLE
    .\Find-AuthoritativeDC.ps1 -Credential (Get-Credential)

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding()]
param(
    [Parameter()]
    [string]$DomainFQDN,

    [Parameter()]
    [PSCredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Resolve domain ---
$domain = Get-ADDomain
if (-not $DomainFQDN) {
    $DomainFQDN = $domain.DNSRoot
}
$pdcEmulator = $domain.PDCEmulator

Write-Host "`n=== Find Authoritative DC for SYSVOL ===" -ForegroundColor Cyan
Write-Host "Domain       : $DomainFQDN"
Write-Host "PDC Emulator : $pdcEmulator"
Write-Host "Time         : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# --- Enumerate all DCs ---
$allDCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
Write-Host "Domain Controllers found: $($allDCs.Count)" -ForegroundColor Yellow
$allDCs | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- Collect diagnostics per DC ---
$results = foreach ($dc in $allDCs) {
    $dcShortName = ($dc -split '\.')[0]
    Write-Host "Inspecting $dc ..." -ForegroundColor Yellow

    # 1. PDC Emulator?
    $isPDC = $dc -eq $pdcEmulator

    # 2. DFS-R service status
    $dfsrStatus = 'Unknown'
    try {
        $invokeParams = @{ ComputerName = $dc; ErrorAction = 'Stop' }
        if ($Credential) { $invokeParams['Credential'] = $Credential }
        $svc = Get-Service -Name 'DFSR' @invokeParams
        $dfsrStatus = $svc.Status.ToString()
    }
    catch {
        Write-Host "  [WARN] Cannot query DFSR service on $dc : $_" -ForegroundColor DarkYellow
    }

    # 3. SYSVOL share reachable?
    $sysvolPath = "\\$dc\SYSVOL\$DomainFQDN\Policies"
    $sysvolReachable = Test-Path -Path $sysvolPath -ErrorAction SilentlyContinue

    # 4. SYSVOL content stats
    $fileCount = 0
    $totalSizeKB = 0
    $newestFile = $null
    if ($sysvolReachable) {
        try {
            $items = Get-ChildItem -Path $sysvolPath -Recurse -File -ErrorAction Stop
            $fileCount = $items.Count
            $totalSizeKB = [math]::Round(($items | Measure-Object -Property Length -Sum).Sum / 1KB, 2)
            if ($items.Count -gt 0) {
                $newestFile = ($items | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            }
        }
        catch {
            Write-Host "  [WARN] Cannot enumerate SYSVOL on $dc : $_" -ForegroundColor DarkYellow
        }
    }

    # 5. Score calculation
    $score = 0
    if ($isPDC) { $score += 3 }
    if ($dfsrStatus -eq 'Running') { $score += 2 }
    if ($sysvolReachable) { $score += 1 }
    # Bonus for content completeness — normalized later
    $score += [math]::Min($fileCount / 10, 2)   # up to 2 points

    [PSCustomObject]@{
        DC              = $dc
        IsPDCEmulator   = $isPDC
        DFSRService     = $dfsrStatus
        SYSVOLReachable = $sysvolReachable
        PolicyFiles     = $fileCount
        TotalSizeKB     = $totalSizeKB
        NewestFile      = $newestFile
        Score           = [math]::Round($score, 2)
    }
}

# --- Display results ---
Write-Host "`n=== Results ===" -ForegroundColor Cyan
$results | Sort-Object Score -Descending |
Format-Table DC, IsPDCEmulator, DFSRService, SYSVOLReachable, PolicyFiles, TotalSizeKB, NewestFile, Score -AutoSize

# --- Recommendation ---
$recommended = $results | Sort-Object Score -Descending | Select-Object -First 1
Write-Host "Recommended authoritative DC: " -NoNewline -ForegroundColor Green
Write-Host $recommended.DC -ForegroundColor White
Write-Host "  PDC Emulator   : $($recommended.IsPDCEmulator)"
Write-Host "  DFSR Service   : $($recommended.DFSRService)"
Write-Host "  SYSVOL Content : $($recommended.PolicyFiles) files ($($recommended.TotalSizeKB) KB)"
Write-Host "  Newest File    : $($recommended.NewestFile)"
Write-Host "  Score          : $($recommended.Score)`n"

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Verify the SYSVOL content on $($recommended.DC) is correct and complete"
Write-Host "  2. Run Set-AuthoritativeSYSVOLRestore.ps1 -DCName '$($recommended.DC.Split('.')[0])'"
Write-Host "  3. Run Set-NonAuthoritativeSYSVOL.ps1 for all other DCs`n"

# --- Return the results for pipeline use ---
$results | Sort-Object Score -Descending
