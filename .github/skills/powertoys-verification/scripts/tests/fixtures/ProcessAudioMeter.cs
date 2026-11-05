// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license. See LICENSE.txt in the skill directory.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

public sealed class PtProcessAudioMeter : IDisposable
{
    public sealed class Observation
    {
        public int ProcessId;
        public long ProcessStartTicks;
        public string StartedUtc;
        public string EndedUtc;
        public string EndpointFingerprint;
        public string Error;
        public int Polls;
        public int AttributedSamples;
        public int AmbiguousAttributions;
        public float InitialPeak;
        public float MaxPeak;
        public float MinimumEndpointVolume = 1;
        public float MinimumSessionVolume = 1;
        public bool Muted;
        public bool Completed;
    }

    private readonly Observation result = new Observation();
    private readonly ManualResetEvent ready = new ManualResetEvent(false);
    private readonly Thread thread;
    private volatile bool stop;
    private readonly int duration;

    public PtProcessAudioMeter(int processId, long processStartTicks, int milliseconds)
    {
        if (processId <= 0 || processStartTicks <= 0 || milliseconds < 500 || milliseconds > 5000)
        {
            throw new ArgumentException("Supply an exact process identity and a 500..5000 ms observation.");
        }

        result.ProcessId = processId;
        result.ProcessStartTicks = processStartTicks;
        duration = milliseconds;
        thread = new Thread(Collect) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
        if (!ready.WaitOne(3000))
        {
            Dispose();
            throw new TimeoutException("Audio observer did not become ready.");
        }

        if (result.Error != null || result.InitialPeak != 0)
        {
            Dispose();
            throw new InvalidOperationException(result.Error ?? "Owned audio was not initially silent.");
        }
    }

    public Observation Finish()
    {
        if (!thread.Join(6500)) { throw new TimeoutException("Audio observer did not finish."); }
        return result;
    }

    public void Dispose()
    {
        stop = true;
        if (!thread.Join(6500)) { throw new TimeoutException("Audio observer did not stop."); }
        ready.Dispose();
    }

    private void CheckIdentity()
    {
        using (var process = Process.GetProcessById(result.ProcessId))
        {
            if (process.StartTime.ToUniversalTime().Ticks != result.ProcessStartTicks)
            {
                throw new InvalidOperationException("Audio process identity changed.");
            }
        }
    }

