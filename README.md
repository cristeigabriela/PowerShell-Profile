My PowerShell profile as a Windows-centric programmer and reverse engineer. See more at my [scripts](https://github.com/cristeigabriel/powershell-scripts/blob/main/Parse-Windbg-Addresses-Breakpoint.ps1).

Some invocations are built using AI instructed to follow a very well defined sequence of actions. I love using PowerShell but not writing scripts in it.

# Commands
### hist
```
> hist nuget*pack
PS C:\Users\allse> hist nuget*pack
Finding in full history using {$_ -like "*nuget*pack*"}
<# ... #>
C:\dev\CENSORED\.nuget\nuget.exe pack .\CENSORED.Ipc.Native.nuspec -p version=1.1.0
```
### Find-PEExports 
```
> Find-PEExports -wow kern* cre*file*mapp
C:\Windows\SysWOW64\kernel32.dll:
        225   DE 0001CFB0 CreateFileMappingA
        226   DF          CreateFileMappingFromApp (forwarded to api-ms-win-core-memory-l1-1-1.CreateFileMappingFromApp)
        227   E0 0005E920 CreateFileMappingNumaA
        228   E1 0002F720 CreateFileMappingNumaW
        229   E2 0001C7A0 CreateFileMappingW
C:\Windows\SysWOW64\KernelBase.dll:
        219   D1 00174330 CreateFile2FromAppW
        222   D4 001743F0 CreateFileFromAppW
        223   D5 0023D810 CreateFileMapping2
        224   D6 0023D960 CreateFileMappingFromApp
        225   D7 00141CC0 CreateFileMappingNumaW
        226   D8 00141C90 CreateFileMappingW
```

### New-GitBranchFromRemote
```
> New-GitBranchFromRemote -LocalBranch git-example -RemoteName daniel -BaseBranch win-43 -Closest
Fetching from 'daniel'...
Fetch complete.
No exact match. Use closest branch 'win-43-subprocessing'? (Y/n): y

About to run:
  git checkout -b git-example daniel/win-43-subprocessing

Proceed? (Y/n): n
Cancelled.
```

### Plex-FixLibraryName
```
> Plex-FixLibraryName -Folder .\Full.Moon.Wo.Sagashite\ -FileFormat mkv

Found 52 file(s) in .\Full.Moon.Wo.Sagashite\:

The following renames will be applied:
  'Full Moon wo Sagashite - 01v2.mkv' -> 'Full.Moon.wo.Sagashite.01v2.mkv'
  'Full Moon wo Sagashite - 02v2.mkv' -> 'Full.Moon.wo.Sagashite.02v2.mkv'
  (...)

Proceed with renaming? (y/n): n
```

### New-KubectlBusyBoxPod
```
> New-KubectlBusyBoxPod -Name fun -Restart "Always" -Attach
Pod 'fun' exists, status: 'Running'
Delete pod 'fun' and recreate it? (y/n): y
Deleting existing pod 'fun'...
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
Pod 'fun' successfully deleted.
Creating BusyBox pod 'fun' with restart policy 'Always'...
Waiting for pod 'fun' to be ready...
Pod 'fun' is ready!
Attaching to /bin/sh inside 'fun'...
/ # mkdir app
/ # echo "hi github" > test.txt
/ # exit
````
