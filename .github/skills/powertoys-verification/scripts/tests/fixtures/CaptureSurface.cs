// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license. See LICENSE.txt in the skill directory.
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

internal static class CaptureSurface
{
    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    [STAThread]
    private static void Main(string[] args)
    {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        Application.EnableVisualStyles();
        using (var background = new Form())
        using (var target = new Form())
        using (var overlay = new Form())
        using (var timer = new Timer())
        {
            background.Text = "Owned opaque capture background";
            background.FormBorderStyle = FormBorderStyle.None;
            background.StartPosition = FormStartPosition.Manual;
            background.Bounds = Screen.PrimaryScreen.Bounds;
            background.BackColor = Color.Navy;
            background.TopMost = true;
            target.Text = "Owned capture acceptance";
            target.StartPosition = FormStartPosition.Manual;
            target.Bounds = new Rectangle(background.Left + 120, background.Top + 120, 640, 380);
            target.BackColor = Color.White;
            target.TopMost = true;
            overlay.Text = "Owned synthetic transparent overlay";
            overlay.FormBorderStyle = FormBorderStyle.None;
            overlay.StartPosition = FormStartPosition.Manual;
            overlay.Bounds = new Rectangle(target.Left + 100, target.Top + 100, 180, 120);
            overlay.BackColor = Color.Red;
            overlay.Opacity = 0.5;
            overlay.TopMost = true;
            var started = DateTime.UtcNow;
            timer.Interval = 100;
            timer.Tick += (sender, e) =>
            {
                if (File.Exists(Path.Combine(args[0], "exit")) ||
                    (DateTime.UtcNow - started).TotalMinutes > 5)
                {
                    target.Close();
                }
            };
            target.Shown += (sender, e) =>
            {
                background.Show();
                target.BringToFront();
                overlay.Show();
                File.WriteAllText(Path.Combine(args[0], "ready.json"),
                    "{\"target\":" + target.Handle.ToInt64() +
                    ",\"background\":" + background.Handle.ToInt64() +
                    ",\"overlay\":" + overlay.Handle.ToInt64() + "}");
                timer.Start();
            };
            try
            {
                Application.Run(target);
            }
            finally
            {
                timer.Stop();
                if (previous != IntPtr.Zero)
                {
                    SetThreadDpiAwarenessContext(previous);
                }
            }
        }
    }
}
