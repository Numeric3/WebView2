# WebView2 UDF

A modern Chromium browser embedded in an AutoIt GUI, driven entirely from AutoIt.

**WebView2** puts the Microsoft Edge rendering engine in a child window of your own
GUI and gives you navigation, JavaScript execution, a two-way message bridge, page
snapshots, PDF export, download interception and cookie control. The UDF talks to the
WebView2 runtime that Windows already ships, through its own COM interfaces: **no SDK,
no DLL to ship, no wrapper binary, no registration, no download.** Only `kernel32`,
`user32`, `ole32` and the system `EmbeddedBrowserWebView.dll` are touched.

- Author: Numeric1
- Forum: https://www.autoitscript.com/forum/
- Requirements: AutoIt 3.3.16+ and Windows 10 or later carrying the
  *Microsoft Edge WebView2 Runtime* (Windows 11 ships it; on Windows 10 it arrives
  with the Edge automatic update)
- Dependencies: none beyond AutoIt itself — `DllCall`, `ObjCreateInterface` and two
  helpers from the standard `<File.au3>`
- Version: 0.3.0

## Why this instead of the existing options?

|                       | WebView2 UDF        | `_IECreate` / IE UDF        | CEF / an external browser    |
|-----------------------|---------------------|-----------------------------|------------------------------|
| Engine                | Current Chromium    | Internet Explorer 11        | Depends on what you bundle   |
| Modern web (ES2020+, flexbox, wasm) | Yes        | No                          | Yes                          |
| Extra files to ship   | **None**            | None                        | A browser runtime of your own |
| Runtime source        | Already on Windows  | Already on Windows          | Bundled and updated by you   |
| JavaScript results    | Returned as strings | Limited, fragile            | Yes                          |
| AutoIt <-> page bridge| Two-way messages    | None                        | The vendor's own binding     |
| PDF / PNG export      | Yes                 | No                          | Yes                          |
| Downloads & cookies   | Interceptable       | Not controllable            | Yes                          |

The point of this UDF is the first column reached with none of the cost in the third:
a real Chromium view and **zero** files added to your distribution.

## Package

| File | Purpose |
|---|---|
| `WebView2.au3` | The UDF (self-contained, `#include-once`) |
| `WebView2_Example_GUI.au3` | Runnable browser demo **and** a 111-check self-test (`--auto`) |
| `WebView2_Example_GUI.png` | Screenshot of the demo |
| `WebView2_Quick_Start.pdf` | 18-page beginner booklet: four commented programs, from the first window to snapshots and PDF |
| `01_first_window.au3` to `04_toolbar.au3` | The four programs the booklet prints, next to the UDF so they run as they are |
| `WebView2_Developer_Guide.md` / `.pdf` | How it is built, why it is built that way, and how to extend it |
| `LICENSE` | MIT — Copyright (c) 2026 Numeric1 |
| `README.md` | This file |

## Quick start

```autoit
#include "WebView2.au3"

Global $hGui = GUICreate("My app", 900, 600)
GUISetState(@SW_SHOW, $hGui)

; Ask for a runtime before building anything on top of it.
If _WV2_GetRuntimePath() = "" Then
    MsgBox(48, "WebView2", "The WebView2 runtime is not installed.")
    Exit
EndIf

Local $iWV = _WV2_Create($hGui)                     ; covers the whole client area
If $iWV = 0 Then
    MsgBox(48, "WebView2", "Create failed: " & _WV2_GetLastErrorMessage())
    Exit
EndIf

_WV2_Navigate($iWV, "https://www.autoitscript.com/")
If _WV2_WaitNavigation($iWV) Then                 ; blocks until the page settles
    Local $sTitle
    _WV2_GetTitle($iWV, $sTitle)
    ConsoleWrite($sTitle & @CRLF)
EndIf

While GUIGetMsg() <> -3
    Sleep(50)
WEnd

_WV2_Destroy($iWV)                                ; balanced: every COM reference is released
```

## Laying out and resizing

The browser is a **real window** inside `$hParent`, not an AutoIt control: it covers
every control whose area overlaps its own, so reserve a band of the client area for
your toolbar instead of drawing over the view. It does not follow
`GUICtrlSetResizing` — it has no control id. Either set its bounds in the resize
handler, or fit it to the client area:

