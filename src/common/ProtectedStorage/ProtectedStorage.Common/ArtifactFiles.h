// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
#pragma once
#include "Common.h"
#include <filesystem>

namespace PowerToys::ProtectedStorage::ArtifactFiles
{
    struct DirectoryIdentity
    {
        DWORD volume;
        uint64_t file;
    };

    inline DirectoryIdentity Identity(HANDLE directory)
    {
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(directory, &info))
            Fail("artifact directory identity");
        return { info.dwVolumeSerialNumber, (static_cast<uint64_t>(info.nFileIndexHigh) << 32) | info.nFileIndexLow };
    }

    inline Handle OpenForDeletion(const std::filesystem::path& path, const std::wstring& writer, bool directory = false)
    {
        Handle file(CreateFileW(path.c_str(), DELETE | READ_CONTROL | FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr));
        if (!file)
            Fail("open exact artifact for deletion");
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(file.get(), &info))
            Fail("artifact identity");
        Require(!(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
                    !!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == directory &&
                    (directory || info.nNumberOfLinks == 1),
                "linked or unexpected artifact refused");
        CheckAcl(file.get(), writer, !writer.empty(), false);
        return file;
    }

    inline void Delete(HANDLE file)
    {
        FILE_DISPOSITION_INFO disposition{ TRUE };
        if (!SetFileInformationByHandle(file, FileDispositionInfo, &disposition, sizeof(disposition)))
            Fail("delete exact artifact by handle");
    }

    template<typename Allowed>
    void RemoveFlatDirectory(const std::filesystem::path& path, const std::wstring& writer, Allowed&& allowed, const DirectoryIdentity* expected = nullptr)
    {
        if (!Exists(path.wstring()))
            return;
        auto ancestors = HoldDirectories(path.parent_path().wstring());
        auto directory = OpenForDeletion(path, writer, true);
        if (expected)
        {
            const auto actual = Identity(directory.get());
            Require(actual.volume == expected->volume && actual.file == expected->file, "artifact directory was replaced");
        }
        std::vector<Handle> files;
        for (const auto& entry : std::filesystem::directory_iterator(path))
        {
            Require(allowed(entry.path().filename().wstring()), "unexpected artifact; retain directory for inspection");
            files.push_back(OpenForDeletion(entry.path(), writer));
        }
        // Pin/validate all children before the first deletion. Never recurse
        // through a source package directory or a privileged helper stage.
        for (const auto& file : files)
            Delete(file.get());
        files.clear();
        Delete(directory.get());
    }
}
