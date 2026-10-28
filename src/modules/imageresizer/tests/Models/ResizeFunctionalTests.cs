// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

extern alias SettingsProducer;

using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using ImageResizer.Properties;
using ImageResizer.Test;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Producer = SettingsProducer::Microsoft.PowerToys.Settings.UI.Library;

namespace ImageResizer.Models
{
    [TestClass]
    [TestCategory("Functional")]
    public sealed class ResizeFunctionalTests : IDisposable
    {
        private static readonly string[] ExpectedBatchNames = { "first (Batch).png", "second image (Batch).png" };
        private readonly TestDirectory _directory = new();

        [TestMethod]
        public async Task BatchResizesMultipleImagesWithoutChangingSources()
        {
            var first = CopyImage("first.png");
            var second = CopyImage("second image.png");
            var original = File.ReadAllBytes(first);
            var batch = CreateBatch(first, second);

            var errors = (await batch.ProcessAsync((_, _) => { }, CreateSettings(), CancellationToken.None)).ToList();

            Assert.AreEqual(0, errors.Count);
            CollectionAssert.AreEquivalent(
                ExpectedBatchNames,
                Directory.GetFiles(batch.DestinationDirectory).Select(Path.GetFileName).ToArray());
            foreach (var source in new[] { first, second })
            {
                CollectionAssert.AreEqual(original, File.ReadAllBytes(source));
                var output = Path.Combine(batch.DestinationDirectory, $"{Path.GetFileNameWithoutExtension(source)} (Batch).png");
                await AssertEx.ImageAsync(output, decoder =>
                {
                    Assert.AreEqual(96u, decoder.PixelWidth);
                    Assert.AreEqual(48u, decoder.PixelHeight);
                });
            }
        }

        [TestMethod]
        public async Task BatchKeepsSuccessfulOutputAndReportsCorruptInput()
        {
            var valid = CopyImage("valid.png");
            var original = File.ReadAllBytes(valid);
            var corrupt = Path.Combine(_directory, "corrupt.png");
            File.WriteAllText(corrupt, "not an image");
            var batch = CreateBatch(valid, corrupt);

            var errors = (await batch.ProcessAsync((_, _) => { }, CreateSettings(), CancellationToken.None)).ToList();

            Assert.AreEqual(1, errors.Count);
            Assert.AreEqual("corrupt.png", errors[0].File);
            CollectionAssert.AreEqual(original, File.ReadAllBytes(valid));
            Assert.AreEqual("not an image", File.ReadAllText(corrupt));
            var output = Directory.GetFiles(batch.DestinationDirectory).Single();
            Assert.AreEqual("valid (Batch).png", Path.GetFileName(output));
            await AssertEx.ImageAsync(output, decoder =>
            {
                Assert.AreEqual(96u, decoder.PixelWidth);
                Assert.AreEqual(48u, decoder.PixelHeight);
            });
        }

        [TestMethod]
        public async Task SettingsUiJsonDrivesRealBatchOutput()
        {
            using var settingsScope = new SettingsTestScope();
            var producer = new Producer.ImageResizerSettings(key => key);
            producer.Properties.ImageresizerSizes.Value = new ObservableCollection<Producer.ImageSize>
            {
                new(17, "Web", Producer.ResizeFit.Stretch, 40, 80, Producer.ResizeUnit.Pixel),
            };
            producer.Properties.ImageresizerIgnoreOrientation.Value = false;
            producer.Properties.ImageresizerKeepDateModified.Value = true;
            producer.Properties.ImageresizerFileName.Value = "%1_%2_%5x%6";
            File.WriteAllText(Settings.SettingsPath, producer.ToJsonString());

            var settings = new Settings();
            settings.Reload();
            var source = CopyImage("contract.png");
            var original = File.ReadAllBytes(source);
            var timestamp = new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc);
            File.SetLastWriteTimeUtc(source, timestamp);
            var batch = CreateBatch(source);

            var errors = (await batch.ProcessAsync((_, _) => { }, settings, CancellationToken.None)).ToList();

            Assert.AreEqual(0, errors.Count);
            var output = Directory.GetFiles(batch.DestinationDirectory).Single();
            Assert.AreEqual("contract_Web_40x80.png", Path.GetFileName(output));
            Assert.AreEqual(timestamp, File.GetLastWriteTimeUtc(output));
            CollectionAssert.AreEqual(original, File.ReadAllBytes(source));
            await AssertEx.ImageAsync(output, decoder =>
            {
                Assert.AreEqual(40u, decoder.PixelWidth);
                Assert.AreEqual(80u, decoder.PixelHeight);
            });
        }

        [TestMethod]
        [DataRow(2)]
        [DataRow(128)]
        public async Task ShellSelectionCreatesExpectedPendingBatch(int imageCount)
        {
            var images = Enumerable.Range(0, imageCount)
                .Select(index => CopyImage($"{index:000} selected \u6d4b\u8bd5 \u00e9 \U0001f4f7.png"))
                .ToArray();
            var corrupt = Path.Combine(_directory, "corrupt.png");
            File.WriteAllText(corrupt, "not an image");
            var unsupported = Path.Combine(_directory, "not an image.txt");
            File.WriteAllText(unsupported, "not an image");
            var expectedFiles = images.Append(corrupt).ToArray();
            var selection = expectedFiles.Append(unsupported).ToArray();
            var originals = selection.ToDictionary(path => path, File.ReadAllBytes);
            var pipeName = $@"\\.\pipe\ImageResizerTest-{Guid.NewGuid():N}";
            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(AppContext.BaseDirectory, "ImageResizer.SelectionTestHost.exe"),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            startInfo.ArgumentList.Add(pipeName);
            foreach (var file in selection)
            {
                startInfo.ArgumentList.Add(file);
            }

            using var sender = Process.Start(startInfo);
            try
            {
                var ready = await sender.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10));
                Assert.AreEqual("READY", ready, "The native sender must create its pipe before receiving.");
                var receive = Task.Run(() => ResizeBatch.FromCommandLine(TextReader.Null, new[] { Environment.ProcessPath, pipeName }));
                await Task.WhenAll(receive, sender.WaitForExitAsync()).WaitAsync(TimeSpan.FromSeconds(10));
                Assert.AreEqual(0, sender.ExitCode, await sender.StandardError.ReadToEndAsync());

                var batch = await receive;
                CollectionAssert.AreEquivalent(expectedFiles, batch.Files.ToArray());
                Assert.IsNull(batch.DestinationDirectory);
                CollectionAssert.AreEquivalent(selection, Directory.GetFiles(_directory));
                foreach (var (path, contents) in originals)
                {
                    CollectionAssert.AreEqual(contents, File.ReadAllBytes(path));
                }
            }
            finally
            {
                if (!sender.HasExited)
                {
                    sender.Kill(entireProcessTree: true);
                    await sender.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
                }
            }
        }

        private string CopyImage(string name)
        {
            var path = Path.Combine(_directory, name);
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Test.png"), path);
            return path;
        }

        private ResizeBatch CreateBatch(params string[] files)
        {
            var batch = new ResizeBatch { DestinationDirectory = Path.Combine(_directory, "output") };
            foreach (var file in files)
            {
                batch.Files.Add(file);
            }

            return batch;
        }

        private static Settings CreateSettings()
        {
            var settings = new Settings();
            settings.Sizes.Clear();
            settings.Sizes.Add(new ResizeSize(0, "Batch", ResizeFit.Fit, 96, 96, ResizeUnit.Pixel));
            return settings;
        }

        public void Dispose()
        {
            _directory.Dispose();
        }
    }
}