```autoit
Case $GUI_EVENT_RESIZED
    _WV2_FitToParent($iWV)      ; back to 0,0 covering the whole client area
```

While the UDF is waiting for the runtime it pumps window messages, so the GUI stays
responsive; call everything from the thread that owns `$hParent`.

## The API at a glance

Every function reports failure the same way: `@error` carries a `$WV2_ERR_*` code and
`@extended` the raw HRESULT (0 when there is none), so a failure is always
explainable without a debugger. The return value on failure is `0`, `-1` or `""`
depending on what the function would have returned.

| Code | Name | Meaning |
|---|---|---|
| 0 | `$WV2_ERR_NONE` | No error (also what a call leaves after success) |
| 1 | `$WV2_ERR_HANDLE` | Invalid or already destroyed handle |
| 2 | `$WV2_ERR_ARG` | Argument not acceptable for this call |
| 3 | `$WV2_ERR_RUNTIME` | WebView2 runtime not found on this machine |
| 4 | `$WV2_ERR_COM` | COM initialisation or interface wrapper failure |
| 5 | `$WV2_ERR_ENV` | Environment creation failed |
| 6 | `$WV2_ERR_CONTROLLER` | Controller creation failed |
| 7 | `$WV2_ERR_NOT_READY` | Instance not usable yet |
| 8 | `$WV2_ERR_CALL` | A WebView2 method returned a failure HRESULT |
| 9 | `$WV2_ERR_TIMEOUT` | The operation did not complete in the allowed time |
| 10 | `$WV2_ERR_FULL` | Too many live instances (16 is the ceiling) |
| 11 | `$WV2_ERR_FILE` | A file handed to the UDF could not be written |

`_WV2_GetLastErrorMessage()` turns the last failure into a sentence, naming the
method that failed and the HRESULT, which is what the example prints.

### Lifecycle and diagnosis

| Function | What it does |
|---|---|
| `_WV2_GetRuntimePath()` | Locates `EmbeddedBrowserWebView.dll` (registry `pv`, then highest version on disk); `""` + `$WV2_ERR_RUNTIME` if absent |
| `_WV2_Create($hParent, $iLeft, $iTop, $iWidth, $iHeight, $sUserDataFolder, $iTimeoutMs)` | Builds environment + controller + view inside `$hParent`. Returns an instance handle, or 0. Up to 16 live at once |
| `_WV2_Destroy($iHandle)` | Tears the view down and releases every reference. Idempotent-guarded: a second call returns `$WV2_ERR_HANDLE` |
| `_WV2_IsReady($iHandle)` | 1 once the view is usable |
| `_WV2_GetLastErrorMessage()` | Human-readable text of the last failure (never a dialog, never console output) |

### Navigation and history

`_WV2_Navigate`, `_WV2_NavigateToString`, `_WV2_WaitNavigation` (returns 1 and puts
the web error id in `@extended`), `_WV2_IsNavigationComplete`, `_WV2_Reload`,
`_WV2_Stop`, `_WV2_GoBack`, `_WV2_GoForward`, `_WV2_CanGoBack`, `_WV2_CanGoForward`,
`_WV2_GetTitle`, `_WV2_GetSource`, `_WV2_GetBrowserVersion`, `_WV2_SetNavigationFilter`.

### Geometry and appearance

`_WV2_SetBounds`, `_WV2_GetBounds`, `_WV2_FitToParent`, `_WV2_SetVisible`,
`_WV2_SetZoom` (0.2 … 10, 1 being 100 %), `_WV2_GetZoom`.

### JavaScript and the message bridge

| Function | What it does |
|---|---|
| `_WV2_ExecuteScript($iHandle, $sScript, ByRef $sResult, $iTimeoutMs)` | Runs the script, brings the JSON-serialized result back as a string |
| `_WV2_AddScriptToExecuteOnDocumentCreated($iHandle, $sScript, ByRef $sId)` | Injects before any page script runs; returns an id to remove it later |
| `_WV2_RemoveScriptToExecuteOnDocumentCreated($iHandle, $sId)` | Cancels that injection |
| `_WV2_PostWebMessage($iHandle, $sJson)` | Host → page, as a JSON object |
| `_WV2_PostWebMessageAsString($iHandle, $sText)` | Host → page, as a plain string |

Inside the page the bridge is the standard WebView2 API:

