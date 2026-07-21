// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace Common.Utilities
{
    internal static class SvgPreviewCacheHelper
    {
        // Upper bound on the number of cached preview files retained on disk before the oldest are evicted.
        private const int MaxCacheEntries = 200;

        internal static string BuildCacheKey(params string[] cacheInputs)
        {
            // Hash incrementally so multi-MB SVG inputs are not first concatenated into one large
            // intermediate string. Each input is length-prefixed so that inputs which themselves contain
            // the delimiter cannot produce an ambiguous byte stream (e.g. ["a\nb", ""] vs ["a", "b\n"]),
            // which would otherwise collide and reuse the wrong cached preview.
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

            foreach (var input in cacheInputs)
            {
                var bytes = Encoding.UTF8.GetBytes(input ?? string.Empty);
                hash.AppendData(BitConverter.GetBytes(bytes.Length));
                hash.AppendData(bytes);
            }

            return Convert.ToHexString(hash.GetHashAndReset());
        }

        internal static string GetCacheFilePath(string cacheRootFolder, string cacheKey)
        {
            // Pure path composition: directory creation is left to WriteCacheFileAtomic so that a failure
            // to create the folder cannot throw here and short-circuit the caller's in-memory fallback.
            return Path.Combine(cacheRootFolder, $"{cacheKey}.html");
        }

        /// <summary>
        /// Writes <paramref name="content"/> to <paramref name="cacheFilePath"/> atomically so that
        /// concurrent Explorer preview/thumbnail instances never observe a partially written or
        /// zero-length cache file. The content is written to a unique temp file and then moved into place.
        /// After a successful write the cache folder is trimmed to <see cref="MaxCacheEntries"/> entries.
        /// </summary>
        /// <returns><c>true</c> if the cache file exists and is non-empty after the call; otherwise <c>false</c>
        /// so the caller can fall back to rendering the content in-memory instead of navigating a missing file.</returns>
        internal static bool WriteCacheFileAtomic(string cacheFilePath, string content)
        {
            var directory = Path.GetDirectoryName(cacheFilePath);
            if (string.IsNullOrEmpty(directory))
            {
                return false;
            }

            Directory.CreateDirectory(directory);

            var tempFilePath = Path.Combine(directory, $"{Guid.NewGuid():N}.tmp");

            try
            {
                File.WriteAllText(tempFilePath, content);
                File.Move(tempFilePath, cacheFilePath, overwrite: true);
            }
            catch (Exception)
            {
                // Any failure (IO contention, access denied, path too long, ...) must not leave a temp file
                // behind and must let the caller fall back to in-memory rendering, so swallow, clean up,
                // and report success via the file-existence check below.
                TryDelete(tempFilePath);
            }

            EvictOldEntries(directory, cacheFilePath);

            return CacheFileIsUsable(cacheFilePath);
        }

        /// <summary>
        /// Returns whether the cache file exists and is non-empty, never throwing (a deleted/evicted file
        /// between checks must not surface as an exception that aborts the preview/thumbnail).
        /// </summary>
        internal static bool CacheFileIsUsable(string cacheFilePath)
        {
            try
            {
                var info = new FileInfo(cacheFilePath);
                return info.Exists && info.Length > 0;
            }
            catch (Exception)
            {
                return false;
            }
        }

        private static void EvictOldEntries(string cacheFolder, string protectedFilePath)
        {
            try
            {
                var files = new DirectoryInfo(cacheFolder).GetFiles("*.html");
                if (files.Length <= MaxCacheEntries)
                {
                    return;
                }

                var protectedName = Path.GetFileName(protectedFilePath);

                // Order newest-first with a deterministic tie-breaker (name) so files sharing an identical
                // LastWriteTimeUtc are ordered stably, and never evict the file that was just written.
                foreach (var file in files
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .ThenByDescending(f => f.Name, StringComparer.Ordinal)
                    .Skip(MaxCacheEntries))
                {
                    if (!string.Equals(file.Name, protectedName, StringComparison.OrdinalIgnoreCase))
                    {
                        TryDelete(file.FullName);
                    }
                }
            }
            catch (Exception)
            {
            }
        }

        private static void TryDelete(string path)
        {
            try
            {
                File.Delete(path);
            }
            catch (Exception)
            {
            }
        }
    }
}
