Invoke-Expression (&'C:\Program Files\starship\bin\starship.exe' init powershell)

# NOTE(gabriela): allow the execution of arbitrary scripts, etc!
Set-ExecutionPolicy Unrestricted -Scope CurrentUser

<# =========================================================================
   SHELL UTILITIES
========================================================================= #>

function hist {
    $find = $args -join ' '

    # Get all known names/aliases for the 'hist' function
    $histCommandNames = @()
    $command = Get-Command hist -ErrorAction SilentlyContinue
    if ($command) {
        $histCommandNames += $command.Name
        if ($command.CommandType -eq 'Function') {
            $histCommandNames += (Get-Alias | Where-Object { $_.Definition -eq 'hist' }).Name
        }
    }

    Write-Host " HIST " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Searching for " -ForegroundColor Gray -NoNewline
    Write-Host "*$find*" -ForegroundColor White

    Write-Host ""

    Get-Content (Get-PSReadlineOption).HistorySavePath |
        Where-Object {
            $_ -like "*$find*" -and
            ($histCommandNames -notcontains ($_ -split '\s+')[0])
        } |
        Get-Unique |
        more
}


<# =========================================================================
   GIT HELPERS
========================================================================= #>

function New-GitBranchFromRemote {
    <#
    .SYNOPSIS
        Safely create a new local git branch from a remote branch, verifying and confirming everything.

    .PARAMETER LocalBranch
        The name of the new local branch.

    .PARAMETER RemoteName
        The remote name (e.g., origin, upstream).

    .PARAMETER BaseBranch
        The remote branch to base from (exact or partial).

    .PARAMETER Closest
        If specified, the function will attempt to find and suggest the closest matching remote branch
        and ask for user confirmation before using it.

    .EXAMPLE
        New-GitBranchFromRemote -LocalBranch fix/foo -RemoteName origin -BaseBranch feature/bar
    #>

    param(
        [Parameter(Mandatory = $true)][string]$LocalBranch,
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][string]$BaseBranch,
        [switch]$Closest
    )

    function Throw-IfGitFailed($output, $code) {
        if ($code -ne 0) {
            Write-Error "Git command failed:`n$output"
            throw "Git error"
        }
    }

    function Get-LeadingIndent($s) {
        return ($s.Length - $s.TrimStart().Length)
    }

    # Check git availability
    try {
        git --version *>$null
    } catch {
        Write-Error "git is not available on PATH."
        return
    }

    # Parse git remote -v
    $remotesRaw = git remote -v 2>&1
    Throw-IfGitFailed $remotesRaw $LASTEXITCODE

    $remoteEntries = @()
    foreach ($line in $remotesRaw -split "`n") {
        $l = $line.Trim()
        if (-not $l) { continue }
        if ($l -match '^(?<name>\S+)\s+(?<url>\S+)\s+\((?<perm>[^)]+)\)') {
            $remoteEntries += [pscustomobject]@{
                Name = $Matches['name']
                Url  = $Matches['url']
                Perm = $Matches['perm']
            }
        }
    }

    $remote = $remoteEntries | Where-Object { $_.Name -ieq $RemoteName -and $_.Perm -ieq 'fetch' }
    if (-not $remote) {
        Write-Error "No (fetch) entry found for remote '$RemoteName'."
        Write-Host "  Available remotes:" -ForegroundColor Gray
        $remoteEntries | ForEach-Object { Write-Host "    $($_.Name) " -ForegroundColor White -NoNewline; Write-Host "($($_.Perm)) -> $($_.Url)" -ForegroundColor DarkGray }
        return
    }

    # Fetch remote (safe)
    Write-Host " GIT " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Fetching from " -ForegroundColor Gray -NoNewline
    Write-Host "$RemoteName" -ForegroundColor White -NoNewline
    Write-Host "..." -ForegroundColor DarkGray
    $fetchOut = git fetch $RemoteName 2>&1
    Throw-IfGitFailed $fetchOut $LASTEXITCODE
    Write-Host "  Fetch complete." -ForegroundColor Gray

    # Parse remote branches
    $showOut = git remote show $RemoteName 2>&1
    Throw-IfGitFailed $showOut $LASTEXITCODE
    $lines = $showOut -split "`n"

    $foundIdx = ($lines | Select-String -Pattern '^\s*Remote branches:' | Select-Object -First 1).LineNumber
    if (-not $foundIdx) {
        Write-Error "Could not find 'Remote branches:' in remote show output."
        return
    }

    $foundIdx--
    $sectionIndent = Get-LeadingIndent $lines[$foundIdx]
    $branches = @()

    for ($i = $foundIdx + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq '') { break }
        if ((Get-LeadingIndent $line) -le $sectionIndent) { break }
        $name = $line.Trim().Split(' ')[0]
        if ($name) { $branches += $name }
    }

    if (-not $branches) {
        Write-Error "No remote branches found for '$RemoteName'."
        return
    }

    $chosen = $branches | Where-Object { $_ -ieq $BaseBranch } | Select-Object -First 1
    if ($chosen) {
        Write-Host "  Found exact branch: " -ForegroundColor Gray -NoNewline
        Write-Host "$chosen" -ForegroundColor White
    }
    else {
        $candidates = $branches | Where-Object { $_ -like "$BaseBranch*" }
        if (-not $candidates) {
            $candidates = $branches | Where-Object { $_ -match [Regex]::Escape($BaseBranch) }
        }

        if (-not $candidates) {
            Write-Host "  No remote branch found matching " -ForegroundColor Gray -NoNewline
            Write-Host "'$BaseBranch'" -ForegroundColor White
            Write-Host "  Available branches on " -ForegroundColor Gray -NoNewline
            Write-Host "$RemoteName" -ForegroundColor White -NoNewline
            Write-Host ":" -ForegroundColor Gray
            $branches | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            return
        }

        $preferred = $candidates | Sort-Object { $_.Length } | Select-Object -First 1
        if (-not $Closest) {
            Write-Host "  No exact branch " -ForegroundColor Gray -NoNewline
            Write-Host "'$BaseBranch'" -ForegroundColor White -NoNewline
            Write-Host " found. Closest matches:" -ForegroundColor Gray
            $candidates | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host "  Re-run with " -ForegroundColor Gray -NoNewline
            Write-Host "-Closest" -ForegroundColor White -NoNewline
            Write-Host " to choose automatically." -ForegroundColor Gray
            return
        }

        Write-Host "  No exact match. Use closest branch " -ForegroundColor Gray -NoNewline
        Write-Host "'$preferred'" -ForegroundColor White -NoNewline
        $answer = Read-Host "? (Y/n)"
        if ($answer -match '^[Nn]') { Write-Host "  Aborted." -ForegroundColor DarkGray; return }
        $chosen = $preferred
    }

    # Confirm before checkout
    $cmd = "git checkout -b $LocalBranch $RemoteName/$chosen"
    Write-Host ""
    Write-Host " RUN " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " $cmd" -ForegroundColor White
    Write-Host ""
    Write-Host "  Proceed" -ForegroundColor Gray -NoNewline
    $confirm = Read-Host "? (Y/n)"
    if ($confirm -match '^[Nn]') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Running checkout..." -ForegroundColor Gray
    $coOut = & git checkout -b $LocalBranch "$RemoteName/$chosen" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Checkout failed:`n$coOut"
        return
    }

    Write-Host "  $coOut" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Created " -ForegroundColor Gray -NoNewline
    Write-Host "$LocalBranch" -ForegroundColor White -NoNewline
    Write-Host " from " -ForegroundColor Gray -NoNewline
    Write-Host "$RemoteName/$chosen" -ForegroundColor White
}


<# =========================================================================
   KUBERNETES HELPERS
========================================================================= #>

function New-KubectlBusyBoxPod {
    <#
    .SYNOPSIS
        Create a BusyBox pod in Kubernetes with optional auto-attach.

    .PARAMETER Name
        The name of the pod to create.

    .PARAMETER Restart
        Restart policy for the pod. Valid values: Never, OnFailure, Always (default).

    .PARAMETER Attach
        If specified, automatically attach to /bin/sh after pod is ready.

    .EXAMPLE
        New-KubectlBusyBoxPod -Name fun -Attach
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [ValidateSet("Never", "OnFailure", "Always")]
        [string]$Restart = "Always",

        [switch]$Attach
    )

    # --- Sanity checks ---
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl not found in PATH. Please install kubectl first."
        return
    }

    $clusterInfo = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to connect to Kubernetes cluster. Make sure a context is set."
        Write-Host "`n$clusterInfo"
        return
    }

    # --- Check if pod already exists ---
    $getPodOutput = kubectl get pod $Name 2>$null
    if ($LASTEXITCODE -eq 0 -and $getPodOutput) {
        # Split into lines, take second one
        $lines = $getPodOutput -split "`r?`n"
        if ($lines.Length -ge 2) {
            $fields = $lines[1] -split '\s+'
            if ($fields.Length -ge 3) {
                $podName = $fields[0]
                $podStatus = $fields[2]
                Write-Host " POD " -ForegroundColor Black -BackgroundColor White -NoNewline
                Write-Host " $podName " -ForegroundColor White -NoNewline
                Write-Host "exists, status: " -ForegroundColor Gray -NoNewline
                Write-Host "$podStatus" -ForegroundColor White

                # Prompt user to delete existing pod
                Write-Host "  Delete pod " -ForegroundColor Gray -NoNewline
                Write-Host "'$podName'" -ForegroundColor White -NoNewline
                $response = Read-Host " and recreate it? (y/n)"
                if ($response -match '^(y|Y)$') {
                    Write-Host "  Deleting existing pod..." -ForegroundColor DarkGray
                    kubectl delete pod $podName --force --grace-period=0 | Out-Null

                    # Confirm deletion
                    Start-Sleep -Seconds 1
                    kubectl get pod $podName 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Error "Failed to delete existing pod '$podName'. Aborting."
                        return
                    } else {
                        Write-Host "  Pod deleted." -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  Aborted." -ForegroundColor DarkGray
                    return
                }
            }
        }
    }

    # --- Create the pod ---
    $cmd = @(
        "run", $Name,
        "--image=busybox",
        "--restart=$Restart",
        "--", "sleep", "infinity"
    )

    Write-Host " K8S " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Creating " -ForegroundColor Gray -NoNewline
    Write-Host "$Name" -ForegroundColor White -NoNewline
    Write-Host " (restart: $Restart)..." -ForegroundColor DarkGray
    $runResult = kubectl @cmd

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Pod creation failed:"
        Write-Host $runResult
        return
    }

    # --- Wait for pod to become ready ---
    Write-Host "  Waiting for pod to be ready..." -ForegroundColor DarkGray
    kubectl wait --for=condition=Ready pod/$Name --timeout=30s | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Pod '$Name' did not become ready in time."
        return
    }

    Write-Host ""
    Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Pod " -ForegroundColor Gray -NoNewline
    Write-Host "$Name" -ForegroundColor White -NoNewline
    Write-Host " is ready" -ForegroundColor Gray

    # --- Optional attach ---
    if ($Attach) {
        Write-Host ""
        Write-Host " ATTACH " -ForegroundColor Black -BackgroundColor White -NoNewline
        Write-Host " /bin/sh" -ForegroundColor White
        kubectl exec -it $Name -- /bin/sh
    }
}


