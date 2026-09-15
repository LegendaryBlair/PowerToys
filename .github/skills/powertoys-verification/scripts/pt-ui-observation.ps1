#requires -Version 7.0
<#
.SYNOPSIS
Read typed UIA observations without default-value, placeholder or accessible-name fallback.
.NOTES
No activation, focus, scrolling, retries, input or property writes. Observed is not PASS.
Native UIA calls are synchronous; operation recording cannot forcibly interrupt a hung provider.
#>
foreach($dependency in 'pt-uia','pt-state-snapshot','pt-verification-report'){. "$PSScriptRoot\$dependency.ps1"}

function Initialize-PtNativeUiProperty {
    if('PtNativeUiProperty' -as [type]){return}
    # UIAutomationClient.h prefix declarations preserve native vtable order. LiveSetting is
    # absent from the managed identifier registry, so read it through public native UIA.
    Add-Type -TypeDefinition @'
using System;
using System.Linq;
using System.Runtime.InteropServices;
public static class PtNativeUiProperty {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
    [ComImport,Guid("352FFBA8-0973-437C-A61F-F64CAFD81DF9"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface Condition {}
    [ComImport,Guid("D22108AA-8AC5-49A5-837B-37BBB3D7591E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface Element {
        [PreserveSig] int SetFocus();
        [PreserveSig] int GetRuntimeId([MarshalAs(UnmanagedType.SafeArray,SafeArraySubType=VarEnum.VT_I4)] out int[] id);
        [PreserveSig] int FindFirst(int scope,Condition condition,out Element found);
        [PreserveSig] int FindAll(int scope,Condition condition,out IntPtr found);
        [PreserveSig] int FindFirstBuildCache(int scope,Condition condition,IntPtr cache,out Element found);
        [PreserveSig] int FindAllBuildCache(int scope,Condition condition,IntPtr cache,out IntPtr found);
        [PreserveSig] int BuildUpdatedCache(IntPtr cache,out Element updated);
        [PreserveSig] int GetCurrentPropertyValue(int property,[MarshalAs(UnmanagedType.Struct)] out object value);
        [PreserveSig] int GetCurrentPropertyValueEx(int property,[MarshalAs(UnmanagedType.Bool)] bool ignoreDefault,[MarshalAs(UnmanagedType.Struct)] out object value);
    }
    [ComImport,Guid("30CBE57D-D9D0-452A-AB13-7AC5AC4825EE"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface Automation {
        [PreserveSig] int CompareElements(Element a,Element b,out int same);
        [PreserveSig] int CompareRuntimeIds(IntPtr a,IntPtr b,out int same);
        [PreserveSig] int GetRootElement(out Element root);
        [PreserveSig] int ElementFromHandle(IntPtr hwnd,out Element element);
        [PreserveSig] int ElementFromPoint(Point point,out Element element);
        [PreserveSig] int GetFocusedElement(out Element element);
        [PreserveSig] int GetRootElementBuildCache(IntPtr cache,out Element element);
        [PreserveSig] int ElementFromHandleBuildCache(IntPtr hwnd,IntPtr cache,out Element element);
        [PreserveSig] int ElementFromPointBuildCache(Point point,IntPtr cache,out Element element);
        [PreserveSig] int GetFocusedElementBuildCache(IntPtr cache,out Element element);
        [PreserveSig] int CreateTreeWalker(Condition condition,out IntPtr walker);
        [PreserveSig] int get_ControlViewWalker(out IntPtr walker);
        [PreserveSig] int get_ContentViewWalker(out IntPtr walker);
        [PreserveSig] int get_RawViewWalker(out IntPtr walker);
        [PreserveSig] int get_RawViewCondition(out Condition condition);
        [PreserveSig] int get_ControlViewCondition(out Condition condition);
        [PreserveSig] int get_ContentViewCondition(out Condition condition);
        [PreserveSig] int CreateCacheRequest(out IntPtr cache);
        [PreserveSig] int CreateTrueCondition(out Condition condition);
        [PreserveSig] int CreateFalseCondition(out Condition condition);
        [PreserveSig] int CreatePropertyCondition(int property,[MarshalAs(UnmanagedType.Struct)] object value,out Condition condition);
    }
    [DllImport("UIAutomationCore.dll")]
    static extern int UiaGetReservedNotSupportedValue([MarshalAs(UnmanagedType.IUnknown)] out object value);
    public class Result { public bool Supported; public object Value; }
    static void Check(int hr) { Marshal.ThrowExceptionForHR(hr); }
    static void Release(object value) { if(value!=null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
    static bool SameIdentity(object a,object b) {
        IntPtr x=IntPtr.Zero,y=IntPtr.Zero;
        try { x=Marshal.GetIUnknownForObject(a); y=Marshal.GetIUnknownForObject(b); return x==y; }
        finally { if(x!=IntPtr.Zero) Marshal.Release(x); if(y!=IntPtr.Zero) Marshal.Release(y); }
    }
    public static Result Read(long hwnd,int[] runtimeId,int property) {
        Automation automation=null; Element root=null,element=null; Condition condition=null;
        object value=null,reserved=null;
        try {
            automation=(Automation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("FF48DBA4-60EF-4201-AA87-54103EEF594E"),true));
            Check(automation.ElementFromHandle(new IntPtr(hwnd),out root));
            Check(automation.CreatePropertyCondition(30000,runtimeId,out condition));
            Check(root.FindFirst(7,condition,out element));
            if(element==null) throw new COMException("Resolved UIA runtime identity disappeared.",unchecked((int)0x80040201));
            Check(element.GetCurrentPropertyValueEx(property,true,out value));
            Check(element.GetRuntimeId(out var after));
            if(!runtimeId.SequenceEqual(after)) throw new COMException("UIA runtime identity changed.",unchecked((int)0x80040201));
            Check(UiaGetReservedNotSupportedValue(out reserved));
            bool unsupported=value!=null && Marshal.IsComObject(value) && SameIdentity(value,reserved);
            if(value!=null && Marshal.IsComObject(value) && !unsupported)
                throw new InvalidOperationException("Unexpected COM-valued property; not a scalar observation.");
            return new Result { Supported=!unsupported,Value=unsupported?null:value };
        } finally { Release(reserved); Release(value); Release(element); Release(condition); Release(root); Release(automation); }
    }
}
'@ -ErrorAction Stop
}

function Throw-PtUiObservationFailure {
    [CmdletBinding()]
    param([ValidateSet('Missing','Ambiguous','Unsupported','Stale','ReadError')][string]$Status,
        [string]$Message,$Target,$Selector,[string]$Property,[Exception]$Cause)
    $exception=[InvalidOperationException]::new("UI observation ${Status}: $Message",$Cause)
    $exception.Data['UiObservation']=[pscustomobject]@{
        Status=$Status;Property=$Property;Target=$Target;Selector=$Selector;Reason=$Message
        Classification='BLK-INFRASTRUCTURE'
    }
    $record=[Management.Automation.ErrorRecord]::new($exception,"PtUiObservation.$Status",[Management.Automation.ErrorCategory]::InvalidResult,$Selector)
    $PSCmdlet.ThrowTerminatingError($record)
}

function Assert-PtUiObservationTarget {
    param($Target)
    if(-not $Target -or $Target.hwnd -le 0 -or $Target.processId -le 0 -or $Target.processStartTicks -le 0 -or
        [string]::IsNullOrWhiteSpace($Target.className)){
        throw 'Target must be a complete Get-PtWindowIdentity result, not a bare HWND.'
    }
    $current=Get-PtWindowIdentity -Hwnd $Target.hwnd
    if($current.processId -ne $Target.processId -or $current.processStartTicks -ne $Target.processStartTicks -or $current.className -cne $Target.className){
        Throw-PtUiObservationFailure Stale 'The target window/process identity changed.' $Target $null $null
    }
}

function Read-PtUiObservationValue {
    param($Element,[string]$Property,$Target,[int]$MaxTextLength)
    $pattern=$null;$value=$null;$source=$null
    switch($Property){
        Text {
            $password=$Element.GetCurrentPropertyValue([Windows.Automation.AutomationElement]::IsPasswordProperty,$true)
            if($password -isnot [bool] -or $password){
                Throw-PtUiObservationFailure Unsupported 'Text is protected or a non-password state is not exposed; content was not read.' $Target $null $Property
            }
            if($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){
                $value=$pattern.Current.Value;$source='ValuePattern.Value'
            }elseif($Element.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern,[ref]$pattern)){
                $value=$pattern.DocumentRange.GetText($MaxTextLength+1);$source='TextPattern.DocumentRange'
            }else{
                Throw-PtUiObservationFailure Unsupported 'Neither ValuePattern nor TextPattern is supported; Name/placeholder are not text fallbacks.' $Target $null $Property
            }
        }
        IsSelected {
            if(-not $Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)){
                Throw-PtUiObservationFailure Unsupported 'SelectionItemPattern is not supported.' $Target $null $Property
            }
            $value=$pattern.Current.IsSelected;$source='SelectionItemPattern.IsSelected'
        }
        RangeValue {
            if(-not $Element.TryGetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern,[ref]$pattern)){
                Throw-PtUiObservationFailure Unsupported 'RangeValuePattern is not supported.' $Target $null $Property
            }
            $value=$pattern.Current.Value;$source='RangeValuePattern.Value'
        }
        LiveSetting {
            Initialize-PtNativeUiProperty
            $native=[PtNativeUiProperty]::Read($Target.hwnd,[int[]]$Element.GetRuntimeId(),30135)
            if(-not $native.Supported){Throw-PtUiObservationFailure Unsupported 'Native UIA LiveSetting is not supported; no default Off value was substituted.' $Target $null $Property}
            $value=$native.Value;$source='IUIAutomationElement.GetCurrentPropertyValueEx(30135, ignoreDefault=true)'
        }
        default {
            $identifier=[Windows.Automation.AutomationElement]::("${Property}Property")
            $value=$Element.GetCurrentPropertyValue($identifier,$true)
            if([object]::ReferenceEquals($value,[Windows.Automation.AutomationElement]::NotSupported)){
                Throw-PtUiObservationFailure Unsupported "$Property is not supported; its default was ignored." $Target $null $Property
            }
            $source="AutomationElement.$Property (ignoreDefault=true)"
        }
    }
    $valid=switch($Property){
        {$_ -in 'Text','Name','HelpText'} {$value -is [string]}
        {$_ -in 'IsEnabled','IsSelected','HasKeyboardFocus','IsOffscreen'} {$value -is [bool]}
        LiveSetting {$value -is [int] -and $value -in 0,1,2}
        RangeValue {$value -is [double] -and -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)}
        BoundingRectangle {$value -is [Windows.Rect]}
    }
    if(-not $valid){Throw-PtUiObservationFailure ReadError "Unexpected or null value type for $Property; no coercion was applied." $Target $null $Property}
    if($value -is [string] -and $value.Length -gt $MaxTextLength){
        Throw-PtUiObservationFailure ReadError "Text exceeds MaxTextLength=$MaxTextLength; no truncated observation was returned." $Target $null $Property
    }
    if($Property -eq 'BoundingRectangle'){
        if(-not $value.IsEmpty -and @($value.X,$value.Y,$value.Width,$value.Height|Where-Object{[double]::IsNaN($_) -or [double]::IsInfinity($_)}).Count){
            Throw-PtUiObservationFailure ReadError 'Nonempty geometry contains non-finite coordinates.' $Target $null $Property
        }
        $value=if($value.IsEmpty){[pscustomobject]@{IsEmpty=$true;X=$null;Y=$null;Width=$null;Height=$null;Units='PhysicalPixels'}}
            else{[pscustomobject]@{IsEmpty=$false;X=$value.X;Y=$value.Y;Width=$value.Width;Height=$value.Height;Units='PhysicalPixels'}}
    }
    [pscustomobject]@{Value=$value;Source=$source}
}

function Get-PtUiObservation {
    <#
    .SYNOPSIS
    Read one supported semantic property from an exact live target and runtime-unique control.
    .NOTES
    Omit selectors to observe the target window itself. Empty strings, false and zero are
    valid values. Missing/ambiguous/unsupported/stale/read failures throw structured errors.
    #>
    [CmdletBinding(DefaultParameterSetName='Window')]
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory,ParameterSetName='Id')][string]$AutomationId,
        [Parameter(Mandatory,ParameterSetName='Name')][string]$Name,
        [Parameter(Mandatory,ParameterSetName='Id')][Parameter(Mandatory,ParameterSetName='Name')]
        [ValidateSet('ComboBox','Button','Edit','Tab','TabItem','List','ListItem','Pane','Group','Text','Document','Custom','Hyperlink','CheckBox','RadioButton','Tree','TreeItem','Window','Slider','Spinner','ProgressBar')][string]$ControlType,
        [Parameter(ParameterSetName='Id')][Parameter(ParameterSetName='Name')][string]$WithinAutomationId,
        [Parameter(Mandatory)][ValidateSet('Text','Name','HelpText','IsEnabled','IsSelected','HasKeyboardFocus','IsOffscreen','BoundingRectangle','RangeValue','LiveSetting')][string]$Property,
        [ValidateRange(1,1048576)][int]$MaxTextLength=16384,[switch]$SkipRecording)
    $selector=if($PSCmdlet.ParameterSetName -eq 'Id'){@{AutomationId=$AutomationId;ControlType=$ControlType;WithinAutomationId=$WithinAutomationId}}
        elseif($PSCmdlet.ParameterSetName -eq 'Name'){@{Name=$Name;ControlType=$ControlType;WithinAutomationId=$WithinAutomationId}}
        else{@{}}
    $arguments=@{Target=$Target;Property=$Property;MaxTextLength=$MaxTextLength}+$selector
    $active=Get-PtActiveVerificationAttempt
    if(-not $SkipRecording -and $active){
        $encoded=(ConvertTo-Json $arguments -Depth 10 -Compress).Replace("'","''")
        return Invoke-PtVerificationStep $active -Name "Read UI property $Property" `
            -Command "`$p=ConvertFrom-Json -AsHashtable '$encoded'; Get-PtUiObservation @p" `
            -Implementation ${function:Get-PtUiObservation} -ArgumentList @($arguments) -Action {
                param($parameters) Get-PtUiObservation @parameters -SkipRecording
            }
    }
    $dpi=[IntPtr]::Zero
    try{
        Assert-PtUiObservationTarget $Target
        Initialize-PtUiAutomation
        $dpi=[PtDesktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
        $element=if($selector.Count){Resolve-PtUiElement -Hwnd $Target.hwnd @selector}
            else{[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$Target.hwnd)}
        $runtime=@($element.GetRuntimeId())
        if(-not $runtime.Count){Throw-PtUiObservationFailure ReadError 'The resolved control has no runtime identity.' $Target $selector $Property}
        $observed=Read-PtUiObservationValue $element $Property $Target $MaxTextLength
        $offscreen=$element.GetCurrentPropertyValue([Windows.Automation.AutomationElement]::IsOffscreenProperty,$true)
        $offscreenObserved=$offscreen -is [bool]
        if(-not $offscreenObserved -and -not [object]::ReferenceEquals($offscreen,[Windows.Automation.AutomationElement]::NotSupported)){
            Throw-PtUiObservationFailure ReadError 'Unexpected IsOffscreen metadata type; no false value was substituted.' $Target $selector $Property
        }
        if(($runtime -join ',') -cne (@($element.GetRuntimeId()) -join ',')){
            Throw-PtUiObservationFailure Stale 'Control identity changed during the property read.' $Target $selector $Property
        }
        Assert-PtUiObservationTarget $Target
        [pscustomobject]@{
            Status='Observed';Property=$Property;Value=$observed.Value;Source=$observed.Source
            IsOffscreen=$(if($offscreenObserved){$offscreen}else{$null});IsOffscreenObserved=$offscreenObserved
            Target=[pscustomobject]@{hwnd=$Target.hwnd;processId=$Target.processId;processStartTicks=$Target.processStartTicks;className=$Target.className}
            RuntimeId=$runtime;Selector=$selector;CapturedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');Diagnostic=$null
        }
    }catch{
        $failure=$_
        $exception=$failure.Exception
        if($exception.Data.Contains('UiObservation')){
            $exception.Data['UiObservation'].Selector=$selector
            $exception.Data['UiObservation'].Property=$Property
            throw
        }
        $status=$null
        while($exception){
            if($exception.Data.Contains('PtUiResolutionStatus')){$status=[string]$exception.Data['PtUiResolutionStatus'];break}
            if(($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 1400) -or
                $exception.HResult -eq -2147220991 -or $exception.GetType().FullName -eq 'System.Windows.Automation.ElementNotAvailableException'){$status='Stale';break}
            $exception=$exception.InnerException
        }
        if(-not $status){$status=if($failure.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId*'){'Stale'}else{'ReadError'}}
        Throw-PtUiObservationFailure $status $failure.Exception.Message $Target $selector $Property $failure.Exception
    }finally{if($dpi -ne [IntPtr]::Zero){[void][PtDesktop]::SetThreadDpiAwarenessContext($dpi)}}
}
