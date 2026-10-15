# Advanced Paste — module verification profile

**PT module**: `AdvancedPaste` (clipboard transform: plain/markdown/json + AI custom paste)
**Source**: `src\modules\AdvancedPaste\`
**Settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\AdvancedPaste\settings.json`
**Exe**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.AdvancedPaste.exe`
**Named Event**: `Local\PowerToys_AdvancedPaste_ShowUI` (friendly: `AdvancedPaste.ShowUI`)
**Default UI hotkey**: Win+Shift+V (`advanced-paste-ui-hotkey`); paste-as-plain Win+Ctrl+Alt+V
**Settings UI section keys**: IsAIEnabled, AutoCopySelectionForCustomActionHotkey, paste-as-{plain,markdown,json}-hotkey, additional-actions, custom-actions

## Entry-paths (try in order)
1. Enable Advanced Paste through its actual Settings toggle and observe the [module lifecycle](../module-lifecycle.md). Do not rewrite the root enabled flag and restart all PowerToys merely to enable one module. Then `Invoke-PtSharedEvent -Name AdvancedPaste.ShowUI`. Window title "Advanced Paste", class WinUIDesktopWin32WindowClass.
2. Paste options are a ListView: invoke `itm-pasteasplaintex-*` / `itm-pasteasmarkdown-*` / `itm-pasteasjson*` (suffix is dynamic — match by `Select-String 'pasteas...'`). They paste into the previously-focused window.

## Recipes — control/observation map
| Capability | Drive | Observe |
|---|---|---|
| Strip formatting | invoke paste-as-plain ListItem | clipboard format-diff: `HTML Format` removed, `UnicodeText` kept |
| Markdown convert | invoke paste-as-markdown | target app content (Ctrl+A,Ctrl+C read-back) |
| JSON convert (CSV/XML) | invoke paste-as-json | target content read-back |
| Color swatch | clip a `#RRGGBB` string, ShowUI | preview row shows swatch |
| Clipboard history panel | enable Windows history, seed entries, invoke `btn-clipboardhistor-*` | `itm-*` history ListItems enumerable |
| AI custom paste availability | `InputTxtBox` / the current PromptBox; Settings' Paste with AI toggle | `IsAIEnabled` plus an allowed configured provider controls service availability; use supported clipboard content. Missing provider credentials are `BLK-EXTERNAL-APP`. |
| AI section visibility | Settings' **Show the AI paste input box** checkbox (`ShowAIPaste`) | MainPage binds PromptBox visibility to `ShowAIPasteSection`, independently of its `IsEnabled` service binding. Do not use the Paste with AI toggle as a visibility control. |

## Common BLOCKED traps
- `IsAIEnabled=false` disables custom input/provider actions; `ShowAIPaste=false` hides the section.
  A deliberately disabled state is the expected observation in its toggle case, not automatically a blocker.
  An unavailable authorized provider blocks only AI execution, not ordinary paste formats.
- Clipboard-history button collapsed (`ShowClipboardHistoryButton`, MainPage.xaml:172) until Windows clipboard history is ON. Enable `HKCU\Software\Microsoft\Clipboard\EnableClipboardHistory=1` + seed entries first — it IS UIA-enumerable, not BLK-VISUAL-RENDER.
- Notepad RichEdit isn't UIA-readable; read content via Ctrl+A/Ctrl+C then `Clipboard.GetText`.
- Don't mark the clipboard-history panel BLK-VISUAL-RENDER: AP is WinUI 3 → fully UIA-capable. A control absent from the tree is Collapsed by a view-model flag, not opaque — enable its precondition + confirm via XAML `AutomationProperties` before blocking.

## Source citations
- `src\modules\AdvancedPaste\` (settings keys above)
- MainPage.xaml:172 `ShowClipboardHistoryButton`; :192 history ListView (AutomationProperties.Name per item)
- `AdvancedPasteXAML\Pages\MainPage.xaml`: PromptBox `IsEnabled` and `Visibility` bindings.
  `ViewModels\OptionsViewModel.cs`: `IsCustomAIServiceEnabled`, `IsCustomAIAvailable`, `ShowAIPasteSection`.
  `src\settings-ui\Settings.UI\SettingsXAML\Views\AdvancedPastePage.xaml`:
  `AdvancedPaste_EnableAIToggle` versus `AdvancedPasteShowAIPasteSettingsCard`.
