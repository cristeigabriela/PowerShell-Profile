# NOTE(gabriela): allow the execution of arbitrary scripts, etc!
Set-ExecutionPolicy Unrestricted -Scope CurrentUser


<# NOTE(gabriela):

Most of these scripts are written using AI, usually associated with a strong,
step-by-step plangiven to the AI agent. These functions are usually the
resulting output of the aforementioned prompt. I don't particularly enjoy 
writing PowerShell, but I often believe that it's the best choice to integrate
some of this functionality into my system, given the way I want to interact
with it.

Where possible, the prompt for the code is associated.

#>

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

    Write-Host "Finding in full history using {`$_ -like `"*$find*`"}"
    Get-Content (Get-PSReadlineOption).HistorySavePath |
        Where-Object {
            $_ -like "*$find*" -and
            ($histCommandNames -notcontains ($_ -split '\s+')[0])
        } |
        Get-Unique |
        more
}

<# ------------------------------------------------------------------------- #>

<#
Write a powershell script that very specifically:

	1.  Takes an argument, PEName
	2.  Takes an argument, export
	3.  Takes an argument, optional, wow (/wow)
	4.  Looks through directory C:\Windows, C:\Windows\System32 (in this case, if /wow, then C:\Windows\SysWOW64) -- remember these as SearchPath variables
	5.  Uses Select-Object -like * for wildcard pattern matching, over all *files* in folder, to see if they match the patter in in "PEName"
	6.  Saves all files
	7.  Goes through all files using dumpbin /EXPORTS (here a string using both searchpaths + files found) then the PE name
	8.  Store the result of that and check $? for True. if False, then don't record
	9.  Get the command's output, then using select-object filter for -like * for the exports string to use wildcard pattern matching
	10. Store in result string for file like "(full path): (newline) (results per line)"
	11. Print all of these
#>
function Find-PEExports {
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

    $Results = @()

    foreach ($Path in $SearchPaths) {
        # Get matching files based on PEName pattern (only top-level files)
        $Files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$PEName*" }

        foreach ($File in $Files) {
            # Run dumpbin /EXPORTS on the file
            $Output = & dumpbin /EXPORTS "`"$($File.FullName)`"" 2>&1

            # Only continue if dumpbin succeeded
            if ($?) {
                # Filter for lines that match the Export pattern
                $FilteredLines = $Output | Where-Object { $_ -like "*$Export*" }

                if ($FilteredLines.Count -gt 0) {
                    # Format the result
                    $Result = "$($File.FullName):`n$($FilteredLines -join "`n")"
                    $Results += $Result
                }
            }
        }
    }

    # Output all results
    $Results | ForEach-Object { Write-Output $_ }
}

<# -------------------------------------------------------------------------

<#
Write a powershell command for creating a new git branch off of a remote branch:

	1. The powershell command takes in the new local branch name, the remote name, and the base branch name.
	   Plus, a flag, in which the program will instead make the new branch from a remote branch with the closest name, this will be explained later.
	2. It runs git remote --v and parses each line split by whitespace for, in order: name, url, perms
	3. It checks if there's an entry where name is the command line remote name, and perms is (fetch)
	4. If there is, run `git fetch <remote name>`
	5. Do `git remote show <remote name>` and search if there is any entry that fits the command line argument base branch name. you're gonna look for the string "Remote branches:", which may already be indented at the start, and you're gonna read the lines below, which are gonna be indented once more, until the indentation level breaks. 
		5.1 if not, print closest entry (eg. if it starts with the same string)
	6. If the entry is present, finally, take the command line local new branch name, the verified remote name, and the verified remote branch name (or, if the command line flag for closest is set, use the closest fitting remote branch name. but prompt the user for a Y/n response after identifying the closest branch) and run `git checkout -b <local_branch_name> <remote_name>/<remote_branch_name>

Make sure to be very careful about errors, make sure it doesn't execute any extra git commands, and doesn't do any changing action without prior user confirmation
#>
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
        Write-Host "Available remotes:"
        $remoteEntries | ForEach-Object { Write-Host " - $($_.Name) ($($_.Perm)) -> $($_.Url)" }
        return
    }

    # Fetch remote (safe)
    Write-Host "Fetching from '$RemoteName'..."
    $fetchOut = git fetch $RemoteName 2>&1
    Throw-IfGitFailed $fetchOut $LASTEXITCODE
    Write-Host "Fetch complete."

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
        $name = ($line.Trim() -replace '^\*+\s*','' -split '\s+')[0]
        if ($name) { $branches += $name }
    }

    if (-not $branches) {
        Write-Error "No remote branches found for '$RemoteName'."
        return
    }

    $chosen = $branches | Where-Object { $_ -ieq $BaseBranch }
    if ($chosen) {
        $chosen = $chosen[0]
        Write-Host "Found exact branch: $chosen"
    }
    else {
        $candidates = $branches | Where-Object { $_ -like "$BaseBranch*" }
        if (-not $candidates) {
            $candidates = $branches | Where-Object { $_ -match [Regex]::Escape($BaseBranch) }
        }

        if (-not $candidates) {
            Write-Host "No remote branch found matching '$BaseBranch'."
            Write-Host "Available branches on '$RemoteName':"
            $branches | ForEach-Object { Write-Host " - $_" }
            return
        }

        $preferred = $candidates | Sort-Object { $_.Length } | Select-Object -First 1
        if (-not $Closest) {
            Write-Host "No exact branch '$BaseBranch' found. Closest matches:"
            $candidates | ForEach-Object { Write-Host " - $_" }
            Write-Host "Re-run with -Closest to choose automatically."
            return
        }

        $answer = Read-Host "No exact match. Use closest branch '$preferred'? (Y/n)"
        if ($answer -match '^[Nn]') { Write-Host "Aborted."; return }
        $chosen = $preferred
    }

    # Confirm before checkout
    $cmd = "git checkout -b $LocalBranch $RemoteName/$chosen"
    Write-Host "`nAbout to run:`n  $cmd`n"
    $confirm = Read-Host "Proceed? (Y/n)"
    if ($confirm -match '^[Nn]') {
        Write-Host "Cancelled."
        return
    }

    Write-Host "Running checkout..."
    $coOut = & git checkout -b $LocalBranch "$RemoteName/$chosen" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Checkout failed:`n$coOut"
        return
    }

    Write-Host $coOut
    Write-Host "✅ Created local branch '$LocalBranch' from '$RemoteName/$chosen'."
}

<# ------------------------------------------------------------------------- #>

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
        Write-Host "Folder not found: $Folder" -ForegroundColor Red
        return
    }

    # Get all matching files
    $files = Get-ChildItem -Path $Folder -Filter "*$FileFormat" -File
    if (-not $files) {
        Write-Host "No files found with extension '$FileFormat' in '${Folder}'." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Found $($files.Count) file(s) in ${Folder}:" -ForegroundColor Cyan
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
        Write-Host "All files already conform to the naming format." -ForegroundColor Green
        return
    }

    Write-Host "The following renames will be applied:" -ForegroundColor Cyan
    $renameList | ForEach-Object {
        Write-Host "  '$($_.Old)' -> '$($_.New)'" -ForegroundColor Yellow
    }

    Write-Host ""
    $confirm = Read-Host "Proceed with renaming? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Operation cancelled by user." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Renaming files..." -ForegroundColor Cyan
    foreach ($item in $renameList) {
        $oldPath = Join-Path $Folder $item.Old
        $newPath = Join-Path $Folder $item.New
        Rename-Item -Path $oldPath -NewName $item.New
        Write-Host "  Renamed: '$($item.Old)' -> '$($item.New)'" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "All files renamed successfully." -ForegroundColor Green
}

<# ------------------------------------------------------------------------- #>

<#
PROMPT 1:

I want to make a basic powershell command to add to my powershell profile, contained in a single function,
to make a kube pod using the kubectl command with the pod name fun and based on the image busybox 

- I want it to take at least an argument to the function script for the pod name

The command instanciation should run like this:
`kubectl run fun --image=busybox --restart=Never -- sleep infinity`

the `-- sleep infinity` is an absolute necessity to run it forever.

- Make restart be a toggle as an argument so I dont have to keep deleting it every time I restart the cluster.

- After you write the script, come up with some extra suggestions

- Make sure to run some sanity checks to make sure theres a running cluster

Name the script `New-KubectlBusyBoxPod`

--

PROMPT 2 -- continuation:

- Implement an option to auto-attach into /bin/sh to the newly created pod.

- Implement the following functionality: run `kubectl get pod $Name` first to check if the pod exists

If it does, it would look like this:

```
NAME   READY   STATUS    RESTARTS   AGE
fun    1/1     Running   0          5m39s
```

Parse the second line of stdout from the command result, and split by whitespace, and get the first and third
entry from the list (the pod name, and the pod status, and if it exists, break early and say (more formally):

```
pod of $name exists, status: {pod-status}
```

--

1. Change $Restart default to "Always"
2. Quote into single quote the current status if a pod with the name already exists
3. Change the message if the pod with the name already exists to have a red foreground, as it's a bad thing
4. If the pod already exists, implement a y/n prompt for the action of deleting it and proceeding with creation.
   Make sure to delete with `--force` and check if the operation succeeded
#>

function New-KubectlBusyBoxPod {
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
                Write-Host "Pod '$podName' exists, status: '$podStatus'" -ForegroundColor Red

                # Prompt user to delete existing pod
                $response = Read-Host "Delete pod '$podName' and recreate it? (y/n)"
                if ($response -match '^(y|Y)$') {
                    Write-Host "Deleting existing pod '$podName'..." -ForegroundColor Yellow
                    kubectl delete pod $podName --force --grace-period=0 | Out-Null

                    # Confirm deletion
                    Start-Sleep -Seconds 1
                    kubectl get pod $podName 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Error "Failed to delete existing pod '$podName'. Aborting."
                        return
                    } else {
                        Write-Host "Pod '$podName' successfully deleted." -ForegroundColor Green
                    }
                } else {
                    Write-Host "Aborted by user." -ForegroundColor Yellow
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

    Write-Host "Creating BusyBox pod '$Name' with restart policy '$Restart'..." -ForegroundColor Cyan
    $runResult = kubectl @cmd

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Pod creation failed:"
        Write-Host $runResult
        return
    }

    # --- Wait for pod to become ready ---
    Write-Host "Waiting for pod '$Name' to be ready..." -ForegroundColor Yellow
    kubectl wait --for=condition=Ready pod/$Name --timeout=30s | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Pod '$Name' did not become ready in time."
        return
    }

    Write-Host "Pod '$Name' is ready!" -ForegroundColor Green

    # --- Optional attach ---
    if ($Attach) {
        Write-Host "Attaching to /bin/sh inside '$Name'..." -ForegroundColor Cyan
        kubectl exec -it $Name -- /bin/sh
    }
}


<# ------------------------------------------------------------------------- #>
