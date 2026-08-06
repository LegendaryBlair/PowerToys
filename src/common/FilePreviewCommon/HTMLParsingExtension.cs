// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Runtime.InteropServices;

using Markdig;
using Markdig.Extensions.Figures;
using Markdig.Extensions.Tables;
using Markdig.Renderers;
using Markdig.Renderers.Html;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using Microsoft.Win32.SafeHandles;

namespace Microsoft.PowerToys.FilePreviewCommon
{
    /// <summary>
    /// Callback if extension blocks external images.
    /// </summary>
    public delegate void ImagesBlockedCallBack();

    /// <summary>
    /// Markdig Extension to process html nodes in markdown AST.
    /// </summary>
    public partial class HTMLParsingExtension : IMarkdownExtension
    {
        private const uint GenericRead = 0x80000000;
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint FileReadAttributes = 0x00000080;
        private const uint OpenExisting = 3;
        private const uint FileAttributeNormal = 0x00000080;
        private const uint FileFlagBackupSemantics = 0x02000000;

        /// <summary>
        /// Callback if extension blocks external images.
        /// </summary>
        private readonly ImagesBlockedCallBack imagesBlockedCallBack;

        [LibraryImport("kernel32.dll", EntryPoint = "CreateFileW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
        private static partial SafeFileHandle CreateFileHandle(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            nint securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            nint templateFile);

        [LibraryImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", SetLastError = true)]
        private static unsafe partial uint GetFinalPathNameByHandle(SafeFileHandle fileHandle, char* filePath, uint filePathLength, uint flags);

        /// <summary>
        /// Initializes a new instance of the <see cref="HTMLParsingExtension"/> class.
        /// </summary>
        /// <param name="imagesBlockedCallBack">Callback function if image is blocked by extension.</param>
        /// <param name="filePath">Absolute path of markdown file.</param>
        public HTMLParsingExtension(ImagesBlockedCallBack imagesBlockedCallBack, string filePath = "")
        {
            this.imagesBlockedCallBack = imagesBlockedCallBack;
            FilePath = filePath;
        }

        /// <summary>
        /// Gets or sets path to directory containing markdown file.
        /// </summary>
        public string FilePath { get; set; }

        /// <summary>
        /// Gets or sets the base path used for path validation and relative URL computation.
        /// For local files this equals FilePath. For UNC paths this is the share root.
        /// </summary>
        public string? AllowedBasePath { get; set; }

        /// <summary>
        /// Gets or sets a value indicating whether local images should be rendered.
        /// </summary>
        public bool AllowLocalImages { get; set; }

        private static bool IsLocalImage([NotNullWhen(true)] string? url)
        {
            if (string.IsNullOrEmpty(url))
            {
                return false;
            }

            // Reject any URI-like scheme (http:, https:, data:, javascript:, file:, ...).
            // A colon is only permitted as part of a drive path like "C:\" or "C:/".
            int colonIndex = url.IndexOf(':');
            if (colonIndex >= 0)
            {
                bool isDrivePath = colonIndex == 1 && char.IsLetter(url[0]) && url.Length > 2 && (url[2] == '\\' || url[2] == '/');
                if (!isDrivePath)
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Gets the HTTP content type for a supported image path.
        /// </summary>
        /// <param name="imagePath">Path of the image file.</param>
        /// <param name="contentType">The image content type on success.</param>
        /// <returns>True if the file extension is a supported image type.</returns>
        public static bool TryGetImageContentType(string? imagePath, [NotNullWhen(true)] out string? contentType)
        {
            if (string.IsNullOrEmpty(imagePath))
            {
                contentType = null;
                return false;
            }

            string extension = Path.GetExtension(imagePath);
            contentType = extension.ToUpperInvariant() switch
            {
                ".PNG" => "image/png",
                ".JPG" or ".JPEG" => "image/jpeg",
                ".GIF" => "image/gif",
                ".BMP" => "image/bmp",
                ".WEBP" => "image/webp",
                ".SVG" => "image/svg+xml",
                ".ICO" => "image/x-icon",
                ".TIF" or ".TIFF" => "image/tiff",
                ".AVIF" => "image/avif",
                _ => null,
            };

            return contentType != null;
        }

        /// <summary>
        /// Validates that a local image URL resolves to a path inside the allowed base path and
        /// computes the corresponding virtual host URL. Returns false for remote URLs, URI schemes
        /// (data:, javascript:, file:, ...), path traversal outside the base path and malformed paths.
        /// </summary>
        /// <param name="url">Image URL from the markdown document.</param>
        /// <param name="markdownDirectory">Directory containing the markdown file; relative URLs resolve against it.</param>
        /// <param name="allowedBasePath">Base path the resolved path must be contained in. Falls back to <paramref name="markdownDirectory"/> if empty.</param>
        /// <param name="virtualUrl">The rewritten virtual host URL on success.</param>
        /// <returns>True if the URL is a contained local image and <paramref name="virtualUrl"/> was set.</returns>
        public static bool TryGetLocalImageVirtualUrl(string? url, string markdownDirectory, string? allowedBasePath, [NotNullWhen(true)] out string? virtualUrl)
        {
            virtualUrl = null;

            if (!IsLocalImage(url) || string.IsNullOrEmpty(markdownDirectory))
            {
                return false;
            }

            try
            {
                string effectiveBasePath = string.IsNullOrEmpty(allowedBasePath) ? markdownDirectory : allowedBasePath;
                if (!Path.IsPathFullyQualified(markdownDirectory) || !Path.IsPathFullyQualified(effectiveBasePath))
                {
                    return false;
                }

                string basePath = Path.GetFullPath(effectiveBasePath);
                string decodedUrl = Uri.UnescapeDataString(url);
                string resolvedPath = Path.GetFullPath(Path.Combine(markdownDirectory, decodedUrl));
                if (!TryGetImageContentType(resolvedPath, out _))
                {
                    return false;
                }

                string relativePath = Path.GetRelativePath(basePath, resolvedPath);

                if (relativePath == "." || relativePath == ".." ||
                    relativePath.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
                    relativePath.StartsWith(".." + Path.AltDirectorySeparatorChar, StringComparison.Ordinal) ||
                    Path.IsPathRooted(relativePath))
                {
                    return false;
                }

                string[] pathSegments = relativePath.Replace('\\', '/').Split('/');
                for (int i = 0; i < pathSegments.Length; i++)
                {
                    pathSegments[i] = Uri.EscapeDataString(pathSegments[i]);
                }

                virtualUrl = "https://localmdimages/" + string.Join("/", pathSegments);
                return true;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (PathTooLongException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        /// <summary>
        /// Resolves a virtual host image request URL back to a file path and validates that it is
        /// contained in the allowed base path. Used when serving the image bytes for a WebView2
        /// resource request. Returns false for foreign hosts, empty paths, path traversal outside
        /// the base path (including percent-encoded traversal) and malformed paths.
        /// </summary>
        /// <param name="requestUri">The request URL, expected on the localmdimages virtual host.</param>
        /// <param name="allowedBasePath">Base path the resolved file must be contained in.</param>
        /// <param name="resolvedPath">The validated absolute file path on success.</param>
        /// <returns>True if the URL maps to a contained file path and <paramref name="resolvedPath"/> was set.</returns>
        public static bool TryResolveVirtualUrl(string? requestUri, string? allowedBasePath, [NotNullWhen(true)] out string? resolvedPath)
        {
            resolvedPath = null;

            if (string.IsNullOrEmpty(requestUri) || string.IsNullOrEmpty(allowedBasePath))
            {
                return false;
            }

            try
            {
                var uri = new Uri(requestUri);
                if (uri.Scheme != Uri.UriSchemeHttps ||
                    !string.Equals(uri.Host, "localmdimages", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                string relativePath = Uri.UnescapeDataString(uri.AbsolutePath).TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                if (relativePath.Length == 0)
                {
                    return false;
                }

                string basePath = Path.GetFullPath(allowedBasePath);
                string fullPath = Path.GetFullPath(Path.Combine(basePath, relativePath));
                string containmentCheck = Path.GetRelativePath(basePath, fullPath);

                if (containmentCheck == "." || containmentCheck == ".." ||
                    containmentCheck.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
                    containmentCheck.StartsWith(".." + Path.AltDirectorySeparatorChar, StringComparison.Ordinal) ||
                    Path.IsPathRooted(containmentCheck))
                {
                    return false;
                }

                resolvedPath = fullPath;
                return true;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (UriFormatException)
            {
                return false;
            }
            catch (PathTooLongException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        /// <summary>
        /// Opens a virtual-host image after resolving the final file-system paths for both the
        /// allowed base directory and the image handle. This prevents junctions and symbolic links
        /// inside the allowed tree from redirecting the request outside that tree.
        /// </summary>
        /// <param name="requestUri">The request URL, expected on the localmdimages virtual host.</param>
        /// <param name="allowedBasePath">Base path the resolved file must be contained in.</param>
        /// <param name="imageStream">The opened image stream on success. The caller owns the stream.</param>
        /// <param name="resolvedPath">The final resolved file path on success.</param>
        /// <returns>True if the image was opened and its final path is contained in the final base path.</returns>
        public static bool TryOpenVirtualImage(
            string? requestUri,
            string? allowedBasePath,
            [NotNullWhen(true)] out Stream? imageStream,
            [NotNullWhen(true)] out string? resolvedPath)
        {
            imageStream = null;
            resolvedPath = null;

            if (!TryResolveVirtualUrl(requestUri, allowedBasePath, out string? candidatePath) ||
                string.IsNullOrEmpty(allowedBasePath))
            {
                return false;
            }

            const uint ShareMode = FileShareRead | FileShareWrite | FileShareDelete;
            using SafeFileHandle baseHandle = CreateFileHandle(
                allowedBasePath,
                FileReadAttributes,
                ShareMode,
                0,
                OpenExisting,
                FileFlagBackupSemantics,
                0);

            if (baseHandle.IsInvalid)
            {
                return false;
            }

            SafeFileHandle? imageHandle = null;
            try
            {
                imageHandle = CreateFileHandle(
                    candidatePath,
                    GenericRead,
                    ShareMode,
                    0,
                    OpenExisting,
                    FileAttributeNormal,
                    0);

                if (imageHandle.IsInvalid ||
                    !TryGetFinalPath(baseHandle, out string? finalBasePath) ||
                    !TryGetFinalPath(imageHandle, out string? finalImagePath))
                {
                    return false;
                }

                string containmentCheck = Path.GetRelativePath(finalBasePath, finalImagePath);
                if (containmentCheck == "." || containmentCheck == ".." ||
                    containmentCheck.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
                    containmentCheck.StartsWith(".." + Path.AltDirectorySeparatorChar, StringComparison.Ordinal) ||
                    Path.IsPathRooted(containmentCheck))
                {
                    return false;
                }

                imageStream = new FileStream(imageHandle, FileAccess.Read);
                imageHandle = null;
                resolvedPath = finalImagePath;
                return true;
            }
            catch (PathTooLongException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
            catch (IOException)
            {
                return false;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
            finally
            {
                imageHandle?.Dispose();
            }
        }

        private static unsafe bool TryGetFinalPath(SafeFileHandle fileHandle, [NotNullWhen(true)] out string? finalPath)
        {
            finalPath = null;
            char[] buffer = new char[512];

            uint pathLength;
            fixed (char* bufferPointer = buffer)
            {
                pathLength = GetFinalPathNameByHandle(fileHandle, bufferPointer, (uint)buffer.Length, 0);
            }

            if (pathLength == 0)
            {
                return false;
            }

            if (pathLength >= (uint)buffer.Length)
            {
                buffer = new char[checked((int)pathLength + 1)];
                fixed (char* bufferPointer = buffer)
                {
                    pathLength = GetFinalPathNameByHandle(fileHandle, bufferPointer, (uint)buffer.Length, 0);
                }

                if (pathLength == 0 || pathLength >= (uint)buffer.Length)
                {
                    return false;
                }
            }

            finalPath = new string(buffer, 0, (int)pathLength);
            return true;
        }

        /// <inheritdoc/>
        public void Setup(MarkdownPipelineBuilder pipeline)
        {
            if (pipeline != null)
            {
                // Make sure we don't have a delegate twice
                pipeline.DocumentProcessed -= PipelineOnDocumentProcessed;
                pipeline.DocumentProcessed += PipelineOnDocumentProcessed;
            }
        }

        /// <inheritdoc/>
        public void Setup(MarkdownPipeline pipeline, IMarkdownRenderer renderer)
        {
        }

        /// <summary>
        /// Process nodes in markdown AST.
        /// </summary>
        /// <param name="document">Markdown Document.</param>
        public void PipelineOnDocumentProcessed(MarkdownDocument document)
        {
            foreach (var node in document.Descendants())
            {
                if (node is Block)
                {
                    if (node is Table)
                    {
                        node.GetAttributes().AddClass("table table-striped table-bordered");
                    }
                    else if (node is QuoteBlock)
                    {
                        node.GetAttributes().AddClass("blockquote");
                    }
                    else if (node is Figure)
                    {
                        node.GetAttributes().AddClass("figure");
                    }
                    else if (node is FigureCaption)
                    {
                        node.GetAttributes().AddClass("figure-caption");
                    }
                }
                else if (node is Inline)
                {
                    if (node is LinkInline link)
                    {
                        if (link.IsImage)
                        {
                            if (AllowLocalImages && TryGetLocalImageVirtualUrl(link.Url, FilePath, AllowedBasePath, out string? virtualUrl))
                            {
                                link.Url = virtualUrl;
                                link.GetAttributes().AddClass("img-fluid");
                            }
                            else
                            {
                                link.Url = "#";
                                link.GetAttributes().AddClass("img-fluid");
                                imagesBlockedCallBack();
                            }
                        }
                    }
                }
            }
        }
    }
}
