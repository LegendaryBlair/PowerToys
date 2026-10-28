// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

#pragma once

#include <atlbase.h>
#include <atlfile.h>
#include <atlstr.h>
#include <shobjidl_core.h>

namespace ImageResizer
{
    inline HANDLE CreateSelectionPipe(const wchar_t* pipeName)
    {
        constexpr DWORD bufferSize = 4096 * 4;
        return CreateNamedPipeW(
            pipeName,
            PIPE_ACCESS_DUPLEX | WRITE_DAC,
            PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
            PIPE_UNLIMITED_INSTANCES,
            bufferSize,
            bufferSize,
            0,
            nullptr);
    }

    inline HRESULT WaitForSelectionPipeClient(HANDLE pipe)
    {
        if (ConnectNamedPipe(pipe, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED)
        {
            return S_OK;
        }

        return E_FAIL;
    }

    inline void WriteShellSelection(IShellItemArray* selection, ATL::CAtlFile& pipe)
    {
        DWORD fileCount = 0;
        selection->GetCount(&fileCount);
        for (DWORD i = 0; i < fileCount; i++)
        {
            ATL::CComPtr<IShellItem> shellItem;
            if (SUCCEEDED(selection->GetItemAt(i, &shellItem)))
            {
                ATL::CComHeapPtr<wchar_t> itemName;
                if (SUCCEEDED(shellItem->GetDisplayName(SIGDN_FILESYSPATH, &itemName)))
                {
                    ATL::CString fileName(static_cast<LPWSTR>(itemName));
                    fileName.Append(L"\r\n");
                    pipe.Write(fileName, fileName.GetLength() * sizeof(wchar_t));
                }
            }
        }
    }
}
