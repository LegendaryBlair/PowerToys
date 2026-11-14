// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
#include "..\..\..\src\common\ProtectedStorage\ProtectedStorage.Lifecycle\ArtifactCleanup.h"
#include "..\..\..\src\common\ProtectedStorage\ProtectedStorage.Setup\SourceCleanup.h"
#include "..\..\..\src\common\ProtectedStorage\ProtectedStorage.Common\UpdatePayloadCleanup.h"
#include <random>

namespace
{
    using namespace PowerToysProtectedStorage;
    namespace native = PowerToys::ProtectedStorage;
    namespace artifact = ArtifactCleanup;
    namespace profile = ProfileCleanup;
    unsigned checks = 0;
    const std::wstring fixtureOwner = L"S-1-5-21-100-200-300-401";

    void Expect(bool condition, const char* message)
    {
        ++checks;
        if (!condition)
            throw std::runtime_error(message);
    }

    template<typename Action>
    void Reject(Action&& action)
    {
        bool rejected = false;
        try
        {
            action();
        }
        catch (const std::exception&)
        {
            rejected = true;
        }
        Expect(rejected, "unsafe artifact cleanup was accepted");
    }

    struct Fixture
    {
        std::filesystem::path root = std::filesystem::current_path() / (L"ArtifactCleanupTests-" + setup::unique_id());
        std::wstring writer = actor_sid();
        Fixture()
        {
            setup::new_directory(root, L"O:" + writer + L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;" + writer + L")");
        }
        ~Fixture()
        {
            std::error_code error;
            std::filesystem::remove_all(root, error);
        }
    };

