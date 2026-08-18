// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Microsoft.PowerToys.UITest.Next;

/// <summary>
/// Display-mode helpers for capturing/restoring modes, pinning a deterministic CI resolution, and
/// logging monitor topology. Native because winappcli exposes no display API.
/// </summary>
public static class DisplayHelper
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int EnumDisplaySettings(string? lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettings(ref DEVMODE lpDevMode, int dwflags);

    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CDS_TEST = 0x00000002;
    private const int CDS_UPDATEREGISTRY = 0x00000001;
    private const int DISP_CHANGE_SUCCESSFUL = 0;
    private const int DM_PELSWIDTH = 0x00080000;
    private const int DM_PELSHEIGHT = 0x00100000;

    /// <summary>An exact native display mode captured for later restoration.</summary>
    public sealed class DisplayModeSnapshot
    {
        internal readonly DEVMODE Mode;

        internal DisplayModeSnapshot(DEVMODE mode)
        {
            Mode = mode;
        }

        public int Width => Mode.DmPelsWidth;

        public int Height => Mode.DmPelsHeight;
    }

    /// <summary>Capture the primary display's complete current <c>DEVMODE</c>.</summary>
    public static DisplayModeSnapshot? CaptureCurrentMode()
    {
        var mode = CreateDevMode();
        return EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode) != 0
            ? new DisplayModeSnapshot(mode)
            : null;
    }

    /// <summary>Apply only a new primary-display resolution, preserving the other active mode fields.</summary>
    public static bool TrySetResolution(int width, int height)
    {
        var snapshot = CaptureCurrentMode();
        if (snapshot is null)
        {
            return false;
        }

        var mode = snapshot.Mode;
        mode.DmPelsWidth = width;
        mode.DmPelsHeight = height;
        mode.DmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
        return TryApplyMode(ref mode);
    }

    /// <summary>Restore a previously captured complete native display mode.</summary>
    public static bool TryRestoreMode(DisplayModeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var mode = snapshot.Mode;
        return TryApplyMode(ref mode);
    }

    /// <summary>Wait until all active display-mode fields match a captured mode.</summary>
    public static bool WaitForMode(DisplayModeSnapshot expected, int timeoutMs = 5_000)
    {
        ArgumentNullException.ThrowIfNull(expected);
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        do
        {
            var current = CaptureCurrentMode();
            if (current is not null && ModesMatch(current.Mode, expected.Mode))
            {
                return true;
            }

            Thread.Sleep(100);
        }
        while (DateTime.UtcNow < deadline);

        return false;
    }

    /// <summary>
    /// Pin the primary display to <paramref name="width"/> x <paramref name="height"/>. No-op when
    /// already at that resolution. Best-effort — swallows failures because a CI agent may disallow
    /// display-mode changes.
    /// </summary>
    /// <remarks>
    /// Unlike the legacy harness (which left <c>dmFields</c> unset), this reads the current mode via
    /// <c>EnumDisplaySettings(ENUM_CURRENT_SETTINGS)</c> and sets
    /// <c>DM_PELSWIDTH | DM_PELSHEIGHT</c> — the documented, reliable way to request a resolution
    /// change.
    /// </remarks>
    public static void NormalizeResolution(int width, int height)
    {
        try
        {
            var primary = Screen.PrimaryScreen;
            if (primary is not null && primary.Bounds.Width == width && primary.Bounds.Height == height)
            {
                return;
            }

            _ = TrySetResolution(width, height);
        }
        catch
        {
            // Resolution normalization is a CI nicety, not a hard requirement.
        }
    }

    private static DEVMODE CreateDevMode() => new()
    {
        DmDeviceName = new string('\0', 32),
        DmFormName = new string('\0', 32),
        DmSize = (short)Marshal.SizeOf<DEVMODE>(),
    };

    private static bool TryApplyMode(ref DEVMODE mode) =>
        ChangeDisplaySettings(ref mode, CDS_TEST) == DISP_CHANGE_SUCCESSFUL &&
        ChangeDisplaySettings(ref mode, CDS_UPDATEREGISTRY) == DISP_CHANGE_SUCCESSFUL;

    private static bool ModesMatch(DEVMODE left, DEVMODE right) =>
        left.DmPositionX == right.DmPositionX &&
        left.DmPositionY == right.DmPositionY &&
        left.DmDisplayOrientation == right.DmDisplayOrientation &&
        left.DmDisplayFixedOutput == right.DmDisplayFixedOutput &&
        left.DmBitsPerPel == right.DmBitsPerPel &&
        left.DmPelsWidth == right.DmPelsWidth &&
        left.DmPelsHeight == right.DmPelsHeight &&
        left.DmDisplayFlags == right.DmDisplayFlags &&
        left.DmDisplayFrequency == right.DmDisplayFrequency;

    /// <summary>Write the connected-monitor topology to the test log (and console) for diagnostics.</summary>
    public static void LogMonitors(TestContext? testContext = null)
    {
        try
        {
            foreach (var m in MonitorInfo.GetAll())
            {
                var line = $"Monitor '{m.DeviceName}': {m.Width}x{m.Height} at ({m.Left},{m.Top}) primary={m.IsPrimary}";
                testContext?.WriteLine(line);
                Console.WriteLine(line);
            }
        }
        catch
        {
            // Diagnostics only — never let logging fail a test.
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DmDeviceName;
        public short DmSpecVersion;
        public short DmDriverVersion;
        public short DmSize;
        public short DmDriverExtra;
        public int DmFields;
        public int DmPositionX;
        public int DmPositionY;
        public int DmDisplayOrientation;
        public int DmDisplayFixedOutput;
        public short DmColor;
        public short DmDuplex;
        public short DmYResolution;
        public short DmTTOption;
        public short DmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DmFormName;
        public short DmLogPixels;
        public int DmBitsPerPel;
        public int DmPelsWidth;
        public int DmPelsHeight;
        public int DmDisplayFlags;
        public int DmDisplayFrequency;
        public int DmICMMethod;
        public int DmICMIntent;
        public int DmMediaType;
        public int DmDitherType;
        public int DmReserved1;
        public int DmReserved2;
        public int DmPanningWidth;
        public int DmPanningHeight;
    }
}