    private void Collect()
    {
        object instance = null;
        var owned = new List<IntPtr>();
        try
        {
            CheckIdentity();
            instance = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")));
            IntPtr unknown = Marshal.GetIUnknownForObject(instance);
            owned.Add(unknown);
            IntPtr enumerator = Query(unknown, "A95664D2-9614-4F35-A746-DE8DB63617E6");
            owned.Add(enumerator);
            IntPtr devices;
            Check(Method<Enumerate>(enumerator, 3)(enumerator, 0, 1, out devices));
            owned.Add(devices);
            int count;
            Check(Method<Integer>(devices, 3)(devices, out count));
            if (count < 1 || count > 64) { throw new InvalidOperationException("No bounded active render endpoint set."); }
            var managers = new List<IntPtr>();
            var volumes = new List<IntPtr>();
            var ids = new List<string>();
            for (int i = 0; i < count; i++)
            {
                IntPtr device;
                Check(Method<Item>(devices, 4)(devices, i, out device));
                owned.Add(device);
                IntPtr id;
                Check(Method<Pointer>(device, 5)(device, out id));
                try { ids.Add(Marshal.PtrToStringUni(id)); }
                finally { Marshal.FreeCoTaskMem(id); }
                IntPtr manager = ActivateInterface(device, "77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
                managers.Add(manager); owned.Add(manager);
                IntPtr volume = ActivateInterface(device, "5CDF2C82-841E-4546-9722-0CF74078229A");
                volumes.Add(volume); owned.Add(volume);
            }

            ids.Sort(StringComparer.Ordinal);
            using (var hash = SHA256.Create())
            {
                result.EndpointFingerprint = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(string.Join("\n", ids)))).Replace("-", string.Empty);
            }
            result.StartedUtc = DateTime.UtcNow.ToString("o");
            var clock = Stopwatch.StartNew();
            do
            {
                CheckIdentity();
                float peak = 0;
                foreach (IntPtr volume in volumes)
                {
                    float scalar; int muted;
                    Check(Method<Scalar>(volume, 9)(volume, out scalar));
                    Check(Method<Integer>(volume, 15)(volume, out muted));
                    result.MinimumEndpointVolume = Math.Min(result.MinimumEndpointVolume, scalar);
                    result.Muted |= muted != 0;
                }

                foreach (IntPtr manager in managers) { peak = Math.Max(peak, ReadSessions(manager)); }
                if (result.Polls == 0) { result.InitialPeak = peak; }
                result.MaxPeak = Math.Max(result.MaxPeak, peak);
                result.Polls++;
                ready.Set();
                Thread.Sleep(20);
            }
            while (!stop && clock.ElapsedMilliseconds < duration);
            CheckIdentity();
            IntPtr finalDevices;
            Check(Method<Enumerate>(enumerator, 3)(enumerator, 0, 1, out finalDevices));
            try
            {
                int finalCount;
                Check(Method<Integer>(finalDevices, 3)(finalDevices, out finalCount));
                if (finalCount != count) { throw new InvalidOperationException("Render endpoint set changed."); }
                var finalIds = new List<string>();
                for (int i = 0; i < finalCount; i++)
                {
                    IntPtr device;
                    Check(Method<Item>(finalDevices, 4)(finalDevices, i, out device));
                    try
                    {
                        IntPtr id;
                        Check(Method<Pointer>(device, 5)(device, out id));
                        try { finalIds.Add(Marshal.PtrToStringUni(id)); }
                        finally { Marshal.FreeCoTaskMem(id); }
                    }
                    finally { Marshal.Release(device); }
                }

                finalIds.Sort(StringComparer.Ordinal);
                if (string.Join("\n", ids) != string.Join("\n", finalIds)) { throw new InvalidOperationException("Render endpoint identity changed."); }
            }
            finally { Marshal.Release(finalDevices); }
            result.Completed = !stop;
        }
        catch (Exception error) { result.Error = error.Message; }
        finally
        {
            result.EndedUtc = DateTime.UtcNow.ToString("o");
            for (int i = owned.Count - 1; i >= 0; i--) { if (owned[i] != IntPtr.Zero) { Marshal.Release(owned[i]); } }
            if (instance != null) { Marshal.FinalReleaseComObject(instance); }
            ready.Set();
        }
    }

    private float ReadSessions(IntPtr manager)
    {
        IntPtr sessions;
        Check(Method<Pointer>(manager, 5)(manager, out sessions));
        float peak = 0;
        try
        {
            int count;
            Check(Method<Integer>(sessions, 3)(sessions, out count));
            if (count < 0 || count > 1024) { throw new InvalidOperationException("Unbounded audio session enumeration."); }
            for (int i = 0; i < count; i++)
            {
                IntPtr control = IntPtr.Zero, control2 = IntPtr.Zero, meter = IntPtr.Zero, volume = IntPtr.Zero;
                try
                {
                    Check(Method<Item>(sessions, 4)(sessions, i, out control));
                    control2 = Query(control, "BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D");
                    int processId;
                    int attribution = Method<Integer>(control2, 14)(control2, out processId);
                    Check(attribution);
                    if (processId != result.ProcessId) { continue; }
                    // A non-S_OK process result or a system-sounds session is not exclusive attribution.
                    if (attribution != 0 || Method<Status>(control2, 15)(control2) != 1)
                    {
                        result.AmbiguousAttributions++;
                        continue;
                    }

                    meter = Query(control, "C02216F6-8C67-4B5B-9D00-D008E73E0064");
                    volume = Query(control, "87CE5498-68D6-44E5-9215-6DA47EF883D8");
                    float sample, scalar; int muted;
                    Check(Method<Scalar>(meter, 3)(meter, out sample));
                    Check(Method<Scalar>(volume, 4)(volume, out scalar));
                    Check(Method<Integer>(volume, 6)(volume, out muted));
                    if (float.IsNaN(sample) || sample < 0 || sample > 1) { throw new InvalidOperationException("Invalid audio peak."); }
                    result.MinimumSessionVolume = Math.Min(result.MinimumSessionVolume, scalar);
                    result.Muted |= muted != 0;
                    result.AttributedSamples++;
                    peak = Math.Max(peak, sample);
                }
                finally
                {
                    foreach (IntPtr p in new[] { volume, meter, control2, control }) { if (p != IntPtr.Zero) { Marshal.Release(p); } }
                }
            }
        }
        finally { Marshal.Release(sessions); }
        return peak;
    }

    private static void Check(int result) { Marshal.ThrowExceptionForHR(result); }
    private static IntPtr Query(IntPtr value, string interfaceId)
    {
        Guid iid = new Guid(interfaceId); IntPtr result;
        Check(Method<QueryInterfaceCall>(value, 0)(value, ref iid, out result));
        return result;
    }
    private static IntPtr ActivateInterface(IntPtr device, string interfaceId)
    {
        Guid iid = new Guid(interfaceId); IntPtr result;
        Check(Method<Activate>(device, 3)(device, ref iid, 23, IntPtr.Zero, out result));
        return result;
    }
    private static T Method<T>(IntPtr p, int slot) where T : class
    {
        return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(p), slot * IntPtr.Size), typeof(T));
    }
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Enumerate(IntPtr self, int flow, uint state, out IntPtr collection);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Item(IntPtr self, int index, out IntPtr item);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Integer(IntPtr self, out int value);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Scalar(IntPtr self, out float value);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Pointer(IntPtr self, out IntPtr value);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Status(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int QueryInterfaceCall(IntPtr self, ref Guid iid, out IntPtr instance);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Activate(IntPtr self, ref Guid iid, uint context, IntPtr parameters, out IntPtr instance);
}
