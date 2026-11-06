// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using ImageResizer.Models;
using ImageResizer.Properties;
using ImageResizer.Test;
using ImageResizer.Views;
using Microsoft.UI.Dispatching;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ImageResizer.ViewModels
{
    [TestClass]
    [TestCategory("Functional")]
    public sealed class ResizeWorkflowTests
    {
        private const string WorkspaceVariable = "POWERTOYS_IMAGERESIZER_WORKFLOW_TEST_DIRECTORY";
        private static readonly string[] OutputStems = { "first", "second" };

        [TestMethod]
        public Task ConfirmedOptionsDriveOutputBeforeClosing()
            => RunIsolatedAsync(nameof(ConfirmedOptionsDriveOutputBeforeClosing), includeCorruptImage: false);

        [TestMethod]
        public Task MixedBatchKeepsOutputAndShowsErrors()
            => RunIsolatedAsync(nameof(MixedBatchKeepsOutputAndShowsErrors), includeCorruptImage: true);

        private static async Task RunIsolatedAsync(string testName, bool includeCorruptImage)
        {
            var childWorkspace = Environment.GetEnvironmentVariable(WorkspaceVariable);
            if (!string.IsNullOrEmpty(childWorkspace))
            {
                await RunOnDispatcherAsync(() => VerifyWorkflowAsync(childWorkspace, includeCorruptImage));
                return;
            }

            // Settings.Default, its watcher and App events live until this child exits.
            using var workspace = new TestDirectory();
            var results = Path.Combine(workspace, "results");
            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(AppContext.BaseDirectory, "ImageResizer.Test.exe"),
                WorkingDirectory = AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            startInfo.Environment[WorkspaceVariable] = workspace;
            foreach (var argument in new[]
            {
                "--filter", $"FullyQualifiedName={typeof(ResizeWorkflowTests).FullName}.{testName}",
                "--report-trx", "--report-trx-filename", "workflow.trx",
                "--results-directory", results, "--timeout", "30s",
            })
            {
                startInfo.ArgumentList.Add(argument);
            }

            using var child = Process.Start(startInfo);
            var output = child.StandardOutput.ReadToEndAsync();
            var error = child.StandardError.ReadToEndAsync();
            try
            {
                await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(45));
                Assert.AreEqual(0, child.ExitCode, $"{await output}\n{await error}");
                var report = XDocument.Load(Path.Combine(results, "workflow.trx"));
                var counters = report.Descendants().Single(element => element.Name.LocalName == "Counters");
                Assert.AreEqual("1", counters.Attribute("total")?.Value);
                Assert.AreEqual("1", counters.Attribute("executed")?.Value);
                Assert.AreEqual("1", counters.Attribute("passed")?.Value);
                var result = report.Descendants().Single(element => element.Name.LocalName == "UnitTestResult");
                Assert.AreEqual(testName, result.Attribute("testName")?.Value);
            }
            finally
            {
                if (!child.HasExited)
                {
                    child.Kill(entireProcessTree: true);
                    await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
                }
            }
        }

        private static async Task RunOnDispatcherAsync(Func<Task> action)
        {
            var controller = DispatcherQueueController.CreateOnDedicatedThread();
            var completed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            try
            {
                Assert.IsTrue(controller.DispatcherQueue.TryEnqueue(async () =>
                {
                    SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(controller.DispatcherQueue));
                    try
                    {
                        Settings.InitializeDispatcher();
                        await action();
                        completed.SetResult();
                    }
                    catch (Exception ex)
                    {
                        completed.SetException(ex);
                    }
                }));
                await completed.Task.WaitAsync(TimeSpan.FromSeconds(20));
            }
            finally
            {
                await controller.ShutdownQueueAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
            }
        }

        private static async Task VerifyWorkflowAsync(string workspace, bool includeCorruptImage)
        {
            Settings.SettingsPath = Path.Combine(workspace, "settings.json");

            // Filename is configured outside the resize dialog, before this application session.
            new Settings { FileName = "%1_confirmed_%5x%6" }.Save();
            var settings = Settings.Default;
            var initialSettings = File.ReadAllText(Settings.SettingsPath);
            var first = Path.Combine(workspace, "first.png");
            var second = Path.Combine(workspace, includeCorruptImage ? "broken.png" : "second.png");
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Test.png"), first);
            if (includeCorruptImage)
            {
                File.WriteAllText(second, "not an image");
            }
            else
            {
                File.Copy(Path.Combine(AppContext.BaseDirectory, "Test.png"), second);
            }

            var originals = new[] { first, second }.ToDictionary(path => path, File.ReadAllBytes);
            var outputDirectory = Path.Combine(workspace, "output");
            var batch = new ResizeBatch { DestinationDirectory = outputDirectory };
            batch.Files.Add(first);
            batch.Files.Add(second);
            var expectedOutputs = OutputStems.Take(includeCorruptImage ? 1 : 2)
                .Select(name => Path.Combine(outputDirectory, $"{name}_confirmed_60x90.png"))
                .ToArray();
            var view = new RecordingView(() =>
            {
                var actualOutputs = Directory.GetFiles(outputDirectory);
                CollectionAssert.AreEquivalent(expectedOutputs, actualOutputs, $"Actual outputs at close: {string.Join(", ", actualOutputs)}");
                foreach (var path in expectedOutputs)
                {
                    using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.None);
                    Assert.IsTrue(stream.Length > 0, "Output must be written and closed before requesting window closure.");
                }
            });
            var main = new MainViewModel(batch, settings);
            await main.LoadCommand.ExecuteAsync(view);
            Assert.IsInstanceOfType<InputViewModel>(main.CurrentPage);
            var input = (InputViewModel)main.CurrentPage;
            input.Settings.CustomSize.Fit = ResizeFit.Stretch;
            input.Settings.CustomSize.Unit = ResizeUnit.Pixel;
            input.Settings.CustomSize.Width = 60;
            input.Settings.CustomSize.Height = 90;
            input.Settings.SelectedSize = input.Settings.CustomSize;
            input.Settings.IgnoreOrientation = false;
            input.Settings.Replace = false;

            Assert.AreEqual(initialSettings, File.ReadAllText(Settings.SettingsPath), "Editing alone must not replace the persisted confirmation.");
            var progressTransitions = 0;
            main.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName == nameof(MainViewModel.CurrentPage) && main.CurrentPage is ProgressViewModel)
                {
                    progressTransitions++;
                    var persisted = new Settings();
                    persisted.Reload();
                    Assert.AreEqual(60d, persisted.SelectedSize.Width);
                    Assert.AreEqual(90d, persisted.SelectedSize.Height);
                    Assert.AreEqual(ResizeFit.Stretch, persisted.SelectedSize.Fit);
                    Assert.AreEqual(ResizeUnit.Pixel, persisted.SelectedSize.Unit);
                    Assert.IsFalse(persisted.IgnoreOrientation);
                    Assert.IsFalse(persisted.Replace);
                    Assert.AreEqual("%1_confirmed_%5x%6", persisted.FileName);
                }
            };

            Assert.IsTrue(input.ResizeCommand.CanExecute(null));
            input.ResizeCommand.Execute(null);
            Assert.AreEqual(1, progressTransitions, "Confirmation must notify the view to enter the processing stage.");
            Assert.IsInstanceOfType<ProgressViewModel>(main.CurrentPage);
            Assert.IsFalse(Directory.Exists(outputDirectory), "Confirmation should leave processing to the progress-page start command.");
            Assert.AreEqual(0, view.CloseCount);
            using var progress = (ProgressViewModel)main.CurrentPage;

            // The real page's Loaded event invokes this command; XAML wiring remains E2E.
            await progress.StartCommand.ExecuteAsync(null);

            var actualOutputs = Directory.GetFiles(outputDirectory);
            CollectionAssert.AreEquivalent(expectedOutputs, actualOutputs, $"Actual outputs after processing: {string.Join(", ", actualOutputs)}");
            foreach (var path in expectedOutputs)
            {
                await AssertEx.ImageAsync(path, decoder =>
                {
                    Assert.AreEqual(60u, decoder.PixelWidth);
                    Assert.AreEqual(90u, decoder.PixelHeight);
                });
            }

            foreach (var (path, contents) in originals)
            {
                CollectionAssert.AreEqual(contents, File.ReadAllBytes(path));
            }

            if (includeCorruptImage)
            {
                Assert.AreEqual(0, view.CloseCount, "A partial failure must remain available for the user to inspect.");
                Assert.IsInstanceOfType<ResultsViewModel>(main.CurrentPage);
                var results = (ResultsViewModel)main.CurrentPage;
                Assert.AreEqual("broken.png", results.Errors.Single().File);
                results.CloseCommand.Execute(null);
            }

            Assert.AreEqual(1, view.CloseCount);
        }

        private sealed class RecordingView(Action onClose) : IMainView
        {
            public int CloseCount { get; private set; }

            public Task<IEnumerable<string>> OpenPictureFilesAsync()
                => throw new AssertFailedException("The selected batch must not be replaced by a file-picker request.");

            public void Close()
            {
                onClose();
                CloseCount++;
            }
        }
    }
}