```html
<script>
  window.chrome.webview.addEventListener("message", e => console.log(e.data));
  window.chrome.webview.postMessage("page says hello");
</script>
```

### Events

`_WV2_EnableEvent`, `_WV2_GetEvent`, `_WV2_WaitEvent`. Each event carries a `$sData`
string and an `$iValue` integer:

| Constant | `$sData` | `$iValue` |
|---|---|---|
| `$WV2_EVENT_NAVIGATION_STARTING` | uri | 1 when user initiated |
| `$WV2_EVENT_NAVIGATION_COMPLETED` | uri | 1 on success, else the web error id |
| `$WV2_EVENT_WEB_MESSAGE` | message body | 1 plain text / 0 JSON |
| `$WV2_EVENT_NEW_WINDOW` | the uri the page tried to open | — |
| `$WV2_EVENT_TITLE_CHANGED` | the new title | — |
| `$WV2_EVENT_HISTORY_CHANGED` | — | bit 1 = CanGoBack, bit 2 = CanGoForward |
| `$WV2_EVENT_PROCESS_FAILED` | — | a `$WV2_PROCFAIL_*` code |
| `$WV2_EVENT_DOWNLOAD_STARTING` | uri | 1 refused by the host / 0 accepted |

Events queue up, so `_WV2_GetEvent` drains them between two waits; reading an empty
queue returns 0 with `@error = 0`, which is a normal answer rather than a failure.
Waiting on an event you never enabled is refused with `$WV2_ERR_ARG`.

### Page settings

`_WV2_SettingRead($iHandle, $sName)` / `_WV2_SettingWrite($iHandle, $sName, $bValue)`
take one of: `IsScriptEnabled`, `IsWebMessageEnabled`,
`AreDefaultScriptDialogsEnabled`, `IsStatusBarEnabled`, `AreDevToolsEnabled`,
`AreDefaultContextMenusEnabled`, `AreHostObjectsAllowed`, `IsZoomControlEnabled`,
`IsBuiltInErrorPageEnabled`. The name is matched without regard to case, and an
unknown name fails with `$WV2_ERR_ARG`.

### Output: snapshots, PDF, downloads, cookies

| Function | What it does |
|---|---|
| `_WV2_CapturePreview($iHandle, $sFile, $iFormat, $iTimeoutMs)` | PNG (default) or JPEG (`$WV2_IMAGE_JPEG`) image of the page |
| `_WV2_PrintToPdf($iHandle, $sFile, $iTimeoutMs)` | Renders the page to a real PDF through the runtime's own printer |
| `_WV2_SetDownloadFolder($iHandle, $sFolder)` | Where a download lands: the file name chosen by the runtime is kept, only its folder is replaced |
| `_WV2_SetDownloadFilter($iHandle, $sFilter)` | PCRE matched against the uri: a match is refused before the download starts |
| `_WV2_ClearCookies($iHandle)` | Empties the cookie jar of the user data folder |

## Behaviour worth knowing before you use it

- **`_WV2_ExecuteScript` answers in JSON.** A number comes back bare (`42`), a string
  between quotes (`"text"`), an object as its JSON. A script that *throws* is not a
  failure: the call succeeds and `$sResult` becomes `null`, which is also what a
  script with no result gives. When a script can fail, make it return something you
  can test.
- **`_WV2_SetNavigationFilter` needs the event.** The filter is read inside the
  `NavigationStarting` callback, so it only applies while
  `$WV2_EVENT_NAVIGATION_STARTING` is enabled. A refused navigation still reaches the
  queue, so `_WV2_GetEvent` tells you which URL was blocked.
- **Folders have to exist.** `_WV2_SetDownloadFolder` and `_WV2_PrintToPdf` fail with
  `$WV2_ERR_ARG` / `$WV2_ERR_FILE` when the target folder is missing - the UDF never
  creates one. A relative path is completed with the current directory.
- **The PDF uses the defaults of the runtime**: portrait, its own paper size, no
  header, no footer, backgrounds left out. Passing print settings would need
  `ICoreWebView2PrintSettings`, which `PrintToPdf` accepts as NULL here.
- **Cookie clearing is synchronous but the page is not.** It keeps whatever it
  already read: reload the view before testing `document.cookie` again.
- **Waiting pumps messages.** `_WV2_WaitNavigation`, `_WV2_WaitEvent`,
  `_WV2_ExecuteScript` and `_WV2_PrintToPdf` keep the GUI responsive while they block
  the calling line, which is what lets one function wait for a callback that only a
  message on the same thread can deliver.

