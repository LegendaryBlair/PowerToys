// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using ImageResizer.Helpers;
using ImageResizer.Models;

namespace ImageResizer.Test
{
    internal static class SelectionReceiver
    {
        internal const string OutputPathVariable = "POWERTOYS_IMAGERESIZER_TEST_RECEIVER_OUTPUT";

        private static Task<int> Main(string[] args)
        {
            var outputPath = Environment.GetEnvironmentVariable(OutputPathVariable);
            if (string.IsNullOrEmpty(outputPath))
            {
                return TestingPlatformEntryPoint.Main(args);
            }

            // Only the native fixture's child enters this mode; normal launches run MSTest.
            try
            {
                ResourceLoaderInstance.GetString = key => key;
                Console.InputEncoding = Encoding.Unicode;
                var batch = ResizeBatch.FromCommandLine(Console.In, Environment.GetCommandLineArgs());
                File.WriteAllText(outputPath, JsonSerializer.Serialize(new
                {
                    batch.Files,
                    batch.DestinationDirectory,
                    Console.IsInputRedirected,
                }));
                return Task.FromResult(0);
            }
            catch (Exception ex)
            {
                File.WriteAllText(outputPath, JsonSerializer.Serialize(new { Error = ex.ToString() }));
                return Task.FromResult(1);
            }
        }
    }
}
