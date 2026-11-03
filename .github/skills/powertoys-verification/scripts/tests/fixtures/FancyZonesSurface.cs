// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class FancyZonesSurface
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr context);

    private sealed class BackgroundForm : Form
    {
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams value = base.CreateParams;
                value.ExStyle |= 0x80;
                return value;
            }
        }
    }

    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    private static readonly Dictionary<long, Form> Forms = new Dictionary<long, Form>();
    private static string root;
    private static Form main;
    private static int serial;

    private static void Save(string name, object value)
    {
        string staging = Path.Combine(root, name + ".new");
        string destination = Path.Combine(root, name);
        File.WriteAllText(staging, Json.Serialize(value));
        if (File.Exists(destination))
        {
            File.Delete(destination);
        }

        File.Move(staging, destination);
    }

    private static void Record(string kind, long hwnd, int key)
    {
        File.AppendAllText(Path.Combine(root, "events.ndjson"), Json.Serialize(new
        {
            Kind = kind,
            Hwnd = hwnd,
            Key = key,
            Ticks = Stopwatch.GetTimestamp(),
        }) + Environment.NewLine);
    }

    private static Form Create(string name, Rectangle bounds, bool background, Form owner, bool automatic)
    {
        Form form = background ? new BackgroundForm() : new Form();
        form.Text = "FancyZones verification " + name;
        form.Name = name;
        form.StartPosition = automatic ? FormStartPosition.WindowsDefaultLocation : FormStartPosition.Manual;
        form.AutoScaleMode = AutoScaleMode.None;
        if (automatic)
        {
            form.Size = bounds.Size;
        }
        else
        {
            form.Bounds = bounds;
        }

        form.BackColor = background ? Color.FromArgb(35, 43, 55) : Color.FromArgb(225, 236, 246);
        if (background)
        {
            form.FormBorderStyle = FormBorderStyle.None;
            form.ShowInTaskbar = false;
        }
        else
        {
            TextBox edit = new TextBox
            {
                Name = "PtFancyZonesInput",
                AccessibleName = "Owned FancyZones input",
                Multiline = true,
                Dock = DockStyle.Fill,
                BackColor = form.BackColor,
                Text = "Owned FancyZones fixture " + name,
            };
            edit.KeyDown += (sender, e) => Record("KeyDown", form.Handle.ToInt64(), (int)e.KeyCode);
            edit.KeyUp += (sender, e) => Record("KeyUp", form.Handle.ToInt64(), (int)e.KeyCode);
            form.Controls.Add(edit);
        }

        form.ResizeBegin += (sender, e) => Record("MoveBegin", form.Handle.ToInt64(), 0);
        form.ResizeEnd += (sender, e) => Record("MoveEnd", form.Handle.ToInt64(), 0);
        if (owner == null)
        {
            form.Show();
        }
        else
        {
            form.Show(owner);
        }

        Forms.Add(form.Handle.ToInt64(), form);
        return form;
    }

    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Length < 1 || args.Length > 2 || !Directory.Exists(args[0]))
        {
            throw new ArgumentException("An owned existing state directory is required.");
        }

        root = args[0];
        bool targetOnly = args.Length == 2 && args[1] == "target-only";
        if (!SetProcessDpiAwarenessContext(new IntPtr(-4)))
        {
            throw new System.ComponentModel.Win32Exception();
        }

        Application.EnableVisualStyles();
        List<long> backgrounds = new List<long>();
        List<object> backgroundInfo = new List<object>();
        if (!targetOnly)
        {
            foreach (Screen screen in Screen.AllScreens)
            {
                Form background = Create("background-" + backgrounds.Count, screen.WorkingArea, true, null, false);
                backgrounds.Add(background.Handle.ToInt64());
                backgroundInfo.Add(new { Hwnd = background.Handle.ToInt64(), Device = screen.DeviceName, Area = screen.WorkingArea });
            }
        }

        Rectangle area = Screen.PrimaryScreen.WorkingArea;
        main = Create("target", new Rectangle(area.Left + 200, area.Top + 200, 700, 500), false, null, targetOnly);
        Form second = targetOnly ? null : Create("second", new Rectangle(area.Left + 950, area.Top + 230, 650, 430), false, null, false);
        Form child = targetOnly ? null : Create("child", new Rectangle(area.Left + 300, area.Top + 260, 600, 400), false, main, false);
        main.Activate();
        Save("ready.json", new
        {
            Pid = Process.GetCurrentProcess().Id,
            Target = main.Handle.ToInt64(),
            Second = second == null ? 0 : second.Handle.ToInt64(),
            Child = child == null ? 0 : child.Handle.ToInt64(),
            Backgrounds = backgrounds,
            BackgroundInfo = backgroundInfo,
            Frequency = Stopwatch.Frequency,
        });
        Timer timer = new Timer { Interval = 50 };
        timer.Tick += (sender, e) =>
        {
            if (File.Exists(Path.Combine(root, "exit")))
            {
                main.Close();
                return;
            }

            string path = Path.Combine(root, "command.txt");
            if (!File.Exists(path))
            {
                return;
            }

            string command = File.ReadAllText(path);
            File.Delete(path);
            try
            {
                string[] parts = command.Split('|');
                long id = parts.Length > 1 ? long.Parse(parts[1]) : 0;
                switch (parts[0])
                {
                    case "place":
                        Forms[id].WindowState = FormWindowState.Normal;
                        Forms[id].Bounds = new Rectangle(int.Parse(parts[2]), int.Parse(parts[3]), int.Parse(parts[4]), int.Parse(parts[5]));
                        break;
                    case "show":
                        Forms[id].Show();
                        Forms[id].Activate();
                        break;
                    case "hide":
                        Forms[id].Hide();
                        break;
                    case "focus":
                        Forms[id].Activate();
                        Forms[id].Controls[0].Focus();
                        break;
                    case "create":
                    case "create-default":
                    case "create-child":
                        Form created = Create("new-" + (++serial), new Rectangle(200, 200, 650, 430), false, parts[0] == "create-child" ? main : null, parts[0] == "create-default");
                        id = created.Handle.ToInt64();
                        break;
                    case "close":
                        Forms[id].Close();
                        break;
                    default:
                        throw new ArgumentException("Unknown owned fixture operation.");
                }

                Save("response.json", new { Command = command, Hwnd = id, Success = true });
            }
            catch (Exception error)
            {
                Save("response.json", new { Command = command, Success = false, Error = error.Message });
            }
        };
        timer.Start();
        try
        {
            Application.Run(main);
        }
        finally
        {
            timer.Stop();
            foreach (Form form in Forms.Values)
            {
                if (!form.IsDisposed)
                {
                    form.Dispose();
                }
            }

            timer.Dispose();
        }
    }
}
