# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('Any', 'Installed', 'RemovedKeepData')][string]$ExpectedState = 'Any',
    [string]$ExpectedVersion,
    [string]$PeerOwnerSid,
    [switch]$RequireProfileRemoved
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 (pwsh), not an elevated terminal.' }
if (![Environment]::Is64BitProcess) { throw 'Use a 64-bit PowerShell 7 process.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$owner = $identity.User.Value
function Assert-OwnerSid([string]$Sid) {
    if ($Sid -notmatch '^S-1-(?:5-21|12-1)-\d+-\d+-\d+-\d+$' -or
        [Security.Principal.SecurityIdentifier]::new($Sid).Value -cne $Sid) { throw "Unsupported owner SID: $Sid" }
}
Assert-OwnerSid $owner
if (([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in the account being tested, without Run as administrator.'
}
if ($PeerOwnerSid) {
    Assert-OwnerSid $PeerOwnerSid
    if ($PeerOwnerSid -eq $owner) { throw 'PeerOwnerSid must identify the other test account.' }
}
if ($RequireProfileRemoved -and $ExpectedState -ne 'RemovedKeepData') {
    throw 'RequireProfileRemoved is only meaningful with ExpectedState RemovedKeepData.'
}
$output = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $output) { throw 'Use a new output filename; snapshots are never overwritten.' }

if (!('PowerToysIsolation.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace PowerToysIsolation {
 public static class Native {
  [StructLayout(LayoutKind.Sequential)] struct Status {public uint type,state,accepted,win32,specific,checkpoint,hint,pid,flags;}
  [StructLayout(LayoutKind.Sequential)] struct Config {public uint type,start,error;public IntPtr image,group;public uint tag;public IntPtr dependencies,account,display;}
  [StructLayout(LayoutKind.Sequential)] struct FT {public uint low,high;public ulong Value {get{return ((ulong)high<<32)|low;}}}
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string machine,string database,uint access);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,uint access);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool QueryServiceStatusEx(IntPtr service,int level,out Status state,int size,out int needed);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryServiceConfig(IntPtr service,IntPtr config,uint size,out uint needed);
  [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr handle);
  [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegOpenKeyEx(IntPtr root,string name,uint options,uint access,out IntPtr key);
  [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr key);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFileAttributes(string path);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string path,uint access,uint sharing,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder name,ref uint length);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr process,out FT born,out FT exited,out FT kernel,out FT user);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool ProcessIdToSessionId(uint pid,out uint session);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint delay);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr buffer,uint length,out uint needed);
  [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiEnumProductsEx(string product,string owner,uint context,uint index,StringBuilder code,out uint installedContext,StringBuilder installedSid,ref uint sidLength);
  [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiGetProductInfoEx(string code,string owner,uint context,string property,StringBuilder value,ref uint length);
  static void Check(bool ok){if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error());}
  public static int Path(string path){return GetFileAttributes(path)==uint.MaxValue?Marshal.GetLastWin32Error():0;}
  public static int Key(bool users,string path){IntPtr key;int error=RegOpenKeyEx(new IntPtr(unchecked((int)(users?0x80000003:0x80000002))),path,0,0x20019|0x100,out key);if(error==0)RegCloseKey(key);return error;}
  public static int Access(string path,uint access){
   IntPtr h=CreateFile(path,access,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
   if(h==new IntPtr(-1))return Marshal.GetLastWin32Error();CloseHandle(h);return 0;
  }
  public sealed class ServiceInfo {public int NativeCode;public uint State,StartType,Pid;public string Name,Account,Image;}
  public static ServiceInfo Service(string name){
   var r=new ServiceInfo{Name=name};IntPtr manager=OpenSCManager(null,null,1);Check(manager!=IntPtr.Zero);
   try{IntPtr s=OpenService(manager,name,5);if(s==IntPtr.Zero){r.NativeCode=Marshal.GetLastWin32Error();return r;}
    try{Status status;int needed;Check(QueryServiceStatusEx(s,0,out status,Marshal.SizeOf(typeof(Status)),out needed));r.State=status.state;r.Pid=status.pid;
     uint size;QueryServiceConfig(s,IntPtr.Zero,0,out size);IntPtr memory=Marshal.AllocHGlobal((int)size);
     try{Check(QueryServiceConfig(s,memory,size,out size));var c=Marshal.PtrToStructure<Config>(memory);r.StartType=c.start;r.Account=Marshal.PtrToStringUni(c.account);r.Image=Marshal.PtrToStringUni(c.image);}
     finally{Marshal.FreeHGlobal(memory);}
    }finally{CloseServiceHandle(s);}
   }finally{CloseServiceHandle(manager);}return r;
  }
  public sealed class ProcessInfo {public uint Pid,Session;public string Image,Birth,Sid;public bool Alive;public int NativeCode;}
  public static ProcessInfo Process(uint pid){
   var r=new ProcessInfo{Pid=pid};IntPtr p=OpenProcess(0x1000|0x100000,false,pid);
   if(p==IntPtr.Zero){r.NativeCode=Marshal.GetLastWin32Error();return r;}
   try{var text=new StringBuilder(32768);uint size=32768;Check(QueryFullProcessImageName(p,0,text,ref size));r.Image=text.ToString();
    FT birth,exited,kernel,user;Check(GetProcessTimes(p,out birth,out exited,out kernel,out user));r.Birth=birth.Value.ToString();r.Alive=WaitForSingleObject(p,0)==258;Check(ProcessIdToSessionId(pid,out r.Session));
    IntPtr token;Check(OpenProcessToken(p,8,out token));try{uint needed;GetTokenInformation(token,1,IntPtr.Zero,0,out needed);IntPtr buffer=Marshal.AllocHGlobal((int)needed);
     try{Check(GetTokenInformation(token,1,buffer,needed,out needed));r.Sid=new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value;}finally{Marshal.FreeHGlobal(buffer);}
    }finally{CloseHandle(token);}
   }catch(Win32Exception e){r.NativeCode=e.NativeErrorCode;}finally{CloseHandle(p);}return r;
  }
  public sealed class Product {public string Code,Owner,Name,Version,State;public uint Context;}
  static string Property(string code,string owner,string property){uint size=32768;var text=new StringBuilder(32768);uint error=MsiGetProductInfoEx(code,owner,2,property,text,ref size);return error==0?text.ToString():"native:"+error;}
  public static Product[] Products(string owner){
   var result=new List<Product>();for(uint i=0;;i++){var code=new StringBuilder(39);var sid=new StringBuilder(256);uint length=256,context;
    uint error=MsiEnumProductsEx(null,owner,2,i,code,out context,sid,ref length);if(error==259)break;if(error!=0)throw new Win32Exception((int)error);
    var name=Property(code.ToString(),owner,"InstalledProductName");if(name.StartsWith("native:"))name=Property(code.ToString(),owner,"ProductName");
    if(name.StartsWith("native:"))throw new Win32Exception(int.Parse(name.Substring(7)),"MSI product name is unverified");
    if(name!="PowerToys Protected Storage"&&name!="PowerToys (Preview)")continue;
    result.Add(new Product{Code=code.ToString(),Owner=sid.ToString(),Context=context,Name=name,Version=Property(code.ToString(),owner,"VersionString"),State=Property(code.ToString(),owner,"State")});
   }return result.ToArray();
  }
 }
}
'@
}
function Read-SharedBytes([string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if ($stream.Length -gt 64MB) { throw 'Snapshot input exceeds the 64 MiB diagnostic bound.' }
        $memory = [IO.MemoryStream]::new()
        try { $stream.CopyTo($memory); return ,$memory.ToArray() } finally { $memory.Dispose() }
    } finally { $stream.Dispose() }
}
function Hash-Bytes([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function Access-Probes([string]$Path) {
    # OPEN_EXISTING only: request rights then immediately close. Never write,
    # change ACLs or set FILE_DISPOSITION/DELETE_ON_CLOSE.
    [ordered]@{
        Read=[PowerToysIsolation.Native]::Access($Path,0x80000000u)
        Write=[PowerToysIsolation.Native]::Access($Path,0x40000000u)
        Delete=[PowerToysIsolation.Native]::Access($Path,0x10000)
        ChangeAcl=[PowerToysIsolation.Native]::Access($Path,0x40000)
    }
}
$problems = [Collections.Generic.List[string]]::new()
$machine = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$serviceName = "PowerToysProtectedStorage_$owner"
$sidText = (& "$env:SystemRoot\System32\sc.exe" showsid $serviceName | Out-String)
if ($LASTEXITCODE) { throw 'Unable to derive the service SID using sc showsid.' }
$va = [regex]::Match($sidText,'S-1-5-80-\d+-\d+-\d+-\d+-\d+').Value
if (!$va) { throw 'Service SID missing from sc showsid output.' }
$state = Join-Path $env:ProgramData 'PowerToysProtectedStorage'
$dataPath = Join-Path $state "Data\$owner"
$record = Join-Path $state "Installer\$owner"
$codePath = Join-Path $env:ProgramFiles "PowerToysProtectedStorage\Owners\$owner\Code"
$service = [PowerToysIsolation.Native]::Service($serviceName)
$products = @([PowerToysIsolation.Native]::Products($owner))
$carrier = @($products | Where-Object Name -eq 'PowerToys Protected Storage')
$main = @($products | Where-Object Name -eq 'PowerToys (Preview)')
$data = [ordered]@{ReadNative=[PowerToysIsolation.Native]::Access("$dataPath\storage.index",0x80000000u);Stable=$false}
if ($data.ReadNative -eq 0) {
    try {
        for ($attempt=0; $attempt -lt 3; $attempt++) {
            $bytes = Read-SharedBytes "$dataPath\storage.index"
            $index = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            $repository = $index.targets.'workspaces.repository'
            $blob = $null
            $blobName = $null
            if ($repository.generation) {
                $generation = [guid]::ParseExact($repository.generation,'D')
                $blobName = 'blob.' + $generation.ToString('D')
                $blob = Read-SharedBytes (Join-Path $dataPath $blobName)
            }
            $hash = Hash-Bytes $bytes
            if ($hash -eq (Hash-Bytes (Read-SharedBytes "$dataPath\storage.index"))) {
                $data.Stable = $true
                $data.IndexHash = $hash
                $data.BlobHash = if ($null -ne $blob) { Hash-Bytes $blob } else { $null }
                $data.Blob = $blobName
                $data.Epoch = $index.epoch
                $data.InitializationId = $repository.initializationOperationId
                $data.Sequence = [string]$repository.sequence
                break
            }
        }
        if (!$data.Stable) { $problems.Add('Data changed during all snapshot attempts; stop writes and capture again.') }
    } catch { $problems.Add("Cannot capture data: $($_.Exception.Message)") }
} elseif ($data.ReadNative -notin @(2,3)) { $problems.Add("Data access is unverified (native $($data.ReadNative)).") }
$ready = @{}
$bootstrap = $runtime = $null
if ($service.NativeCode -eq 0 -and $service.State -eq 4) {
    try {
        foreach ($line in ([Text.Encoding]::UTF8.GetString((Read-SharedBytes "$dataPath\ready.txt")) -split "`n")) {
            if ($line.Contains('=')) { $key,$value = $line.Trim().Split('=',2); $ready[$key]=$value }
        }
        $bootstrap = [PowerToysIsolation.Native]::Process([uint32]$ready.host_pid)
        $runtime = [PowerToysIsolation.Native]::Process([uint32]$ready.worker_pid)
    } catch { $problems.Add("Cannot verify running identities: $($_.Exception.Message)") }
}
$selfAccess = Access-Probes "$dataPath\storage.index"
$peer = $null
if ($PeerOwnerSid) {
    $peer = [ordered]@{OwnerSid=$PeerOwnerSid;Access=(Access-Probes (Join-Path $state "Data\$PeerOwnerSid\storage.index"))}
    foreach ($right in @('Read','Write','Delete','ChangeAcl')) {
        if ($peer.Access[$right] -ne 5) { $problems.Add("Peer $right must return access-denied 5; got $($peer.Access[$right]). A missing peer is not an isolation pass.") }
    }
}
$profileKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$va"
$profileKeyNative = [PowerToysIsolation.Native]::Key($false,$profileKey)
$profilePath = "$env:SystemRoot\ServiceProfiles\$serviceName"
if ($profileKeyNative -eq 0) {
    $profilePath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath "HKLM:\$profileKey").ProfileImagePath)
}
$profile = [ordered]@{
    Path=$profilePath
    DirectoryNative=[PowerToysIsolation.Native]::Path($profilePath)
    RegistryNative=$profileKeyNative
    HiveNative=[PowerToysIsolation.Native]::Key($true,$va)
    ClassesHiveNative=[PowerToysIsolation.Native]::Key($true,"${va}_Classes")
}
$markers = [ordered]@{}
foreach ($leaf in @('active','retained','purged','pending-install','pending-remove','cleanup-pending','profile-cleanup-id','artifact-cleanup-pending')) {
    $markers[$leaf] = [PowerToysIsolation.Native]::Path((Join-Path $record $leaf))
}
$codeNative = [PowerToysIsolation.Native]::Path($codePath)
$mainRoot = Join-Path $env:LOCALAPPDATA 'PowerToys'
$mainNative = [PowerToysIsolation.Native]::Path($mainRoot)
$mainFile = Join-Path $mainRoot 'PowerToys.exe'
$mainExecutable = [ordered]@{Native=[PowerToysIsolation.Native]::Path($mainFile)}
if ($mainExecutable.Native -eq 0) {
    try {
        $mainExecutable.Hash = Hash-Bytes (Read-SharedBytes $mainFile)
        $mainExecutable.Version = [Diagnostics.FileVersionInfo]::GetVersionInfo($mainFile).FileVersion
    } catch { $problems.Add("Cannot inspect main executable: $($_.Exception.Message)") }
}
$installed = $service.NativeCode -eq 0 -and $service.State -eq 4 -and $service.StartType -eq 2 -and
    $service.Account -ieq "NT SERVICE\$serviceName" -and $carrier.Count -eq 1 -and $main.Count -eq 1 -and
    $carrier[0].State -eq '5' -and $carrier[0].Owner -eq $owner -and $carrier[0].Context -eq 2 -and
    $main[0].State -eq '5' -and $main[0].Owner -eq $owner -and $main[0].Context -eq 2 -and
    $mainNative -eq 0 -and $mainExecutable.Native -eq 0 -and $mainExecutable.Hash -and
    $service.Image -ieq ('"{0}\Bootstrap.exe" --service "{1}"' -f $codePath,$owner) -and
    $markers.active -eq 0 -and $data.Stable -and $bootstrap -and $runtime -and
    $bootstrap.NativeCode -eq 0 -and $runtime.NativeCode -eq 0 -and $bootstrap.Alive -and $runtime.Alive -and
    $bootstrap.Sid -eq $va -and $runtime.Sid -eq $va -and $bootstrap.Session -eq 0 -and $runtime.Session -eq 0 -and
    $bootstrap.Pid -eq $service.Pid -and $bootstrap.Birth -eq $ready.host_birth -and $runtime.Birth -eq $ready.worker_birth -and
    $bootstrap.Image -ieq "$codePath\Bootstrap.exe" -and $runtime.Image -ieq "$codePath\Runtime.exe" -and
    $ready.data_recovery_required -eq '0'
