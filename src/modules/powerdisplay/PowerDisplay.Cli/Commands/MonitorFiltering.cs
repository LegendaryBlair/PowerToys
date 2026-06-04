// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System.Collections.Generic;
using Monitor = PowerDisplay.Common.Models.Monitor;

namespace PowerDisplay.Cli.Commands;

internal static class MonitorFiltering
{
    /// <summary>
    /// Drops monitors the user hid in PowerDisplay settings, matching the GUI which
    /// removes the same ids from its managed list.
    /// </summary>
    public static IReadOnlyList<Monitor> ExcludeHidden(
        IReadOnlyList<Monitor> monitors,
        IReadOnlySet<string> hiddenMonitorIds)
    {
        if (hiddenMonitorIds.Count == 0)
        {
            return monitors;
        }

        var kept = new List<Monitor>(monitors.Count);
        foreach (var m in monitors)
        {
            if (!hiddenMonitorIds.Contains(m.Id))
            {
                kept.Add(m);
            }
        }

        return kept;
    }
}
