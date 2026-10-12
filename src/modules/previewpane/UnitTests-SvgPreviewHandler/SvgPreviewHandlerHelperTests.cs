// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Globalization;
using System.IO;
using System.Text;

using Common.Utilities;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SvgPreviewHandlerUnitTests
{
    [STATestClass]
    public class SvgPreviewHandlerHelperTests
    {
        [TestMethod]
        public void CheckBlockedElementsShouldReturnTrueIfABlockedElementIsPresent()
        {
            // Arrange
            var svgBuilder = new StringBuilder();
            svgBuilder.AppendLine("<svg width =\"200\" height=\"200\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">");
            svgBuilder.AppendLine("\t<script>alert(\"hello\")</script>");
            svgBuilder.AppendLine("</svg>");
            bool foundFilteredElement;

            // Act
            foundFilteredElement = SvgPreviewHandlerHelper.CheckBlockedElements(svgBuilder.ToString());

            // Assert
            Assert.IsTrue(foundFilteredElement);
        }

        [TestMethod]
        public void CheckBlockedElementsShouldReturnTrueIfBlockedElementsIsPresentInNestedLevel()
        {
            // Arrange
            var svgBuilder = new StringBuilder();
            svgBuilder.AppendLine("<svg viewBox=\"0 0 100 100\" xmlns=\"http://www.w3.org/2000/svg\">");
            svgBuilder.AppendLine("\t<circle cx=\"50\" cy=\"50\" r=\"50\">");
            svgBuilder.AppendLine("\t\t<script>alert(\"valid-message\")</script>");
            svgBuilder.AppendLine("\t</circle>");
            svgBuilder.AppendLine("</svg>");
            bool foundFilteredElement;

            // Act
            foundFilteredElement = SvgPreviewHandlerHelper.CheckBlockedElements(svgBuilder.ToString());

            // Assert
            Assert.IsTrue(foundFilteredElement);
        }

        [TestMethod]
        public void CheckBlockedElementsShouldReturnTrueIfMultipleBlockedElementsArePresent()
        {
            // Arrange
            var svgBuilder = new StringBuilder();
            svgBuilder.AppendLine("<svg width =\"200\" height=\"200\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">");
            svgBuilder.AppendLine("\t<script>alert(\"valid-message\")</script>");
            svgBuilder.AppendLine("\t<image href=\"valid-url\" height=\"200\" width=\"200\"/>");
            svgBuilder.AppendLine("</svg>");
            bool foundFilteredElement;

            // Act
            foundFilteredElement = SvgPreviewHandlerHelper.CheckBlockedElements(svgBuilder.ToString());

            // Assert
            Assert.IsTrue(foundFilteredElement);
        }

        [TestMethod]
        public void CheckBlockedElementsShouldReturnFalseIfNoBlockedElementsArePresent()
        {
            // Arrange
            var svgBuilder = new StringBuilder();
            svgBuilder.AppendLine("<svg viewBox=\"0 0 100 100\" xmlns=\"http://www.w3.org/2000/svg\">");
            svgBuilder.AppendLine("\t<circle cx=\"50\" cy=\"50\" r=\"50\">");
            svgBuilder.AppendLine("\t</circle>");
            svgBuilder.AppendLine("</svg>");
            bool foundFilteredElement;

            // Act
            foundFilteredElement = SvgPreviewHandlerHelper.CheckBlockedElements(svgBuilder.ToString());

            // Assert
            Assert.IsFalse(foundFilteredElement);
        }

        [DataTestMethod]
        [DataRow("")]
        [DataRow("  ")]
        [DataRow(null)]
        public void CheckBlockedElementsShouldReturnFalseIfSvgDataIsNullOrWhiteSpaces(string svgData)
        {
            // Arrange
            bool foundFilteredElement;

            // Act
            foundFilteredElement = SvgPreviewHandlerHelper.CheckBlockedElements(svgData);

            // Assert
            Assert.IsFalse(foundFilteredElement);
        }

        [TestMethod]
        public void BuildCacheKeyShouldReturnSameValueForSameInputs()
        {
            // Arrange
            var firstKey = SvgPreviewCacheHelper.BuildCacheKey("v1", "svg-preview", "sample data");

            // Act
            var secondKey = SvgPreviewCacheHelper.BuildCacheKey("v1", "svg-preview", "sample data");

            // Assert
            Assert.AreEqual(firstKey, secondKey);
        }

        [TestMethod]
        public void BuildCacheKeyShouldReturnDifferentValueForDifferentInputs()
        {
            // Arrange
            var firstKey = SvgPreviewCacheHelper.BuildCacheKey("v1", "svg-preview", "sample data");

            // Act
            var secondKey = SvgPreviewCacheHelper.BuildCacheKey("v1", "svg-preview", "different data");

            // Assert
            Assert.AreNotEqual(firstKey, secondKey);
        }

        [TestMethod]
        public void BuildCacheKeyShouldNotCollideForAmbiguousDelimiterInputs()
        {
            // Arrange - two different input tuples that would produce the same byte stream if inputs
            // were joined by a delimiter without length-prefixing.
            var firstKey = SvgPreviewCacheHelper.BuildCacheKey("a\nb", string.Empty);

            // Act
            var secondKey = SvgPreviewCacheHelper.BuildCacheKey("a", "b\n");

            // Assert
            Assert.AreNotEqual(firstKey, secondKey);
        }

        [TestMethod]
        public void CanNavigateToStringShouldUseUtf8ByteCount()
        {
            Assert.IsTrue(SvgPreviewCacheHelper.CanNavigateToString(new string('a', 1_500_000)));
            Assert.IsFalse(SvgPreviewCacheHelper.CanNavigateToString(new string('漢', 500_001)));
        }

        [TestMethod]
        public void TryWriteTemporaryFileShouldWriteContent()
        {
            var folder = Path.Combine(Path.GetTempPath(), "SvgCacheTest_" + Path.GetRandomFileName());
            string filePath = string.Empty;
            try
            {
                var result = SvgPreviewCacheHelper.TryWriteTemporaryFile(folder, "content", out filePath);

                Assert.IsTrue(result);
                Assert.AreEqual("content", File.ReadAllText(filePath));
            }
            finally
            {
                SvgPreviewCacheHelper.DeleteFileBestEffort(filePath);
                DeleteDirectoryBestEffort(folder);
            }
        }

        [TestMethod]
        public void WriteCacheFileAtomicShouldWriteContentAndReturnTrue()
        {
            var folder = Path.Combine(Path.GetTempPath(), "SvgCacheTest_" + Path.GetRandomFileName());
            try
            {
                var filePath = SvgPreviewCacheHelper.GetCacheFilePath(folder, "key1");

                var result = SvgPreviewCacheHelper.WriteCacheFileAtomic(filePath, "<html>content</html>");

                Assert.IsTrue(result);
                Assert.IsTrue(File.Exists(filePath));
                Assert.AreEqual("<html>content</html>", File.ReadAllText(filePath));
            }
            finally
            {
                DeleteDirectoryBestEffort(folder);
            }
        }

        [TestMethod]
        public void WriteCacheFileAtomicShouldOverwriteExistingEntry()
        {
            var folder = Path.Combine(Path.GetTempPath(), "SvgCacheTest_" + Path.GetRandomFileName());
            try
            {
                var filePath = SvgPreviewCacheHelper.GetCacheFilePath(folder, "key1");

                SvgPreviewCacheHelper.WriteCacheFileAtomic(filePath, "first");
                SvgPreviewCacheHelper.WriteCacheFileAtomic(filePath, "second");

                Assert.AreEqual("second", File.ReadAllText(filePath));
            }
            finally
            {
                DeleteDirectoryBestEffort(folder);
            }
        }

        [TestMethod]
        public void WriteCacheFileAtomicShouldReturnFalseWhenDirectoryCannotBeCreated()
        {
            var folder = Path.Combine(Path.GetTempPath(), "SvgCacheTest_" + Path.GetRandomFileName());
            try
            {
                File.WriteAllText(folder, "not a directory");
                var filePath = SvgPreviewCacheHelper.GetCacheFilePath(folder, "key1");

                var result = SvgPreviewCacheHelper.WriteCacheFileAtomic(filePath, "content");

                Assert.IsFalse(result);
            }
            finally
            {
                File.Delete(folder);
            }
        }

        [TestMethod]
        public void WriteCacheFileAtomicShouldEvictOldEntriesBeyondLimit()
        {
            var folder = Path.Combine(Path.GetTempPath(), "SvgCacheTest_" + Path.GetRandomFileName());
            try
            {
                for (int i = 0; i < 210; i++)
                {
                    var filePath = SvgPreviewCacheHelper.GetCacheFilePath(folder, "key" + i.ToString(CultureInfo.InvariantCulture));
                    SvgPreviewCacheHelper.WriteCacheFileAtomic(filePath, "content" + i.ToString(CultureInfo.InvariantCulture));
                }

                var remaining = Directory.GetFiles(folder, "*.html").Length;
                Assert.IsTrue(remaining <= 200, "Expected at most 200 cached files after eviction, found " + remaining.ToString(CultureInfo.InvariantCulture) + ".");
            }
            finally
            {
                DeleteDirectoryBestEffort(folder);
            }
        }

        private static void DeleteDirectoryBestEffort(string folder)
        {
            try
            {
                if (Directory.Exists(folder))
                {
                    Directory.Delete(folder, true);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}
