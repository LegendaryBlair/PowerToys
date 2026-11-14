// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
#pragma once
#include "ProfileCleanup.h"
#include "..\ProtectedStorage.Common\ArtifactFiles.h"

namespace PowerToysProtectedStorage::ArtifactCleanup
{
    namespace native = PowerToys::ProtectedStorage;
    namespace cleanup = ProfileCleanup;

    inline bool Terminal(const std::wstring& operation, const std::wstring& phase)
    {
        return (operation == L"install" && (phase == L"finalize-install" || phase == L"undo-install")) ||
               ((operation == L"remove" || operation == L"purge") && (phase == L"commit-remove" || phase == L"undo-remove")) ||
               (operation == L"repair" && phase == L"finalize-repair");
    }

    inline std::wstring Operation(const std::filesystem::path& source)
    {
        const auto name = source.filename().wstring();
        const std::wstring prefix(product::setupPrefix);
        if (source.parent_path() != product::stage_root() || name.rfind(prefix, 0) != 0 ||
            !setup::valid_id(name.substr(prefix.size())))
            throw failure("unexpected provisioning stage", ERROR_INVALID_NAME);
        return name.substr(prefix.size());
    }

    inline std::wstring ReadWord(const std::filesystem::path& path)
    {
        std::wistringstream input(cleanup::ReadText(path));
        std::wstring word, extra;
        if (!(input >> word) || (input >> extra))
            throw failure("invalid provisioning completion metadata", ERROR_INVALID_DATA);
        return word;
    }