## Design notes worth knowing

- **No loader, and that is the one documented risk.** The environment is created with
  `CreateWebViewEnvironmentWithOptionsInternal`, an export of the runtime's own
  `EmbeddedBrowserWebView.dll`. Microsoft documents `CreateCoreWebView2EnvironmentWithOptions`
  in `WebView2Loader.dll` instead, so this entry point is **undocumented**: it works on
  every runtime tested, and it could change in a future runtime update. That is why
  `_WV2_GetRuntimePath` and `_WV2_Create` fail loudly with an HRESULT rather than
  guessing, and why the self-test exists.
- **Callbacks are AutoIt objects.** COM pointers handed to a callback are borrowed,
  so every wrapper is built with `ObjCreateInterface(..., False)` — the vtable tag
  starts at slot 0 and the wrapper neither adds nor releases a reference. AddRef and
  Release are called explicitly, which is what makes `_WV2_Destroy` balanced and
  crash-free.
- **Some methods are reached through the vtable.** A method that only exists on a
  newer interface (`PrintToPdf`, the cookie manager, the download handlers) is found
  with `QueryInterface` and called with `DllCallAddress`: an `ObjCreateInterface` tag
  would have to declare every method of that interface — eighty of them before
  `PrintToPdf` alone.
- **`put_Bounds` is special.** `ICoreWebView2Controller::put_Bounds` takes its RECT
  *by value*. On x86 the tag declares four longs; on x64 the runtime reads the
  *address* of those sixteen bytes instead, and every other shape of the argument
  crashes the process. `__WV2_PutBounds` therefore branches on `@AutoItX64` and, on
  64 bits, calls the method through the vtable with a pointer to a `DllStruct`.
- **Silent by construction.** The UDF never shows a `MsgBox` and never writes to the
  console. Diagnostics are only ever available through `_WV2_GetLastErrorMessage()`
  and `@error` / `@extended`.

## Example and self-test

`WebView2_Example_GUI.au3` runs as a small browser: address bar with Go, back,
forward, reload and stop, a bottom band with A-/A+ zoom, `JS` (runs a script and
shows the answer), `Shot` (PNG of the page), `PDF` (prints the page), and a status
line that reports what the view publishes - title changes, user navigations, page
messages (answered back to the page), links with `target=_blank` reopened in the same
view, downloads raised by a page, and a failed browser process.

With `--auto` the same file runs headless as a 111-check suite instead and exits 0
when everything passes:

```
AutoIt3.exe WebView2_Example_GUI.au3 --auto
```

The suite covers the whole API - lifecycle, geometry, navigation, events, JavaScript,
the message bridge, settings, snapshots, PDF, downloads (folder, filter, refusal
leaving nothing on disk) and cookies. It needs **no network**: it drives `file://` and
`NavigateToString` pages, and leaves no file behind. Verified on AutoIt 3.3.16.1 on
**both x86 (`AutoIt3.exe`) and x64 (`AutoIt3_x64.exe`)**: `passed=111 failed=0`.

## Quick start booklet

`WebView2_Quick_Start.pdf` (18 pages, same typesetting as the guide) is the entry
point for someone who just wants to use the UDF: no COM, no vtable, no headers.

1. Your first window - one include, one window, one page.
2. Events and messages - the queue, in both directions.
3. Your own content - HTML from a string, JavaScript answers.
4. Fitting the window - bounds, resize, zoom.
5. Recipes - snapshot, PDF, downloads, cookies, settings.
6. When it goes wrong - twelve error codes, five traps, the 40-function cheat sheet.

The four complete programs it prints sit next to `WebView2.au3` and run as
printed. Every one of them is local: no network, no server, no file left behind.

## Developer guide

