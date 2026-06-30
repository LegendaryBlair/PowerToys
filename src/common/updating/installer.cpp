#include "pch.h"

#include "installer.h"
#include <common/version/version.h>
#include <common/utils/MsiUtils.h>
#include <common/utils/os-detect.h>
#include "utils/winapi_error.h"

#include <common/logger/logger.h>

#include <wincrypt.h>
#include <wintrust.h>
#include <softpub.h>

#pragma comment(lib, "wintrust.lib")
#pragma comment(lib, "crypt32.lib")

namespace // Strings in this namespace should not be localized
{
    const wchar_t DONT_SHOW_AGAIN_RECORD_REGISTRY_PATH[] = L"delete_previous_powertoys_confirm";

    const wchar_t TOAST_TITLE[] = L"PowerToys";

    const wchar_t MSIX_PACKAGE_NAME[] = L"Microsoft.PowerToys";
    const wchar_t MSIX_PACKAGE_PUBLISHER[] = L"CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US";
}

namespace updating
{
    winrt::Windows::Foundation::IAsyncOperation<bool> uninstall_previous_msix_version_async()
    {
        winrt::Windows::Management::Deployment::PackageManager package_manager;

        try
        {
            auto packages = package_manager.FindPackagesForUser({}, MSIX_PACKAGE_NAME, MSIX_PACKAGE_PUBLISHER);
            VersionHelper current_version(VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION);

            for (auto package : packages)
            {
                VersionHelper msix_version(package.Id().Version().Major, package.Id().Version().Minor, package.Id().Version().Revision);

                if (msix_version < current_version)
                {
                    co_await package_manager.RemovePackageAsync(package.Id().FullName());
                    co_return true;
                }
            }
        }
        catch (...)
        {
        }
        co_return false;
    }

    namespace
    {
        // Returns true only when the leaf signer certificate selected by WinVerifyTrust has
        // Organization (O) set to "Microsoft Corporation".
        bool installer_signed_by_microsoft(PCCERT_CONTEXT certContext)
        {
            if (!certContext)
            {
                return false;
            }

            // Match on the certificate's Organization (O) field rather than the simple display
            // name (which is the CN and can legitimately vary, e.g. ".NET"). PowerToys is signed
            // with O="Microsoft Corporation", matching the MSIX publisher check above.
            // Mutable copy of the OID string: CertGetNameStringW takes a non-const void* type param.
            char organizationOid[] = szOID_ORGANIZATION_NAME;
            const DWORD nameLen = CertGetNameStringW(certContext, CERT_NAME_ATTR_TYPE, 0, organizationOid, nullptr, 0);
            if (nameLen <= 1)
            {
                return false;
            }

            std::wstring organization(nameLen, L'\0');
            CertGetNameStringW(certContext, CERT_NAME_ATTR_TYPE, 0, organizationOid, organization.data(), nameLen);
            organization.resize(nameLen - 1); // drop the trailing null terminator

            return organization == L"Microsoft Corporation";
        }
    }

    bool verify_installer_trust(const std::wstring& installerPath, HANDLE verifiedFileHandle)
    {
        WINTRUST_FILE_INFO fileInfo{};
        fileInfo.cbStruct = sizeof(fileInfo);
        fileInfo.pcwszFilePath = installerPath.c_str();
        fileInfo.hFile = verifiedFileHandle; // verify the exact bytes we hold open, closing the TOCTOU window
        fileInfo.pgKnownSubject = nullptr;

        GUID actionGuid = WINTRUST_ACTION_GENERIC_VERIFY_V2;

        WINTRUST_DATA trustData{};
        trustData.cbStruct = sizeof(trustData);
        trustData.dwUIChoice = WTD_UI_NONE;
        trustData.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
        trustData.dwUnionChoice = WTD_CHOICE_FILE;
        trustData.dwStateAction = WTD_STATEACTION_VERIFY;
        trustData.dwProvFlags = WTD_SAFER_FLAG;
        trustData.pFile = &fileInfo;

        const LONG status = WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &actionGuid, &trustData);

        auto closeTrust = wil::scope_exit([&] {
            trustData.dwStateAction = WTD_STATEACTION_CLOSE;
            WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &actionGuid, &trustData);
        });

        if (status != ERROR_SUCCESS)
        {
            Logger::error(L"Installer Authenticode trust verification failed for '{}' (status: {:#010x})", installerPath, static_cast<uint32_t>(status));
            return false;
        }

        const auto providerData = WTHelperProvDataFromStateData(trustData.hWVTStateData);
        const auto signer = providerData ? WTHelperGetProvSignerFromChain(providerData, 0, FALSE, 0) : nullptr;
        const auto signerCert = (signer && signer->csCertChain > 0 && signer->pasCertChain) ? signer->pasCertChain[0].pCert : nullptr;

        if (!installer_signed_by_microsoft(signerCert))
        {
            Logger::error(L"Installer '{}' passed Authenticode trust verification, but its expected Microsoft Corporation signer organization could not be confirmed; refusing to run it elevated", installerPath);
            return false;
        }

        return true;
    }
}