<# =========================================================================
   WINDOWS PE ANALYSIS
========================================================================= #>

function Find-PEExports {
    <#
    .SYNOPSIS
        Search Windows PE files for exported functions matching a pattern.

    .PARAMETER PEName
        Wildcard pattern to match PE file names.

    .PARAMETER Export
        Wildcard pattern to match export names.

    .PARAMETER wow
        If specified, search SysWOW64 instead of System32.

    .EXAMPLE
        Find-PEExports -PEName "kernel32" -Export "Create*"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PEName,

        [Parameter(Mandatory = $true)]
        [string]$Export,

        [switch]$wow
    )

    # Check if dumpbin is in PATH
    $DumpbinPath = Get-Command dumpbin -ErrorAction SilentlyContinue
    if (-not $DumpbinPath) {
        Write-Error "'dumpbin' was not found in your system PATH. Please run from a Developer Command Prompt or add it to PATH."
        return
    }

    # Set search paths
    $SearchPaths = @("C:\Windows", "C:\Windows\System32")
    if ($wow) {
        $SearchPaths = @("C:\Windows", "C:\Windows\SysWOW64")
    }

    Write-Host ""
    Write-Host " PE " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Searching for exports matching " -ForegroundColor Gray -NoNewline
    Write-Host "'$Export'" -ForegroundColor White -NoNewline
    Write-Host " in " -ForegroundColor Gray -NoNewline
    Write-Host "'*$PEName*'" -ForegroundColor White
    Write-Host ""

    $totalMatches = 0

    foreach ($Path in $SearchPaths) {
        # Get matching files based on PEName pattern (only top-level files)
        $Files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$PEName*" }

        foreach ($File in $Files) {
            # Run dumpbin /EXPORTS on the file
            $Output = & dumpbin /EXPORTS "`"$($File.FullName)`"" 2>&1

            # Only continue if dumpbin succeeded
            if (-not $?) { continue }

            # Parse the output
            $lines = $Output -split "`r?`n"
            $inExportSection = $false
            $exports = @()

            foreach ($line in $lines) {
                # Start parsing after the header line
                if ($line -match '^\s*ordinal\s+hint\s+RVA\s+name') {
                    $inExportSection = $true
                    continue
                }

                # Stop at Summary section
                if ($line -match '^\s*Summary\s*$') {
                    break
                }

                if ($inExportSection -and $line.Trim() -ne '') {
                    # Split by whitespace, first 3 are ordinal/hint/RVA, rest is name
                    $parts = $line.Trim() -split '\s+'
                    if ($parts.Count -ge 4) {
                        $RVA  = $null;
                        $Name = $null
                        if ($parts[2] -match '^[0-9a-fA-F]+$') {
                            $RVA =  $parts[2]
                            $Name = $parts[3..$parts.Length] -join ' '
                        } else {
                            $RVA = "forward";
                            $Name = $parts[2..$parts.Length] -join ' '
                        }
                        $exports += [PSCustomObject]@{
                            Ordinal = $parts[0]
                            Hint    = $parts[1]
                            RVA     = $RVA
                            Name    = $Name
                        }
                    }
                }
            }

            # Filter exports matching the pattern
            $matchedExports = $exports | Where-Object { $_.Name -like "*$Export*" }

            if ($matchedExports.Count -gt 0) {
                # Calculate max widths for each column
                $maxOrd = [math]::Max(3, ($matchedExports | ForEach-Object { $_.Ordinal.Length } | Measure-Object -Maximum).Maximum)
                $maxHint = [math]::Max(4, ($matchedExports | ForEach-Object { $_.Hint.Length } | Measure-Object -Maximum).Maximum)
                $maxRva = [math]::Max(3, ($matchedExports | ForEach-Object { $_.RVA.Length } | Measure-Object -Maximum).Maximum)

                Write-Host "  $($File.Name)" -ForegroundColor White
                Write-Host "    " -NoNewline
                Write-Host ("{0,$maxOrd}" -f "ord") -ForegroundColor Black -BackgroundColor White -NoNewline
                Write-Host " " -NoNewline
                Write-Host ("{0,$maxHint}" -f "hint") -ForegroundColor Black -BackgroundColor White -NoNewline
                Write-Host " " -NoNewline
                Write-Host ("{0,$maxRva}" -f "rva") -ForegroundColor Black -BackgroundColor White -NoNewline
                Write-Host " " -NoNewline
                Write-Host ("{0,4}" -f "name") -ForegroundColor Black -BackgroundColor White -NoNewline
                Write-Host ""
                Write-Host ""
                foreach ($exp in $matchedExports) {
                    Write-Host "    " -NoNewline
                    Write-Host ("{0,$maxOrd}" -f $exp.Ordinal) -ForegroundColor Black -BackgroundColor White -NoNewline
                    Write-Host " " -NoNewline
                    Write-Host ("{0,$maxHint}" -f $exp.Hint) -ForegroundColor Black -BackgroundColor White -NoNewline
                    Write-Host " " -NoNewline
                    Write-Host ("{0,$maxRva}" -f $exp.RVA) -ForegroundColor Black -BackgroundColor White -NoNewline
                    Write-Host "  $($exp.Name)" -ForegroundColor Gray
                }
                Write-Host ""
                $totalMatches += $matchedExports.Count
            }
        }
    }

    if ($totalMatches -eq 0) {
        Write-Host "  No matching exports found." -ForegroundColor DarkGray
    } else {
        Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
        Write-Host " Found " -ForegroundColor Gray -NoNewline
        Write-Host "$totalMatches" -ForegroundColor White -NoNewline
        Write-Host " matching export(s)" -ForegroundColor Gray
    }
}

function Find-PEString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [switch]$Recursive,
        [switch]$FullPath
    )

    $stringsExe = "C:\Users\gabriela\Desktop\Sysinternals Suite\strings64.exe"

    if (-not (Test-Path $stringsExe)) {
        Write-Error "strings64.exe not found at: $stringsExe"
        return
    }

    Write-Host ""
    Write-Host " STR " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Searching for strings matching " -ForegroundColor Gray -NoNewline
    Write-Host "'$Pattern'" -ForegroundColor White -NoNewline
    Write-Host " in " -ForegroundColor Gray -NoNewline
    Write-Host "$Path" -ForegroundColor White
    Write-Host ""

    # Build GCI args
    $gciArgs = @{ Path = $Path; File = $true }
    if ($Recursive) { $gciArgs.Recurse = $true }

    # Collect PE files
    $files = @()
    $files += Get-ChildItem @gciArgs -Filter *.exe
    $files += Get-ChildItem @gciArgs -Filter *.dll

    $totalMatches = 0
    $lastFile = $null
    $offsetWidth = 12  # Fixed width for hex offsets (0xXXXXXXXX)

    foreach ($file in $files) {
        $output = & $stringsExe -o $file.FullName 2>$null
        if (-not $output) { continue }

        foreach ($line in $output) {
            # Strings line: "<offset>:<string>"
            if ($line -match "^([0-9A-Fa-fx]+):(.*)$") {
                $offsetDec = $Matches[1].Trim()
                $text      = $Matches[2].Trim()

                if ($text -Like $Pattern) {
                    # Print file header only if file changed
                    if ($file.FullName -ne $lastFile) {
                        if ($null -ne $lastFile) { Write-Host "" }
                        $name = if ($FullPath) { $file.FullName } else { $file.Name }
                        Write-Host "  $name" -ForegroundColor White
                        Write-Host "    " -NoNewline
                        Write-Host ("{0,$offsetWidth}" -f "offset") -ForegroundColor Black -BackgroundColor White -NoNewline
                        Write-Host " " -NoNewline
                        Write-Host "text" -ForegroundColor Black -BackgroundColor White
                        Write-Host ""
                        $lastFile = $file.FullName
                    }

                    # Convert decimal -> hex (0xXXXXXXXX)
                    $offsetInt = [int]$offsetDec
                    $offsetHex = ("0x{0:X}" -f $offsetInt)

                    Write-Host "    " -NoNewline
                    Write-Host ("{0,$offsetWidth}" -f $offsetHex) -ForegroundColor Black -BackgroundColor White -NoNewline
                    Write-Host "  $text" -ForegroundColor Gray

                    $totalMatches++
                }
            }
        }
    }

    Write-Host ""

    if ($totalMatches -eq 0) {
        Write-Host "  No matching strings found." -ForegroundColor DarkGray
    } else {
        Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
        Write-Host " Found " -ForegroundColor Gray -NoNewline
        Write-Host "$totalMatches" -ForegroundColor White -NoNewline
        Write-Host " matching string(s)" -ForegroundColor Gray
    }
}

function Find-WinConstant {
    <#
    .SYNOPSIS
        Search Windows SDK headers for constant definitions matching a pattern.

    .PARAMETER Pattern
        Wildcard pattern to match constant names. Use * for wildcards.

    .PARAMETER NoSort
        Switch to disable the default numeric sorting and use alphabetical sorting instead.

    .PARAMETER CaseSensitive
        Switch to perform a case-sensitive search. Defaults to case-insensitive.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $false)]
        [switch]$NoSort,

        [Parameter(Mandatory = $false)]
        [switch]$CaseSensitive
    )

    # Check if rg is in PATH
    $RgPath = Get-Command rg.exe -ErrorAction SilentlyContinue
    if (-not $RgPath) {
        Write-Error "'rg.exe' (ripgrep) was not found in your system PATH."
        return
    }

    # Path Construction & Sanitization
    $WinSDKLib = Join-Path $env:WindowsSdkDir "Include\$($env:WindowsSDKLibVersion)"
    $WinSDKLib = $WinSDKLib.TrimEnd('/').TrimEnd('\')

    if (-not (Test-Path $WinSDKLib)) {
        Write-Error "Windows SDK Path not found: $WinSDKLib"
        return
    }

    Write-Host ""
    Write-Host " SDK " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Searching for constants matching " -ForegroundColor Gray -NoNewline
    Write-Host "'$Pattern'" -ForegroundColor White
    Write-Host ""

    # Logic for Wildcards (*)
    $LeftBound = if ($Pattern.StartsWith("*")) { "[a-zA-Z0-9_]*" } else { "\b" }
    $RightBound = if ($Pattern.EndsWith("*")) { "[a-zA-Z0-9_]*" } else { "\b" }
    $CleanPattern = $Pattern.Trim('*')

    # Define Regex
    $Regex = "$LeftBound$CleanPattern$RightBound\s*=?\s*(0x[0-9a-fA-F]+|\d+)\b"

    # Invoke ripgrep (conditionally add -i)
    $RgArgs = @("-oI", "--no-filename")
    if (-not $CaseSensitive) { $RgArgs += "-i" }
    $RgArgs += $Regex
    $RgArgs += $WinSDKLib

    $Results = & rg.exe @RgArgs 2>&1

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
        Write-Error "ripgrep failed with exit code $LASTEXITCODE"
        return
    }

    # Parse results
    $constants = @()
    $MatchModifier = if ($CaseSensitive) { "" } else { "(?i)" }
    
    foreach ($Line in $Results) {
        if ($Line -match "$MatchModifier^(?<Literal>[a-z0-9_]+)\s*=?\s*(?<Value>.+)$") {
            $LiteralName = $Matches.Literal
            $StringValue = $Matches.Value
            
            # Windows PowerShell 5.1 safe base detection
            $Base = if ($StringValue.StartsWith("0x")) { 16 } else { 10 }
            
            try {
                $NumericValue = [Convert]::ToInt64($StringValue, $Base)
                
                $constants += [PSCustomObject]@{
                    Name        = $LiteralName
                    Value       = $StringValue
                    NumericSort = $NumericValue
                }
            } catch {
                continue
            }
        }
    }

    # Remove duplicates and Apply Sort Logic
    # Default behavior is now numeric sort unless -NoSort is used
    if (-not $NoSort) {
        $constants = $constants | Sort-Object NumericSort, Name -Unique
    } else {
        $constants = $constants | Sort-Object Name, Value -Unique
    }

    if ($constants.Count -eq 0) {
        Write-Host "  No matching constants found." -ForegroundColor DarkGray
        return
    }

    # Calculate column widths
    $maxName = [math]::Max(4, ($constants | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    $maxValue = [math]::Max(5, ($constants | ForEach-Object { $_.Value.Length } | Measure-Object -Maximum).Maximum)

    # Print header
    Write-Host "  " -NoNewline
    Write-Host ("{0,-$maxName}" -f "name") -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " " -NoNewline
    Write-Host ("{0,$maxValue}" -f "value") -ForegroundColor Black -BackgroundColor White
    Write-Host ""

    # Print results
    foreach ($const in $constants) {
        Write-Host "  " -NoNewline
        Write-Host ("{0,-$maxName}" -f $const.Name) -ForegroundColor White -NoNewline
        Write-Host " " -NoNewline
        Write-Host ("{0,$maxValue}" -f $const.Value) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Found " -ForegroundColor Gray -NoNewline
    Write-Host "$($constants.Count)" -ForegroundColor White -NoNewline
    Write-Host " matching constant(s)" -ForegroundColor Gray
}

<# =========================================================================
   MEDIA UTILITIES
========================================================================= #>

function Plex-FixLibraryName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder,

        [Parameter(Mandatory = $true)]
        [string]$FileFormat
    )

    # Validate folder
    if (-not (Test-Path $Folder)) {
        Write-Error "Folder not found: $Folder"
        return
    }

    # Get all matching files
    $files = Get-ChildItem -Path $Folder -Filter "*$FileFormat" -File
    if (-not $files) {
        Write-Host "  No files found with extension " -ForegroundColor Gray -NoNewline
        Write-Host "'$FileFormat'" -ForegroundColor White -NoNewline
        Write-Host " in " -ForegroundColor Gray -NoNewline
        Write-Host "$Folder" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host " PLEX " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " Found " -ForegroundColor Gray -NoNewline
    Write-Host "$($files.Count)" -ForegroundColor White -NoNewline
    Write-Host " file(s)" -ForegroundColor Gray
    Write-Host ""

    # Prepare rename list
    $renameList = @()

    foreach ($file in $files) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $extension = $file.Extension

        # Step 1: Normalize "s##e##" → "##.##"
        # e.g., "S01E02" -> "01.02"
        $normalized = [regex]::Replace(
            $baseName,
            '(?i)s(\d+)\s*e(\d+)',
            { param($m) "$($m.Groups[1].Value).$($m.Groups[2].Value)" }
        )

        # Step 2: Extract sequences of alphanumeric characters
        $matches = [regex]::Matches($normalized, '[a-zA-Z0-9]+')

        if ($matches.Count -gt 0) {
            $segments = $matches | ForEach-Object { $_.Value }
            $newBaseName = ($segments -join '.')
            $newName = "$newBaseName$extension"
        } else {
            $newName = $file.Name
        }

        # Only consider renaming if different
        if ($newName -ne $file.Name) {
            $renameList += [PSCustomObject]@{
                Old = $file.Name
                New = $newName
                Path = $file.FullName
            }
        }
    }

    if (-not $renameList) {
        Write-Host "  All files already conform to the naming format." -ForegroundColor Gray
        return
    }

    Write-Host "  Renames to apply:" -ForegroundColor Gray
    $renameList | ForEach-Object {
        Write-Host "    $($_.Old)" -ForegroundColor DarkGray -NoNewline
        Write-Host " -> " -ForegroundColor Gray -NoNewline
        Write-Host "$($_.New)" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  Proceed" -ForegroundColor Gray -NoNewline
    $confirm = Read-Host "? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "  Renaming..." -ForegroundColor DarkGray
    foreach ($item in $renameList) {
        $oldPath = Join-Path $Folder $item.Old
        $newPath = Join-Path $Folder $item.New
        Rename-Item -Path $oldPath -NewName $item.New
        Write-Host "    $($item.New)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host " OK " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " All files renamed" -ForegroundColor Gray
}


<# =========================================================================
   HELP
========================================================================= #>

function gabi {
    Write-Host ""
    Write-Host " HELP " -ForegroundColor Black -BackgroundColor White -NoNewline
    Write-Host " PowerShell Profile Utilities" -ForegroundColor Gray
    Write-Host ""

    # Shell Utilities
    Write-Host "  SHELL" -ForegroundColor White
    Write-Host "    hist" -ForegroundColor White -NoNewline
    Write-Host " <pattern>" -ForegroundColor DarkGray -NoNewline
    Write-Host "  Search command history" -ForegroundColor Gray
    Write-Host ""

    # Git Helpers
    Write-Host "  GIT" -ForegroundColor White
    Write-Host "    New-GitBranchFromRemote" -ForegroundColor White -NoNewline
    Write-Host " -LocalBranch -RemoteName -BaseBranch [-Closest]" -ForegroundColor DarkGray
    Write-Host "      Create local branch from remote, with fuzzy matching" -ForegroundColor Gray
    Write-Host ""

    # Kubernetes Helpers
    Write-Host "  KUBERNETES" -ForegroundColor White
    Write-Host "    New-KubectlBusyBoxPod" -ForegroundColor White -NoNewline
    Write-Host " [-Name] [-Restart] [-Attach]" -ForegroundColor DarkGray
    Write-Host "      Spin up a busybox pod for debugging" -ForegroundColor Gray
    Write-Host ""

    # PE Analysis
    Write-Host "  PE ANALYSIS" -ForegroundColor White
    Write-Host "    Find-PEExports" -ForegroundColor White -NoNewline
    Write-Host " -PEName -Export [-wow]" -ForegroundColor DarkGray
    Write-Host "      Search DLL exports in System32/SysWOW64" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Find-PEString" -ForegroundColor White -NoNewline
    Write-Host " -Path -Pattern [-Recursive] [-FullPath]" -ForegroundColor DarkGray
    Write-Host "      Search strings in PE files (exe/dll)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Find-WinConstant [-NoSort] [-CaseSensitive]" -ForegroundColor White -NoNewline
    Write-Host " -Pattern" -ForegroundColor DarkGray
    Write-Host "      Search Windows SDK headers for constant definitions" -ForegroundColor Gray
    Write-Host ""

    # Media Utilities
    Write-Host "  MEDIA" -ForegroundColor White
    Write-Host "    Plex-FixLibraryName" -ForegroundColor White -NoNewline
    Write-Host " -Folder -FileFormat" -ForegroundColor DarkGray
    Write-Host "      Rename media files to Plex-friendly format" -ForegroundColor Gray
    Write-Host ""
}
