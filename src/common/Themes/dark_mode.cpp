// Native Win32 dark-mode helpers built on top of the undocumented
// uxtheme.dll ordinals shipped with Windows 10 1903+ / Windows 11.
//
// Reference: https://github.com/microsoft/PowerToys/issues/31813
// Precedent: src/modules/ZoomIt/ZoomIt/Utility.cpp
#include "dark_mode.h"
#include "theme_helpers.h"

#include <memory>
#include <mutex>
#include <type_traits>

namespace
{
    enum class PreferredAppMode
    {
        Default,
        AllowDark,
        ForceDark,
        ForceLight,
        Max
    };

    using fnSetPreferredAppMode = PreferredAppMode(WINAPI*)(PreferredAppMode appMode);
    using fnFlushMenuThemes = void(WINAPI*)();

    struct BrushDeleter
    {
        void operator()(HBRUSH brush) const noexcept
        {
            DeleteObject(reinterpret_cast<HGDIOBJ>(brush));
        }
    };

    using unique_hbrush = std::unique_ptr<std::remove_pointer_t<HBRUSH>, BrushDeleter>;

    fnSetPreferredAppMode pSetPreferredAppMode = nullptr;
    fnFlushMenuThemes pFlushMenuThemes = nullptr;

    std::once_flag init_flag;

    // Mirrors the surface color used by ZoomIt's dark menus for visual
    // consistency across PowerToys-owned native menus.
    constexpr COLORREF DarkMenuSurfaceColor = RGB(45, 45, 45);

    unique_hbrush& GetDarkMenuBrush()
    {
        static unique_hbrush brush{ CreateSolidBrush(DarkMenuSurfaceColor) };
        return brush;
    }

    void LoadOrdinals()
    {
        HMODULE hUxTheme = GetModuleHandleW(L"uxtheme.dll");
        if (!hUxTheme)
        {
            hUxTheme = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        }
        if (!hUxTheme)
        {
            return;
        }

        pSetPreferredAppMode = reinterpret_cast<fnSetPreferredAppMode>(
            GetProcAddress(hUxTheme, MAKEINTRESOURCEA(135)));
        pFlushMenuThemes = reinterpret_cast<fnFlushMenuThemes>(
            GetProcAddress(hUxTheme, MAKEINTRESOURCEA(136)));
    }

    void ApplyPreferredAppMode()
    {
        if (!pSetPreferredAppMode)
        {
            return;
        }

        const bool dark = MenuTheme::IsDarkModeEnabled();
        pSetPreferredAppMode(dark ? PreferredAppMode::ForceDark : PreferredAppMode::ForceLight);

        if (pFlushMenuThemes)
        {
            pFlushMenuThemes();
        }
    }
}

void MenuTheme::Initialize()
{
    std::call_once(init_flag, LoadOrdinals);
    ApplyPreferredAppMode();
}

void MenuTheme::Refresh()
{
    Initialize();
}

bool MenuTheme::IsDarkModeEnabled()
{
    // Follow the *system* theme — the same signal the tray icon and the theme-change handler use —
    // rather than uxtheme's ShouldAppsUseDarkMode() (app theme). Otherwise, when Windows is set to a
    // custom mode where app and system themes differ, the menu would theme differently from the icon.
    return ThemeHelpers::GetSystemTheme() == Theme::Dark;
}

void MenuTheme::ApplyToMenu(HMENU menu)
{
    if (!menu)
    {
        return;
    }

    Initialize();
    if (!pSetPreferredAppMode)
    {
        return;
    }

    MENUINFO mi = { sizeof(mi) };
    mi.fMask = MIM_BACKGROUND | MIM_APPLYTOSUBMENUS;

    if (IsDarkModeEnabled())
    {
        mi.hbrBack = GetDarkMenuBrush().get();
    }
    else
    {
        mi.hbrBack = nullptr;
    }

    SetMenuInfo(menu, &mi);
}
