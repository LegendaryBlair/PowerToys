// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using ImageResizer.Helpers;
using Microsoft.VisualStudio.TestTools.UnitTesting;

[assembly: DoNotParallelize]

namespace ImageResizer.Test
{
    [TestClass]
    public sealed class TestEnvironment
    {
        [AssemblyInitialize]
        public static void Initialize(TestContext context)
        {
            // The test executable owns this resource provider for its entire lifetime.
            ResourceLoaderInstance.GetString = key => key;
        }

        [AssemblyCleanup]
        public static void Cleanup()
        {
            ResourceLoaderInstance.GetString = null;
        }
    }
}
