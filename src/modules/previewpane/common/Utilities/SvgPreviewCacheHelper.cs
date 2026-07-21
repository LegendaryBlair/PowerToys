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
            // intermediate string (which would allocate the StringBuilder buffer, its ToString(), and
            // the UTF-8 byte[] all at once).
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var separator = new[] { (byte)'\n' };

            foreach (var input in cacheInputs)
            {
                hash.AppendData(Encoding.UTF8.GetBytes(input ?? string.Empty));
                hash.AppendData(separator);
            }

            return Convert.ToHexString(hash.GetHashAndReset());
        }

        internal static string GetCacheFilePath(string cacheRootFolder, string cacheKey)
        {
            Directory.CreateDirectory(cacheRootFolder);
            return Path.Combine(cacheRootFolder, $"{cacheKey}.html");
        }

        /// <summary>
        /// Writes <paramref name="content"/> to <paramref name="cacheFilePath"/> atomically so that
        /// concurrent Explorer preview/thumbnail instances never observe a partially written or
        /// zero-length cache file. The content is written to a unique temp file and then moved into place.
        /// After a successful write the cache folder is trimmed to <see cref="MaxCacheEntries"/> entries.
        /// </summary>
        internal static void WriteCacheFileAtomic(string cacheFilePath, string content)
        {
            var directory = Path.GetDirectoryName(cacheFilePath);
            Directory.CreateDirectory(directory);

            var tempFilePath = Path.Combine(directory, $"{Guid.NewGuid():N}.tmp");

            try
            {
                File.WriteAllText(tempFilePath, content);
                File.Move(tempFilePath, cacheFilePath, overwrite: true);
            }
            catch (IOException)
            {
                // Another instance produced the same cache entry concurrently; drop our temp copy.
                TryDelete(tempFilePath);
            }

            EvictOldEntries(directory);
        }

        private static void EvictOldEntries(string cacheFolder)
        {
            try
            {
                var files = new DirectoryInfo(cacheFolder).GetFiles("*.html");
                if (files.Length <= MaxCacheEntries)
                {
                    return;
                }

                foreach (var file in files.OrderByDescending(f => f.LastWriteTimeUtc).Skip(MaxCacheEntries))
                {
                    TryDelete(file.FullName);
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
