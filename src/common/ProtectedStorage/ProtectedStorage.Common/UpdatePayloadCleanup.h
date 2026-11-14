// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
#pragma once
#include "ArtifactFiles.h"

namespace PowerToys::ProtectedStorage
{
    inline void TrimTerminalUpdate(const std::filesystem::path& transaction, const std::wstring& owner, const std::wstring& va, const std::wstring& operation)
    {
        Require(ValidId(operation) && transaction.filename() == operation, "update cleanup operation binding");
        auto directories = HoldDirectories(transaction.wstring());
        CheckAcl(directories.back().get(), va, true, false);
        auto gate = TransactionGate(transaction.wstring());
        ReadTransaction(transaction.wstring(), owner, operation);
        Require(IsTerminal(Journal(transaction.wstring())), "unresolved update payloads must be retained");
        std::vector<Handle> files;
        for (const auto* generation : { L"old", L"new" })
        {
            const auto directory = transaction / generation;
            if (!Exists(directory.wstring()))
                continue;
            auto pins = HoldDirectories(directory.wstring());
            CheckAcl(pins.back().get(), va, true, false);
            for (auto& pin : pins)
                directories.push_back(std::move(pin));
            for (const auto* leaf : { L"Bootstrap.exe", L"Runtime.exe" })
            {
                const auto path = directory / leaf;
                if (Exists(path.wstring()))
                    files.push_back(ArtifactFiles::OpenForDeletion(path, va));
            }
        }
        const auto updater = transaction / L"Updater.exe";
        if (Exists(updater.wstring()))
            files.push_back(ArtifactFiles::OpenForDeletion(updater, va));
        // Catalogs, signatures, manifests and decision/journal metadata remain:
        // old/new signed callers must still be able to query the terminal result.
        for (const auto& file : files)
            ArtifactFiles::Delete(file.get());
    }

    inline DWORD TrimCompletedUpdates(const std::wstring& data, const std::wstring& owner, const std::wstring& va)
    {
        DWORD pending = ERROR_SUCCESS;
        try
        {
            const std::filesystem::path transactions = std::filesystem::path(data) / L"transactions";
            if (!Exists(transactions.wstring()))
                return ERROR_SUCCESS;
            auto pins = HoldDirectories(transactions.wstring());
            CheckAcl(pins.back().get(), va, true, false);
            for (const auto& entry : std::filesystem::directory_iterator(transactions))
            {
                try
                {
                    TrimTerminalUpdate(entry.path(), owner, va, entry.path().filename().wstring());
                }
                catch (const Error& error)
                {
                    pending = error.code ? error.code : ERROR_INVALID_STATE;
                }
            }
        }
        catch (const Error& error)
        {
            pending = error.code ? error.code : ERROR_INVALID_STATE;
        }
        catch (const std::filesystem::filesystem_error& error)
        {
            pending = static_cast<DWORD>(error.code().value());
        }
        return pending;
    }
}
