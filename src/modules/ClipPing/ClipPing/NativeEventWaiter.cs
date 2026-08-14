// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Threading;

using Microsoft.UI.Dispatching;

namespace ClipPing;

public static class NativeEventWaiter
{
    public static void WaitForEvents(params (string EventName, Action Callback)[] events)
    {
        ArgumentNullException.ThrowIfNull(events);
        if (events.Length == 0)
        {
            throw new ArgumentException("At least one event must be provided.", nameof(events));
        }

        var dispatcherQueue = DispatcherQueue.GetForCurrentThread()
            ?? throw new InvalidOperationException("NativeEventWaiter must be started from a thread with a DispatcherQueue.");
        var t = new Thread(() =>
        {
            var eventHandles = new WaitHandle[events.Length];

            for (int i = 0; i < events.Length; i++)
            {
                var (eventName, _) = events[i];
                eventHandles[i] = new EventWaitHandle(false, EventResetMode.AutoReset, eventName);
            }

            while (true)
            {
                var index = WaitHandle.WaitAny(eventHandles);
                dispatcherQueue.TryEnqueue(() => events[index].Callback());
            }
        });

        t.IsBackground = true;
        t.Start();
    }
}