$removed = $service.NativeCode -eq 1060 -and $carrier.Count -eq 0 -and $main.Count -eq 0 -and
    $codeNative -in @(2,3) -and $mainNative -in @(2,3) -and $markers.retained -eq 0 -and
    $markers.active -in @(2,3) -and $data.Stable
$profileRemoved = @('DirectoryNative','RegistryNative','HiveNative','ClassesHiveNative' | Where-Object {$profile[$_] -notin @(2,3)}).Count -eq 0
if ($ExpectedState -eq 'Installed' -and !$installed) { $problems.Add('Installed instance checks failed; inspect service, registrations, ready and exact process identities.') }
if ($ExpectedState -eq 'RemovedKeepData' -and !$removed) { $problems.Add('Confirmed service/main/carrier/Code removal with retained readable data was not established.') }
if ($RequireProfileRemoved -and (!$profileRemoved -or $markers.'cleanup-pending' -notin @(2,3) -or $markers.'profile-cleanup-id' -notin @(2,3))) {
    $problems.Add('Profile removal or profile-pending cleanup is incomplete/unverified.')
}
if ($ExpectedVersion) {
    $version = [version]$ExpectedVersion
    $msiVersion = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Build
    if (!$installed -or $ready.version -ne $ExpectedVersion -or $carrier[0].Version -ne $msiVersion -or
        $main[0].Version -ne $ExpectedVersion -or $mainExecutable.Version -ne $ExpectedVersion) {
        $problems.Add("Expected the installed release $ExpectedVersion.")
    }
}
if ($data.Stable) {
    foreach ($right in @('Write','Delete','ChangeAcl')) {
        if ($selfAccess[$right] -ne 5) { $problems.Add("Owner $right unexpectedly returned $($selfAccess[$right]); only read access is expected.") }
    }
}
$snapshot = [ordered]@{
    Schema=1; CapturedUtc=[datetime]::UtcNow.ToString('o')
    Machine=(Hash-Bytes ([Text.Encoding]::UTF8.GetBytes("$machine|$env:COMPUTERNAME")))
    OwnerSid=$owner; OwnerName=$identity.Name; VaSid=$va
    Service=$service; Carrier=$carrier; Main=$main; Bootstrap=$bootstrap; Runtime=$runtime
    MainExecutable=$mainExecutable
    Data=$data; OwnerAccess=$selfAccess; Peer=$peer; Profile=$profile; Markers=$markers
    CodeNative=$codeNative; MainRootNative=$mainNative
    Checks=[ordered]@{Installed=[bool]$installed;RemovedKeepData=[bool]$removed;ProfileRemoved=$profileRemoved}
    Errors=@($problems)
}
$parent = [IO.Path]::GetDirectoryName($output)
[IO.Directory]::CreateDirectory($parent) | Out-Null
$stream = [IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try {
    $encoded = [Text.Encoding]::UTF8.GetBytes(($snapshot | ConvertTo-Json -Depth 10))
    $stream.Write($encoded,0,$encoded.Length)
} finally { $stream.Dispose() }
Write-Output "Snapshot: $output"
Write-Output "Owner SID: $owner"
Write-Output "Installed=$installed RemovedKeepData=$removed ProfileRemoved=$profileRemoved"
if ($problems.Count) { throw ($problems -join "`n") }
