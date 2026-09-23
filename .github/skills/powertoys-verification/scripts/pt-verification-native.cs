// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PtVerification
{
    public static class Desktop
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
        [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, uint attribute, out int value, uint size);

        public static int Cloaked(IntPtr hwnd)
        {
            int value;
            int result = DwmGetWindowAttribute(hwnd, 14, out value, 4);
            if (result != 0) Marshal.ThrowExceptionForHR(result);
            return value;
        }
    }

    // Clipboard handles are copied eagerly while locked. No user clipboard data is written to disk.
    public sealed class ClipboardGuard : IDisposable
    {
        private sealed class Entry
        {
            public uint Format;
            public byte[] Bytes;
            public IntPtr Bitmap;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BitmapInfo
        {
            public int Type, Width, Height, WidthBytes;
            public ushort Planes, BitsPixel;
            public IntPtr Bits;
        }

        [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr owner);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] private static extern uint EnumClipboardFormats(uint format);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetClipboardData(uint format);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetClipboardData(uint format, IntPtr data);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool EmptyClipboard();
        [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
        [DllImport("user32.dll")] private static extern IntPtr GetClipboardOwner();
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr CopyImage(IntPtr handle, uint type, int x, int y, uint flags);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern UIntPtr GlobalSize(IntPtr memory);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalLock(IntPtr memory);
        [DllImport("kernel32.dll")] private static extern bool GlobalUnlock(IntPtr memory);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr size);
        [DllImport("kernel32.dll")] private static extern IntPtr GlobalFree(IntPtr memory);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr handle);
        [DllImport("gdi32.dll", EntryPoint = "GetObjectW")] private static extern int GetObject(IntPtr handle, int size, out BitmapInfo bitmap);
        [DllImport("gdi32.dll")] private static extern int GetBitmapBits(IntPtr handle, int count, byte[] data);

        private readonly List<Entry> entries = new List<Entry>();
        private readonly IntPtr owner;
        private bool disposed;
        public uint ExpectedSequence { get; private set; }
        public bool Restored { get; private set; }
        public int FormatCount { get { return entries.Count; } }
        public bool BitmapFromPng { get; private set; }

        private static Exception Failure(string operation)
        {
            return new Win32Exception(Marshal.GetLastWin32Error(), operation);
        }

        private void Lock()
        {
            if (disposed) throw new ObjectDisposedException(nameof(ClipboardGuard));
            if (!Desktop.IsWindow(owner)) throw new InvalidOperationException("Clipboard owner window no longer exists.");
            if (!OpenClipboard(owner)) throw Failure("OpenClipboard");
        }

        private static void Unlock()
        {
            if (!CloseClipboard()) throw Failure("CloseClipboard");
        }

        private static byte[] ReadMemory(IntPtr handle)
        {
            ulong size = GlobalSize(handle).ToUInt64();
            if (size == 0 || size > 64 * 1024 * 1024) throw new InvalidOperationException("Unsupported/oversized clipboard memory.");
            IntPtr pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero) throw Failure("GlobalLock");
            try
            {
                var bytes = new byte[(int)size];
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                return bytes;
            }
            finally { GlobalUnlock(handle); }
        }

        private static byte[] ReadBitmap(IntPtr handle)
        {
            BitmapInfo bitmap;
            if (GetObject(handle, Marshal.SizeOf<BitmapInfo>(), out bitmap) == 0) throw Failure("GetObject bitmap");
            int size = checked(Math.Abs(bitmap.Height) * bitmap.WidthBytes);
            if (size <= 0 || size > 64 * 1024 * 1024) throw new InvalidOperationException("Unsupported bitmap size.");
            var bytes = new byte[size];
            if (GetBitmapBits(handle, size, bytes) != size) throw Failure("GetBitmapBits");
            return bytes;
        }

        public ClipboardGuard(long ownerHwnd) : this(ownerHwnd, IntPtr.Zero, 0) { }

        public ClipboardGuard(long ownerHwnd, IntPtr pngBitmap, uint expectedSequence)
        {
            owner = new IntPtr(ownerHwnd);
            uint ownerPid;
            Desktop.GetWindowThreadProcessId(owner, out ownerPid);
            if (ownerPid != (uint)Process.GetCurrentProcess().Id) throw new InvalidOperationException("Use an owned window in this process.");
            Lock();
            try
            {
                if (pngBitmap != IntPtr.Zero && GetClipboardSequenceNumber() != expectedSequence)
                    throw new InvalidOperationException("Clipboard changed while materializing its PNG image.");
                uint format = 0;
                while ((format = EnumClipboardFormats(format)) != 0)
                {
                    if (format != 2 && format != 1 && format != 7 && format != 8 && format != 13 &&
                        format != 15 && format != 16 && format != 17 && format < 0xC000)
                        throw new InvalidOperationException("Unsupported clipboard format: " + format);
                    IntPtr handle = GetClipboardData(format);
                    if (handle == IntPtr.Zero) throw Failure("GetClipboardData " + format);
                    var entry = new Entry { Format = format };
                    if (format == 2)
                    {
                        try { entry.Bytes = ReadBitmap(handle); }
                        catch (Win32Exception) when (pngBitmap != IntPtr.Zero)
                        {
                            // Some remote clipboard providers expose an unusable CF_BITMAP but valid PNG.
                            handle = pngBitmap;
                            entry.Bytes = ReadBitmap(handle);
                            BitmapFromPng = true;
                        }
                        entry.Bitmap = CopyImage(handle, 0, 0, 0, 0x2000);
                        if (entry.Bitmap == IntPtr.Zero) throw Failure("CopyImage");
                    }
                    else entry.Bytes = ReadMemory(handle);
                    entries.Add(entry);
                }
                if (Marshal.GetLastWin32Error() != 0) throw Failure("EnumClipboardFormats");
                ExpectedSequence = GetClipboardSequenceNumber();
            }
            catch { Dispose(); throw; }
            finally { Unlock(); }
        }

        private void Check()
        {
            if (Restored) throw new InvalidOperationException("Clipboard guard already restored.");
            if (GetClipboardSequenceNumber() != ExpectedSequence) throw new InvalidOperationException("Clipboard conflict: unacknowledged write.");
        }

        public void AssertUnchanged()
        {
            Lock();
            try { Check(); }
            finally { Unlock(); }
        }

        public uint AcceptWrite(uint beforeSequence, int writerPid)
        {
            Lock();
            try
            {
                if (Restored || beforeSequence != ExpectedSequence) throw new InvalidOperationException("Stale clipboard action receipt.");
                uint actual = GetClipboardSequenceNumber();
                uint pid;
                Desktop.GetWindowThreadProcessId(GetClipboardOwner(), out pid);
                if (actual == beforeSequence || pid != (uint)writerPid || writerPid <= 0)
                    throw new InvalidOperationException("Clipboard write not attributable to the declared writer.");
                ExpectedSequence = actual;
                return actual;
            }
            finally { Unlock(); }
        }

        private static IntPtr Allocate(Entry entry)
        {
            if (entry.Format == 2)
            {
                IntPtr bitmap = CopyImage(entry.Bitmap, 0, 0, 0, 0x2000);
                if (bitmap == IntPtr.Zero) throw Failure("CopyImage restore");
                return bitmap;
            }
            IntPtr handle = GlobalAlloc(0x42, new UIntPtr((uint)entry.Bytes.Length));
            if (handle == IntPtr.Zero) throw Failure("GlobalAlloc");
            IntPtr pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero) { GlobalFree(handle); throw Failure("GlobalLock restore"); }
            try { Marshal.Copy(entry.Bytes, 0, pointer, entry.Bytes.Length); }
            finally { GlobalUnlock(handle); }
            return handle;
        }

        private static void Free(uint format, IntPtr handle)
        {
            if (format == 2) DeleteObject(handle);
            else GlobalFree(handle);
        }

        public void Restore()
        {
            Lock();
            var allocated = new List<IntPtr>();
            bool emptied = false;
            try
            {
                Check();
                foreach (var entry in entries) allocated.Add(Allocate(entry));
                if (!EmptyClipboard()) throw Failure("EmptyClipboard");
                emptied = true;
                for (int i = 0; i < entries.Count; i++)
                {
                    if (SetClipboardData(entries[i].Format, allocated[i]) == IntPtr.Zero) throw Failure("SetClipboardData restore");
                    allocated[i] = IntPtr.Zero; // Ownership transfers to Windows.
                }
                foreach (var entry in entries)
                {
                    IntPtr handle = GetClipboardData(entry.Format);
                    if (handle == IntPtr.Zero) throw Failure("Read restored clipboard");
                    byte[] actual = entry.Format == 2 ? ReadBitmap(handle) : ReadMemory(handle);
                    if (actual.Length != entry.Bytes.Length) throw new InvalidOperationException("Clipboard restoration length differs.");
                    for (int i = 0; i < actual.Length; i++)
                        if (actual[i] != entry.Bytes[i]) throw new InvalidOperationException("Clipboard restoration content differs.");
                }
                Restored = true;
            }
            finally
            {
                for (int i = 0; i < allocated.Count; i++)
                    if (allocated[i] != IntPtr.Zero) Free(entries[i].Format, allocated[i]);
                if (emptied) ExpectedSequence = GetClipboardSequenceNumber();
                Unlock();
            }
        }

        public void Dispose()
        {
            if (disposed) return;
            foreach (var entry in entries) if (entry.Bitmap != IntPtr.Zero) DeleteObject(entry.Bitmap);
            disposed = true;
        }

        public static void ReleaseBitmap(IntPtr bitmap)
        {
            if (bitmap != IntPtr.Zero && !DeleteObject(bitmap)) throw Failure("DeleteObject temporary bitmap");
        }
    }
}
