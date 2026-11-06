// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

#pragma once

#include <atlbase.h>
#include <atlfile.h>
#include <atlstr.h>
#include <shlobj.h>
#include <memory>
#include <string>

#include "../../../common/utils/HDropIterator.h"

namespace ImageResizer
{
    inline HRESULT StartClassicSelectionReceiver(
        const std::wstring& applicationPath,
        PCIDLIST_ABSOLUTE destination,
        WORD showWindow,
        ATL::CAtlFile& writer,
        PROCESS_INFORMATION& processInformation)
    {
        SECURITY_ATTRIBUTES attributes{ sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE };
        HANDLE readHandle = nullptr;
        HANDLE writeHandle = nullptr;
        if (!CreatePipe(&readHandle, &writeHandle, &attributes, 0))
        {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        ATL::CAtlFile reader(readHandle);
        writer.Attach(writeHandle);
        if (!SetHandleInformation(writeHandle, HANDLE_FLAG_INHERIT, 0))
        {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        ATL::CString commandLine;
        commandLine.Format(L"\"%s\"", applicationPath.c_str());
        if (destination)
        {
            wchar_t folder[MAX_PATH];
            if (!SHGetPathFromIDListW(destination, folder))
            {
                return E_FAIL;
            }

            commandLine.AppendFormat(L" /d \"%s\"", folder);
        }

        STARTUPINFOW startupInfo{};
        startupInfo.cb = sizeof(startupInfo);
        startupInfo.hStdInput = readHandle;
        startupInfo.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
        startupInfo.wShowWindow = showWindow;
        processInformation = {};
        if (!CreateProcessW(nullptr, commandLine.GetBuffer(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startupInfo, &processInformation))
        {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        return S_OK;
    }

    inline void WriteClassicShellSelection(IDataObject* dataObject, IShellItemArray* selection, ATL::CAtlFile& writer)
    {
        if (!selection)
        {
            HDropIterator item(dataObject);
            for (item.First(); !item.IsDone(); item.Next())
            {
                std::unique_ptr<TCHAR, decltype(&free)> path(item.CurrentItem(), free);
                ATL::CString fileName(path.get());
                fileName.Append(L"\r\n");
                writer.Write(fileName, fileName.GetLength() * sizeof(wchar_t));
            }
        }
        else
        {
            DWORD fileCount = 0;
            selection->GetCount(&fileCount);
            for (DWORD i = 0; i < fileCount; i++)
            {
                ATL::CComPtr<IShellItem> shellItem;
                selection->GetItemAt(i, &shellItem);
                ATL::CComHeapPtr<wchar_t> itemName;
                shellItem->GetDisplayName(SIGDN_FILESYSPATH, &itemName);
                ATL::CString fileName(static_cast<LPWSTR>(itemName));
                fileName.Append(L"\r\n");
                writer.Write(fileName, fileName.GetLength() * sizeof(wchar_t));
            }
        }
    }
}