    void FlatStageTests()
    {
        Fixture f;
        const auto stage = f.root / L"stage";
        std::filesystem::create_directory(stage);
        product::write_new(stage / L"Carrier.msi", { 'm' });
        product::write_new(stage / L"request", { 'r' });
        product::write_new(stage / L"unexpected", { 'x' });
        Reject([&] { native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf); });
        Expect(std::filesystem::exists(stage / L"Carrier.msi"), "preflight must retain all files if a leaf is unknown");
        std::filesystem::remove(stage / L"unexpected");
        auto locked = native::OpenRead((stage / L"request").wstring());
        Reject([&] { native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf); });
        Expect(std::filesystem::exists(stage / L"Carrier.msi"), "busy proof prevents partial cleanup before validation completes");
        locked.reset();
        const native::ArtifactFiles::DirectoryIdentity wrong{ 0, 0 };
        Reject([&] { native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf, &wrong); });
        const auto linked = f.root / L"external-msi";
        check(CreateHardLinkW(linked.c_str(), (stage / L"Carrier.msi").c_str(), nullptr) != FALSE, "artifact hard-link fixture");
        Reject([&] { native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf); });
        Expect(std::filesystem::exists(linked) && std::filesystem::exists(stage / L"Carrier.msi"), "linked source is refused without deleting either reference");
        std::filesystem::remove(linked);
        native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf);
        Expect(!std::filesystem::exists(stage), "released stage is removed");
        native::ArtifactFiles::RemoveFlatDirectory(stage, f.writer, artifact::AllowedLeaf);
        Expect(artifact::Terminal(L"install", L"finalize-install") && artifact::Terminal(L"remove", L"commit-remove") &&
                   artifact::Terminal(L"repair", L"finalize-repair"),
               "known completion authorizes retirement");
        Expect(!artifact::Terminal(L"install", L"prepared") && !artifact::Terminal(L"remove", L"finalize-install"),
               "unknown/mismatched completion cannot discard recovery material");
        const auto operation = setup::unique_id();
        const auto request = "format=1\nowner=" + ToUtf8(fixtureOwner) + "\noperation=" + ToUtf8(operation) + "\nvolume=7\nfile=11\n";
        const auto identity = artifact::RequestIdentity(request, fixtureOwner, operation);
        Expect(identity.volume == 7 && identity.file == 11, "queued retirement binds to the original directory");
        Reject([&] { artifact::RequestIdentity(request, fixtureOwner, setup::unique_id()); });
        Reject([&] { artifact::RequestIdentity(request, f.writer, operation); });
        Reject([&] { artifact::RequestIdentity(request + "source=C:\\Users\n", fixtureOwner, operation); });
        std::mt19937 random(0x41525446);
        for (unsigned sample = 0; sample < 256; ++sample)
        {
            std::string text;
            for (unsigned length = random() % 160; length; --length)
                text.push_back(static_cast<char>(random() % 128));
            Reject([&] { artifact::RequestIdentity(text, fixtureOwner, operation); });
        }
    }

    void UpdateTests()
    {
        Fixture f;
        const auto id = native::NewId();
        const auto directory = f.root / L"transactions" / id;
        std::filesystem::create_directories(directory / L"old");
        std::filesystem::create_directory(directory / L"new");
        const native::Transaction metadata{ fixtureOwner, id, native::ParseVersion("1.0.0.0"), native::ParseVersion("1.0.1.0"), std::string(64, 'a'), std::string(64, 'b'), std::string(64, 'c'), std::string(64, 'd'), std::string(64, 'e'), std::string(64, 'f') };
        native::WriteTransaction(directory.wstring(), metadata);
        for (const auto* generation : { L"old", L"new" })
            for (const auto* leaf : { L"Bootstrap.exe", L"Runtime.exe", L"manifest.txt", L"manifest.p7s", L"ClientCatalog.json", L"ClientCatalog.p7s" })
                product::write_new(directory / generation / leaf, { 'f', 'i', 'x' });
        product::write_new(directory / L"Updater.exe", { 'f', 'i', 'x' });
        product::write_new(f.root / L"blob.keep", { 'd', 'a', 't', 'a' });
        native::RecordOperation(directory.wstring(), "prepared", "awaiting decision");
        Reject([&] { native::TrimTerminalUpdate(directory, fixtureOwner, f.writer, id); });
        Expect(std::filesystem::exists(directory / L"Updater.exe"), "prepared update retains recovery executables");
        native::RecordOperation(directory.wstring(), "committed", "known native MSI commit");
        const auto response = native::MsiResponse(directory.wstring(), fixtureOwner, id);
        auto pin = native::OpenRead((directory / L"Updater.exe").wstring());
        Reject([&] { native::TrimTerminalUpdate(directory, fixtureOwner, f.writer, id); });
        Expect(std::filesystem::exists(directory / L"old" / L"Bootstrap.exe"), "mapped updater/proof prevents premature retirement");
        pin.reset();
        Reject([&] { native::TrimTerminalUpdate(directory, L"S-1-5-21-100-200-300-999", f.writer, id); });
        native::TrimTerminalUpdate(directory, fixtureOwner, f.writer, id);
        Expect(!std::filesystem::exists(directory / L"Updater.exe") &&
                   !std::filesystem::exists(directory / L"old" / L"Bootstrap.exe") &&
                   !std::filesystem::exists(directory / L"new" / L"Runtime.exe"),
               "terminal execution copies are reclaimed");
        Expect(native::MsiResponse(directory.wstring(), fixtureOwner, id) == response, "terminal response survives payload retirement");
        Expect(std::filesystem::exists(directory / L"old" / L"ClientCatalog.p7s") &&
                   std::filesystem::exists(directory / L"new" / L"ClientCatalog.json") &&
                   std::filesystem::exists(f.root / L"blob.keep"),
               "signed caller proofs and KeepData are preserved");
        native::DecideOperation(directory.wstring(), fixtureOwner, id, native::Command::MsiCommit);
        native::TrimTerminalUpdate(directory, fixtureOwner, f.writer, id);
        Expect(native::MsiResponse(directory.wstring(), fixtureOwner, id) == response, "repeat commit/query remain idempotent");
    }

    void Sql(MSIHANDLE database, const std::wstring& text)
    {
        setup::msi_handle view;
        result(MsiDatabaseOpenViewW(database, text.c_str(), &view.value), "source fixture SQL");
        result(MsiViewExecute(view.value, 0), "execute source fixture SQL");
    }

    void CreateSource(const std::filesystem::path& directory, const std::wstring& upgrade)
    {
        std::filesystem::create_directory(directory);
        setup::msi_handle database;
        result(MsiOpenDatabaseW((directory / L"Carrier.msi").c_str(), MSIDBOPEN_CREATE, &database.value), "create non-installable MSI source fixture");
        Sql(database.value, L"CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) LOCALIZABLE PRIMARY KEY `Property`)");
        Sql(database.value, L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductCode','{12345678-ABCD-4321-ABCD-123456789012}')");
        Sql(database.value, L"INSERT INTO `Property` (`Property`,`Value`) VALUES ('UpgradeCode','" + upgrade + L"')");
        result(MsiDatabaseCommit(database.value), "commit source fixture database");
        product::write_new(directory / L"result.txt", { 'r' });
        product::write_new(directory / L"native-msi.log", { 'l' });
    }

    void SourceTests()
    {
        Fixture f;
        const auto source = f.root / setup::unique_id();
        CreateSource(source, product::upgradeCode);
        unsigned queries = 0;
        Expect(!SourceCleanup::Retire(source, f.writer, [&](const auto&, const auto&) { ++queries; return true; }),
               "registered product must retain its maintenance source");
        Expect(queries == 1 && std::filesystem::exists(source / L"Carrier.msi"), "registration gate precedes mutation");
        auto proof = native::OpenRead((source / L"native-msi.log").wstring());
        Reject([&] { SourceCleanup::Retire(source, f.writer, [](const auto&, const auto&) { return false; }); });
        Expect(std::filesystem::exists(source / L"Carrier.msi"), "source/log handles must close before deletion");
        proof.reset();
        Expect(SourceCleanup::Retire(source, f.writer, [](const auto&, const auto&) { return false; }),
               "uninstalled source is reclaimed");
        Expect(!std::filesystem::exists(source), "source stage no longer exists");
        Expect(!SourceCleanup::Registered(L"{12345678-ABCD-4321-ABCD-123456789012}", f.writer),
               "read-only MSI registration query confirms uninstalled fixture identity");
        const auto foreign = f.root / setup::unique_id();
        CreateSource(foreign, L"{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}");
        Reject([&] { SourceCleanup::Retire(foreign, f.writer, [](const auto&, const auto&) { return false; }); });
        Expect(std::filesystem::exists(foreign / L"Carrier.msi"), "foreign MSI is not cleanup authority");
        const auto replaced = f.root / setup::unique_id();
        const auto original = f.root / L"original-source";
        CreateSource(replaced, product::upgradeCode);
        unsigned observations = 0;
        Reject([&] {
            SourceCleanup::Retire(replaced, f.writer, [&](const auto&, const auto&) {
                if (++observations == 2)
                {
                    std::filesystem::rename(replaced, original);
                    CreateSource(replaced, product::upgradeCode);
                }
                return false;
            });
        });
        Expect(std::filesystem::exists(replaced / L"Carrier.msi") && std::filesystem::exists(original / L"Carrier.msi"),
               "source directory replacement must not retire the replacement or the original");
    }

    std::vector<BYTE> GuiWorker()
    {
        auto file = native::OpenRead(product::module_path());
        auto bytes = native::ReadAll(file.get());
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(bytes.data());
        Expect(bytes.size() > sizeof(IMAGE_DOS_HEADER) && dos->e_magic == IMAGE_DOS_SIGNATURE &&
                   dos->e_lfanew > 0 && static_cast<size_t>(dos->e_lfanew) + sizeof(IMAGE_NT_HEADERS) <= bytes.size(),
               "test PE header");
        auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(bytes.data() + dos->e_lfanew);
        Expect(nt->Signature == IMAGE_NT_SIGNATURE, "test PE signature");
        nt->OptionalHeader.Subsystem = IMAGE_SUBSYSTEM_WINDOWS_GUI;
        return bytes;
    }

    template<typename Action>
    void Task(const std::wstring& operation, Action&& action)
    {
        const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        Expect(SUCCEEDED(initialized), "initialize task fixture observer");
        struct Close
        {
            ~Close() { CoUninitialize(); }
        } close;
        Microsoft::WRL::ComPtr<ITaskService> scheduler;
        Expect(SUCCEEDED(CoCreateInstance(CLSID_TaskScheduler, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&scheduler))), "scheduler fixture");
        VARIANT empty{};
        Expect(SUCCEEDED(scheduler->Connect(empty, empty, empty, empty)), "connect fixture scheduler");
        BSTR root = SysAllocString(L"\\"), name = SysAllocString(profile::TaskName(operation, profile::CleanupKind::Artifacts).c_str());
        Microsoft::WRL::ComPtr<ITaskFolder> folder;
        const auto opened = scheduler->GetFolder(root, &folder);
        SysFreeString(root);
        Expect(SUCCEEDED(opened), "open scheduler root");
        Microsoft::WRL::ComPtr<IRegisteredTask> task;
        const auto found = folder->GetTask(name, &task);
        SysFreeString(name);
        Expect(SUCCEEDED(found), "fixture artifact task exists");
        action(task.Get());
    }

    void ArtifactLiveCase()
    {
        const auto operation = setup::unique_id();
        const auto source = product::stage_root() / (product::setupPrefix + operation);
        const auto worker = artifact::Root() / operation;
        std::wcout << L"artifactFixture=" << source << L" operation=" << operation << L"\n"
                   << std::flush;
        setup::new_directory(source, system_acl());
        for (const auto& parent : { product::state_root(), product::state_root() / L"Installer", artifact::Root() })
        {
            directory(parent, system_acl());
            product::assert_system_directory(parent);
        }
        setup::new_directory(worker, system_acl());
        product::write_new_text(source / L"owner.txt", fixtureOwner);
        product::write_new_text(source / L"operation.txt", L"remove");
        product::write_new_text(source / L"finalized", L"commit-remove");
        product::write_new_text(source / L"commit-remove.result", L"0");
        product::write_new(source / L"ProvisionBroker.exe", { 'f' });
        artifact::ValidateCompletion(source, fixtureOwner);
        native::ArtifactFiles::DirectoryIdentity identity{};
        {
            auto pins = native::HoldDirectories(source.wstring());
            identity = native::ArtifactFiles::Identity(pins.back().get());
        }
        product::write_new(worker / L"Cleanup.exe", GuiWorker());
        product::write_new_text(worker / L"request", L"format=1\nowner=" + fixtureOwner + L"\noperation=" + operation + L"\nvolume=" + std::to_wstring(identity.volume) + L"\nfile=" + std::to_wstring(identity.file) + L"\n");
        auto proof = native::OpenRead((source / L"ProvisionBroker.exe").wstring());
        profile::Schedule(worker, fixtureOwner, operation, profile::CleanupKind::Artifacts);
        bool ran = false;
        const auto firstDeadline = GetTickCount64() + 90000;
        while (!ran && GetTickCount64() < firstDeadline)
        {
            Task(operation, [&](IRegisteredTask* task) {
                TASK_STATE state{};
                LONG code = 0;
                task->get_State(&state);
                task->get_LastTaskResult(&code);
                ran = state != TASK_STATE_RUNNING && code == 1 && profile::Exists(worker / L"last-error");
            });
            if (!ran)
                Sleep(250);
        }
        Expect(ran && profile::Exists(source / L"owner.txt") && profile::Exists(worker / L"Cleanup.exe"),
               "busy stage retains completion proof and retry worker");
        proof.reset();
        Task(operation, [](IRegisteredTask* task) {
            VARIANT empty{};
            Microsoft::WRL::ComPtr<IRunningTask> running;
            Expect(SUCCEEDED(task->Run(empty, &running)), "retry released artifact stage");
        });
        const auto deadline = GetTickCount64() + 90000;
        while ((profile::Exists(source) || profile::Exists(worker) || profile::Exists(artifact::Root() / (operation + L".cmd"))) &&
               GetTickCount64() < deadline)
            Sleep(250);
        Expect(!profile::Exists(source) && !profile::Exists(worker) && !profile::Exists(artifact::Root() / (operation + L".cmd")),
               "completed source stage, signed-worker fixture and script self-clean");
        std::wcout << L"PASS actual SYSTEM artifact cleanup task; operation=" << operation << L"\n"
                   << std::flush;
    }
}

unsigned RunArtifactCleanupTests()
{
    checks = 0;
    FlatStageTests();
    UpdateTests();
    SourceTests();
    return checks;
}

std::optional<int> RunArtifactCleanupLiveTests(int argc, wchar_t** argv)
{
    if (argc == 4 && std::wstring(argv[1]) == L"retry-artifacts")
    {
        require_system();
        Expect(argv[2] == fixtureOwner && setup::valid_id(argv[3]), "live worker only accepts its isolated owner");
        return static_cast<int>(artifact::Run(argv[2], argv[3]));
    }
    if (argc != 2 || std::wstring(argv[1]) != L"--artifact-cleanup-live")
        return std::nullopt;
    require_system();
    ArtifactLiveCase();
    return 0;
}