`WebView2_Developer_Guide.md` (and the same text as an 18-page PDF typeset with the
author's [PDFX](https://www.autoitscript.com/forum/topic/213930-udf-pdfx/) UDF) goes one
floor down: it explains the machinery, not the API.

1. The COM model in AutoIt — pointers, `ObjCreateInterface` tags, raw vtable slots, and
   the environment call that removes the loader.
2. Handler objects in a global heap — fake vtables, one callback set for every view,
   `QueryInterface` as a gate, `AddRef`/`Release` that never free.
3. Vtable ranks and `WebView2.h` — how slot numbers are counted, why a tag may stop early
   but never skip, and how `QueryInterface` doubles as the runtime version check.
4. x86 and x64: `put_Bounds` — the four argument shapes that were measured on the 64-bit
   runtime, the one that works, and why `hr = 0` is not proof.
5. Adding a method in six steps — worked end to end on the two calls behind
   `_WV2_ClearCookies`.
6. Diagnosing a failure — the `@error` / `@extended` plumbing, an HRESULT table, how to
   bisect a crash that prints nothing, and the four asynchronous methods.
7. Threading and the message pump — the STA, the pump, the GUI loop, and the teardown
   order the runtime expects.
8. Limits, pitfalls, references.

Read chapters 1 to 4 to understand it, 5 to 8 to change it.

## Known limits

- **The environment entry point is undocumented** (see *Design notes*). If a future
  runtime stops exporting `CreateWebViewEnvironmentWithOptionsInternal`,
  `_WV2_Create` fails with `$WV2_ERR_ENV` / `$WV2_ERR_RUNTIME` — it will not crash.
  The fallback is the single `DllCall` site inside `_WV2_Create`, at the cost of
  shipping Microsoft's `WebView2Loader.dll`.
- The runtime must already be installed; the UDF reports `$WV2_ERR_RUNTIME` and never
  installs anything.
- Up to 16 concurrent instances per script (`$WV2_ERR_FULL` beyond that).
- One instance is bound to the thread that created it — do not call it from a
  different thread.
- A `file://` or `NavigateToString` page has a null origin and cannot carry a cookie;
  `document.cookie` stays empty there by design.
- Chromium allows only the **first** automatic download of a page; a second scripted
  one is silently dropped and raises no `DownloadStarting` event. A redirected
  download appears on disk 0–3 s after the event, so wait for the file rather than
  assuming it is missing.
- `_WV2_ClearCookies` clears cookies only. Cache, history and localStorage need
  `ICoreWebView2Profile2::ClearBrowsingData`, which the view itself does not expose.
- Cookies live in the user data folder: views sharing `$sUserDataFolder` share the jar.
- With `$sUserDataFolder = ""` the view uses a private temporary folder named
  `AutoItWebView2_<pid>_<slot>` in `@TempDir`. `_WV2_Destroy` cannot always delete it at
  once — the browser process holds it for a few seconds — so it is removed by the next
  `_WV2_Create` that takes the same slot. Pass a folder yourself when the profile has to
  survive or be audited.

## References

- WebView2 Win32 C++ reference (the interfaces this UDF drives):
  https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/
- `ICoreWebView2Settings`, the page toggles behind `_WV2_SettingRead` / `_WV2_SettingWrite`:
  https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2settings
- User data folder, i.e. what `$sUserDataFolder` and `_WV2_ClearCookies` act on:
  https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder
- Runtime distribution and how to detect it (the basis of `_WV2_GetRuntimePath`):
  https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution

## License

MIT — Copyright (c) 2026 Numeric1. The `LICENSE` file must travel with any copy or
substantial portion of the code, and the `Author`/`License` lines of every source file
must stay intact. In short: use it, ship it, sell what you build with it, keep the
notice.

WebView2 itself is Microsoft's; the interface identifiers and vtable layout used here
follow their SDK (MIT). No Microsoft code is reproduced in this package.

## Related work

- The long-running forum thread [Microsoft Edge — WebView2](https://www.autoitscript.com/forum/topic/204362-microsoft-edge-webview2-embed-web-code-in-your-native-application/)
  is where AutoIt WebView2 embedding was first explored; those snippets load
  `WebView2Loader-x86/x64.dll`.
- [Ralle1976/Autoit-WebView2-UDF](https://github.com/Ralle1976/Autoit-WebView2-UDF) (MIT)
  packages WebView2 with `WebView2Loader*.dll` plus a helper DLL, 14 functions and a
  polling bridge, and adds a React component library on top.
- `OrdoWebView2.ocx` wraps WebView2 in a third-party ActiveX control, installed by its
  own setup.

What is different here: nothing to ship (the runtime's own DLL is called directly), real
COM event sinks instead of polling, and PDF, snapshots, downloads and cookies in the same
API. See the *Design notes* about the undocumented entry point that makes that possible.
