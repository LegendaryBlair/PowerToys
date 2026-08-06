#include "pch.h"
// pch.h first
#include "newplus_icon_utilities.h"
#include <mutex>
#include <unordered_map>

#pragma comment(lib, "Shlwapi.lib")

namespace newplus::icon_utilities
{

std::wstring get_explorer_icon(const std::filesystem::path& path, bool is_directory)
{
    // Cache by full path — directories are excluded because their icon can change via desktop.ini
    // without a DLL reload. Extension is intentionally NOT used as the key: icons for types like .exe
    // and .lnk are per-file (the icon comes from the binary/shortcut itself), so an extension key would
    // return the first-seen file's icon for every template of that type.
    if (!is_directory)
    {
        // Explorer can call into the shell extension on multiple threads concurrently, so the
        // process-wide cache must be synchronized to avoid a data race on the unordered_map.
        // The lock is only ever held around the map lookup/insert and never while calling into the
        // shell (SHGetFileInfo/AssocQueryString), because those calls can be reentrant and would
        // otherwise risk deadlocking this non-recursive mutex on the same thread.
        static std::mutex s_icon_cache_mutex;
        static std::unordered_map<std::wstring, std::wstring> s_icon_cache;
        const std::wstring key = path.wstring();

        {
            std::lock_guard<std::mutex> cache_lock(s_icon_cache_mutex);
            const auto it = s_icon_cache.find(key);
            if (it != s_icon_cache.end())
                return it->second;
        }

        std::wstring icon_resource;

        SHFILEINFO shell_file_info = { 0 };
        SHGetFileInfo(key.c_str(), 0, &shell_file_info, sizeof(shell_file_info), SHGFI_ICONLOCATION);
        const std::wstring icon_path = shell_file_info.szDisplayName;
        if (!icon_path.empty())
        {
            icon_resource = icon_path + L"," + std::to_wstring(shell_file_info.iIcon);
        }
        else
        {
            WCHAR icon_resource_specifier[MAX_PATH] = { 0 };
            DWORD buffer_length = MAX_PATH;
            const std::wstring extension = path.extension().wstring();
            AssocQueryString(ASSOCF_INIT_IGNOREUNKNOWN, ASSOCSTR_DEFAULTICON,
                             extension.c_str(), NULL, icon_resource_specifier, &buffer_length);
            icon_resource = icon_resource_specifier;
        }

        {
            std::lock_guard<std::mutex> cache_lock(s_icon_cache_mutex);
            // Only cache successful (non-empty) lookups so a transient SHGetFileInfo/AssocQueryString
            // failure cannot permanently poison the cache with an empty icon for that path.
            if (!icon_resource.empty())
            {
                s_icon_cache[key] = icon_resource;
            }
        }

        return icon_resource;
    }

    // Directories: always read fresh from the shell
    SHFILEINFO shell_file_info = { 0 };
    const std::wstring filepath = path.wstring();
    SHGetFileInfo(filepath.c_str(), 0, &shell_file_info, sizeof(shell_file_info), SHGFI_ICONLOCATION);
    const std::wstring icon_path = shell_file_info.szDisplayName;
    if (!icon_path.empty())
    {
        return icon_path + L"," + std::to_wstring(shell_file_info.iIcon);
    }

    WCHAR icon_resource_specifier[MAX_PATH] = { 0 };
    DWORD buffer_length = MAX_PATH;
    AssocQueryString(ASSOCF_INIT_IGNOREUNKNOWN, ASSOCSTR_DEFAULTICON,
                     L"", NULL, icon_resource_specifier, &buffer_length);
    return icon_resource_specifier;
}

HICON get_explorer_icon_handle(const std::filesystem::path& path)
{
    SHFILEINFO shell_file_info = { 0 };
    const std::wstring filepath = path.wstring();
    SHGetFileInfo(filepath.c_str(), 0, &shell_file_info, sizeof(shell_file_info), SHGFI_ICON);
    if (shell_file_info.hIcon)
    {
        return shell_file_info.hIcon;
    }

    WCHAR icon_resource_specifier[MAX_PATH] = { 0 };
    DWORD buffer_length = MAX_PATH;
    const std::wstring extension = path.extension().wstring();
    AssocQueryString(ASSOCF_INIT_IGNOREUNKNOWN, ASSOCSTR_DEFAULTICON,
                     extension.c_str(), NULL, icon_resource_specifier, &buffer_length);
    const std::wstring icon_resource = icon_resource_specifier;
    const auto icon_x = GetSystemMetrics(SM_CXSMICON);
    const auto icon_y = GetSystemMetrics(SM_CYSMICON);
    return static_cast<HICON>(LoadImage(NULL, icon_resource.c_str(), IMAGE_ICON, icon_x, icon_y, LR_LOADFROMFILE));
}

}
