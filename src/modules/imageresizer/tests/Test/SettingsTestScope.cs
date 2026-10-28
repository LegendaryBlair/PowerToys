// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using ImageResizer.Properties;

namespace ImageResizer.Test
{
    internal sealed class SettingsTestScope : IDisposable
    {
        private readonly TestDirectory _directory = new();
        private readonly string _originalPath = Settings.SettingsPath;

        public SettingsTestScope()
        {
            // An existing directory also prevents Reload from migrating legacy user settings.
            Settings.SettingsPath = Path.Combine(_directory, "settings.json");
        }

        public void Dispose()
        {
            Settings.SettingsPath = _originalPath;
            _directory.Dispose();
        }
    }
}
