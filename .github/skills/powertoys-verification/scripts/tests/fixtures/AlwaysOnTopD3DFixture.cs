// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license. See LICENSE.txt in the skill directory.
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class PtAotD3DFixture : IDisposable
{
    private readonly Form form;
    private readonly Rectangle bounds;
    private readonly FormBorderStyle borderStyle;
    private readonly FormWindowState windowState;
    private readonly bool originalTopmost;
    private IntPtr direct3D;
    private IntPtr device;
    private DisplayMode originalMode;

    public bool Active { get; private set; }
    public int DeviceType { get; private set; }
    public int CreationResult { get; private set; }
    public bool DisplayModeRestored { get; private set; }

    public PtAotD3DFixture(Form target, int deviceType)
    {
        if (target == null || (deviceType != 1 && deviceType != 2))
        {
            throw new ArgumentException("Supply an owned Form and HAL (1) or reference (2) device.");
        }

        form = target;
        bounds = form.Bounds;
        borderStyle = form.FormBorderStyle;
        windowState = form.WindowState;
        originalTopmost = (GetWindowLong(form.Handle, -20) & 8) != 0;
        DeviceType = deviceType;
        try
        {
            form.WindowState = FormWindowState.Normal;
            form.FormBorderStyle = FormBorderStyle.None;
            direct3D = Direct3DCreate9(32);
            if (direct3D == IntPtr.Zero)
            {
                throw new InvalidOperationException("Direct3DCreate9 returned no interface.");
            }

            DisplayMode mode;
            Marshal.ThrowExceptionForHR(Method<GetDisplayMode>(direct3D, 8)(direct3D, 0, out mode));
            originalMode = mode;
            form.Bounds = new Rectangle(0, 0, (int)mode.Width, (int)mode.Height);
            form.Activate();
            var parameters = new PresentParameters
            {
                Width = mode.Width,
                Height = mode.Height,
                Format = mode.Format,
                Count = 1,
                SwapEffect = 1,
                Window = form.Handle,
                Windowed = 0,
                RefreshRate = mode.RefreshRate,
                Interval = 0x80000000,
            };
            // IDirect3D9::CreateDevice follows IUnknown and the adapter-query methods.
            CreationResult = Method<CreateDevice>(direct3D, 16)(
                direct3D, 0, deviceType, form.Handle, 0x22, ref parameters, out device);
            if (CreationResult < 0 || device == IntPtr.Zero)
            {
                throw new InvalidOperationException(string.Format(
                    "Exclusive D3D device {0} failed: HRESULT 0x{1:X8}.", deviceType, CreationResult));
            }

            Active = true;
            PresentFrame();
            SetTopmost(originalTopmost);
        }
        catch (Exception error)
        {
            Dispose();
            error.Data["DisplayModeRestored"] = DisplayModeRestored;
            throw;
        }
    }

    public void PresentFrame()
    {
        if (!Active || device == IntPtr.Zero)
        {
            throw new InvalidOperationException("The owned D3D device is not active.");
        }

        // The caller independently observes the notification state; Present alone is not that proof.
        Marshal.ThrowExceptionForHR(Method<Clear>(device, 43)(device, 0, IntPtr.Zero, 1, 0xFF000080, 1, 0));
        Marshal.ThrowExceptionForHR(Method<Present>(device, 17)(
            device, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero));
    }

    public void Dispose()
    {
        Active = false;
        if (device != IntPtr.Zero)
        {
            Marshal.Release(device);
            device = IntPtr.Zero;
        }

        if (direct3D != IntPtr.Zero)
        {
            DisplayMode current;
            int result = Method<GetDisplayMode>(direct3D, 8)(direct3D, 0, out current);
            DisplayModeRestored = result >= 0 && current.Width == originalMode.Width &&
                current.Height == originalMode.Height && current.Format == originalMode.Format &&
                current.RefreshRate == originalMode.RefreshRate;
            Marshal.Release(direct3D);
            direct3D = IntPtr.Zero;
        }

        if (!form.IsDisposed)
        {
            form.WindowState = FormWindowState.Normal;
            form.FormBorderStyle = borderStyle;
            form.Bounds = bounds;
            form.WindowState = windowState;
            SetTopmost(originalTopmost);
        }
    }

    private void SetTopmost(bool value)
    {
        if (!SetWindowPos(form.Handle, new IntPtr(value ? -1 : -2), 0, 0, 0, 0, 0x13))
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    private static T Method<T>(IntPtr instance, int slot) where T : class
    {
        return (T)(object)Marshal.GetDelegateForFunctionPointer(
            Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * IntPtr.Size), typeof(T));
    }

    [DllImport("d3d9.dll", ExactSpelling = true)]
    private static extern IntPtr Direct3DCreate9(uint version);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetDisplayMode(IntPtr instance, uint adapter, out DisplayMode mode);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int CreateDevice(IntPtr instance, uint adapter, int type, IntPtr window,
        uint flags, ref PresentParameters parameters, out IntPtr device);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int Present(IntPtr instance, IntPtr source, IntPtr destination, IntPtr window, IntPtr dirty);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int Clear(IntPtr instance, uint count, IntPtr rectangles, uint flags, uint color, float depth, uint stencil);

    [StructLayout(LayoutKind.Sequential)]
    private struct DisplayMode
    {
        public uint Width, Height, RefreshRate;
        public int Format;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PresentParameters
    {
        public uint Width, Height;
        public int Format;
        public uint Count;
        public int MultiSample;
        public uint Quality;
        public int SwapEffect;
        public IntPtr Window;
        public int Windowed, AutoDepth, DepthFormat;
        public uint Flags, RefreshRate, Interval;
    }
}
