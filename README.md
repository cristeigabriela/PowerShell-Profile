My PowerShell profile as a Windows-centric programmer and reverse engineer. See more at my [scripts](https://github.com/cristeigabriel/powershell-scripts/blob/main/Parse-Windbg-Addresses-Breakpoint.ps1).

Some invocations are built using AI instructed to follow a very well defined sequence of actions. I love using PowerShell but not writing scripts in it.

<img width="967" height="767" alt="image" src="https://github.com/user-attachments/assets/d06930f4-4c4f-43e8-a9be-1c248e19a0b2" />


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

 PE  Searching for exports matching 'cre*file*mapp' in '*kern**'

  kernel32.dll
    ord hint      rva name

    226   DF 0001CFB0  CreateFileMappingA
    227   E0  forward  CreateFileMappingFromApp (forwarded to api-ms-win-core-memory-l1-1-1.CreateFileMappingFromApp)
    228   E1 0005F660  CreateFileMappingNumaA
    229   E2 00030490  CreateFileMappingNumaW
    230   E3 0001C7A0  CreateFileMappingW

  KernelBase.dll
    ord hint      rva name

    220   D2 00178E10  CreateFile2FromAppW
    223   D5 00178ED0  CreateFileFromAppW
    224   D6 00243720  CreateFileMapping2
    225   D7 00243870  CreateFileMappingFromApp
    226   D8 00145EA0  CreateFileMappingNumaW
    227   D9 00145E70  CreateFileMappingW

 OK  Found 11 matching export(s)
```

### Find-PEString
```
> Find-PEString C:\Windows\System32\kernel32.dll "* ERROR *"

 STR  Searching for strings matching '* ERROR *' in C:\Windows\System32\kernel32.dll

  kernel32.dll
          offset text

         0x918A8  WER/Recovery/%u:%u: ERROR Invalid params
         0x918D8  WER/CrashAPI/%u:%u: ERROR Invalid args
         0x91900  WER/CrashAPI/%u:%u: ERROR Unable to get the pPeb, WerpCurrentPeb failed
         0x91950  WER/Heap/%u:%u: ERROR Invalid args
```

### Find-WinConstant
```
> Find-WinConstant "PROC_TH*" -CaseSensitive

 SDK  Searching for constants matching 'PROC_TH*'

  name                                     value

  PROC_THREAD_ATTRIBUTE_REPLACE_VALUE 0x00000001
  PROC_THREAD_ATTRIBUTE_NUMBER        0x0000FFFF
  PROC_THREAD_ATTRIBUTE_THREAD        0x00010000
  PROC_THREAD_ATTRIBUTE_INPUT         0x00020000
  PROC_THREAD_ATTRIBUTE_ADDITIVE      0x00040000

 OK  Found 5 matching constant(s)
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
