function Import-PtClipboardNativeStub {
    $ErrorActionPreference='Stop'
    if('PtClipboard.ClipboardGuard' -as [type]){throw 'Offline clipboard tests require a fresh process.'}
    $source=[IO.File]::ReadAllText("$PSScriptRoot\..\..\pt-clipboard-guard.cs")
    $bodies=@{
        IsWindow='return PtClipboardNativeStub.OwnerAlive;'
        GetWindowThreadProcessId='processId = hwnd == new IntPtr(1) ? (uint)Process.GetCurrentProcess().Id : (uint)PtClipboardNativeStub.WriterPid; return 1;'
        OpenClipboard='return PtClipboardNativeStub.Open(owner);'
        CloseClipboard='return PtClipboardNativeStub.Close();'
        EnumClipboardFormats='return PtClipboardNativeStub.Next(format);'
        GetClipboardData='return PtClipboardNativeStub.Get(format);'
        SetClipboardData='return PtClipboardNativeStub.Set(format, data);'
        EmptyClipboard='return PtClipboardNativeStub.Empty();'
        GetClipboardSequenceNumber='return PtClipboardNativeStub.Sequence;'
        GetClipboardOwner='return new IntPtr(2);'
        GetOpenClipboardWindow='return IntPtr.Zero;'
        CopyImage='throw new NotSupportedException("Bitmap is outside this synthetic memory test.");'
        GlobalSize='return PtClipboardNativeStub.Size(memory);'
        GlobalLock='return memory;'
        GlobalUnlock='return true;'
        GlobalAlloc='return PtClipboardNativeStub.Allocate(size);'
        GlobalFree='return PtClipboardNativeStub.Free(memory);'
        DeleteObject='throw new NotSupportedException("Bitmap is outside this synthetic memory test.");'
        GetObject='bitmap = default(BitmapInfo); throw new NotSupportedException("Bitmap is outside this synthetic memory test.");'
        GetBitmapBits='throw new NotSupportedException("Bitmap is outside this synthetic memory test.");'
    }
    $seen=[Collections.Generic.HashSet[string]]::new()
    $source=[regex]::Replace($source,'\[DllImport\([^\r\n]+?\)\]\s*(public|private) static extern (\w+) (\w+)\(([^;\r\n]*)\);',{
        param($match)
        $name=$match.Groups[3].Value
        if(-not $bodies.ContainsKey($name) -or -not $seen.Add($name)){throw "Unmapped or duplicate native boundary: $name"}
        "$($match.Groups[1].Value) static $($match.Groups[2].Value) $name($($match.Groups[4].Value)) { $($bodies[$name]) }"
    })
    if($source.Contains('DllImport') -or $seen.Count -ne $bodies.Count){throw 'Offline native substitution is incomplete; refusing to run.'}
    $start='return process.StartTime.ToUniversalTime().Ticks;'
    if(-not $source.Contains($start)){throw 'Writer identity boundary changed.'}
    $source=$source.Replace($start,'return PtClipboardNativeStub.WriterTicks;')
    $stub=[regex]::Replace([IO.File]::ReadAllText("$PSScriptRoot\ClipboardNativeStub.cs"),'(?m)^using .*;\r?\n','')
    Add-Type -TypeDefinition ($source+"`n"+$stub)
    [PtClipboardNativeStub]::Reset()
}
