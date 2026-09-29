// Synthetic memory/sequence boundary for the real ClipboardGuard implementation. No OS clipboard calls.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class PtClipboardNativeStub
{
    public static uint Sequence = 100;
    public static int WriterPid = Process.GetCurrentProcess().Id;
    public static long WriterTicks = Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
    public static int OpenFailures, OpenError = 5, OpenCalls, EmptyCalls, SetCalls, GetCalls, AllocCalls;
    public static int FailSetCall, FailGetCall, FailAllocCall;
    public static bool OwnerAlive = true, Locked, FailUnlock;
    private static readonly Dictionary<IntPtr, int> memory = new Dictionary<IntPtr, int>();
    private static readonly SortedDictionary<uint, IntPtr> clipboard = new SortedDictionary<uint, IntPtr>();

    public static void Reset()
    {
        foreach (var handle in new List<IntPtr>(memory.Keys)) Free(handle);
        clipboard.Clear();
        Sequence = 100;
        WriterPid = Process.GetCurrentProcess().Id;
        WriterTicks = Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
        OpenFailures = OpenCalls = EmptyCalls = SetCalls = GetCalls = AllocCalls = 0;
        FailSetCall = FailGetCall = FailAllocCall = 0;
        OpenError = 5; OwnerAlive = true; Locked = FailUnlock = false;
        Put(13, new byte[] { 65, 0, 0, 0 });
        Put(0xC000, new byte[] { 66, 67, 0 });
        AllocCalls = 0;
    }

    private static void RequireLock()
    {
        if (!Locked) throw new InvalidOperationException("Synthetic clipboard operation requires a lock.");
    }

    public static bool Open(IntPtr owner)
    {
        OpenCalls++;
        if (OpenFailures-- > 0 || Locked) { Marshal.SetLastPInvokeError(OpenError); return false; }
        Locked = true; Marshal.SetLastPInvokeError(0); return true;
    }

    public static bool Close()
    {
        RequireLock(); Locked = false;
        Marshal.SetLastPInvokeError(FailUnlock ? 6 : 0);
        return !FailUnlock;
    }

    public static uint Next(uint previous)
    {
        RequireLock(); Marshal.SetLastPInvokeError(0);
        foreach (var format in clipboard.Keys) if (format > previous) return format;
        return 0;
    }

    public static IntPtr Get(uint format)
    {
        RequireLock(); GetCalls++;
        if (GetCalls == FailGetCall) { Marshal.SetLastPInvokeError(6); return IntPtr.Zero; }
        return clipboard.TryGetValue(format, out var handle) ? handle : IntPtr.Zero;
    }

    public static IntPtr Set(uint format, IntPtr handle)
    {
        RequireLock(); SetCalls++;
        if (SetCalls == FailSetCall) { Marshal.SetLastPInvokeError(8); return IntPtr.Zero; }
        clipboard[format] = handle; Sequence++; return handle;
    }

    public static bool Empty()
    {
        RequireLock(); EmptyCalls++;
        foreach (var handle in clipboard.Values) Free(handle);
        clipboard.Clear(); Sequence++;
        WriterPid = Process.GetCurrentProcess().Id;
        return true;
    }

    private static void Put(uint format, byte[] bytes)
    {
        var handle = Allocate((UIntPtr)(uint)bytes.Length);
        if (handle == IntPtr.Zero) throw new Win32Exception(8);
        Marshal.Copy(bytes, 0, handle, bytes.Length); clipboard[format] = handle;
    }

    public static void Write(byte value, int writerPid)
    {
        if (Locked) throw new InvalidOperationException("Synthetic writer cannot write while locked.");
        foreach (var handle in clipboard.Values) Free(handle);
        clipboard.Clear(); Put(13, new byte[] { value, 0, 0, 0 });
        WriterPid = writerPid; Sequence++;
    }

    public static byte[] Bytes(uint format)
    {
        var handle = clipboard[format]; var bytes = new byte[memory[handle]];
        Marshal.Copy(handle, bytes, 0, bytes.Length); return bytes;
    }

    public static int FormatCount { get { return clipboard.Count; } }
    public static int AllocationCount { get { return memory.Count; } }
    public static UIntPtr Size(IntPtr handle) { return (UIntPtr)(uint)memory[handle]; }
    public static IntPtr Allocate(UIntPtr size)
    {
        AllocCalls++;
        if (AllocCalls == FailAllocCall) { Marshal.SetLastPInvokeError(8); return IntPtr.Zero; }
        var handle = Marshal.AllocHGlobal((int)size.ToUInt64()); memory.Add(handle, (int)size.ToUInt64()); return handle;
    }
    public static IntPtr Free(IntPtr handle)
    {
        if (memory.Remove(handle)) Marshal.FreeHGlobal(handle);
        return IntPtr.Zero;
    }
}
