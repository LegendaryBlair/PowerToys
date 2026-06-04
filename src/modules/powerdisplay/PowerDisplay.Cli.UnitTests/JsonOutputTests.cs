// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System.IO;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PowerDisplay.Cli.Errors;
using PowerDisplay.Cli.Output;

namespace PowerDisplay.Cli.UnitTests;

[TestClass]
public class JsonOutputTests
{
    [TestMethod]
    public void SetResult_HasVersionAndCamelCaseKeys_OnStdout()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var json = new JsonCliOutput(stdout, stderr);

        json.WriteSetResult(new CliSetResult
        {
            Monitor = new CliMonitorRef { Number = 1, Id = "A", Name = "Dell", Method = "DDC/CI" },
            Setting = "brightness",
            BeforeRaw = 30,
            AfterRaw = 50,
            BeforeDisplay = "30%",
            AfterDisplay = "50%",
        });

        var doc = JsonDocument.Parse(stdout.ToString());
        Assert.AreEqual("1.0", doc.RootElement.GetProperty("version").GetString());
        Assert.AreEqual("set", doc.RootElement.GetProperty("command").GetString());
        Assert.AreEqual(50, doc.RootElement.GetProperty("afterRaw").GetInt32());
        Assert.AreEqual(string.Empty, stderr.ToString());
    }

    [TestMethod]
    public void ErrorResult_GoesToStderr_NotStdout()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var json = new JsonCliOutput(stdout, stderr);

        json.WriteError(new CliErrorResult
        {
            Command = "set",
            Error = new CliError { Code = CliErrorCodes.OutOfRange, ExitCode = CliExitCodes.OutOfRange, Message = "x" },
        });

        Assert.AreEqual(string.Empty, stdout.ToString());
        var doc = JsonDocument.Parse(stderr.ToString());
        Assert.IsFalse(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.AreEqual("OUT_OF_RANGE", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
    }

    [TestMethod]
    public void SetResult_NullBefore_IsOmitted()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var json = new JsonCliOutput(stdout, stderr);

        json.WriteSetResult(new CliSetResult
        {
            Monitor = new CliMonitorRef { Number = 1, Id = "A", Name = "Dell", Method = "DDC/CI" },
            Setting = "brightness",
            BeforeRaw = null,
            AfterRaw = 50,
            BeforeDisplay = null,
            AfterDisplay = "50%",
        });

        var doc = JsonDocument.Parse(stdout.ToString());
        Assert.IsFalse(doc.RootElement.TryGetProperty("beforeRaw", out _));
        Assert.IsFalse(doc.RootElement.TryGetProperty("beforeDisplay", out _));
    }
}