    inline void RequireServiceAbsent(const std::wstring& name)
    {
        service scm(OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT));
        check(scm.value != nullptr, "artifact cleanup SCM");
        service broker(OpenServiceW(scm.value, name.c_str(), SERVICE_QUERY_STATUS));
        if (broker.value)
            throw failure("broker still registered; retain executable", ERROR_BUSY);
        const auto error = GetLastError();
        if (error != ERROR_SERVICE_DOES_NOT_EXIST)
            throw failure("broker absence unverified", error);
    }

    inline void ValidateCompletion(const std::filesystem::path& source, const std::wstring& owner)
    {
        product::assert_system_directory(source);
        if (ReadWord(source / L"owner.txt") != canonical_owner(owner))
            throw failure("provisioning cleanup owner mismatch", ERROR_INVALID_OWNER);
        const auto phase = ReadWord(source / L"finalized");
        if (!Terminal(ReadWord(source / L"operation.txt"), phase))
            throw failure("unresolved provisioning operation", ERROR_INVALID_STATE);
        const auto result = ReadWord(source / (phase + L".result"));
        if (result != L"0" && result != L"3010" && result != L"1641")
            throw failure("provisioning completion failed", ERROR_INVALID_STATE);
    }

    inline bool AllowedLeaf(const std::wstring& leaf)
    {
        if (leaf == L"AuthorizedSetup.exe" || leaf == L"ProvisionBroker.exe" || leaf == L"Provisioner.exe" ||
            leaf == L"Carrier.msi" || leaf == L"request" || leaf == L"owner.txt" || leaf == L"operation.txt" ||
            leaf == L"prepared" || leaf == L"finalized" || leaf == L"cleanup-pending" || leaf == L"evidence.txt" ||
            leaf == L"artifact-cleanup-pending")
            return true;
        for (const auto* phase : { L"provision", L"install", L"commit-install", L"prepare-remove", L"prepare-purge", L"commit-remove", L"undo-remove", L"undo-install", L"repair-bootstrap", L"finalize-install", L"finalize-repair" })
        {
            const std::wstring prefix(phase);
            if (leaf == prefix + L".result")
                return true;
            if (leaf.rfind(prefix + L"-", 0) == 0 && leaf.size() == prefix.size() + 1 + 32 + 4 &&
                leaf.substr(leaf.size() - 4) == L".log" && setup::valid_id(leaf.substr(prefix.size() + 1, 32)))
                return true;
        }
        return false;
    }

    inline void RemoveStage(const std::filesystem::path& source, const native::ArtifactFiles::DirectoryIdentity* expected = nullptr)
    {
        native::ArtifactFiles::RemoveFlatDirectory(source, L"", AllowedLeaf, expected);
    }

    inline std::filesystem::path Root()
    {
        return product::state_root() / L"Installer" / L"Staging";
    }

    inline void Queue(const std::filesystem::path& source, const std::wstring& owner, const std::filesystem::path& lifecycle)
    {
        require_system();
        const auto operation = Operation(source);
        canonical_owner(owner);
        auto sourcePins = native::HoldDirectories(source.wstring());
        ValidateCompletion(source, owner);
        const auto identity = native::ArtifactFiles::Identity(sourcePins.back().get());
        for (const auto& parent : { product::state_root(), product::state_root() / L"Installer", Root() })
        {
            directory(parent, system_acl());
            product::assert_system_directory(parent);
        }
        const auto worker = Root() / operation;
        if (!cleanup::Exists(worker))
            setup::new_directory(worker, system_acl());
        product::assert_system_directory(worker);
        const auto request = L"format=1\nowner=" + owner + L"\noperation=" + operation +
                             L"\nvolume=" + std::to_wstring(identity.volume) + L"\nfile=" + std::to_wstring(identity.file) + L"\n";
        if (!cleanup::Exists(worker / L"request"))
            product::write_new_text(worker / L"request", request);
        else if (cleanup::ReadText(worker / L"request") != request)
            throw failure("retained artifact request does not match this stage", ERROR_INVALID_OWNER);
        if (!cleanup::Exists(worker / L"Cleanup.exe"))
        {
            handle image(CreateFileW(lifecycle.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
            check(image.value != INVALID_HANDLE_VALUE, "hold signed artifact cleanup worker");
            Maintenance::VerifySignedFile(lifecycle);
            product::write_new(worker / L"Cleanup.exe", Maintenance::ReadLocked(image.value));
        }
        Maintenance::VerifySignedFile(worker / L"Cleanup.exe");
        cleanup::Schedule(worker, owner, operation, cleanup::CleanupKind::Artifacts);
    }

    inline void QueueCompleted(const std::filesystem::path& current, const std::wstring& owner, const std::filesystem::path& lifecycle)
    {
        Queue(current, owner, lifecycle);
        bool pending = false;
        for (const auto& entry : std::filesystem::directory_iterator(product::stage_root()))
        {
            if (entry.path() == current || entry.path().filename().wstring().rfind(product::setupPrefix, 0) != 0)
                continue;
            bool eligible = false;
            try
            {
                Operation(entry.path());
                ValidateCompletion(entry.path(), owner);
                RequireServiceAbsent(entry.path().filename().wstring());
                eligible = true;
                Queue(entry.path(), owner, lifecycle);
            }
            catch (const std::exception&)
            {
                pending = pending || eligible;
            }
        }
        if (pending)
            throw failure("older completed stage cleanup could not be scheduled", ERROR_RETRY);
    }

    inline native::ArtifactFiles::DirectoryIdentity RequestIdentity(const std::string& text, const std::wstring& owner, const std::wstring& operation)
    {
        canonical_owner(owner);
        if (!setup::valid_id(operation))
            throw failure("artifact request operation", ERROR_INVALID_DATA);
        const auto request = native::ParseKeys(text, { "format", "owner", "operation", "volume", "file" });
        if (request.at("format") != "1" || request.at("owner") != ToUtf8(owner) || request.at("operation") != ToUtf8(operation))
            throw failure("artifact cleanup request mismatch", ERROR_INVALID_OWNER);
        const auto volume = native::Decimal(request.at("volume"));
        const auto file = native::Decimal(request.at("file"));
        if (volume > MAXDWORD || !file)
            throw failure("artifact directory identity", ERROR_INVALID_DATA);
        return { static_cast<DWORD>(volume), file };
    }

    inline DWORD Run(const std::wstring& owner, const std::wstring& operation)
    {
        require_system();
        canonical_owner(owner);
        if (!setup::valid_id(operation))
            throw failure("artifact cleanup operation", ERROR_INVALID_DATA);
        const auto worker = Root() / operation;
        if (_wcsicmp(product::module_path().c_str(), (worker / L"Cleanup.exe").c_str()))
            throw failure("artifact cleanup fixed worker path", ERROR_ACCESS_DENIED);
        for (const auto& path : { product::state_root(), product::state_root() / L"Installer", Root(), worker })
            product::assert_system_directory(path);
        const auto expected = RequestIdentity(ToUtf8(cleanup::ReadText(worker / L"request")), owner, operation);
        const auto source = product::stage_root() / (product::setupPrefix + operation);
        try
        {
            RequireServiceAbsent(source.filename().wstring());
            if (cleanup::Exists(source))
            {
                product::assert_system_directory(source);
                RemoveStage(source, &expected);
            }
            const auto done = Root() / (operation + L".done");
            if (!cleanup::Exists(done))
                product::write_new(done, {});
            return ERROR_SUCCESS;
        }
        catch (const native::Error& error)
        {
            cleanup::WriteText(worker / L"last-error", std::to_wstring(error.code));
            return error.code ? error.code : ERROR_INSTALL_FAILURE;
        }
        catch (const failure& error)
        {
            cleanup::WriteText(worker / L"last-error", std::to_wstring(error.code));
            return error.code ? error.code : ERROR_INSTALL_FAILURE;
        }
    }
}
