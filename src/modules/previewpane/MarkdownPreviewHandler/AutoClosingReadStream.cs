// Copyright (c) Microsoft Corporation
// The Microsoft Corporation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace Microsoft.PowerToys.PreviewHandler.Markdown
{
    // Stream implementations passed through the WinRT ABI must be partial for trimming and AOT.
    internal sealed partial class AutoClosingReadStream : Stream
    {
        private readonly long _length;
        private Stream _innerStream;
        private bool _disposed;
        private long _position;

        public AutoClosingReadStream(Stream innerStream)
        {
            _innerStream = innerStream ?? throw new ArgumentNullException(nameof(innerStream));
            _length = innerStream.Length;
            _position = innerStream.Position;
        }

        public bool IsComplete { get; private set; }

        public override bool CanRead => !_disposed;

        public override bool CanSeek => !_disposed && !IsComplete;

        public override bool CanWrite => false;

        public override long Length
        {
            get
            {
                ThrowIfDisposed();
                return _length;
            }
        }

        public override long Position
        {
            get
            {
                ThrowIfDisposed();
                return _position;
            }

            set
            {
                if (IsComplete)
                {
                    throw new NotSupportedException();
                }

                GetInnerStream().Position = value;
                _position = value;
            }
        }

        public override void Flush()
        {
            if (!IsComplete)
            {
                GetInnerStream().Flush();
            }
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            return IsComplete ? 0 : CompleteRead(GetInnerStream().Read(buffer, offset, count));
        }

        public override int Read(Span<byte> buffer)
        {
            return IsComplete ? 0 : CompleteRead(GetInnerStream().Read(buffer));
        }

        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (IsComplete)
            {
                return 0;
            }

            int bytesRead = await GetInnerStream().ReadAsync(buffer.AsMemory(offset, count), cancellationToken).ConfigureAwait(false);
            return CompleteRead(bytesRead);
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (IsComplete)
            {
                return 0;
            }

            int bytesRead = await GetInnerStream().ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            return CompleteRead(bytesRead);
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            if (IsComplete)
            {
                throw new NotSupportedException();
            }

            _position = GetInnerStream().Seek(offset, origin);
            return _position;
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
            if (!_disposed)
            {
                if (disposing)
                {
                    _innerStream?.Dispose();
                }

                _innerStream = null;
                _disposed = true;
            }

            base.Dispose(disposing);
        }

        private int CompleteRead(int bytesRead)
        {
            if (bytesRead == 0)
            {
                IsComplete = true;
                _innerStream?.Dispose();
                _innerStream = null;
            }
            else
            {
                _position += bytesRead;
            }

            return bytesRead;
        }

        private Stream GetInnerStream()
        {
            ThrowIfDisposed();
            return _innerStream ?? throw new ObjectDisposedException(nameof(AutoClosingReadStream));
        }

        private void ThrowIfDisposed()
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
        }
    }
}
