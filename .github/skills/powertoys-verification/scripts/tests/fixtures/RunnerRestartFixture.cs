// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class RunnerRestartFixture
{
    private delegate IntPtr WindowProcedure(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        internal uint Style;
        internal WindowProcedure Procedure;
        internal int ClassExtra;
        internal int WindowExtra;
        internal IntPtr Instance;
        internal IntPtr Icon;
        internal IntPtr Cursor;
        internal IntPtr Background;
        internal string MenuName;
        internal string ClassName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        internal IntPtr Window;
        internal uint Id;
        internal IntPtr WParam;
        internal IntPtr LParam;
        internal uint Time;
        internal int X;
        internal int Y;
        internal uint Private;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClass(ref WindowClass value);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(uint extendedStyle, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern void PostQuitMessage(int result);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetMessage(out Message message, IntPtr window, uint minimum, uint maximum);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref Message message);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern UIntPtr SetTimer(IntPtr window, UIntPtr id, uint milliseconds, IntPtr callback);

    private static readonly WindowProcedure Procedure = HandleMessage;

    private static IntPtr HandleMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == 0x0010 || message == 0x0113)
        {
            DestroyWindow(window);
            return IntPtr.Zero;
        }

        if (message == 0x0002)
        {
            PostQuitMessage(0);
            return IntPtr.Zero;
        }

        return DefWindowProc(window, message, wParam, lParam);
    }

    private static int Main()
    {
        var windowClass = new WindowClass { ClassName = "PToyTrayIconWindow", Procedure = Procedure };
        if (RegisterClass(ref windowClass) == 0)
        {
            return 1;
        }

        var window = CreateWindowEx(0, windowClass.ClassName, "Runner restart fixture", 0, 0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (window == IntPtr.Zero || SetTimer(window, new UIntPtr(1), 30000, IntPtr.Zero) == UIntPtr.Zero)
        {
            return 2;
        }

        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "fixture-ready.txt"), Process.GetCurrentProcess().Id.ToString());
        Message message;
        int result;
        while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
        {
            DispatchMessage(ref message);
        }

        GC.KeepAlive(Procedure);
        return result == -1 ? 3 : 0;
    }
}
