// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

#include <Windows.h>
#include <shlobj.h>
#include <cstdio>
#include <memory>
#include <vector>

#include "../../ImageResizerContextMenu/ShellSelection.h"
#include "../../dll/ClassicShellSelection.h"

namespace
{
    struct ShellItemDeleter
    {
        using pointer = PIDLIST_ABSOLUTE;

        void operator()(pointer item) const
        {
            ILFree(item);
        }
    };

    HRESULT SendClassicSelection(IShellItemArray* selection, const wchar_t* receiverPath, const wchar_t* destinationPath)
    {
        ATL::CComPtr<IDataObject> dataObject;
        HRESULT result = selection->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&dataObject));
        if (FAILED(result))
        {
            return result;
        }

        PIDLIST_ABSOLUTE destination = nullptr;
        if (*destinationPath)
        {
            result = SHParseDisplayName(destinationPath, nullptr, &destination, 0, nullptr);
            if (FAILED(result))
            {
                return result;
            }
        }

        std::unique_ptr<ITEMIDLIST, ShellItemDeleter> ownedDestination(destination);
        ATL::CAtlFile writer;
        PROCESS_INFORMATION processInformation{};
        result = ImageResizer::StartClassicSelectionReceiver(receiverPath, destination, SW_HIDE, writer, processInformation);
        if (FAILED(result))
        {
            return result;
        }

        ATL::CHandle process(processInformation.hProcess);
        ATL::CHandle thread(processInformation.hThread);
        ImageResizer::WriteClassicShellSelection(dataObject, nullptr, writer);
        writer.Close();

        if (WaitForSingleObject(process, 10000) != WAIT_OBJECT_0)
        {
            TerminateProcess(process, 1);
            WaitForSingleObject(process, 5000);
            return HRESULT_FROM_WIN32(ERROR_TIMEOUT);
        }

        DWORD exitCode = 1;
        if (!GetExitCodeProcess(process, &exitCode))
        {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        return exitCode == 0 ? S_OK : E_FAIL;
    }

    HRESULT SendSelection(int argc, wchar_t** argv)
    {
        const bool classic = wcscmp(argv[1], L"--classic") == 0;
        if (classic && argc < 5)
        {
            return E_INVALIDARG;
        }

        using ShellItemId = std::unique_ptr<ITEMIDLIST, ShellItemDeleter>;
        std::vector<ShellItemId> ownedItems;
        std::vector<PCIDLIST_ABSOLUTE> items;
        for (int i = classic ? 4 : 2; i < argc; i++)
        {
            PIDLIST_ABSOLUTE item = nullptr;
            HRESULT result = SHParseDisplayName(argv[i], nullptr, &item, 0, nullptr);
            if (FAILED(result))
            {
                return result;
            }

            ShellItemId ownedItem(item);
            items.push_back(item);
            ownedItems.push_back(std::move(ownedItem));
        }

        ATL::CComPtr<IShellItemArray> selection;
        HRESULT result = SHCreateShellItemArrayFromIDLists(static_cast<UINT>(items.size()), items.data(), &selection);
        if (FAILED(result))
        {
            return result;
        }

        if (classic)
        {
            return SendClassicSelection(selection, argv[2], argv[3]);
        }

        HANDLE pipe = ImageResizer::CreateSelectionPipe(argv[1]);
        if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE)
        {
            return HRESULT_FROM_WIN32(GetLastError());
        }

        ATL::CAtlFile writer(pipe);
        // The managed test starts its production receiver only after the pipe exists.
        std::puts("READY");
        std::fflush(stdout);
        result = ImageResizer::WaitForSelectionPipeClient(pipe);
        if (SUCCEEDED(result))
        {
            ImageResizer::WriteShellSelection(selection, writer);
        }

        return result;
    }
}

int wmain(int argc, wchar_t** argv)
{
    if (argc < 3)
    {
        return 2;
    }

    HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(result))
    {
        return 3;
    }

    try
    {
        result = SendSelection(argc, argv);
    }
    catch (...)
    {
        result = E_FAIL;
    }

    CoUninitialize();
    if (FAILED(result))
    {
        std::fprintf(stderr, "Shell selection failed: 0x%08lX\n", static_cast<unsigned long>(result));
        return 1;
    }

    return 0;
}
