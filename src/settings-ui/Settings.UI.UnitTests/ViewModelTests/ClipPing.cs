// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO.Abstractions;
using System.Text.Json;

using Microsoft.PowerToys.Settings.UI.Library;
using Microsoft.PowerToys.Settings.UI.Library.Enumerations;
using Microsoft.PowerToys.Settings.UI.UnitTests.BackwardsCompatibility;
using Microsoft.PowerToys.Settings.UI.ViewModels;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;

namespace ViewModelTests
{
    [TestClass]
    public class ClipPing
    {
        private Mock<SettingsUtils> _settingsUtilsMock;
        private GeneralSettings _generalSettings;
        private ClipPingSettings _clipPingSettings;

        [TestInitialize]
        public void SetUp()
        {
            _settingsUtilsMock = new Mock<SettingsUtils>(new FileSystem(), null);
            _generalSettings = new GeneralSettings();
            _generalSettings.Enabled.ClipPing = false;
            _clipPingSettings = new ClipPingSettings();
        }

        [TestMethod]
        public void IsEnabled_WhenChanged_ShouldUpdateGeneralSettingsAndSendIpc()
        {
            var ipcInvoked = false;
            var viewModel = CreateViewModel(msg =>
            {
                var outgoingSettings = JsonSerializer.Deserialize<OutGoingGeneralSettings>(msg);
                Assert.IsNotNull(outgoingSettings);
                Assert.IsTrue(outgoingSettings.GeneralSettings.Enabled.ClipPing);
                ipcInvoked = true;
                return 0;
            });

            viewModel.IsEnabled = true;

            Assert.IsTrue(_generalSettings.Enabled.ClipPing);
            Assert.IsTrue(ipcInvoked);
        }

        [TestMethod]
        public void OverlayColor_WhenChanged_ShouldPersistClipPingSettings()
        {
            var viewModel = CreateViewModel();

            viewModel.OverlayColor = "#123456";

            Assert.AreEqual("#123456", viewModel.OverlayColor);
            _settingsUtilsMock.Verify(
                x => x.SaveSettings(
                    It.Is<string>(json => JsonSerializer.Deserialize<ClipPingSettings>(json).Properties.OverlayColor.Value == "#123456"),
                    ClipPingSettings.ModuleName,
                    It.IsAny<string>()),
                Times.Once);
        }

        [TestMethod]
        public void OverlayType_WhenChanged_ShouldPersistClipPingSettings()
        {
            var viewModel = CreateViewModel();

            viewModel.OverlayType = (int)ClipPingOverlay.Border;

            Assert.AreEqual((int)ClipPingOverlay.Border, viewModel.OverlayType);
            _settingsUtilsMock.Verify(
                x => x.SaveSettings(
                    It.Is<string>(json => JsonSerializer.Deserialize<ClipPingSettings>(json).Properties.OverlayType == ClipPingOverlay.Border),
                    ClipPingSettings.ModuleName,
                    It.IsAny<string>()),
                Times.Once);
        }

        private ClipPingViewModel CreateViewModel(Func<string, int> ipcCallback = null)
        {
            var generalSettingsUtils = new Mock<SettingsUtils>(new FileSystem(), null);
            generalSettingsUtils
                .Setup(x => x.GetSettingsOrDefault<GeneralSettings>(It.IsAny<string>(), It.IsAny<string>()))
                .Returns(_generalSettings);

            var clipPingSettingsUtils = new Mock<SettingsUtils>(new FileSystem(), null);
            clipPingSettingsUtils
                .Setup(x => x.GetSettingsOrDefault<ClipPingSettings>(It.IsAny<string>(), It.IsAny<string>()))
                .Returns(_clipPingSettings);

            return new ClipPingViewModel(
                _settingsUtilsMock.Object,
                new BackCompatTestProperties.MockSettingsRepository<GeneralSettings>(generalSettingsUtils.Object),
                new BackCompatTestProperties.MockSettingsRepository<ClipPingSettings>(clipPingSettingsUtils.Object),
                ipcCallback ?? (_ => 0));
        }
    }
}
