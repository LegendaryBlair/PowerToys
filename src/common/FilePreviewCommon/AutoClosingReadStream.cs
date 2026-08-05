// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace Microsoft.PowerToys.FilePreviewCommon
{
    internal sealed partial class AutoClosingReadStream : Stream
    {
        private Stream? _innerStream;

        public AutoClosingReadStream(Stream innerStream)
        {
            _innerStream = innerStream ?? throw new ArgumentNullException(nameof(innerStream));
        }

        public override bool CanRead => _innerStream?.CanRead ?? false;

        public override bool CanSeek => _innerStream?.CanSeek ?? false;

        public override bool CanWrite => false;

        public override long Length => GetInnerStream().Length;

        public override long Position
        {
            get => GetInnerStream().Position;
            set => GetInnerStream().Position = value;
        }

        public override void Flush()
        {
            GetInnerStream().Flush();
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            return CompleteRead(GetInnerStream().Read(buffer, offset, count));
        }

        public override int Read(Span<byte> buffer)
        {
            return CompleteRead(GetInnerStream().Read(buffer));
        }

        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            int bytesRead = await GetInnerStream().ReadAsync(buffer.AsMemory(offset, count), cancellationToken).ConfigureAwait(false);
            return CompleteRead(bytesRead);
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            int bytesRead = await GetInnerStream().ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            return CompleteRead(bytesRead);
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            return GetInnerStream().Seek(offset, origin);
        }

        public override void SetLength(long value)
        {
            throw new NotSupportedException();
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            throw new NotSupportedException();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _innerStream?.Dispose();
            }

            _innerStream = null;
            base.Dispose(disposing);
        }

        private int CompleteRead(int bytesRead)
        {
            if (bytesRead == 0)
            {
                Dispose();
            }

            return bytesRead;
        }

        private Stream GetInnerStream()
        {
            return _innerStream ?? throw new ObjectDisposedException(nameof(AutoClosingReadStream));
        }
    }
}
