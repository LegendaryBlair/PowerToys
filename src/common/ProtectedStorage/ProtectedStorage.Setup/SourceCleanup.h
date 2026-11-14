// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
#pragma once
#include "SetupSupport.h"
#include "..\ProtectedStorage.Common\ArtifactFiles.h"

namespace PowerToysProtectedStorage::SourceCleanup
{
    inline bool Registered(const std::wstring& product, const std::wstring& owner)
    {
        wchar_t code[39]{}, sid[256]{};
        DWORD length = 256;
        MSIINSTALLCONTEXT context{};
        const auto users = MsiEnumProductsExW(product.c_str(), owner.c_str(), MSIINSTALLCONTEXT_USERMANAGED | MSIINSTALLCONTEXT_USERUNMANAGED, 0, code, &context, sid, &length);
        if (users == ERROR_SUCCESS)
            return true;
        result(users == ERROR_NO_MORE_ITEMS ? ERROR_SUCCESS : users, "verify owner source no longer registered");
        length = 256;
        const auto machine = MsiEnumProductsExW(product.c_str(), nullptr, MSIINSTALLCONTEXT_MACHINE, 0, code, &context, sid, &length);
        if (machine == ERROR_SUCCESS)
            return true;
        result(machine == ERROR_NO_MORE_ITEMS ? ERROR_SUCCESS : machine, "verify machine source no longer registered");
        return false;
    }

    inline bool SourceLeaf(const std::wstring& leaf)
    {
        return leaf == L"Carrier.msi" || leaf == L"result.txt" || leaf == L"native-msi.log";
    }

    template<typename IsRegistered>
    bool Retire(const std::filesystem::path& directory, const std::wstring& owner, IsRegistered&& registered)
    {
        canonical_owner(owner);
        if (!setup::valid_id(directory.filename().wstring()))
            throw failure("unexpected owner source directory", ERROR_INVALID_NAME);
        auto parents = PowerToys::ProtectedStorage::HoldDirectories(directory.parent_path().wstring());
        std::wstring productCode;
        PowerToys::ProtectedStorage::ArtifactFiles::DirectoryIdentity identity{};
        {
            auto pins = PowerToys::ProtectedStorage::HoldDirectories(directory.wstring());
            PowerToys::ProtectedStorage::CheckAcl(pins.back().get(), owner, true, false);
            identity = PowerToys::ProtectedStorage::ArtifactFiles::Identity(pins.back().get());
            if (std::filesystem::is_empty(directory))
            {
                pins.clear();
                PowerToys::ProtectedStorage::ArtifactFiles::RemoveFlatDirectory(directory, owner, SourceLeaf, &identity);
                return true;
            }
            const auto package = directory / L"Carrier.msi";
            handle file(CreateFileW(package.c_str(), GENERIC_READ | READ_CONTROL, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
            check(file.value != INVALID_HANDLE_VALUE, "hold exact source package for retirement");
            PowerToys::ProtectedStorage::CheckAcl(file.value, owner, true, false);
            Maintenance::ReadLocked(file.value);
            setup::msi_handle database;
            result(MsiOpenDatabaseW(package.c_str(), MSIDBOPEN_READONLY, &database.value), "inspect source package without executing MSI");
            if (setup::database_property(database.value, L"UpgradeCode") != product::upgradeCode ||
                !setup::database_property(database.value, L"ALLUSERS").empty())
                throw failure("source is not the owner carrier", ERROR_INVALID_DATA);
            productCode = setup::database_property(database.value, L"ProductCode");
            GUID guid{};
            if (productCode.size() != 38 || FAILED(CLSIDFromString(productCode.c_str(), &guid)))
                throw failure("invalid source product identity", ERROR_INVALID_DATA);
            if (registered(productCode, owner))
                return false;
        }
        // Called after the owner maintenance gate and confirmed native uninstall.
        // Both database and source-proof handles must be closed before deletion.
        if (registered(productCode, owner))
            return false;
        PowerToys::ProtectedStorage::ArtifactFiles::RemoveFlatDirectory(directory, owner, SourceLeaf, &identity);
        return true;
    }

    inline DWORD RetireUninstalled(const std::filesystem::path& sources, const std::wstring& owner)
    {
        DWORD pending = ERROR_SUCCESS;
        try
        {
            if (!setup::exists(sources))
                return pending;
            auto pins = PowerToys::ProtectedStorage::HoldDirectories(sources.wstring());
            for (const auto& entry : std::filesystem::directory_iterator(sources))
            {
                try
                {
                    Retire(entry.path(), owner, Registered);
                }
                catch (const failure& error)
                {
                    pending = error.code;
                }
                catch (const PowerToys::ProtectedStorage::Error& error)
                {
                    pending = error.code;
                }
            }
            pins.clear();
            if (!RemoveDirectoryW(sources.c_str()))
            {
                const auto error = GetLastError();
                if (error != ERROR_DIR_NOT_EMPTY && error != ERROR_FILE_NOT_FOUND)
                    pending = error;
            }
        }
        catch (const failure& error)
        {
            pending = error.code;
        }
        catch (const PowerToys::ProtectedStorage::Error& error)
        {
            pending = error.code;
        }
        catch (const std::filesystem::filesystem_error& error)
        {
            pending = static_cast<DWORD>(error.code().value());
        }
        return pending;
    }
}
