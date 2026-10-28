; #INDEX# =======================================================================================================================
; Title .........: WebView2 UDF
; AutoIt Version : 3.3.16+
; Language .......: English
; Version ........: 0.3.0
; Modified .......: 2026-10-28
; Description ...: Embeds the Microsoft Edge (Chromium) rendering engine inside an AutoIt GUI window.
;                  The UDF talks to the WebView2 runtime that Windows already provides through its own
;                  COM interfaces: no SDK, no DLL to ship, no wrapper binary, no registration, no
;                  download. Only kernel32, user32, ole32 and the system EmbeddedBrowserWebView.dll
;                  are touched.
;                  Navigation, bounds, zoom, JavaScript, the two way web message bridge, the page
;                  settings, event queueing, PNG/JPEG snapshots, a PDF export of the page, the
;                  downloads raised by a page and the cookies of the profile are all driven from
;                  AutoIt.
; Author ........: Numeric1
; Link ..........: https://www.autoitscript.com/forum/
; License .......: MIT, Copyright (c) 2026 Numeric1. Keep this header and the LICENSE file in any
;                  copy or redistribution. WebView2 interface identifiers and vtable layout follow
;                  the Microsoft WebView2 SDK (MIT); no Microsoft code is reproduced here.
; ===============================================================================================================================
; Requirements: Windows 10 or later carrying the "Microsoft Edge WebView2 Runtime", which every
; maintained Windows 10/11 installation already has. _WV2_GetRuntimePath() locates it; a missing
; runtime is reported as $WV2_ERR_RUNTIME, never installed.
;
; Design notes:
;   * One handle = one environment + one controller + one web view, all living in the thread that
;     called _WV2_Create. Up to 16 handles can be alive at the same time.
;   * COM pointers received as a callback argument are borrowed, so every wrapper is built with
;     ObjCreateInterface(..., False): the tag then starts at vtable slot 0 and the wrapper neither
;     adds nor releases a reference. The UDF calls AddRef/Release explicitly, which is what makes
;     _WV2_Destroy balanced and crash free.
;   * ICoreWebView2Controller::put_Bounds receives its RECT *by value*, so the x86 tag declares four
;     longs. Declaring "struct*" pushes a pointer, the callee reads the stack as coordinates and
;     the call never returns. On x64 neither four longs, nor two int64, nor AutoIt's own by-value
;     "struct" survive the call: the runtime reads the address of the sixteen bytes, so
;     __WV2_PutBounds calls that one method through the vtable with a pointer to a DllStruct.
;   * A method that only exists on a newer version of an interface is reached by QueryInterface on the
;     raw pointer, then called through DllCallAddress: an ObjCreateInterface tag would have to declare
;     every method of that interface, eighty of them before PrintToPdf alone.
;   * The UDF never shows a dialog and never writes to the console. Every failure is reported by
;     @error (a $WV2_ERR_* code) and @extended (the raw HRESULT when there is one).

#include-once
#include <File.au3>

; #CONSTANTS# ===================================================================================================================
; Error codes returned through @error
Global Const $WV2_ERR_NONE = 0
Global Const $WV2_ERR_HANDLE = 1          ; invalid or destroyed handle
Global Const $WV2_ERR_ARG = 2             ; invalid argument for this call
Global Const $WV2_ERR_RUNTIME = 3         ; WebView2 runtime not found on this machine
Global Const $WV2_ERR_COM = 4             ; COM initialisation or interface wrapper failure
Global Const $WV2_ERR_ENV = 5             ; environment creation failed
Global Const $WV2_ERR_CONTROLLER = 6      ; controller creation failed
Global Const $WV2_ERR_NOT_READY = 7       ; instance not usable yet
Global Const $WV2_ERR_CALL = 8            ; a WebView2 method returned a failure HRESULT
Global Const $WV2_ERR_TIMEOUT = 9         ; operation did not complete in the allowed time
Global Const $WV2_ERR_FULL = 10           ; too many live instances
Global Const $WV2_ERR_FILE = 11           ; a file given to the UDF could not be written

; Default timeouts, in milliseconds
Global Const $WV2_CREATE_TIMEOUT = 15000
Global Const $WV2_NAV_TIMEOUT = 30000

; Interface identifiers published by the WebView2 SDK
Global Const $WV2_IID_UNKNOWN = "{00000000-0000-0000-C000-000000000046}"
Global Const $WV2_IID_ENV = "{B96D755E-0319-4E92-A296-23436F46A1FC}"
Global Const $WV2_IID_CTL = "{4D00C0D1-9434-4EB6-8078-8697A560334F}"
Global Const $WV2_IID_WV = "{76ECEACB-0462-4D94-AC83-423A6793775E}"
Global Const $WV2_IID_ENVCB = "{4E8A3389-C9D8-4BD2-B6B5-124FEE6CC14D}"
Global Const $WV2_IID_CTLCB = "{6C4819F3-C9B7-4260-8127-C9F5BDE7F68C}"
Global Const $WV2_IID_NAVH = "{D33A35BF-1C49-4F98-93AB-006E0533FE1C}"
Global Const $WV2_IID_NAVARGS = "{30D68B7D-20D9-4752-A9CA-EC8448FBB5C1}"
Global Const $WV2_IID_NAVSH = "{9ADBE429-F36D-432B-9DDC-F8881FBD76E3}"
Global Const $WV2_IID_NAVSARGS = "{5B495469-E119-438A-9B18-7604F25F2E49}"
Global Const $WV2_IID_MSGH = "{57213F19-00E6-49FA-8E07-898EA01ECBD2}"
Global Const $WV2_IID_MSGARGS = "{0F99A40C-E962-4207-9E92-E3D542EFF849}"
Global Const $WV2_IID_NEWH = "{D4C185FE-C81C-4989-97AF-2D3FA7AB5651}"
Global Const $WV2_IID_NEWARGS = "{34ACB11C-FC37-4418-9132-F9C21D1EAFB9}"
Global Const $WV2_IID_PROCARGS = "{8155A9A4-1474-4A86-8CAE-151B0FA6B8CA}"
Global Const $WV2_IID_PROCH = "{79E0AEA4-990B-42D9-AA1D-0FCC2E5BC7F1}"
Global Const $WV2_IID_TITLEH = "{F5F2B923-953E-4042-9F95-F3A118E1AFD4}"
Global Const $WV2_IID_HISTH = "{C79A420C-EFD9-4058-9295-3E8B4BCAB645}"
Global Const $WV2_IID_EXECH = "{49511172-CC67-4BCA-9923-137112F4C4CC}"
Global Const $WV2_IID_ADDSCH = "{B99369F3-9B11-47B5-BC6F-8E7895FCEA17}"
Global Const $WV2_IID_CAPH = "{697E05E9-3D8F-45FA-96F4-8FFE1EDEDAF5}"
Global Const $WV2_IID_SETTINGS = "{E562E4F0-D7FA-43AC-8D71-C05150499F00}"
; The newer versions of ICoreWebView2 asked for through QueryInterface, and the interfaces they hand out.
Global Const $WV2_IID_WV2 = "{9E8F0CF8-E670-4B5E-B2BC-73E061E3184C}"
Global Const $WV2_IID_WV4 = "{20D02D59-6DF2-42DC-BD06-F98A694B1302}"
Global Const $WV2_IID_WV7 = "{79C24D83-09A3-45AE-9418-487F32A58740}"
Global Const $WV2_IID_PRINTH = "{CCF1EF04-FD8E-4D5F-B2DE-0983E41B8C36}"
Global Const $WV2_IID_DLH = "{EFEDC989-C396-41CA-83F7-07F845A55724}"
Global Const $WV2_IID_DLARGS = "{E99BBE21-43E9-4544-A732-282764EAFA60}"
Global Const $WV2_IID_COOKIE = "{177CD9E7-B6F5-451A-94A0-5D7A3A4C4141}"

; Event types reported through _WV2_GetEvent and _WV2_WaitEvent
Global Const $WV2_EVENT_NAVIGATION_STARTING = 1        ; $sData = uri, $iValue = 1 if user initiated
Global Const $WV2_EVENT_NAVIGATION_COMPLETED = 2       ; $sData = uri, $iValue = 1 success / web error id
Global Const $WV2_EVENT_WEB_MESSAGE = 3                ; $sData = message, $iValue = 1 plain / 0 json
Global Const $WV2_EVENT_NEW_WINDOW = 4                 ; $sData = uri the page tried to open
Global Const $WV2_EVENT_TITLE_CHANGED = 5              ; $sData = new title
Global Const $WV2_EVENT_HISTORY_CHANGED = 6            ; back or forward availability changed
Global Const $WV2_EVENT_PROCESS_FAILED = 7             ; $iValue = a $WV2_PROCFAIL_* code
Global Const $WV2_EVENT_DOWNLOAD_STARTING = 8          ; $sData = uri, $iValue = 1 refused / 0 accepted

; Process failure kinds, COREWEBVIEW2_PROCESS_FAILED_KIND
Global Const $WV2_PROCFAIL_BROWSER = 0
Global Const $WV2_PROCFAIL_RENDER_EXITED = 1
Global Const $WV2_PROCFAIL_RENDER_UNRESPONSIVE = 2
Global Const $WV2_PROCFAIL_FRAME_RENDER_EXITED = 3
Global Const $WV2_PROCFAIL_UTILITY_EXITED = 4
Global Const $WV2_PROCFAIL_SANDBOX_HELPER_EXITED = 5
Global Const $WV2_PROCFAIL_GPU_EXITED = 6
Global Const $WV2_PROCFAIL_PPAPI_PLUGIN_EXITED = 7
Global Const $WV2_PROCFAIL_PPAPI_BROKER_EXITED = 8
Global Const $WV2_PROCFAIL_UNKNOWN_EXITED = 9

; Image formats accepted by _WV2_CapturePreview
Global Const $WV2_IMAGE_PNG = 0
Global Const $WV2_IMAGE_JPEG = 1

Global Const $WV2_EXEC_TIMEOUT = 5000
Global Const $WV2_PRINT_TIMEOUT = 30000

; Internal constants
Global Const $__WV2_MAX = 16
Global Const $__WV2_PTRS_PER_BLOCK = 5            ; 4 vtable slots + 1 object pointer
Global Const $__WV2_HR_E_NOINTERFACE = 0x80004002
Global Const $__WV2_HR_E_FAIL = 0x80004005         ; returned when a raw call could not even be made
Global Const $__WV2_CLSID_KEY = "Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
Global Const $__WV2_DLL_NAME = "EmbeddedBrowserWebView.dll"
Global Const $__WV2_QCAP = 64                     ; events kept per instance before they are dropped

; Handler slots. One fake COM object is laid out per (instance, slot), which is what lets a single
; set of shared callbacks serve every view: the this-pointer gives back both the instance and the slot.
Global Const $__WV2_H_ENV = 1                     ; environment created
Global Const $__WV2_H_CTL = 2                     ; controller created
Global Const $__WV2_H_NAVC = 3                    ; NavigationCompleted
Global Const $__WV2_H_NAVS = 4                    ; NavigationStarting
Global Const $__WV2_H_MSG = 5                     ; WebMessageReceived
Global Const $__WV2_H_NEW = 6                     ; NewWindowRequested
Global Const $__WV2_H_TITLE = 7                   ; DocumentTitleChanged
Global Const $__WV2_H_HIST = 8                    ; HistoryChanged
Global Const $__WV2_H_PROC = 9                    ; ProcessFailed
Global Const $__WV2_H_EXEC = 10                   ; ExecuteScript answer
Global Const $__WV2_H_ADDSCRIPT = 11              ; AddScriptToExecuteOnDocumentCreated answer
Global Const $__WV2_H_CAP = 12                    ; CapturePreview answer
Global Const $__WV2_H_PRINT = 13                  ; PrintToPdf answer
Global Const $__WV2_H_DOWNLOAD = 14               ; DownloadStarting
Global Const $__WV2_SLOT_COUNT = 14

; Vtable slots of the methods called raw through QueryInterface, counted from the official WebView2.h.
; Slot 0 is QueryInterface, slot 3 is the first method the interface itself declares.
Global Const $__WV2_VT_QI = 0
Global Const $__WV2_VT_RELEASE = 2
Global Const $__WV2_VT_PRINTTOPDF = 80            ; ICoreWebView2_7::PrintToPdf
Global Const $__WV2_VT_ADDDL = 75                 ; ICoreWebView2_4::add_DownloadStarting
Global Const $__WV2_VT_REMOVEDL = 76              ; ICoreWebView2_4::remove_DownloadStarting
Global Const $__WV2_VT_DLA_OP = 3                 ; DownloadStartingEventArgs::get_DownloadOperation
Global Const $__WV2_VT_DLA_CANCEL = 5             ; DownloadStartingEventArgs::put_Cancel
Global Const $__WV2_VT_DLA_PATH = 6               ; DownloadStartingEventArgs::get_ResultFilePath
Global Const $__WV2_VT_DLA_PATHPUT = 7            ; DownloadStartingEventArgs::put_ResultFilePath
Global Const $__WV2_VT_DLO_URI = 9                ; DownloadOperation::get_Uri
Global Const $__WV2_VT_GETCOOKIE = 66             ; ICoreWebView2_2::get_CookieManager
Global Const $__WV2_VT_COOKIEDALL = 10            ; ICoreWebView2CookieManager::DeleteAllCookies
Global Const $__WV2_VT_PUTBOUNDS = 6              ; ICoreWebView2Controller::put_Bounds
; Which newer version of ICoreWebView2 __WV2_ViewIf has to bring back.
Global Const $__WV2_IF_2 = 1
Global Const $__WV2_IF_4 = 2
Global Const $__WV2_IF_7 = 3

; Interface tags. Entry 1 maps to vtable slot 0 because every wrapper is built with flag = False.
; Method order and parameter types are those of the official WebView2.h.
Global Const $__WV2_TAG_IUNKNOWN = "QueryInterface hresult(ptr;ptr); AddRef dword(); Release dword(); "
Global Const $__WV2_TAG_ENV = $__WV2_TAG_IUNKNOWN & _
		"CreateCoreWebView2Controller hresult(ptr;ptr); CreateWebResourceResponse hresult(ptr;int;wstr;wstr;ptr); get_BrowserVersionString hresult(wstr*);"
Global Const $__WV2_TAG_CTL = $__WV2_TAG_IUNKNOWN & _
		"get_IsVisible hresult(int*); put_IsVisible hresult(int); get_Bounds hresult(struct*); put_Bounds hresult(long;long;long;long);" & _
		"get_ZoomFactor hresult(double*); put_ZoomFactor hresult(double); add_ZoomFactorChanged hresult(ptr;int64*); remove_ZoomFactorChanged hresult(int64);" & _
		"SetBoundsAndZoomFactor hresult(long;long;long;long;double); MoveFocus hresult(int); add_MoveFocusRequested hresult(ptr;int64*); remove_MoveFocusRequested hresult(int64);" & _
		"add_GotFocus hresult(ptr;int64*); remove_GotFocus hresult(int64); add_LostFocus hresult(ptr;int64*); remove_LostFocus hresult(int64);" & _
		"add_AcceleratorKeyPressed hresult(ptr;int64*); remove_AcceleratorKeyPressed hresult(int64); get_ParentWindow hresult(ptr*); put_ParentWindow hresult(ptr);" & _
		"NotifyParentWindowPositionChanged hresult(); Close hresult(); get_CoreWebView2 hresult(ptr*);"
Global Const $__WV2_TAG_WV = $__WV2_TAG_IUNKNOWN & _
		"get_Settings hresult(ptr*); get_Source hresult(wstr*); Navigate hresult(wstr); NavigateToString hresult(wstr);" & _
		"add_NavigationStarting hresult(ptr;int64*); remove_NavigationStarting hresult(int64);" & _
		"add_ContentLoading hresult(ptr;int64*); remove_ContentLoading hresult(int64);" & _
		"add_SourceChanged hresult(ptr;int64*); remove_SourceChanged hresult(int64);" & _
		"add_HistoryChanged hresult(ptr;int64*); remove_HistoryChanged hresult(int64);" & _
		"add_NavigationCompleted hresult(ptr;int64*); remove_NavigationCompleted hresult(int64);" & _
		"add_FrameNavigationStarting hresult(ptr;int64*); remove_FrameNavigationStarting hresult(int64);" & _
		"add_FrameNavigationCompleted hresult(ptr;int64*); remove_FrameNavigationCompleted hresult(int64);" & _
		"add_ScriptDialogOpening hresult(ptr;int64*); remove_ScriptDialogOpening hresult(int64);" & _
		"add_PermissionRequested hresult(ptr;int64*); remove_PermissionRequested hresult(int64);" & _
		"add_ProcessFailed hresult(ptr;int64*); remove_ProcessFailed hresult(int64);" & _
		"AddScriptToExecuteOnDocumentCreated hresult(wstr;ptr); RemoveScriptToExecuteOnDocumentCreated hresult(wstr);" & _
		"ExecuteScript hresult(wstr;ptr); CapturePreview hresult(dword;ptr;ptr); Reload hresult();" & _
		"PostWebMessageAsJson hresult(wstr); PostWebMessageAsString hresult(wstr);" & _
		"add_WebMessageReceived hresult(ptr;int64*); remove_WebMessageReceived hresult(int64);" & _
		"CallDevToolsProtocolMethod hresult(wstr;wstr;ptr); get_BrowserProcessId hresult(dword*);" & _
		"get_CanGoBack hresult(int*); get_CanGoForward hresult(int*); GoBack hresult(); GoForward hresult();" & _
		"GetDevToolsProtocolEventReceiver hresult(wstr;ptr*); Stop hresult();" & _
		"add_NewWindowRequested hresult(ptr;int64*); remove_NewWindowRequested hresult(int64);" & _
		"add_DocumentTitleChanged hresult(ptr;int64*); remove_DocumentTitleChanged hresult(int64);" & _
		"get_DocumentTitle hresult(wstr*);"
Global Const $__WV2_TAG_NAVARGS = $__WV2_TAG_IUNKNOWN & _
		"get_IsSuccess hresult(int*); get_WebErrorStatus hresult(dword*); get_NavigationId hresult(int64*);"
Global Const $__WV2_TAG_NAVSARGS = $__WV2_TAG_IUNKNOWN & _
		"get_Uri hresult(wstr*); get_IsUserInitiated hresult(int*); get_IsRedirected hresult(int*); get_RequestHeaders hresult(ptr*);" & _
		"get_Cancel hresult(int*); put_Cancel hresult(int); get_NavigationId hresult(int64*);"
Global Const $__WV2_TAG_MSGARGS = $__WV2_TAG_IUNKNOWN & _
		"get_Source hresult(wstr*); get_WebMessageAsJson hresult(wstr*); TryGetWebMessageAsString hresult(wstr*);"
Global Const $__WV2_TAG_NEWARGS = $__WV2_TAG_IUNKNOWN & _
		"get_Uri hresult(wstr*); put_NewWindow hresult(ptr); get_NewWindow hresult(ptr*); put_Handled hresult(int); get_Handled hresult(int*);" & _
		"get_IsUserInitiated hresult(int*); GetDeferral hresult(ptr*); get_WindowFeatures hresult(ptr*);"
Global Const $__WV2_TAG_PROCARGS = $__WV2_TAG_IUNKNOWN & _
		"get_ProcessFailedKind hresult(dword*);"
; The nine settings of this runtime version, in vtable order. All are BOOL, read with get_ and written with put_.
Global Const $__WV2_TAG_SETTINGS = $__WV2_TAG_IUNKNOWN & _
		"get_IsScriptEnabled hresult(int*); put_IsScriptEnabled hresult(int);" & _
		"get_IsWebMessageEnabled hresult(int*); put_IsWebMessageEnabled hresult(int);" & _
		"get_AreDefaultScriptDialogsEnabled hresult(int*); put_AreDefaultScriptDialogsEnabled hresult(int);" & _
		"get_IsStatusBarEnabled hresult(int*); put_IsStatusBarEnabled hresult(int);" & _
		"get_AreDevToolsEnabled hresult(int*); put_AreDevToolsEnabled hresult(int);" & _
		"get_AreDefaultContextMenusEnabled hresult(int*); put_AreDefaultContextMenusEnabled hresult(int);" & _
		"get_AreHostObjectsAllowed hresult(int*); put_AreHostObjectsAllowed hresult(int);" & _
		"get_IsZoomControlEnabled hresult(int*); put_IsZoomControlEnabled hresult(int);" & _
		"get_IsBuiltInErrorPageEnabled hresult(int*); put_IsBuiltInErrorPageEnabled hresult(int);"

; #VARIABLES# ===================================================================================================================
Global $__WV2_iLastError = $WV2_ERR_NONE
Global $__WV2_iLastHR = 0
Global $__WV2_sLastFunc = ""
Global $__WV2_iCoState = 0                            ; 1 once the UDF has initialised COM
Global $__WV2_iClientW = 0                            ; scratch client size of the parent window
Global $__WV2_iClientH = 0

; Instance table. Slot 0 is never used.
Global $__WV2_aUsed[$__WV2_MAX + 1]
Global $__WV2_oEnv[$__WV2_MAX + 1]
Global $__WV2_oCtl[$__WV2_MAX + 1]
Global $__WV2_pCtl[$__WV2_MAX + 1]                  ; raw ICoreWebView2Controller pointer behind $__WV2_oCtl
Global $__WV2_oWv[$__WV2_MAX + 1]
Global $__WV2_pWv[$__WV2_MAX + 1]                  ; raw ICoreWebView2 pointer behind $__WV2_oWv
; The newer versions of ICoreWebView2, asked for through QueryInterface when a method first needs one
; and released with the view. Index: $__WV2_IF_2, $__WV2_IF_4 or $__WV2_IF_7, slot 0 is never used.
Global $__WV2_pWvIf[$__WV2_MAX + 1][4]
Global $__WV2_oSettings[$__WV2_MAX + 1]
Global $__WV2_pObj[$__WV2_MAX + 1][$__WV2_SLOT_COUNT + 1]   ; address of each fake handler object
Global $__WV2_iTok[$__WV2_MAX + 1][$__WV2_SLOT_COUNT + 1]   ; cookie returned by add_*, 0 when not subscribed
Global $__WV2_hParent[$__WV2_MAX + 1]
Global $__WV2_iLeft[$__WV2_MAX + 1]
Global $__WV2_iTop[$__WV2_MAX + 1]
Global $__WV2_iRight[$__WV2_MAX + 1]                  ; last bounds, held as a RECT
Global $__WV2_iBottom[$__WV2_MAX + 1]
Global $__WV2_bEnv[$__WV2_MAX + 1]                    ; environment callback answered
Global $__WV2_bCtl[$__WV2_MAX + 1]                    ; controller callback answered
Global $__WV2_bReady[$__WV2_MAX + 1]
Global $__WV2_bEnvErr[$__WV2_MAX + 1]
Global $__WV2_bCtlErr[$__WV2_MAX + 1]
Global $__WV2_bNavDone[$__WV2_MAX + 1]
Global $__WV2_bNavOK[$__WV2_MAX + 1]
Global $__WV2_iWebErr[$__WV2_MAX + 1]
Global $__WV2_iHR[$__WV2_MAX + 1]
Global $__WV2_sUser[$__WV2_MAX + 1]
Global $__WV2_bTempUser[$__WV2_MAX + 1]
Global $__WV2_sVersion[$__WV2_MAX + 1]
Global $__WV2_sNavFilter[$__WV2_MAX + 1]              ; regular expression, empty means never cancel
Global $__WV2_sDlFilter[$__WV2_MAX + 1]               ; regular expression, empty means never refuse
Global $__WV2_sDlFolder[$__WV2_MAX + 1]               ; empty means the folder chosen by the runtime

; One block of five pointers per (instance, handler slot) holds a fake vtable and its object.
; A single global struct owns that memory for the life of the script, so no copy semantics apply.
Global $__WV2_tHeap = 0
Global $__WV2_iPtrSize = 0
; One set of callbacks serves every handler object of every instance: the this-pointer tells which
; instance and which slot is calling, so one registration per slot covers the whole life of the script.
Global $__WV2_hCbQI = 0
Global $__WV2_hCbAddRef = 0
Global $__WV2_hCbRelease = 0
Global $__WV2_hCbInv[$__WV2_SLOT_COUNT + 1]
; The Invoke function and the callback parameter list of every slot. Index 0 is never used.
Global $__WV2_aInvFunc[$__WV2_SLOT_COUNT + 1] = [ _
		"", "__WV2_InvEnv", "__WV2_InvCtl", "__WV2_InvNavC", "__WV2_InvNavS", "__WV2_InvMsg", "__WV2_InvNew", _
		"__WV2_InvTitle", "__WV2_InvHist", "__WV2_InvProc", "__WV2_InvExec", "__WV2_InvAddScript", "__WV2_InvCap", _
		"__WV2_InvPrint", "__WV2_InvDl"]
Global $__WV2_aInvArgs[$__WV2_SLOT_COUNT + 1] = [ _
		"", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", _
		"ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr;ptr", "ptr;ptr", "ptr;long;long", _
		"ptr;ptr;ptr"]
; The handler IID accepted by QueryInterface for each slot, so a fake object never claims an interface
; whose vtable it does not carry.
Global $__WV2_aInvIID[$__WV2_SLOT_COUNT + 1] = [ _
		"", $WV2_IID_ENVCB, $WV2_IID_CTLCB, $WV2_IID_NAVH, $WV2_IID_NAVSH, $WV2_IID_MSGH, $WV2_IID_NEWH, _
		$WV2_IID_TITLEH, $WV2_IID_HISTH, $WV2_IID_PROCH, $WV2_IID_EXECH, $WV2_IID_ADDSCH, $WV2_IID_CAPH, _
		$WV2_IID_PRINTH, $WV2_IID_DLH]

; Queue of the events received per instance, read in order by _WV2_GetEvent.
Global $__WV2_aEvtType[$__WV2_MAX + 1][$__WV2_QCAP]
Global $__WV2_aEvtStr[$__WV2_MAX + 1][$__WV2_QCAP]
Global $__WV2_aEvtNum[$__WV2_MAX + 1][$__WV2_QCAP]
Global $__WV2_iEvtHead[$__WV2_MAX + 1]
Global $__WV2_iEvtCount[$__WV2_MAX + 1]
Global $__WV2_iEvtDrop[$__WV2_MAX + 1]

; State of the asynchronous operations, one set per (instance, slot): ExecuteScript,
; AddScriptToExecuteOnDocumentCreated, CapturePreview and PrintToPdf each answer through their own slot.
; PrintToPdf also keeps its BOOL answer in the text cell: a successful call that refused to write the
; file is a different failure from a call that failed.
Global $__WV2_bOpDone[$__WV2_MAX + 1][$__WV2_SLOT_COUNT + 1]
Global $__WV2_iOpHR[$__WV2_MAX + 1][$__WV2_SLOT_COUNT + 1]
Global $__WV2_sOpOut[$__WV2_MAX + 1][$__WV2_SLOT_COUNT + 1]

; ===============================================================================================================================
; Public API
; ===============================================================================================================================

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetRuntimePath
; Description ...: Locates the WebView2 runtime already installed on the machine.
; Syntax ........: _WV2_GetRuntimePath()
; Parameters ....: none
; Return values .: Success: full path of the EmbeddedBrowserWebView.dll matching this AutoIt bitness.
;                  Failure: "" with @error = $WV2_ERR_RUNTIME.
; Author ........: Numeric1
; Remarks .......: The version registered for all users is tried first, then the one registered for the
;                  current user, then the highest version found on disk. Nothing is downloaded.
; Related .......: _WV2_Create
; ===============================================================================================================================
Func _WV2_GetRuntimePath()
	Local $i, $j
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	$__WV2_sLastFunc = "_WV2_GetRuntimePath"

	Local $sVer = ""
	Local $bFound = False
	Local $aHives[3] = ["HKLM\", "HKLM64\", "HKCU\"]
	For $i = 0 To 2
		$sVer = RegRead($aHives[$i] & $__WV2_CLSID_KEY, "pv")
		If @Error = 0 And $sVer <> "" Then
			$bFound = True
			ExitLoop
		EndIf
	Next

	If $bFound Then
		Local $sPath = __WV2_DllForVersion($sVer)
		If $sPath <> "" Then Return SetError(0, 0, $sPath)
	EndIf

	; Fall back to the highest version found on disk.
	Local $sBest = "", $sFound = ""
	For $i = 1 To 2
		Local $sRoot = __WV2_ProgramFiles($i = 1) & "\Microsoft\EdgeWebView\Application"
		If Not FileExists($sRoot) Then ContinueLoop
		Local $aDirs = _FileListToArray($sRoot, "*", $FLTA_FOLDERS)
		If @Error Or Not IsArray($aDirs) Then ContinueLoop
		For $j = 1 To $aDirs[0]
			If Not StringRegExp($aDirs[$j], "^\d+\.\d+\.\d+\.\d+$") Then ContinueLoop
			Local $sDll = __WV2_DllForVersion($aDirs[$j])
			If $sDll <> "" And __WV2_CompareVersion($aDirs[$j], $sBest) > 0 Then
				$sBest = $aDirs[$j]
				$sFound = $sDll
			EndIf
		Next
	Next
	If $sFound <> "" Then Return SetError(0, 0, $sFound)

	$__WV2_iLastError = $WV2_ERR_RUNTIME
	Return SetError($__WV2_iLastError, 0, "")
EndFunc   ;==>_WV2_GetRuntimePath

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_Create
; Description ...: Creates a WebView2 view inside a window and returns its handle.
; Syntax ........: _WV2_Create($hParent[, $iLeft = 0[, $iTop = 0[, $iWidth = -1[, $iHeight = -1[,
;                  $sUserDataFolder = ""[, $iTimeoutMs = $WV2_CREATE_TIMEOUT]]]]])
; Parameters ....: $hParent - Handle of the window the browser is attached to, usually a GUICreate one.
;                  $iLeft - X coordinate of the browser area, in the client area of $hParent.
;                  $iTop - Y coordinate of the browser area, in the client area of $hParent.
;                  $iWidth - Width in pixels. -1 uses the rest of the client width.
;                  $iHeight - Height in pixels. -1 uses the rest of the client height.
;                  $sUserDataFolder - Folder holding the browser profile (cache, cookies, history).
;                     "" uses a private temporary folder, tied to the handle number, that is removed
;                     when the slot is used again.
;                  $iTimeoutMs - Time allowed for the runtime to answer, in milliseconds.
; Return values .: Success: handle >= 1.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: The browser is a real window inside $hParent and covers the AutoIt controls that
;                  overlap its area; leave a band of its client area free for a toolbar, or create the
;                  controls on a sibling window. Windows messages are pumped while waiting, so the GUI
;                  stays responsive. Call this from the thread that owns $hParent.
;
;                  A temporary profile folder cannot always be deleted by _WV2_Destroy: the browser
;                  process holds it for a few seconds. It is then deleted by the next _WV2_Create that
;                  takes the same handle, and a folder left in the temporary directory when the program
;                  ends is only that: a folder. Give $sUserDataFolder yourself when the profile matters.
; Related .......: _WV2_Destroy, _WV2_Navigate, _WV2_FitToParent
; ===============================================================================================================================
Func _WV2_Create($hParent, $iLeft = 0, $iTop = 0, $iWidth = -1, $iHeight = -1, $sUserDataFolder = "", $iTimeoutMs = $WV2_CREATE_TIMEOUT)
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	$__WV2_sLastFunc = "_WV2_Create"

	If Not IsHWnd($hParent) Then
		$__WV2_iLastError = $WV2_ERR_ARG
		Return SetError($__WV2_iLastError, 0, 0)
	EndIf
	__WV2_InitHeap()
	Local $i = __WV2_Alloc()
	If $i = 0 Then
		$__WV2_iLastError = $WV2_ERR_FULL
		Return SetError($__WV2_iLastError, 0, 0)
	EndIf

	Local $sDll = _WV2_GetRuntimePath()
	If $sDll = "" Then
		$__WV2_iLastError = $WV2_ERR_RUNTIME
		__WV2_Free($i)
		Return SetError($__WV2_iLastError, 0, 0)
	EndIf

	; The runtime must be reached from a single threaded apartment. The UDF never calls
	; CoUninitialize, so a COM aware script keeps working after a view is destroyed.
	If $__WV2_iCoState = 0 Then
		Local $aCo = DllCall("ole32.dll", "long", "CoInitializeEx", "ptr", 0, "dword", 2)
		If @Error Or $aCo[0] < 0 Then
			$__WV2_iLastError = $WV2_ERR_COM
			$__WV2_iLastHR = (@Error ? 0 : $aCo[0])
			__WV2_Free($i)
			Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
		EndIf
		$__WV2_iCoState = 1
	EndIf

	__WV2_ClientSize($hParent)
	$__WV2_hParent[$i] = $hParent
	$__WV2_iLeft[$i] = Int($iLeft)
	$__WV2_iTop[$i] = Int($iTop)
	$__WV2_iRight[$i] = $__WV2_iLeft[$i] + ($iWidth < 0 ? $__WV2_iClientW - $__WV2_iLeft[$i] : Int($iWidth))
	$__WV2_iBottom[$i] = $__WV2_iTop[$i] + ($iHeight < 0 ? $__WV2_iClientH - $__WV2_iTop[$i] : Int($iHeight))

	$sUserDataFolder = StringStripWS(String($sUserDataFolder), 3)
	If $sUserDataFolder = "" Then
		$sUserDataFolder = @TempDir & "\AutoItWebView2_" & @AutoItPID & "_" & $i
		$__WV2_bTempUser[$i] = True
		; The browser process keeps a profile folder for a few seconds after the view is gone, which is
		; longer than _WV2_Destroy waits, so what the previous view of this slot left behind is removed here.
		If FileExists($sUserDataFolder) Then DirRemove($sUserDataFolder, 1)
	Else
		$__WV2_bTempUser[$i] = False
	EndIf
	DirCreate($sUserDataFolder)
	$__WV2_sUser[$i] = $sUserDataFolder

	__WV2_BuildAllHandlers($i)

	; The environment answers through __WV2_InvEnv, which immediately requests the controller.
	Local $aCE = DllCall($sDll, "long", "CreateWebViewEnvironmentWithOptionsInternal", _
			"bool", 1, "int", 0, "wstr", $sUserDataFolder, "ptr", 0, "ptr", $__WV2_pObj[$i][$__WV2_H_ENV])
	If @Error Then
		__WV2_SetErr($WV2_ERR_RUNTIME, 0, "CreateWebViewEnvironmentWithOptionsInternal")
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If $aCE[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_ENV, $aCE[0], "CreateWebViewEnvironmentWithOptionsInternal")
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	If Not __WV2_WaitFor($i, $iTimeoutMs) Then
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	; From here on everything runs on the calling thread, with a live controller.
	If __WV2_PutBounds($i, $__WV2_iLeft[$i], $__WV2_iTop[$i], $__WV2_iRight[$i], $__WV2_iBottom[$i]) = 0 Then
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $hr = $__WV2_oCtl[$i].put_IsVisible(1)
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2Controller::put_IsVisible")
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	; NavigationCompleted is the one event every handle needs: _WV2_WaitNavigation waits on it.
	If Not __WV2_Attach($i, $__WV2_H_NAVC) Then
		__WV2_Fail($i)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	__WV2_ClientSize($__WV2_hParent[$i])
	Local $s = ""
	If $__WV2_oEnv[$i].get_BrowserVersionString($s) = 0 Then $__WV2_sVersion[$i] = $s
	$__WV2_bReady[$i] = True
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, $i)
EndFunc   ;==>_WV2_Create

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_Destroy
; Description ...: Releases a WebView2 view and everything its handle owns.
; Syntax ........: _WV2_Destroy($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1. @extended holds the HRESULT of the controller Close call, 0 if none.
;                  Failure: 0 with @error = $WV2_ERR_HANDLE.
; Author ........: Numeric1
; Remarks .......: The release order is the one the runtime expects: unregister the event handler,
;                  release the web view, close the controller and release it, release the environment.
;                  A temporary user data folder is deleted here when the browser process lets go of it,
;                  otherwise by the next _WV2_Create of the same handle; one supplied by the caller is
;                  left alone either way. The browser window disappears with the call.
; Related .......: _WV2_Create
; ===============================================================================================================================
Func _WV2_Destroy($iHandle)
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	$__WV2_sLastFunc = "_WV2_Destroy"
	If Not __WV2_Valid($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	__WV2_Teardown($iHandle)
	__WV2_Free($iHandle)
	Return SetError(0, $__WV2_iLastHR, 1)
EndFunc   ;==>_WV2_Destroy

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_IsReady
; Description ...: Tells whether a handle is usable.
; Syntax ........: _WV2_IsReady($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: 1 ready, 0 not ready or invalid. @error is always 0.
; Author ........: Numeric1
; Related .......: _WV2_Create
; ===============================================================================================================================
Func _WV2_IsReady($iHandle)
	If Not __WV2_Valid($iHandle) Then Return SetError(0, 0, 0)
	Return SetError(0, 0, $__WV2_bReady[$iHandle] ? 1 : 0)
EndFunc   ;==>_WV2_IsReady

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_Navigate
; Description ...: Starts a navigation to an URL.
; Syntax ........: _WV2_Navigate($iHandle, $sUrl)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sUrl - Absolute http:, https:, file: or data: URL.
; Return values .: Success: 1. The navigation itself is asynchronous: use _WV2_WaitNavigation or poll
;                  _WV2_IsNavigationComplete.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_NavigateToString, _WV2_WaitNavigation
; ===============================================================================================================================
Func _WV2_Navigate($iHandle, $sUrl)
	$__WV2_sLastFunc = "_WV2_Navigate"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sUrl) Or $sUrl = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_Navigate")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	__WV2_BeginNavigation($iHandle)
	Local $hr = $__WV2_oWv[$iHandle].Navigate($sUrl)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2::Navigate")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_Navigate

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_NavigateToString
; Description ...: Renders an HTML string, with no file and no server.
; Syntax ........: _WV2_NavigateToString($iHandle, $sHtml)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sHtml - Complete HTML document.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Remarks .......: The document is served from an internal data URI, so _WV2_GetSource does not return
;                  the HTML. Scripts, styles and images addressed by an absolute URL load normally.
; Related .......: _WV2_Navigate
; ===============================================================================================================================
Func _WV2_NavigateToString($iHandle, $sHtml)
	$__WV2_sLastFunc = "_WV2_NavigateToString"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sHtml) Or $sHtml = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_NavigateToString")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	__WV2_BeginNavigation($iHandle)
	Local $hr = $__WV2_oWv[$iHandle].NavigateToString($sHtml)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2::NavigateToString")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_NavigateToString

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_WaitNavigation
; Description ...: Waits until the running navigation is over.
; Syntax ........: _WV2_WaitNavigation($iHandle[, $iTimeoutMs = $WV2_NAV_TIMEOUT])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $iTimeoutMs - Time allowed, in milliseconds.
; Return values .: Success: 1, @extended = 0 when the page loaded or the COREWEBVIEW2_WEB_ERROR_STATUS
;                  value when it failed.
;                  Failure: 0, with @error set to a $WV2_ERR_* code ($WV2_ERR_TIMEOUT when out of time).
; Author ........: Numeric1
; Remarks .......: Windows messages are pumped while waiting, so the GUI keeps working.
;                  A navigation refused by _WV2_SetNavigationFilter ends here with @extended = 14, the
;                  cancellation status, not a connection failure.
; Related .......: _WV2_IsNavigationComplete, _WV2_Navigate, _WV2_SetNavigationFilter
; ===============================================================================================================================
Func _WV2_WaitNavigation($iHandle, $iTimeoutMs = $WV2_NAV_TIMEOUT)
	$__WV2_sLastFunc = "_WV2_WaitNavigation"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $tEnd = TimerInit()
	While Not $__WV2_bNavDone[$iHandle]
		__WV2_Pump(20)
		If TimerDiff($tEnd) > $iTimeoutMs Then
			__WV2_SetErr($WV2_ERR_TIMEOUT, 0, "_WV2_WaitNavigation")
			Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
		EndIf
	WEnd
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, $__WV2_iWebErr[$iHandle], 1)
EndFunc   ;==>_WV2_WaitNavigation

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_IsNavigationComplete
; Description ...: Tells whether the last navigation of a handle is over.
; Syntax ........: _WV2_IsNavigationComplete($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1 completed, 0 still running. @error is always 0.
;                  Failure: -1 with @error = $WV2_ERR_HANDLE.
;                  @extended carries the last COREWEBVIEW2_WEB_ERROR_STATUS value, 0 meaning no error.
; Author ........: Numeric1
; Related .......: _WV2_WaitNavigation
; ===============================================================================================================================
Func _WV2_IsNavigationComplete($iHandle)
	$__WV2_sLastFunc = "_WV2_IsNavigationComplete"
	If Not __WV2_Valid($iHandle) Then Return SetError($__WV2_iLastError, 0, -1)
	If Not $__WV2_bReady[$iHandle] Then Return SetError(0, 0, 0)
	Return SetError(0, $__WV2_iWebErr[$iHandle], $__WV2_bNavDone[$iHandle] ? 1 : 0)
EndFunc   ;==>_WV2_IsNavigationComplete

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetTitle
; Description ...: Reads the title of the current document.
; Syntax ........: _WV2_GetTitle($iHandle, $sTitle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sTitle - Variable receiving the title, passed by reference.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_GetSource
; ===============================================================================================================================
Func _WV2_GetTitle($iHandle, ByRef $sTitle)
	$__WV2_sLastFunc = "_WV2_GetTitle"
	$sTitle = ""
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $s = ""
	Local $hr = $__WV2_oWv[$iHandle].get_DocumentTitle($s)
	If $hr <> 0 Then
		__WV2_Result($hr, "ICoreWebView2::get_DocumentTitle")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$sTitle = $s
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_GetTitle

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetSource
; Description ...: Reads the URI of the current document.
; Syntax ........: _WV2_GetSource($iHandle, $sUrl)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sUrl - Variable receiving the URI, passed by reference.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_GetTitle
; ===============================================================================================================================
Func _WV2_GetSource($iHandle, ByRef $sUrl)
	$__WV2_sLastFunc = "_WV2_GetSource"
	$sUrl = ""
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $s = ""
	Local $hr = $__WV2_oWv[$iHandle].get_Source($s)
	If $hr <> 0 Then
		__WV2_Result($hr, "ICoreWebView2::get_Source")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$sUrl = $s
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_GetSource

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetBounds
; Description ...: Moves and resizes the browser area inside its parent window.
; Syntax ........: _WV2_SetBounds($iHandle, $iLeft, $iTop, $iWidth, $iHeight)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $iLeft - X coordinate in the client area of the parent window.
;                  $iTop - Y coordinate in the client area of the parent window.
;                  $iWidth - Width in pixels.
;                  $iHeight - Height in pixels.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_FitToParent, _WV2_SetVisible
; ===============================================================================================================================
Func _WV2_SetBounds($iHandle, $iLeft, $iTop, $iWidth, $iHeight)
	$__WV2_sLastFunc = "_WV2_SetBounds"
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	$__WV2_iLeft[$iHandle] = Int($iLeft)
	$__WV2_iTop[$iHandle] = Int($iTop)
	$__WV2_iRight[$iHandle] = $__WV2_iLeft[$iHandle] + Int($iWidth)
	$__WV2_iBottom[$iHandle] = $__WV2_iTop[$iHandle] + Int($iHeight)
	; The RECT is a by-value struct: x86 uses the wrapper, x64 a vtable call. See __WV2_PutBounds.
	Local $bOk = __WV2_PutBounds($iHandle, $__WV2_iLeft[$iHandle], $__WV2_iTop[$iHandle], $__WV2_iRight[$iHandle], $__WV2_iBottom[$iHandle])
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_SetBounds

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetBounds
; Description ...: Reads the browser area currently used inside the parent window.
; Syntax ........: _WV2_GetBounds($iHandle, $iLeft, $iTop, $iWidth, $iHeight)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $iLeft - Variable receiving the X coordinate, passed by reference.
;                  $iTop - Variable receiving the Y coordinate, passed by reference.
;                  $iWidth - Variable receiving the width, passed by reference.
;                  $iHeight - Variable receiving the height, passed by reference.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_SetBounds
; ===============================================================================================================================
Func _WV2_GetBounds($iHandle, ByRef $iLeft, ByRef $iTop, ByRef $iWidth, ByRef $iHeight)
	$__WV2_sLastFunc = "_WV2_GetBounds"
	$iLeft = 0
	$iTop = 0
	$iWidth = 0
	$iHeight = 0
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $tRc = DllStructCreate("long left;long top;long right;long bottom")
	Local $hr = $__WV2_oCtl[$iHandle].get_Bounds($tRc)
	If $hr <> 0 Then
		__WV2_Result($hr, "ICoreWebView2Controller::get_Bounds")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$iLeft = DllStructGetData($tRc, "left")
	$iTop = DllStructGetData($tRc, "top")
	$iWidth = DllStructGetData($tRc, "right") - $iLeft
	$iHeight = DllStructGetData($tRc, "bottom") - $iTop
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_GetBounds

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_FitToParent
; Description ...: Resizes the browser so that it covers the whole client area of its parent window.
; Syntax ........: _WV2_FitToParent($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Remarks .......: Call it from a WM_SIZE handler to keep the browser in step with its window.
; Related .......: _WV2_SetBounds
; ===============================================================================================================================
Func _WV2_FitToParent($iHandle)
	$__WV2_sLastFunc = "_WV2_FitToParent"
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	__WV2_ClientSize($__WV2_hParent[$iHandle])
	Return _WV2_SetBounds($iHandle, 0, 0, $__WV2_iClientW, $__WV2_iClientH)
EndFunc   ;==>_WV2_FitToParent

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetVisible
; Description ...: Shows or hides the browser without destroying it.
; Syntax ........: _WV2_SetVisible($iHandle, $bVisible)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $bVisible - True to show, False to hide.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_SetBounds
; ===============================================================================================================================
Func _WV2_SetVisible($iHandle, $bVisible)
	$__WV2_sLastFunc = "_WV2_SetVisible"
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $hr = $__WV2_oCtl[$iHandle].put_IsVisible($bVisible ? 1 : 0)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2Controller::put_IsVisible")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_SetVisible

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetZoom
; Description ...: Sets the zoom factor of the page.
; Syntax ........: _WV2_SetZoom($iHandle, $fZoom)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $fZoom - From 0.2 to 10; 1 is 100 %.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_GetZoom
; ===============================================================================================================================
Func _WV2_SetZoom($iHandle, $fZoom)
	$__WV2_sLastFunc = "_WV2_SetZoom"
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	$fZoom = Number($fZoom)
	If $fZoom < 0.2 Or $fZoom > 10 Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_SetZoom")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $hr = $__WV2_oCtl[$iHandle].put_ZoomFactor($fZoom)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2Controller::put_ZoomFactor")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_SetZoom

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetZoom
; Description ...: Reads the zoom factor of the page.
; Syntax ........: _WV2_GetZoom($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: the zoom as a number, @error = 0.
;                  Failure: -1, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_SetZoom
; ===============================================================================================================================
Func _WV2_GetZoom($iHandle)
	$__WV2_sLastFunc = "_WV2_GetZoom"
	If Not __WV2_GuardCtl($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	Local $d = 0
	Local $hr = $__WV2_oCtl[$iHandle].get_ZoomFactor($d)
	If $hr <> 0 Then
		__WV2_Result($hr, "ICoreWebView2Controller::get_ZoomFactor")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	EndIf
	Return SetError(0, 0, $d)
EndFunc   ;==>_WV2_GetZoom

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_Reload
; Description ...: Reloads the current document.
; Syntax ........: _WV2_Reload($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_GoBack, _WV2_GoForward, _WV2_Stop
; ===============================================================================================================================
Func _WV2_Reload($iHandle)
	$__WV2_sLastFunc = "_WV2_Reload"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	__WV2_BeginNavigation($iHandle)
	Local $bOk = __WV2_Result($__WV2_oWv[$iHandle].Reload(), "ICoreWebView2::Reload")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_Reload

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GoBack
; Description ...: Moves one entry back in the navigation history.
; Syntax ........: _WV2_GoBack($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_CanGoBack, _WV2_GoForward
; ===============================================================================================================================
Func _WV2_GoBack($iHandle)
	$__WV2_sLastFunc = "_WV2_GoBack"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	__WV2_BeginNavigation($iHandle)
	Local $bOk = __WV2_Result($__WV2_oWv[$iHandle].GoBack(), "ICoreWebView2::GoBack")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_GoBack

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GoForward
; Description ...: Moves one entry forward in the navigation history.
; Syntax ........: _WV2_GoForward($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Related .......: _WV2_CanGoForward, _WV2_GoBack
; ===============================================================================================================================
Func _WV2_GoForward($iHandle)
	$__WV2_sLastFunc = "_WV2_GoForward"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	__WV2_BeginNavigation($iHandle)
	Local $bOk = __WV2_Result($__WV2_oWv[$iHandle].GoForward(), "ICoreWebView2::GoForward")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_GoForward

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_Stop
; Description ...: Cancels the navigation in progress.
; Syntax ........: _WV2_Stop($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; ===============================================================================================================================
Func _WV2_Stop($iHandle)
	$__WV2_sLastFunc = "_WV2_Stop"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $bOk = __WV2_Result($__WV2_oWv[$iHandle].Stop(), "ICoreWebView2::Stop")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_Stop

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_CanGoBack
; Description ...: Tells whether the history holds an entry before the current one.
; Syntax ........: _WV2_CanGoBack($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1 or 0, @error = 0.
;                  Failure: -1, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_GoBack, _WV2_CanGoForward
; ===============================================================================================================================
Func _WV2_CanGoBack($iHandle)
	$__WV2_sLastFunc = "_WV2_CanGoBack"
	Local $iValue = __WV2_BoolMethod($iHandle, "get_CanGoBack", "ICoreWebView2::get_CanGoBack")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $iValue)
EndFunc   ;==>_WV2_CanGoBack

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_CanGoForward
; Description ...: Tells whether the history holds an entry after the current one.
; Syntax ........: _WV2_CanGoForward($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1 or 0, @error = 0.
;                  Failure: -1, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_GoForward, _WV2_CanGoBack
; ===============================================================================================================================
Func _WV2_CanGoForward($iHandle)
	$__WV2_sLastFunc = "_WV2_CanGoForward"
	Local $iValue = __WV2_BoolMethod($iHandle, "get_CanGoForward", "ICoreWebView2::get_CanGoForward")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $iValue)
EndFunc   ;==>_WV2_CanGoForward

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetBrowserVersion
; Description ...: Reads the version of the runtime driving a view.
; Syntax ........: _WV2_GetBrowserVersion($iHandle, $sVersion)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sVersion - Variable receiving the version, for instance "155.0.4283.62".
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_GetRuntimePath
; ===============================================================================================================================
Func _WV2_GetBrowserVersion($iHandle, ByRef $sVersion)
	$__WV2_sLastFunc = "_WV2_GetBrowserVersion"
	$sVersion = ""
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If $__WV2_sVersion[$iHandle] <> "" Then
		$sVersion = $__WV2_sVersion[$iHandle]
		Return SetError(0, 0, 1)
	EndIf
	Local $s = ""
	Local $hr = $__WV2_oEnv[$iHandle].get_BrowserVersionString($s)
	If $hr <> 0 Then
		__WV2_Result($hr, "ICoreWebView2Environment::get_BrowserVersionString")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$sVersion = $s
	$__WV2_sVersion[$iHandle] = $s
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_GetBrowserVersion

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetLastErrorMessage
; Description ...: Builds a human readable description of the last failure.
; Syntax ........: _WV2_GetLastErrorMessage()
; Parameters ....: none
; Return values .: A string such as "Method call failed in ICoreWebView2::Navigate (HRESULT 0x80070057)",
;                  or "" when the last call succeeded. @error is always 0.
; Author ........: Numeric1
; Remarks .......: Read only view of the information every function reports through @error and
;                  @extended, which is handy while debugging.
; Related .......: _WV2_Create
; ===============================================================================================================================
Func _WV2_GetLastErrorMessage()
	If $__WV2_iLastError = $WV2_ERR_NONE Then Return SetError(0, 0, "")
	Local $s = $__WV2_sLastFunc
	If $__WV2_iLastHR <> 0 Then $s &= " (HRESULT 0x" & Hex($__WV2_iLastHR, 8) & ")"
	Return SetError(0, 0, __WV2_ErrText($__WV2_iLastError) & " in " & $s)
EndFunc   ;==>_WV2_GetLastErrorMessage

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_EnableEvent
; Description ...: Turns the queueing of one WebView2 event on or off for a view.
; Syntax ........: _WV2_EnableEvent($iHandle, $iEvent[, $bEnable = True])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $iEvent - One of the $WV2_EVENT_* constants.
;                  $bEnable - True to receive the event, False to stop receiving it.
; Return values .: Success: 1.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: $WV2_EVENT_NAVIGATION_COMPLETED is already enabled by _WV2_Create: leaving it off
;                  breaks _WV2_WaitNavigation, which waits on it. Two events carry a policy with them:
;                  while $WV2_EVENT_NAVIGATION_STARTING is enabled the filter of
;                  _WV2_SetNavigationFilter can cancel a navigation, and while
;                  $WV2_EVENT_NEW_WINDOW is enabled the popup window the page asks for is always
;                  cancelled, so a script embedding a page never has to chase a window it did not open.
;                  Enabling an event twice is allowed and does nothing.
; Related .......: _WV2_GetEvent, _WV2_WaitEvent, _WV2_SetNavigationFilter
; ===============================================================================================================================
Func _WV2_EnableEvent($iHandle, $iEvent, $bEnable = True)
	$__WV2_sLastFunc = "_WV2_EnableEvent"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $iSlot = __WV2_EventSlot($iEvent)
	If $iSlot = 0 Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_EnableEvent")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If $bEnable Then
		If Not __WV2_Attach($iHandle, $iSlot) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Else
		__WV2_Detach($iHandle, $iSlot)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_EnableEvent

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_GetEvent
; Description ...: Reads the oldest event the view has queued.
; Syntax ........: _WV2_GetEvent($iHandle, $sData, $iValue)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sData - Variable receiving the text of the event, passed by reference.
;                  $iValue - Variable receiving the number of the event, passed by reference.
; Return values .: Success: a $WV2_EVENT_* code, 0 when the queue is empty. @error is always 0.
;                  Failure: -1 with @error set to a $WV2_ERR_* code.
;                  @extended carries the number of events dropped because the queue was full.
; Author ........: Numeric1
; Remarks .......: Nothing is read here: events are collected by the message loop of the thread, so
;                  call this from the GUI loop, after GUIGetMsg. Each event puts the meaning of $sData
;                  and $iValue in the $WV2_EVENT_* constant, and $iValue is 0 when it carries nothing.
;                  The queue keeps 64 events per view; the oldest is dropped when it overflows.
; Related .......: _WV2_WaitEvent, _WV2_EnableEvent
; ===============================================================================================================================
Func _WV2_GetEvent($iHandle, ByRef $sData, ByRef $iValue)
	$__WV2_sLastFunc = "_WV2_GetEvent"
	$sData = ""
	$iValue = 0
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	Local $iType = 0
	__WV2_PopEvent($iHandle, $iType, $sData, $iValue)
	Return SetError(0, $__WV2_iEvtDrop[$iHandle], $iType)
EndFunc   ;==>_WV2_GetEvent

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_WaitEvent
; Description ...: Waits for the next event of one type.
; Syntax ........: _WV2_WaitEvent($iHandle, $iEvent, $iTimeoutMs, $sData, $iValue)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $iEvent - The $WV2_EVENT_* code to wait for.
;                  $iTimeoutMs - Time allowed, in milliseconds.
;                  $sData - Variable receiving the text of the event, passed by reference.
;                  $iValue - Variable receiving the number of the event, passed by reference.
; Return values .: Success: 1, @extended = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code ($WV2_ERR_TIMEOUT when out of
;                  time, $WV2_ERR_ARG when the event cannot be waited for).
; Author ........: Numeric1
; Remarks .......: The event has to be enabled first. Events of another type already in the queue
;                  stay there: this function takes the oldest event of the type asked for and leaves the rest
;                  in order for _WV2_GetEvent. Windows messages are pumped while waiting.
; Related .......: _WV2_GetEvent, _WV2_EnableEvent
; ===============================================================================================================================
Func _WV2_WaitEvent($iHandle, $iEvent, $iTimeoutMs, ByRef $sData, ByRef $iValue)
	$__WV2_sLastFunc = "_WV2_WaitEvent"
	$sData = ""
	$iValue = 0
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $iSlot = __WV2_EventSlot($iEvent)
	If $iSlot = 0 Or $__WV2_iTok[$iHandle][$iSlot] = 0 Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_WaitEvent")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $tEnd = TimerInit()
	While 1
		If __WV2_PopEventOfType($iHandle, $iEvent, $sData, $iValue) Then
			$__WV2_iLastError = $WV2_ERR_NONE
			Return SetError(0, 0, 1)
		EndIf
		__WV2_Pump(20)
		If TimerDiff($tEnd) > $iTimeoutMs Then
			__WV2_SetErr($WV2_ERR_TIMEOUT, 0, "_WV2_WaitEvent")
			$sData = ""
			$iValue = 0
			Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
		EndIf
	WEnd
EndFunc   ;==>_WV2_WaitEvent

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetNavigationFilter
; Description ...: Refuses the navigations whose URL matches a regular expression.
; Syntax ........: _WV2_SetNavigationFilter($iHandle, $sFilter)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sFilter - PCRE pattern matched against the URL, "" (the default) allows everything.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code.
; Author ........: Numeric1
; Remarks .......: The filter is read inside the NavigationStarting callback, so it only works while
;                  $WV2_EVENT_NAVIGATION_STARTING is enabled. A cancelled navigation still reaches
;                  the queue: _WV2_GetEvent reports which URL was refused.
; Related .......: _WV2_EnableEvent
; ===============================================================================================================================
Func _WV2_SetNavigationFilter($iHandle, $sFilter)
	$__WV2_sLastFunc = "_WV2_SetNavigationFilter"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sFilter) Then $sFilter = String($sFilter)
	$__WV2_sNavFilter[$iHandle] = $sFilter
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_SetNavigationFilter

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetDownloadFolder
; Description ...: Chooses the folder the downloads of the page land in.
; Syntax ........: _WV2_SetDownloadFolder($iHandle, $sFolder)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sFolder - An existing folder, "" (the default) leaving the choice to the runtime.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code ($WV2_ERR_ARG when $sFolder is not
;                  an existing folder, the error of the subscription otherwise) and @extended set to
;                  the raw HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: The file name chosen by the runtime - it comes from the server or from the link - is
;                  kept, only its folder is replaced. The download itself goes on in the browser
;                  process: this says where the file ends up, nothing else. A relative path is completed
;                  with the current directory and a trailing separator is dropped.
;
;                  The call enables $WV2_EVENT_DOWNLOAD_STARTING so the folder applies without a
;                  separate _WV2_EnableEvent, and every download is then queued: _WV2_GetEvent gives the
;                  URI the page asked for, with $iValue = 0. Pass "" to hand the choice back to the
;                  runtime.
; Related .......: _WV2_SetDownloadFilter, _WV2_EnableEvent, _WV2_SetNavigationFilter
; ===============================================================================================================================
Func _WV2_SetDownloadFolder($iHandle, $sFolder)
	$__WV2_sLastFunc = "_WV2_SetDownloadFolder"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sFolder) Then $sFolder = String($sFolder)
	Local $sPath = StringStripWS($sFolder, 3)
	; A separator left at the end would double up when the file name is appended to the folder.
	While StringRight($sPath, 1) = "\" Or StringRight($sPath, 1) = "/"
		$sPath = StringTrimRight($sPath, 1)
	WEnd
	If $sPath <> "" And Not StringInStr($sPath, "\") And Not StringInStr($sPath, "/") Then $sPath = _PathFull($sPath)
	If $sPath <> "" And Not StringInStr(FileGetAttrib($sPath), "D") Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_SetDownloadFolder")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If Not __WV2_Attach($iHandle, $__WV2_H_DOWNLOAD) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	$__WV2_sDlFolder[$iHandle] = $sPath
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_SetDownloadFolder

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SetDownloadFilter
; Description ...: Refuses the downloads whose URI matches a regular expression.
; Syntax ........: _WV2_SetDownloadFilter($iHandle, $sFilter)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sFilter - PCRE pattern matched against the URI of the download, "" (the default)
;                   allows everything.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw
;                  HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: A refused download never reaches the disk and the browser process is told before a
;                  single byte moves. It still goes to the event queue, with $iValue = 1, so the program
;                  can say what was blocked. Like _WV2_SetDownloadFolder, the call enables
;                  $WV2_EVENT_DOWNLOAD_STARTING by itself.
; Related .......: _WV2_SetDownloadFolder, _WV2_SetNavigationFilter, _WV2_GetEvent
; ===============================================================================================================================
Func _WV2_SetDownloadFilter($iHandle, $sFilter)
	$__WV2_sLastFunc = "_WV2_SetDownloadFilter"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sFilter) Then $sFilter = String($sFilter)
	If Not __WV2_Attach($iHandle, $__WV2_H_DOWNLOAD) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	$__WV2_sDlFilter[$iHandle] = $sFilter
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_SetDownloadFilter

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_ExecuteScript
; Description ...: Runs JavaScript in the page and brings the answer back.
; Syntax ........: _WV2_ExecuteScript($iHandle, $sScript, $sResult[, $iTimeoutMs = $WV2_EXEC_TIMEOUT])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sScript - JavaScript to run.
;                  $sResult - Variable receiving the answer, passed by reference.
;                  $iTimeoutMs - Time allowed for the page to answer, in milliseconds.
; Return values .: Success: 1, @extended = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw
;                  HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: $sResult is the JSON text produced by the runtime for the last expression: a number
;                  comes back bare (42), a string between quotes ("text"), an object as its JSON
;                  ({"a":1}). A script that throws is not a failure: the runtime answers successfully
;                  and $sResult becomes null, which is also what a script with no result gives. When a
;                  script can fail, have it return something you can test instead.
;                  Only one script may run at a time per view. Windows messages are pumped while
;                  waiting.
; Related .......: _WV2_AddScriptToExecuteOnDocumentCreated, _WV2_PostWebMessageAsString
; ===============================================================================================================================
Func _WV2_ExecuteScript($iHandle, $sScript, ByRef $sResult, $iTimeoutMs = $WV2_EXEC_TIMEOUT)
	$__WV2_sLastFunc = "_WV2_ExecuteScript"
	$sResult = ""
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sScript) Or $sScript = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_ExecuteScript")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	__WV2_BeginOp($iHandle, $__WV2_H_EXEC)
	Local $hr = $__WV2_oWv[$iHandle].ExecuteScript($sScript, $__WV2_pObj[$iHandle][$__WV2_H_EXEC])
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2::ExecuteScript")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If Not __WV2_WaitOp($iHandle, $__WV2_H_EXEC, $iTimeoutMs) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $iScriptHR = $__WV2_iOpHR[$iHandle][$__WV2_H_EXEC]
	$sResult = $__WV2_sOpOut[$iHandle][$__WV2_H_EXEC]
	If $iScriptHR <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, 1, "ICoreWebView2::ExecuteScript")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_ExecuteScript

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_AddScriptToExecuteOnDocumentCreated
; Description ...: Registers JavaScript that runs in every document as soon as it is created.
; Syntax ........: _WV2_AddScriptToExecuteOnDocumentCreated($iHandle, $sScript, $sId[, $iTimeoutMs = $WV2_EXEC_TIMEOUT])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sScript - JavaScript, run before the scripts of the page.
;                  $sId - Variable receiving the identifier the runtime gives the script, passed by
;                    reference; keep it for _WV2_RemoveScriptToExecuteOnDocumentCreated.
;                  $iTimeoutMs - Time allowed for the runtime to answer, in milliseconds.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: The script reaches the main frame of every page loaded afterwards by this view,
;                  which is how a page is given a bridge before its own code runs.
; Related .......: _WV2_RemoveScriptToExecuteOnDocumentCreated, _WV2_ExecuteScript
; ===============================================================================================================================
Func _WV2_AddScriptToExecuteOnDocumentCreated($iHandle, $sScript, ByRef $sId, $iTimeoutMs = $WV2_EXEC_TIMEOUT)
	$__WV2_sLastFunc = "_WV2_AddScriptToExecuteOnDocumentCreated"
	$sId = ""
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sScript) Or $sScript = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_AddScriptToExecuteOnDocumentCreated")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	__WV2_BeginOp($iHandle, $__WV2_H_ADDSCRIPT)
	Local $hr = $__WV2_oWv[$iHandle].AddScriptToExecuteOnDocumentCreated($sScript, $__WV2_pObj[$iHandle][$__WV2_H_ADDSCRIPT])
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2::AddScriptToExecuteOnDocumentCreated")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If Not __WV2_WaitOp($iHandle, $__WV2_H_ADDSCRIPT, $iTimeoutMs) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If $__WV2_iOpHR[$iHandle][$__WV2_H_ADDSCRIPT] <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $__WV2_iOpHR[$iHandle][$__WV2_H_ADDSCRIPT], "ICoreWebView2::AddScriptToExecuteOnDocumentCreated")
		$sId = $__WV2_sOpOut[$iHandle][$__WV2_H_ADDSCRIPT]
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$sId = $__WV2_sOpOut[$iHandle][$__WV2_H_ADDSCRIPT]
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_AddScriptToExecuteOnDocumentCreated

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_RemoveScriptToExecuteOnDocumentCreated
; Description ...: Removes a script registered by _WV2_AddScriptToExecuteOnDocumentCreated.
; Syntax ........: _WV2_RemoveScriptToExecuteOnDocumentCreated($iHandle, $sId)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sId - Identifier returned with the script.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_ExecuteScript.
; Author ........: Numeric1
; Remarks .......: Pages already loaded keep the script: it only stops running for the next documents.
; Related .......: _WV2_AddScriptToExecuteOnDocumentCreated
; ===============================================================================================================================
Func _WV2_RemoveScriptToExecuteOnDocumentCreated($iHandle, $sId)
	$__WV2_sLastFunc = "_WV2_RemoveScriptToExecuteOnDocumentCreated"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sId) Or $sId = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_RemoveScriptToExecuteOnDocumentCreated")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $hr = $__WV2_oWv[$iHandle].RemoveScriptToExecuteOnDocumentCreated($sId)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2::RemoveScriptToExecuteOnDocumentCreated")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_RemoveScriptToExecuteOnDocumentCreated

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_PostWebMessage
; Description ...: Sends a JSON value from the host to the page.
; Syntax ........: _WV2_PostWebMessage($iHandle, $sJson)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sJson - Valid JSON, for instance '{"cmd":"refresh"}'.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Remarks .......: The page receives it through window.chrome.webview.addEventListener("message").
;                  Malformed JSON is refused by the runtime, which reports it as $WV2_ERR_CALL.
; Related .......: _WV2_PostWebMessageAsString, _WV2_EnableEvent
; ===============================================================================================================================
Func _WV2_PostWebMessage($iHandle, $sJson)
	$__WV2_sLastFunc = "_WV2_PostWebMessage"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sJson) Or $sJson = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_PostWebMessage")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $hr = $__WV2_oWv[$iHandle].PostWebMessageAsJson($sJson)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2::PostWebMessageAsJson")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_PostWebMessage

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_PostWebMessageAsString
; Description ...: Sends a plain string from the host to the page.
; Syntax ........: _WV2_PostWebMessageAsString($iHandle, $sText)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sText - The string, read as it is by the page.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Remarks .......: The page listens with window.chrome.webview.addEventListener("message", handler)
;                  and finds the string in handler.data, which is what makes this form easier than
;                  JSON on both sides of the bridge.
; Related .......: _WV2_PostWebMessage
; ===============================================================================================================================
Func _WV2_PostWebMessageAsString($iHandle, $sText)
	$__WV2_sLastFunc = "_WV2_PostWebMessageAsString"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sText) Then $sText = String($sText)
	Local $hr = $__WV2_oWv[$iHandle].PostWebMessageAsString($sText)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2::PostWebMessageAsString")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_PostWebMessageAsString

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SettingRead
; Description ...: Reads one setting of a view.
; Syntax ........: _WV2_SettingRead($iHandle, $sName)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sName - One of: IsScriptEnabled, IsWebMessageEnabled, AreDefaultScriptDialogsEnabled,
;                    IsStatusBarEnabled, AreDevToolsEnabled, AreDefaultContextMenusEnabled,
;                    AreHostObjectsAllowed, IsZoomControlEnabled, IsBuiltInErrorPageEnabled.
; Return values .: Success: 1 or 0, @error = 0.
;                  Failure: -1, with @error set to a $WV2_ERR_* code and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Related .......: _WV2_SettingWrite
; ===============================================================================================================================
Func _WV2_SettingRead($iHandle, $sName)
	$__WV2_sLastFunc = "_WV2_SettingRead"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	Local $oSettings = __WV2_Settings($iHandle)
	If Not IsObj($oSettings) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	Local $iValue = 0
	Local $hr = 0
	Switch StringStripWS($sName, 8)
		Case "IsScriptEnabled"
			$hr = $oSettings.get_IsScriptEnabled($iValue)
		Case "IsWebMessageEnabled"
			$hr = $oSettings.get_IsWebMessageEnabled($iValue)
		Case "AreDefaultScriptDialogsEnabled"
			$hr = $oSettings.get_AreDefaultScriptDialogsEnabled($iValue)
		Case "IsStatusBarEnabled"
			$hr = $oSettings.get_IsStatusBarEnabled($iValue)
		Case "AreDevToolsEnabled"
			$hr = $oSettings.get_AreDevToolsEnabled($iValue)
		Case "AreDefaultContextMenusEnabled"
			$hr = $oSettings.get_AreDefaultContextMenusEnabled($iValue)
		Case "AreHostObjectsAllowed"
			$hr = $oSettings.get_AreHostObjectsAllowed($iValue)
		Case "IsZoomControlEnabled"
			$hr = $oSettings.get_IsZoomControlEnabled($iValue)
		Case "IsBuiltInErrorPageEnabled"
			$hr = $oSettings.get_IsBuiltInErrorPageEnabled($iValue)
		Case Else
			__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_SettingRead")
			Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	EndSwitch
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2Settings::get_" & $sName)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	Return SetError(0, 0, $iValue ? 1 : 0)
EndFunc   ;==>_WV2_SettingRead

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_SettingWrite
; Description ...: Changes one setting of a view.
; Syntax ........: _WV2_SettingWrite($iHandle, $sName, $bValue)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sName - The same nine names as _WV2_SettingRead.
;                  $bValue - True to turn the setting on, False to turn it off.
; Return values .: Success: 1, failure: 0 with @error / @extended as for _WV2_Navigate.
; Author ........: Numeric1
; Remarks .......: The change applies to every page this view loads from now on, and the name is
;                  matched without regard to case or spaces.
; Related .......: _WV2_SettingRead
; ===============================================================================================================================
Func _WV2_SettingWrite($iHandle, $sName, $bValue)
	$__WV2_sLastFunc = "_WV2_SettingWrite"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $oSettings = __WV2_Settings($iHandle)
	If Not IsObj($oSettings) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $iValue = ($bValue ? 1 : 0)
	Local $hr = 0
	Switch StringStripWS($sName, 8)
		Case "IsScriptEnabled"
			$hr = $oSettings.put_IsScriptEnabled($iValue)
		Case "IsWebMessageEnabled"
			$hr = $oSettings.put_IsWebMessageEnabled($iValue)
		Case "AreDefaultScriptDialogsEnabled"
			$hr = $oSettings.put_AreDefaultScriptDialogsEnabled($iValue)
		Case "IsStatusBarEnabled"
			$hr = $oSettings.put_IsStatusBarEnabled($iValue)
		Case "AreDevToolsEnabled"
			$hr = $oSettings.put_AreDevToolsEnabled($iValue)
		Case "AreDefaultContextMenusEnabled"
			$hr = $oSettings.put_AreDefaultContextMenusEnabled($iValue)
		Case "AreHostObjectsAllowed"
			$hr = $oSettings.put_AreHostObjectsAllowed($iValue)
		Case "IsZoomControlEnabled"
			$hr = $oSettings.put_IsZoomControlEnabled($iValue)
		Case "IsBuiltInErrorPageEnabled"
			$hr = $oSettings.put_IsBuiltInErrorPageEnabled($iValue)
		Case Else
			__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_SettingWrite")
			Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndSwitch
	Local $bOk = __WV2_Result($hr, "ICoreWebView2Settings::put_" & $sName)
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_SettingWrite

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_CapturePreview
; Description ...: Saves what the view currently shows as a PNG or JPEG file.
; Syntax ........: _WV2_CapturePreview($iHandle, $sFile[, $iFormat = $WV2_IMAGE_PNG[, $iTimeoutMs = $WV2_EXEC_TIMEOUT]])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sFile - Full path of the image to write; an existing file is replaced.
;                  $iFormat - $WV2_IMAGE_PNG (default) or $WV2_IMAGE_JPEG.
;                  $iTimeoutMs - Time allowed for the runtime to draw, in milliseconds.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code ($WV2_ERR_FILE when the image was
;                  produced but could not be written) and @extended set to the raw HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: The image is built in memory by the runtime and written by this function, so no
;                  temporary file is left behind. A view that is hidden or has never painted gives an
;                  empty or black image, which is what Chromium itself reports.
; Related .......: _WV2_SetVisible
; ===============================================================================================================================
Func _WV2_CapturePreview($iHandle, $sFile, $iFormat = $WV2_IMAGE_PNG, $iTimeoutMs = $WV2_EXEC_TIMEOUT)
	$__WV2_sLastFunc = "_WV2_CapturePreview"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sFile) Or StringStripWS($sFile, 3) = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If $iFormat <> $WV2_IMAGE_PNG And $iFormat <> $WV2_IMAGE_JPEG Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	; An in-memory IStream is enough: ole32 builds it, the runtime writes into it, and releasing the
	; stream releases the memory block it holds. The pointer is used raw all the way through.
	Local $aCS = DllCall("ole32.dll", "long", "CreateStreamOnHGlobal", "ptr", 0, "int", 1, "ptr*", 0)
	If @Error Or Not IsArray($aCS) Or $aCS[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_COM, (@Error ? 0 : $aCS[0]), "CreateStreamOnHGlobal")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $pStream = $aCS[3]

	__WV2_BeginOp($iHandle, $__WV2_H_CAP)
	Local $hr = $__WV2_oWv[$iHandle].CapturePreview($iFormat, $pStream, $__WV2_pObj[$iHandle][$__WV2_H_CAP])
	If $hr <> 0 Then
		__WV2_ReleaseExternal($pStream)
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2::CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If Not __WV2_WaitOp($iHandle, $__WV2_H_CAP, $iTimeoutMs) Then
		__WV2_ReleaseExternal($pStream)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $iDrawHR = $__WV2_iOpHR[$iHandle][$__WV2_H_CAP]
	If $iDrawHR <> 0 Then
		__WV2_ReleaseExternal($pStream)
		__WV2_SetErr($WV2_ERR_CALL, $iDrawHR, "ICoreWebView2CapturePreviewCompletedHandler")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	; Read the block back before releasing the stream, which is what frees it.
	; GlobalSize is a SIZE_T, so it is asked for as uint_ptr: a "ptr" return would arrive as a
	; hexadecimal string instead of a number.
	Local $aGH = DllCall("ole32.dll", "long", "GetHGlobalFromStream", "ptr", $pStream, "ptr*", 0)
	Local $hGlob = ((Not @Error) And IsArray($aGH) And $aGH[0] = 0 ? $aGH[2] : 0)
	Local $bImage = Binary("")
	If $hGlob <> 0 Then
		Local $aSZ = DllCall("kernel32.dll", "uint_ptr", "GlobalSize", "ptr", $hGlob)
		Local $iSize = ((Not @Error) And IsArray($aSZ) ? $aSZ[0] : 0)
		If $iSize > 0 Then
			; GlobalLock also returns a pointer, which has to be turned back into a number before it
			; can be used as the address of a structure.
			Local $aLK = DllCall("kernel32.dll", "ptr", "GlobalLock", "ptr", $hGlob)
			If (Not @Error) And IsArray($aLK) And Number($aLK[0]) <> 0 Then
				Local $tRaw = DllStructCreate("byte[" & $iSize & "]", Number($aLK[0]))
				If Not @Error Then $bImage = DllStructGetData($tRaw, 1)
				DllCall("kernel32.dll", "int", "GlobalUnlock", "ptr", $hGlob)
			EndIf
		EndIf
	EndIf
	__WV2_ReleaseExternal($pStream)

	If BinaryLen($bImage) = 0 Then
		__WV2_SetErr($WV2_ERR_CALL, 0, "ICoreWebView2::CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	; 16 alone is binary read, which fails when the file does not exist yet: 2 is what asks for the
	; write, and it clears a file already sitting at that path.
	Local $hOut = FileOpen($sFile, 16 + 2)
	If $hOut = -1 Then
		__WV2_SetErr($WV2_ERR_FILE, 0, "_WV2_CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $bWritten = FileWrite($hOut, $bImage)
	FileClose($hOut)
	If Not $bWritten Then
		__WV2_SetErr($WV2_ERR_FILE, 0, "_WV2_CapturePreview")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_CapturePreview

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_PrintToPdf
; Description ...: Writes the page to a PDF file.
; Syntax ........: _WV2_PrintToPdf($iHandle, $sFile[, $iTimeoutMs = $WV2_PRINT_TIMEOUT])
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
;                  $sFile - Path of the PDF to write. A relative path is completed with the current
;                   directory. The folder it points to has to exist.
;                  $iTimeoutMs - Time allowed for the page to print, in milliseconds.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw
;                  HRESULT (0 if none). $WV2_ERR_FILE means the folder is missing or the runtime
;                  refused to write the file; $WV2_ERR_CALL carries the HRESULT of the refusal.
; Author ........: Numeric1
; Remarks .......: The page is printed with the defaults of the runtime: portrait, its own paper size,
;                  no header, no footer, backgrounds left out. ICoreWebView2_7::PrintToPdf takes an
;                  ICoreWebView2PrintSettings pointer for everything else; NULL is passed here, which is
;                  what gives those defaults. Windows messages are pumped while waiting, so the GUI stays
;                  responsive, and only one print may run at a time per view.
; Related .......: _WV2_CapturePreview, _WV2_WaitNavigation
; ===============================================================================================================================
Func _WV2_PrintToPdf($iHandle, $sFile, $iTimeoutMs = $WV2_PRINT_TIMEOUT)
	$__WV2_sLastFunc = "_WV2_PrintToPdf"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	If Not IsString($sFile) Or StringStripWS($sFile, 3) = "" Then
		__WV2_SetErr($WV2_ERR_ARG, 0, "_WV2_PrintToPdf")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	; The runtime writes the file itself and wants a full path, so a relative path is completed here and
	; a missing folder is reported as $WV2_ERR_FILE instead of coming back as an opaque HRESULT.
	Local $sPath = _PathFull($sFile)
	Local $sDrv = "", $sDir = "", $sName = "", $sExt = ""
	_PathSplit($sPath, $sDrv, $sDir, $sName, $sExt)
	If $sDrv & $sDir <> "" And Not FileExists($sDrv & $sDir) Then
		__WV2_SetErr($WV2_ERR_FILE, 0, "_WV2_PrintToPdf")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	Local $p7 = __WV2_ViewIf($iHandle, $__WV2_IF_7)
	If $p7 = 0 Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $pFn = __WV2_VtFn($p7, $__WV2_VT_PRINTTOPDF)
	If $pFn = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	__WV2_BeginOp($iHandle, $__WV2_H_PRINT)
	; PrintToPdf(result file path, print settings, handler). NULL settings means the defaults.
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $p7, "wstr", $sPath, "ptr", 0, _
			"ptr", $__WV2_pObj[$iHandle][$__WV2_H_PRINT])
	If @Error Or Not IsArray($aCall) Then
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2_7::PrintToPdf")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If $aCall[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $aCall[0], "ICoreWebView2_7::PrintToPdf")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If Not __WV2_WaitOp($iHandle, $__WV2_H_PRINT, $iTimeoutMs) Then
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $iDoneHR = $__WV2_iOpHR[$iHandle][$__WV2_H_PRINT]
	If $iDoneHR <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $iDoneHR, "ICoreWebView2PrintToPdfCompletedHandler")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	; The handler carries a BOOL as well: a call that ends with S_OK and FALSE produced nothing.
	If $__WV2_sOpOut[$iHandle][$__WV2_H_PRINT] = "0" Then
		__WV2_SetErr($WV2_ERR_FILE, 0, "ICoreWebView2PrintToPdfCompletedHandler")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return SetError(0, 0, 1)
EndFunc   ;==>_WV2_PrintToPdf

; #FUNCTION# ====================================================================================================================
; Name ..........: _WV2_ClearCookies
; Description ...: Empties the cookie jar of the view.
; Syntax ........: _WV2_ClearCookies($iHandle)
; Parameters ....: $iHandle - Handle returned by _WV2_Create.
; Return values .: Success: 1, @error = 0.
;                  Failure: 0, with @error set to a $WV2_ERR_* code and @extended set to the raw
;                  HRESULT (0 if none).
; Author ........: Numeric1
; Remarks .......: The call is synchronous, but the page keeps whatever it already read: reload it
;                  before testing document.cookie again. Cookies live in the user data folder, so every
;                  view started with the same $sUserDataFolder shares the jar and is affected too. The
;                  cache, the history, the localStorage and the rest of the profile are left alone:
;                  clearing them needs ICoreWebView2Profile2::ClearBrowsingData, which the view itself
;                  does not expose.
; Related .......: _WV2_Create, _WV2_ExecuteScript
; ===============================================================================================================================
Func _WV2_ClearCookies($iHandle)
	$__WV2_sLastFunc = "_WV2_ClearCookies"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)

	Local $p2 = __WV2_ViewIf($iHandle, $__WV2_IF_2)
	If $p2 = 0 Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	Local $pFn = __WV2_VtFn($p2, $__WV2_VT_GETCOOKIE)
	If $pFn = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	; get_CookieManager answers with a pointer that carries a reference of its own.
	Local $tOut = DllStructCreate("ptr")
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $p2, "ptr", DllStructGetPtr($tOut))
	If @Error Or Not IsArray($aCall) Then
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2_2::get_CookieManager")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	If $aCall[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $aCall[0], "ICoreWebView2_2::get_CookieManager")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf
	Local $pCookie = DllStructGetData($tOut, 1)
	If $pCookie = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2_2::get_CookieManager")
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	EndIf

	Local $hr = __WV2_CallNoArg($pCookie, $__WV2_VT_COOKIEDALL)
	__WV2_ReleaseExternal($pCookie)
	Local $bOk = __WV2_Result($hr, "ICoreWebView2CookieManager::DeleteAllCookies")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_ClearCookies

; ===============================================================================================================================
; Internal functions
; ===============================================================================================================================

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_DllForVersion
; Description ...: Builds the path of EmbeddedBrowserWebView.dll for an installed version.
; ===============================================================================================================================
Func __WV2_ProgramFiles($b32)
	; The runtime installs side by side with Edge, which is 32 bit on most machines.
	Local $sVar = ($b32 ? "ProgramFiles(x86)" : "ProgramFiles")
	Local $sDir = EnvGet($sVar)
	If $sDir = "" Then $sDir = @ProgramFilesDir
	Return $sDir
EndFunc   ;==>__WV2_ProgramFiles

Func __WV2_DllForVersion($sVer)
	Local $i
	Local $sArch = (@AutoItX64 ? "x64" : "x86")
	For $i = 1 To 2
		Local $sRoot = __WV2_ProgramFiles($i = 1) & "\Microsoft\EdgeWebView\Application\" & $sVer & "\EBWebView\" & $sArch
		Local $sDll = $sRoot & "\" & $__WV2_DLL_NAME
		If FileExists($sDll) Then Return $sDll
	Next
	Return ""
EndFunc   ;==>__WV2_DllForVersion

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_CompareVersion
; Description ...: Compares two dotted versions numerically. Returns 1, -1 or 0.
; ===============================================================================================================================
Func __WV2_CompareVersion($sA, $sB)
	If $sB = "" Then Return 1
	Local $i
	Local $aA = StringSplit($sA, "."), $aB = StringSplit($sB, ".")
	For $i = 1 To 4
		If $i > $aA[0] Then Return -1
		If $i > $aB[0] Then Return 1
		If Number($aA[$i]) > Number($aB[$i]) Then Return 1
		If Number($aA[$i]) < Number($aB[$i]) Then Return -1
	Next
	Return 0
EndFunc   ;==>__WV2_CompareVersion

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InitHeap
; Description ...: Reserves the memory holding every fake handler object and registers the callbacks
;                  that serve them, once per script.
;                  Each (instance, slot) block is five pointers: four vtable slots and the object
;                  cell that points back at them.
; ===============================================================================================================================
Func __WV2_InitHeap()
	If $__WV2_tHeap <> 0 Then Return
	$__WV2_iPtrSize = DllStructGetSize(DllStructCreate("ptr"))
	$__WV2_tHeap = DllStructCreate("ptr data[" & ($__WV2_MAX * $__WV2_SLOT_COUNT * $__WV2_PTRS_PER_BLOCK) & "]")
	$__WV2_hCbQI = DllCallbackRegister("__WV2_QI", "long", "ptr;ptr;ptr")
	$__WV2_hCbAddRef = DllCallbackRegister("__WV2_AddRef", "dword", "ptr")
	$__WV2_hCbRelease = DllCallbackRegister("__WV2_Release", "dword", "ptr")
	Local $i
	For $i = 1 To $__WV2_SLOT_COUNT
		$__WV2_hCbInv[$i] = DllCallbackRegister($__WV2_aInvFunc[$i], "long", $__WV2_aInvArgs[$i])
	Next
EndFunc   ;==>__WV2_InitHeap

Func __WV2_BlockBase($i, $iSlot)
	Return (($i - 1) * $__WV2_SLOT_COUNT + ($iSlot - 1)) * $__WV2_PTRS_PER_BLOCK
EndFunc   ;==>__WV2_BlockBase

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_BuildHandler
; Description ...: Lays out one fake COM object in the heap: four vtable slots and, right after them,
;                  the object cell that points back at the vtable.
; ===============================================================================================================================
Func __WV2_BuildHandler($i, $iSlot)
	Local $b = __WV2_BlockBase($i, $iSlot)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbQI), $b + 1)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbAddRef), $b + 2)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbRelease), $b + 3)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbInv[$iSlot]), $b + 4)
	; DllStructGetPtr only takes one index, so the object address is computed from the heap base.
	Local $pBase = DllStructGetPtr($__WV2_tHeap)
	DllStructSetData($__WV2_tHeap, "data", $pBase + $b * $__WV2_iPtrSize, $b + 5)
	$__WV2_pObj[$i][$iSlot] = $pBase + ($b + 4) * $__WV2_iPtrSize
EndFunc   ;==>__WV2_BuildHandler

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_BuildAllHandlers
; Description ...: Lays out the whole row of handler objects of one instance. Sixty pointer writes
;                  cost less than tracking which of them will ever be needed.
; ===============================================================================================================================
Func __WV2_BuildAllHandlers($i)
	Local $j
	For $j = 1 To $__WV2_SLOT_COUNT
		__WV2_BuildHandler($i, $j)
	Next
EndFunc   ;==>__WV2_BuildAllHandlers

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_FreeHandlers
; Description ...: Forgets the handler objects of an instance. The shared callbacks and the heap block
;                  itself stay alive: they are reused by the next _WV2_Create.
; ===============================================================================================================================
Func __WV2_FreeHandlers($i)
	Local $j
	For $j = 1 To $__WV2_SLOT_COUNT
		$__WV2_pObj[$i][$j] = 0
	Next
EndFunc   ;==>__WV2_FreeHandlers

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_FindInst
; Description ...: Finds which instance and which handler slot a fake object pointer belongs to.
;                  @extended returns the slot.
; ===============================================================================================================================
Func __WV2_FindInst($pThis)
	Local $i, $j
	For $i = 1 To $__WV2_MAX
		If $__WV2_aUsed[$i] Then
			For $j = 1 To $__WV2_SLOT_COUNT
				If $__WV2_pObj[$i][$j] = $pThis Then Return SetError(0, $j, $i)
			Next
		EndIf
	Next
	Return SetError(1, 0, 0)
EndFunc   ;==>__WV2_FindInst

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_QI / __WV2_AddRef / __WV2_Release
; Description ...: IUnknown of the fake handler objects. Each object answers for IUnknown and for the
;                  handler interface of its own slot only, and both with the same pointer. AddRef and
;                  Release report counts of their own: these objects live in the UDF heap and are
;                  freed by __WV2_FreeHandlers, never by the runtime.
; ===============================================================================================================================
Func __WV2_QI($pThis, $pRIID, $pPPV)
	__WV2_FindInst($pThis)
	Local $bKnown = Not @Error
	Local $iSlot = @extended
	Local $sIID = __WV2_IIDString($pRIID)
	Local $pOut = 0
	If $bKnown And ($sIID = $WV2_IID_UNKNOWN Or $sIID = $__WV2_aInvIID[$iSlot]) Then $pOut = $pThis
	DllStructSetData(DllStructCreate("ptr", $pPPV), 1, $pOut)
	If $pOut = 0 Then Return $__WV2_HR_E_NOINTERFACE
	Return 0
EndFunc   ;==>__WV2_QI

Func __WV2_AddRef($pThis)
	If $pThis = 0 Then Return 0
	Return 1
EndFunc   ;==>__WV2_AddRef

Func __WV2_Release($pThis)
	If $pThis = 0 Then Return 0
	Return 0
EndFunc   ;==>__WV2_Release

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_VtFn
; Description ...: Address of one entry of the vtable of an interface pointer.
; Remarks .......: Slot 0 is QueryInterface and slot 2 Release, so the first method an interface itself
;                  declares sits at slot 3. Used for the methods no ObjCreateInterface tag carries.
; ===============================================================================================================================
Func __WV2_VtFn($pObj, $iSlot)
	If $pObj = 0 Or $iSlot < 0 Then Return 0
	If $__WV2_iPtrSize = 0 Then $__WV2_iPtrSize = DllStructGetSize(DllStructCreate("ptr"))
	Local $pVTable = DllStructGetData(DllStructCreate("ptr", $pObj), 1)
	If @Error Or $pVTable = 0 Then Return 0
	Local $pFn = DllStructGetData(DllStructCreate("ptr", $pVTable + $iSlot * $__WV2_iPtrSize), 1)
	If @Error Or $pFn = 0 Then Return 0
	Return $pFn
EndFunc   ;==>__WV2_VtFn

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_ReleaseExternal
; Description ...: Calls Release on an interface pointer owned by the operating system.
; Remarks .......: ObjCreateInterface cannot wrap the streams returned by ole32 here: doing so crashed
;                  the process. The vtable is read instead and Release is its third entry.
; ===============================================================================================================================
Func __WV2_ReleaseExternal($pObj)
	If $pObj = 0 Then Return 0
	Local $pFn = __WV2_VtFn($pObj, $__WV2_VT_RELEASE)
	If $pFn = 0 Then Return 0
	Local $aRet = DllCallAddress("dword", $pFn, "ptr", $pObj)
	If @Error Or Not IsArray($aRet) Then Return 0
	Return $aRet[0]
EndFunc   ;==>__WV2_ReleaseExternal

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_QiView / __WV2_ViewIf
; Description ...: Asks the web view of an instance for a newer version of its own interface
;                  (ICoreWebView2_2, _4 or _7). __WV2_ViewIf keeps the answer, so every version is
;                  asked for once and released with the view.
; Remarks .......: A wrapper made by ObjCreateInterface cannot be asked for another interface: the call
;                  is made on the raw pointer instead, which is why __WV2_InvCtl keeps it. The pointer
;                  returned by QueryInterface carries a reference of its own.
; ===============================================================================================================================
Func __WV2_QiView($i, $sIID)
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	If $__WV2_pWv[$i] = 0 Then
		__WV2_SetErr($WV2_ERR_NOT_READY, 0, "__WV2_QiView")
		Return 0
	EndIf
	Local $pQI = __WV2_VtFn($__WV2_pWv[$i], $__WV2_VT_QI)
	If $pQI = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")
		Return 0
	EndIf
	; CLSIDFromString turns the text form of the IID into the sixteen bytes QueryInterface expects.
	; The structure has to stay alive until the call is over, so it lives here.
	Local $tIID = DllStructCreate("byte[16]")
	Local $aCS = DllCall("ole32.dll", "long", "CLSIDFromString", "wstr", $sIID, "ptr", DllStructGetPtr($tIID))
	If @Error Or Not IsArray($aCS) Or $aCS[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_COM, (IsArray($aCS) ? $aCS[0] : 0), "CLSIDFromString")
		Return 0
	EndIf
	Local $tOut = DllStructCreate("ptr")
	Local $aRet = DllCallAddress("long", $pQI, "ptr", $__WV2_pWv[$i], "ptr", DllStructGetPtr($tIID), _
			"ptr", DllStructGetPtr($tOut))
	If @Error Or Not IsArray($aRet) Then
		__WV2_SetErr($WV2_ERR_COM, 0, "IUnknown::QueryInterface")
		Return 0
	EndIf
	; E_NOINTERFACE only says the installed runtime is older than the method asked for.
	If $aRet[0] <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $aRet[0], "QueryInterface " & $sIID)
		Return 0
	EndIf
	Local $pIf = DllStructGetData($tOut, 1)
	If @Error Or $pIf = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "QueryInterface " & $sIID)
		Return 0
	EndIf
	Return $pIf
EndFunc   ;==>__WV2_QiView

Func __WV2_ViewIf($i, $iIf)
	If $__WV2_pWvIf[$i][$iIf] <> 0 Then Return $__WV2_pWvIf[$i][$iIf]
	Local $sIID = ""
	Switch $iIf
		Case $__WV2_IF_2
			$sIID = $WV2_IID_WV2
		Case $__WV2_IF_4
			$sIID = $WV2_IID_WV4
		Case $__WV2_IF_7
			$sIID = $WV2_IID_WV7
		Case Else
			__WV2_SetErr($WV2_ERR_ARG, 0, "__WV2_ViewIf")
			Return 0
	EndSwitch
	$__WV2_pWvIf[$i][$iIf] = __WV2_QiView($i, $sIID)
	Return $__WV2_pWvIf[$i][$iIf]
EndFunc   ;==>__WV2_ViewIf

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_CallNoArg / __WV2_CallBool / __WV2_CallWStr / __WV2_WStrProp
; Description ...: The four shapes a WebView2 method takes when it is called raw through its vtable
;                  entry: nothing, one BOOL, one text, or one text handed back.
; Return values .: The HRESULT of the call, or the text read for __WV2_WStrProp ("" when it failed).
; Remarks .......: A text coming back from the runtime was allocated with CoTaskMemAlloc, so
;                  __WV2_WStrProp copies it and frees it before returning.
; ===============================================================================================================================
Func __WV2_CallNoArg($pObj, $iSlot)
	Local $pFn = __WV2_VtFn($pObj, $iSlot)
	If $pFn = 0 Then Return $__WV2_HR_E_FAIL
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $pObj)
	If @Error Or Not IsArray($aCall) Then Return $__WV2_HR_E_FAIL
	Return $aCall[0]
EndFunc   ;==>__WV2_CallNoArg

Func __WV2_CallBool($pObj, $iSlot, $iValue)
	Local $pFn = __WV2_VtFn($pObj, $iSlot)
	If $pFn = 0 Then Return $__WV2_HR_E_FAIL
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $pObj, "int", $iValue ? 1 : 0)
	If @Error Or Not IsArray($aCall) Then Return $__WV2_HR_E_FAIL
	Return $aCall[0]
EndFunc   ;==>__WV2_CallBool

Func __WV2_CallWStr($pObj, $iSlot, $sText)
	Local $pFn = __WV2_VtFn($pObj, $iSlot)
	If $pFn = 0 Then Return $__WV2_HR_E_FAIL
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $pObj, "wstr", $sText)
	If @Error Or Not IsArray($aCall) Then Return $__WV2_HR_E_FAIL
	Return $aCall[0]
EndFunc   ;==>__WV2_CallWStr

Func __WV2_WStrProp($pObj, $iSlot)
	Local $pFn = __WV2_VtFn($pObj, $iSlot)
	If $pFn = 0 Then Return ""
	Local $tOut = DllStructCreate("ptr")
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $pObj, "ptr", DllStructGetPtr($tOut))
	If @Error Or Not IsArray($aCall) Or $aCall[0] <> 0 Then Return ""
	Local $pStr = DllStructGetData($tOut, 1)
	If $pStr = 0 Then Return ""
	Local $sText = __WV2_CopyWStr($pStr)
	DllCall("ole32.dll", "none", "CoTaskMemFree", "ptr", $pStr)
	Return $sText
EndFunc   ;==>__WV2_WStrProp

Func __WV2_FileName($sPath)
	Local $aMatch = StringRegExp($sPath, "([^\\/]+)$", 1)
	If @Error Or Not IsArray($aMatch) Then Return $sPath
	Return $aMatch[0]
EndFunc   ;==>__WV2_FileName

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_PutBounds
; Description ...: Sends the bounds to ICoreWebView2Controller::put_Bounds.
;                  The header declares the RECT by value, and on x86 that is what happens: four longs
;                  fit the tag of the wrapper. The 64 bit runtime does not read them that way - it takes
;                  the address of the sixteen bytes - and every other shape of that argument, four longs
;                  or the two halves of the struct, crashes the process. The address is therefore handed
;                  over through the vtable there, which is also the only way to check the outcome: the
;                  bounds read back with get_Bounds are the ones that were sent.
; Return values .: 1 the call succeeded, 0 with $__WV2_iLastError and $__WV2_iLastHR set.
; ===============================================================================================================================
Func __WV2_PutBounds($i, $iLeft, $iTop, $iRight, $iBottom)
	If Not @AutoItX64 Then Return __WV2_Result($__WV2_oCtl[$i].put_Bounds($iLeft, $iTop, $iRight, $iBottom), _
			"ICoreWebView2Controller::put_Bounds")

	Local $pFn = __WV2_VtFn($__WV2_pCtl[$i], $__WV2_VT_PUTBOUNDS)
	If $pFn = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")
		Return 0
	EndIf
	Local $tRc = DllStructCreate("long l; long t; long r; long b")
	DllStructSetData($tRc, "l", $iLeft)
	DllStructSetData($tRc, "t", $iTop)
	DllStructSetData($tRc, "r", $iRight)
	DllStructSetData($tRc, "b", $iBottom)
	Local $aCall = DllCallAddress("long", $pFn, "ptr", $__WV2_pCtl[$i], "ptr", DllStructGetPtr($tRc))
	If @Error Or Not IsArray($aCall) Then
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2Controller::put_Bounds")
		Return 0
	EndIf
	Return __WV2_Result($aCall[0], "ICoreWebView2Controller::put_Bounds")
EndFunc   ;==>__WV2_PutBounds

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvEnv
; Description ...: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler::Invoke.
;                  Wraps the borrowed environment pointer, takes ownership of the reference the
;                  callback was handed, and immediately requests a controller.
; ===============================================================================================================================
Func __WV2_InvEnv($pThis, $pHr, $pObj)
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	$__WV2_iHR[$i] = Number($pHr)
	If $__WV2_iHR[$i] <> 0 Or $pObj = 0 Then
		$__WV2_bEnvErr[$i] = True
		Return 0
	EndIf
	$__WV2_oEnv[$i] = ObjCreateInterface($pObj, $WV2_IID_ENV, $__WV2_TAG_ENV, False)
	If @Error Or Not IsObj($__WV2_oEnv[$i]) Then
		$__WV2_iHR[$i] = 0
		$__WV2_bEnvErr[$i] = True
		Return 0
	EndIf
	$__WV2_oEnv[$i].AddRef()
	$__WV2_iHR[$i] = $__WV2_oEnv[$i].CreateCoreWebView2Controller($__WV2_hParent[$i], $__WV2_pObj[$i][$__WV2_H_CTL])
	$__WV2_bEnv[$i] = True
	Return 0
EndFunc   ;==>__WV2_InvEnv

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvCtl
; Description ...: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler::Invoke.
;                  Wraps the borrowed controller pointer, takes ownership of its reference and reads
;                  the web view, whose pointer already carries the reference owned by this instance.
; ===============================================================================================================================
Func __WV2_InvCtl($pThis, $pHr, $pObj)
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	$__WV2_iHR[$i] = Number($pHr)
	If $__WV2_iHR[$i] <> 0 Or $pObj = 0 Then
		$__WV2_bCtlErr[$i] = True
		Return 0
	EndIf
	$__WV2_oCtl[$i] = ObjCreateInterface($pObj, $WV2_IID_CTL, $__WV2_TAG_CTL, False)
	If @Error Or Not IsObj($__WV2_oCtl[$i]) Then
		$__WV2_iHR[$i] = 0
		$__WV2_bCtlErr[$i] = True
		Return 0
	EndIf
	; Kept raw as well: x64 put_Bounds needs a vtable call, which an ObjCreateInterface wrapper cannot express.
	$__WV2_pCtl[$i] = Number($pObj)
	$__WV2_oCtl[$i].AddRef()
	Local $pWv = 0
	$__WV2_iHR[$i] = $__WV2_oCtl[$i].get_CoreWebView2($pWv)
	If $__WV2_iHR[$i] <> 0 Or $pWv = 0 Then
		$__WV2_bCtlErr[$i] = True
		Return 0
	EndIf
	$__WV2_oWv[$i] = ObjCreateInterface($pWv, $WV2_IID_WV, $__WV2_TAG_WV, False)
	If @Error Or Not IsObj($__WV2_oWv[$i]) Then
		$__WV2_iHR[$i] = 0
		$__WV2_bCtlErr[$i] = True
		Return 0
	EndIf
	; The same pointer, kept raw: a method that only exists on a newer version of the interface is
	; reached by QueryInterface on it, which an ObjCreateInterface wrapper cannot do.
	$__WV2_pWv[$i] = Number($pWv)
	$__WV2_bCtl[$i] = True
	Return 0
EndFunc   ;==>__WV2_InvCtl

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvNavC
; Description ...: ICoreWebView2NavigationCompletedEventHandler::Invoke.
;                  Reads the outcome of the navigation from the borrowed arguments pointer, records it
;                  for _WV2_WaitNavigation and queues it for _WV2_GetEvent.
; ===============================================================================================================================
Func __WV2_InvNavC($pThis, $pSender, $pArgs)
	Local $i = __WV2_FindInst($pThis)
	If @Error Or $pSender = 0 Then Return 0 ; $pSender is the web view, already held by the instance
	$__WV2_bNavDone[$i] = True
	$__WV2_bNavOK[$i] = False
	$__WV2_iWebErr[$i] = 0
	Local $sUri = ""
	If $pArgs <> 0 Then
		Local $oArgs = ObjCreateInterface($pArgs, $WV2_IID_NAVARGS, $__WV2_TAG_NAVARGS, False)
		If Not @Error And IsObj($oArgs) Then
			Local $iOK = 0
			If $oArgs.get_IsSuccess($iOK) = 0 Then $__WV2_bNavOK[$i] = ($iOK <> 0)
			If Not $__WV2_bNavOK[$i] Then
				Local $iStatus = 0
				If $oArgs.get_WebErrorStatus($iStatus) = 0 Then $__WV2_iWebErr[$i] = $iStatus
			EndIf
		EndIf
		$oArgs = 0 ; non owning wrapper: the runtime keeps the arguments object alive
	EndIf
	Local $oWv = ObjCreateInterface($pSender, $WV2_IID_WV, $__WV2_TAG_WV, False)
	If Not @Error And IsObj($oWv) Then
		If $oWv.get_Source($sUri) <> 0 Then $sUri = ""
		$oWv = 0
	EndIf
	__WV2_PushEvent($i, $WV2_EVENT_NAVIGATION_COMPLETED, $sUri, $__WV2_bNavOK[$i] ? 1 : $__WV2_iWebErr[$i])
	Return 0
EndFunc   ;==>__WV2_InvNavC

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvNavS
; Description ...: ICoreWebView2NavigationStartingEventHandler::Invoke.
;                  Queues the target URI and applies the navigation filter of the instance: a URI that
;                  matches the filter is cancelled through put_Cancel before the callback returns.
; ===============================================================================================================================
Func __WV2_InvNavS($pThis, $pSender, $pArgs)
	#forceref $pSender
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	If $pArgs = 0 Then Return 0
	Local $oArgs = ObjCreateInterface($pArgs, $WV2_IID_NAVSARGS, $__WV2_TAG_NAVSARGS, False)
	If @Error Or Not IsObj($oArgs) Then Return 0
	Local $sUri = "", $iUser = 0
	$oArgs.get_Uri($sUri)
	$oArgs.get_IsUserInitiated($iUser)
	__WV2_PushEvent($i, $WV2_EVENT_NAVIGATION_STARTING, $sUri, $iUser <> 0 ? 1 : 0)
	If $__WV2_sNavFilter[$i] <> "" And StringRegExp($sUri, $__WV2_sNavFilter[$i]) Then $oArgs.put_Cancel(1)
	$oArgs = 0
	Return 0
EndFunc   ;==>__WV2_InvNavS

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvMsg
; Description ...: ICoreWebView2WebMessageReceivedEventHandler::Invoke.
;                  A page can post either a plain string or a JSON value; the plain form is tried
;                  first and $iValue tells which one was received (1 = string, 0 = JSON).
; ===============================================================================================================================
Func __WV2_InvMsg($pThis, $pSender, $pArgs)
	#forceref $pSender
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	If $pArgs = 0 Then Return 0
	Local $oArgs = ObjCreateInterface($pArgs, $WV2_IID_MSGARGS, $__WV2_TAG_MSGARGS, False)
	If @Error Or Not IsObj($oArgs) Then Return 0
	Local $sText = ""
	If $oArgs.TryGetWebMessageAsString($sText) = 0 And $sText <> "" Then
		__WV2_PushEvent($i, $WV2_EVENT_WEB_MESSAGE, $sText, 1)
	Else
		$sText = ""
		$oArgs.get_WebMessageAsJson($sText)
		__WV2_PushEvent($i, $WV2_EVENT_WEB_MESSAGE, $sText, 0)
	EndIf
	$oArgs = 0
	Return 0
EndFunc   ;==>__WV2_InvMsg

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvNew
; Description ...: ICoreWebView2NewWindowRequestedEventHandler::Invoke.
;                  The runtime would refuse to create a window it cannot show, so the request is
;                  cancelled here and its URI is queued: the host decides what to do with it.
; ===============================================================================================================================
Func __WV2_InvNew($pThis, $pSender, $pArgs)
	#forceref $pSender
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	If $pArgs = 0 Then Return 0
	Local $oArgs = ObjCreateInterface($pArgs, $WV2_IID_NEWARGS, $__WV2_TAG_NEWARGS, False)
	If @Error Or Not IsObj($oArgs) Then Return 0
	Local $sUri = ""
	$oArgs.get_Uri($sUri)
	$oArgs.put_Handled(1)
	__WV2_PushEvent($i, $WV2_EVENT_NEW_WINDOW, $sUri, 0)
	$oArgs = 0
	Return 0
EndFunc   ;==>__WV2_InvNew

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvTitle
; Description ...: ICoreWebView2DocumentTitleChangedEventHandler::Invoke.
;                  These callbacks carry no useful arguments object, so the title is read from the
;                  web view itself while the pointer is still alive.
; ===============================================================================================================================
Func __WV2_InvTitle($pThis, $pSender, $pArgs)
	#forceref $pArgs
	Local $i = __WV2_FindInst($pThis)
	If @Error Or $pSender = 0 Then Return 0
	Local $sTitle = ""
	Local $oWv = ObjCreateInterface($pSender, $WV2_IID_WV, $__WV2_TAG_WV, False)
	If Not @Error And IsObj($oWv) Then
		$oWv.get_DocumentTitle($sTitle)
		$oWv = 0
	EndIf
	__WV2_PushEvent($i, $WV2_EVENT_TITLE_CHANGED, $sTitle, 0)
	Return 0
EndFunc   ;==>__WV2_InvTitle

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvHist
; Description ...: ICoreWebView2HistoryChangedEventHandler::Invoke.
;                  $iValue is a bit mask: 1 when going back is possible, 2 when going forward is.
; ===============================================================================================================================
Func __WV2_InvHist($pThis, $pSender, $pArgs)
	#forceref $pArgs
	Local $i = __WV2_FindInst($pThis)
	If @Error Or $pSender = 0 Then Return 0
	Local $iValue = 0
	Local $oWv = ObjCreateInterface($pSender, $WV2_IID_WV, $__WV2_TAG_WV, False)
	If Not @Error And IsObj($oWv) Then
		Local $iB = 0, $iF = 0
		If $oWv.get_CanGoBack($iB) = 0 And $iB Then $iValue = 1
		If $oWv.get_CanGoForward($iF) = 0 And $iF Then $iValue = BitOR($iValue, 2)
		$oWv = 0
	EndIf
	__WV2_PushEvent($i, $WV2_EVENT_HISTORY_CHANGED, "", $iValue)
	Return 0
EndFunc   ;==>__WV2_InvHist

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvProc
; Description ...: ICoreWebView2ProcessFailedEventHandler::Invoke.
;                  $iValue holds the COREWEBVIEW2_PROCESS_FAILED_KIND value, a $WV2_PROCFAIL_* code.
; ===============================================================================================================================
Func __WV2_InvProc($pThis, $pSender, $pArgs)
	#forceref $pSender
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	If $pArgs = 0 Then Return 0
	Local $oArgs = ObjCreateInterface($pArgs, $WV2_IID_PROCARGS, $__WV2_TAG_PROCARGS, False)
	If @Error Or Not IsObj($oArgs) Then Return 0
	Local $iKind = 0
	$oArgs.get_ProcessFailedKind($iKind)
	$oArgs = 0
	__WV2_PushEvent($i, $WV2_EVENT_PROCESS_FAILED, "", $iKind)
	If $iKind = $WV2_PROCFAIL_BROWSER Then
		; Nothing answers after the browser process is gone: report every wait as finished.
		$__WV2_bNavDone[$i] = True
		$__WV2_bNavOK[$i] = False
	EndIf
	Return 0
EndFunc   ;==>__WV2_InvProc

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvExec / __WV2_InvAddScript
; Description ...: Invoke of the two handlers carrying a HRESULT and a wide string. The string is
;                  borrowed, so it is copied into the instance before returning.
; ===============================================================================================================================
Func __WV2_InvExec($pThis, $pHr, $pStr)
	Return __WV2_InvString($__WV2_H_EXEC, $pThis, $pHr, $pStr)
EndFunc   ;==>__WV2_InvExec

Func __WV2_InvAddScript($pThis, $pHr, $pStr)
	Return __WV2_InvString($__WV2_H_ADDSCRIPT, $pThis, $pHr, $pStr)
EndFunc   ;==>__WV2_InvAddScript

Func __WV2_InvString($iSlot, $pThis, $pHr, $pStr)
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	$__WV2_iOpHR[$i][$iSlot] = Number($pHr)
	$__WV2_sOpOut[$i][$iSlot] = __WV2_CopyWStr($pStr)
	$__WV2_bOpDone[$i][$iSlot] = True
	Return 0
EndFunc   ;==>__WV2_InvString

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_CopyWStr
; Description ...: Copies a UTF-16 string owned by the runtime into an AutoIt string. A pointer
;                  received as a callback argument is only valid while the callback runs, so nothing
;                  here may be deferred.
; ===============================================================================================================================
Func __WV2_CopyWStr($pStr)
	If $pStr = 0 Then Return ""
	Local $aL = DllCall("kernel32.dll", "dword", "lstrlenW", "ptr", $pStr)
	If @Error Or Not IsArray($aL) Or $aL[0] = 0 Then Return ""
	Local $tRaw = DllStructCreate("byte[" & ($aL[0] * 2) & "]", $pStr)
	If @Error Then Return ""
	Return BinaryToString(DllStructGetData($tRaw, 1), 2)
EndFunc   ;==>__WV2_CopyWStr

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvCap
; Description ...: ICoreWebView2CapturePreviewCompletedHandler::Invoke. Carries a HRESULT only.
; ===============================================================================================================================
Func __WV2_InvCap($pThis, $pHr)
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	$__WV2_iOpHR[$i][$__WV2_H_CAP] = Number($pHr)
	$__WV2_bOpDone[$i][$__WV2_H_CAP] = True
	Return 0
EndFunc   ;==>__WV2_InvCap

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvPrint
; Description ...: ICoreWebView2PrintToPdfCompletedHandler::Invoke. Carries a HRESULT and the answer of
;                  the print itself: the call can succeed while the page refuses to produce a file.
; ===============================================================================================================================
Func __WV2_InvPrint($pThis, $iHr, $iResult)
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	$__WV2_iOpHR[$i][$__WV2_H_PRINT] = $iHr
	$__WV2_sOpOut[$i][$__WV2_H_PRINT] = ($iResult ? "1" : "0")
	$__WV2_bOpDone[$i][$__WV2_H_PRINT] = True
	Return 0
EndFunc   ;==>__WV2_InvPrint

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_InvDl
; Description ...: ICoreWebView2DownloadStartingEventHandler::Invoke.
;                  Reads the URI of the download from the operation the arguments hand out, then applies
;                  the two rules of the instance: a URI matching the filter is refused through put_Cancel,
;                  any other download keeps the file name chosen by the runtime but is moved into the
;                  folder set with put_ResultFilePath. The outcome goes to the event queue.
; ===============================================================================================================================
Func __WV2_InvDl($pThis, $pSender, $pArgs)
	#forceref $pSender
	Local $i = __WV2_FindInst($pThis)
	If @Error Then Return 0
	If $pArgs = 0 Then Return 0

	; get_DownloadOperation answers with a pointer of its own, so it is read and released here.
	Local $pOp = 0
	Local $tOp = DllStructCreate("ptr")
	Local $pFnOp = __WV2_VtFn($pArgs, $__WV2_VT_DLA_OP)
	If $pFnOp <> 0 Then
		Local $aOp = DllCallAddress("long", $pFnOp, "ptr", $pArgs, "ptr", DllStructGetPtr($tOp))
		If (Not @Error) And IsArray($aOp) And $aOp[0] = 0 Then $pOp = DllStructGetData($tOp, 1)
	EndIf
	Local $sUri = ""
	If $pOp <> 0 Then $sUri = __WV2_WStrProp($pOp, $__WV2_VT_DLO_URI)

	Local $bRefused = ($__WV2_sDlFilter[$i] <> "" And StringRegExp($sUri, $__WV2_sDlFilter[$i]))
	If $bRefused Then
		__WV2_CallBool($pArgs, $__WV2_VT_DLA_CANCEL, 1)
	ElseIf $__WV2_sDlFolder[$i] <> "" Then
		; ResultFilePath already holds the full path the runtime picked, file name included: the folder
		; of that path is replaced and nothing else.
		Local $sPath = __WV2_WStrProp($pArgs, $__WV2_VT_DLA_PATH)
		If $sPath <> "" Then __WV2_CallWStr($pArgs, $__WV2_VT_DLA_PATHPUT, $__WV2_sDlFolder[$i] & "\" & __WV2_FileName($sPath))
	EndIf
	If $pOp <> 0 Then __WV2_ReleaseExternal($pOp)

	__WV2_PushEvent($i, $WV2_EVENT_DOWNLOAD_STARTING, $sUri, $bRefused ? 1 : 0)
	Return 0
EndFunc   ;==>__WV2_InvDl

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_PushEvent / __WV2_PopEvent / __WV2_PopEventOfType
; Description ...: Ring buffer of the events received by an instance. The buffer never blocks a
;                  callback: when it is full the oldest event is dropped and the drop counter
;                  returned through @extended by _WV2_GetEvent grows.
; ===============================================================================================================================
Func __WV2_PushEvent($i, $iType, $sData, $iValue)
	Local $iPos
	If $__WV2_iEvtCount[$i] < $__WV2_QCAP Then
		$iPos = Mod($__WV2_iEvtHead[$i] + $__WV2_iEvtCount[$i], $__WV2_QCAP)
		$__WV2_iEvtCount[$i] += 1
	Else
		$__WV2_iEvtDrop[$i] += 1
		$__WV2_iEvtHead[$i] = Mod($__WV2_iEvtHead[$i] + 1, $__WV2_QCAP)
		$iPos = Mod($__WV2_iEvtHead[$i] + $__WV2_QCAP - 1, $__WV2_QCAP)
	EndIf
	$__WV2_aEvtType[$i][$iPos] = $iType
	$__WV2_aEvtStr[$i][$iPos] = String($sData)
	$__WV2_aEvtNum[$i][$iPos] = Number($iValue)
EndFunc   ;==>__WV2_PushEvent

Func __WV2_PopEvent($i, ByRef $iType, ByRef $sData, ByRef $iValue)
	If $__WV2_iEvtCount[$i] = 0 Then Return False
	$iType = $__WV2_aEvtType[$i][$__WV2_iEvtHead[$i]]
	$sData = $__WV2_aEvtStr[$i][$__WV2_iEvtHead[$i]]
	$iValue = $__WV2_aEvtNum[$i][$__WV2_iEvtHead[$i]]
	$__WV2_aEvtStr[$i][$__WV2_iEvtHead[$i]] = ""
	$__WV2_iEvtHead[$i] = Mod($__WV2_iEvtHead[$i] + 1, $__WV2_QCAP)
	$__WV2_iEvtCount[$i] -= 1
	Return True
EndFunc   ;==>__WV2_PopEvent

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_PopEventOfType
; Description ...: Takes the oldest event of one type out of the queue and leaves the others in it.
; Remarks .......: The entries that were queued before the one taken move one slot back, so reading
;                  the queue afterwards still gives them in the order they arrived.
; ===============================================================================================================================
Func __WV2_PopEventOfType($i, $iWant, ByRef $sData, ByRef $iValue)
	Local $k, $iCount = $__WV2_iEvtCount[$i]
	Local $iOff = -1
	For $k = 0 To $iCount - 1
		If $__WV2_aEvtType[$i][Mod($__WV2_iEvtHead[$i] + $k, $__WV2_QCAP)] = $iWant Then
			$iOff = $k
			ExitLoop
		EndIf
	Next
	If $iOff < 0 Then Return False
	Local $iPos = Mod($__WV2_iEvtHead[$i] + $iOff, $__WV2_QCAP)
	$sData = $__WV2_aEvtStr[$i][$iPos]
	$iValue = $__WV2_aEvtNum[$i][$iPos]
	For $k = $iOff To 1 Step -1
		Local $iTo = Mod($__WV2_iEvtHead[$i] + $k, $__WV2_QCAP)
		Local $iFrom = Mod($__WV2_iEvtHead[$i] + $k - 1, $__WV2_QCAP)
		$__WV2_aEvtType[$i][$iTo] = $__WV2_aEvtType[$i][$iFrom]
		$__WV2_aEvtStr[$i][$iTo] = $__WV2_aEvtStr[$i][$iFrom]
		$__WV2_aEvtNum[$i][$iTo] = $__WV2_aEvtNum[$i][$iFrom]
	Next
	$__WV2_aEvtStr[$i][$__WV2_iEvtHead[$i]] = ""
	$__WV2_iEvtHead[$i] = Mod($__WV2_iEvtHead[$i] + 1, $__WV2_QCAP)
	$__WV2_iEvtCount[$i] = $iCount - 1
	Return True
EndFunc   ;==>__WV2_PopEventOfType

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_WaitOp
; Description ...: Pumps messages until an asynchronous operation answers, or the time is over.
; ===============================================================================================================================
Func __WV2_WaitOp($i, $iSlot, $iTimeoutMs)
	Local $tEnd = TimerInit()
	While Not $__WV2_bOpDone[$i][$iSlot]
		__WV2_Pump(20)
		If TimerDiff($tEnd) > $iTimeoutMs Then
			__WV2_SetErr($WV2_ERR_TIMEOUT, 0, "__WV2_WaitOp")
			Return False
		EndIf
	WEnd
	Return True
EndFunc   ;==>__WV2_WaitOp

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_BeginOp
; Description ...: Arms the state of an asynchronous operation before its method is called.
; ===============================================================================================================================
Func __WV2_BeginOp($i, $iSlot)
	$__WV2_bOpDone[$i][$iSlot] = False
	$__WV2_iOpHR[$i][$iSlot] = 0
	$__WV2_sOpOut[$i][$iSlot] = ""
EndFunc   ;==>__WV2_BeginOp

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_Attach / __WV2_Detach
; Description ...: Subscribe one handler slot of an instance to its WebView2 event and register the
;                  cookie returned by add_*, which is what remove_* needs. The method name cannot be
;                  built at run time, so each slot is written out.
; ===============================================================================================================================
Func __WV2_Attach($i, $iSlot)
	If $__WV2_iTok[$i][$iSlot] <> 0 Then Return True
	Local $iTok = 0
	Local $hr = 0
	Switch $iSlot
		Case $__WV2_H_NAVC
			$hr = $__WV2_oWv[$i].add_NavigationCompleted($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_NAVS
			$hr = $__WV2_oWv[$i].add_NavigationStarting($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_MSG
			$hr = $__WV2_oWv[$i].add_WebMessageReceived($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_NEW
			$hr = $__WV2_oWv[$i].add_NewWindowRequested($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_TITLE
			$hr = $__WV2_oWv[$i].add_DocumentTitleChanged($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_HIST
			$hr = $__WV2_oWv[$i].add_HistoryChanged($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_PROC
			$hr = $__WV2_oWv[$i].add_ProcessFailed($__WV2_pObj[$i][$iSlot], $iTok)
		Case $__WV2_H_DOWNLOAD
			; The download event is the only one that lives on a newer version of the interface, so it
			; is subscribed through the raw vtable entry of ICoreWebView2_4.
			Local $p4 = __WV2_ViewIf($i, $__WV2_IF_4)
			If $p4 = 0 Then Return False
			Local $pFn = __WV2_VtFn($p4, $__WV2_VT_ADDDL)
			If $pFn = 0 Then
				__WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")
				Return False
			EndIf
			Local $tTok = DllStructCreate("int64")
			Local $aCall = DllCallAddress("long", $pFn, "ptr", $p4, "ptr", $__WV2_pObj[$i][$iSlot], _
					"ptr", DllStructGetPtr($tTok))
			If @Error Or Not IsArray($aCall) Then
				__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2_4::add_DownloadStarting")
				Return False
			EndIf
			$hr = $aCall[0]
			$iTok = DllStructGetData($tTok, 1)
		Case Else
			__WV2_SetErr($WV2_ERR_ARG, 0, "__WV2_Attach")
			Return False
	EndSwitch
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2::add_" & __WV2_SlotName($iSlot))
		Return False
	EndIf
	$__WV2_iTok[$i][$iSlot] = $iTok
	Return True
EndFunc   ;==>__WV2_Attach

Func __WV2_Detach($i, $iSlot)
	If $__WV2_iTok[$i][$iSlot] = 0 Then Return
	Local $iTok = $__WV2_iTok[$i][$iSlot]
	Switch $iSlot
		Case $__WV2_H_NAVC
			$__WV2_oWv[$i].remove_NavigationCompleted($iTok)
		Case $__WV2_H_NAVS
			$__WV2_oWv[$i].remove_NavigationStarting($iTok)
		Case $__WV2_H_MSG
			$__WV2_oWv[$i].remove_WebMessageReceived($iTok)
		Case $__WV2_H_NEW
			$__WV2_oWv[$i].remove_NewWindowRequested($iTok)
		Case $__WV2_H_TITLE
			$__WV2_oWv[$i].remove_DocumentTitleChanged($iTok)
		Case $__WV2_H_HIST
			$__WV2_oWv[$i].remove_HistoryChanged($iTok)
		Case $__WV2_H_PROC
			$__WV2_oWv[$i].remove_ProcessFailed($iTok)
		Case $__WV2_H_DOWNLOAD
			; remove_DownloadStarting takes its token by value: one int64 pushed on the stack.
			Local $p4 = __WV2_ViewIf($i, $__WV2_IF_4)
			If $p4 <> 0 Then DllCallAddress("long", __WV2_VtFn($p4, $__WV2_VT_REMOVEDL), "ptr", $p4, "int64", $iTok)
	EndSwitch
	$__WV2_iTok[$i][$iSlot] = 0
EndFunc   ;==>__WV2_Detach

Func __WV2_SlotName($iSlot)
	Switch $iSlot
		Case $__WV2_H_ENV
			Return "CreateCoreWebView2EnvironmentCompleted"
		Case $__WV2_H_CTL
			Return "CreateCoreWebView2ControllerCompleted"
		Case $__WV2_H_NAVC
			Return "NavigationCompleted"
		Case $__WV2_H_NAVS
			Return "NavigationStarting"
		Case $__WV2_H_MSG
			Return "WebMessageReceived"
		Case $__WV2_H_NEW
			Return "NewWindowRequested"
		Case $__WV2_H_TITLE
			Return "DocumentTitleChanged"
		Case $__WV2_H_HIST
			Return "HistoryChanged"
		Case $__WV2_H_PROC
			Return "ProcessFailed"
		Case $__WV2_H_EXEC
			Return "ExecuteScript"
		Case $__WV2_H_ADDSCRIPT
			Return "AddScriptToExecuteOnDocumentCreated"
		Case $__WV2_H_CAP
			Return "CapturePreview"
		Case $__WV2_H_PRINT
			Return "PrintToPdf"
		Case $__WV2_H_DOWNLOAD
			Return "DownloadStarting"
		Case Else
			Return "slot " & $iSlot
	EndSwitch
EndFunc   ;==>__WV2_SlotName

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_Settings
; Description ...: Reads and keeps the settings interface of an instance. get_Settings hands out a
;                  pointer that already carries the reference owned by this instance, so the wrapper
;                  is built without flag (no reference added) and __WV2_Teardown releases it once.
; ===============================================================================================================================
Func __WV2_Settings($i)
	If IsObj($__WV2_oSettings[$i]) Then Return $__WV2_oSettings[$i]
	Local $p = 0
	Local $hr = $__WV2_oWv[$i].get_Settings($p)
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, "ICoreWebView2::get_Settings")
		Return 0
	EndIf
	If $p = 0 Then
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2::get_Settings")
		Return 0
	EndIf
	$__WV2_oSettings[$i] = ObjCreateInterface($p, $WV2_IID_SETTINGS, $__WV2_TAG_SETTINGS, False)
	If @Error Or Not IsObj($__WV2_oSettings[$i]) Then
		$__WV2_oSettings[$i] = 0
		__WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2Settings wrapper")
		Return 0
	EndIf
	Return $__WV2_oSettings[$i]
EndFunc   ;==>__WV2_Settings

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_EventSlot
; Description ...: Maps a $WV2_EVENT_* code onto the handler slot that carries it.
; ===============================================================================================================================
Func __WV2_EventSlot($iEvent)
	Switch $iEvent
		Case $WV2_EVENT_NAVIGATION_STARTING
			Return $__WV2_H_NAVS
		Case $WV2_EVENT_NAVIGATION_COMPLETED
			Return $__WV2_H_NAVC
		Case $WV2_EVENT_WEB_MESSAGE
			Return $__WV2_H_MSG
		Case $WV2_EVENT_NEW_WINDOW
			Return $__WV2_H_NEW
		Case $WV2_EVENT_TITLE_CHANGED
			Return $__WV2_H_TITLE
		Case $WV2_EVENT_HISTORY_CHANGED
			Return $__WV2_H_HIST
		Case $WV2_EVENT_PROCESS_FAILED
			Return $__WV2_H_PROC
		Case $WV2_EVENT_DOWNLOAD_STARTING
			Return $__WV2_H_DOWNLOAD
	EndSwitch
	Return 0
EndFunc   ;==>__WV2_EventSlot

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_WaitFor
; Description ...: Pumps messages until the environment and the controller are both in place.
; ===============================================================================================================================
Func __WV2_WaitFor($i, $iTimeoutMs)
	Local $tEnd = TimerInit()
	While 1
		If $__WV2_bCtl[$i] Then
			$__WV2_iLastError = $WV2_ERR_NONE
			$__WV2_iLastHR = 0
			Return True
		EndIf
		If $__WV2_bEnvErr[$i] Then
			__WV2_SetErr($WV2_ERR_ENV, $__WV2_iHR[$i], "ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler")
			Return False
		EndIf
		If $__WV2_bCtlErr[$i] Then
			__WV2_SetErr($WV2_ERR_CONTROLLER, $__WV2_iHR[$i], "ICoreWebView2CreateCoreWebView2ControllerCompletedHandler")
			Return False
		EndIf
		If TimerDiff($tEnd) > $iTimeoutMs Then
			__WV2_SetErr($WV2_ERR_TIMEOUT, $__WV2_iHR[$i], "_WV2_Create")
			Return False
		EndIf
		__WV2_Pump(20)
	WEnd
EndFunc   ;==>__WV2_WaitFor

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_Pump
; Description ...: Runs the message queue of the current thread for a while, the way a GUI loop does.
; ===============================================================================================================================
Func __WV2_Pump($iMs)
	Local Static $tMsg = DllStructCreate("ptr hwnd;uint message;ptr wParam;ptr lParam;dword time;long x;long y")
	Local $tEnd = TimerInit()
	While TimerDiff($tEnd) < $iMs
		Local $aPM = DllCall("user32.dll", "bool", "PeekMessageW", "ptr", DllStructGetPtr($tMsg), "ptr", 0, "dword", 0, "dword", 0, "dword", 1)
		If @Error Or Not $aPM[0] Then
			Sleep(2)
		Else
			DllCall("user32.dll", "bool", "TranslateMessage", "ptr", DllStructGetPtr($tMsg))
			DllCall("user32.dll", "lresult", "DispatchMessageW", "ptr", DllStructGetPtr($tMsg))
		EndIf
	WEnd
EndFunc   ;==>_WV2_Pump

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_Alloc / __WV2_Free / __WV2_Teardown
; Description ...: Instance table. A handle is a slot number, valid until _WV2_Destroy releases it.
; ===============================================================================================================================
Func __WV2_Alloc()
	Local $i, $j
	For $i = 1 To $__WV2_MAX
		If Not $__WV2_aUsed[$i] Then
			$__WV2_aUsed[$i] = 1
			$__WV2_oEnv[$i] = 0
			$__WV2_oCtl[$i] = 0
			$__WV2_pCtl[$i] = 0
			$__WV2_oWv[$i] = 0
			$__WV2_pWv[$i] = 0
			$__WV2_pWvIf[$i][$__WV2_IF_2] = 0
			$__WV2_pWvIf[$i][$__WV2_IF_4] = 0
			$__WV2_pWvIf[$i][$__WV2_IF_7] = 0
			$__WV2_oSettings[$i] = 0
			$__WV2_hParent[$i] = 0
			$__WV2_iLeft[$i] = 0
			$__WV2_iTop[$i] = 0
			$__WV2_iRight[$i] = 0
			$__WV2_iBottom[$i] = 0
			$__WV2_bEnv[$i] = False
			$__WV2_bCtl[$i] = False
			$__WV2_bReady[$i] = False
			$__WV2_bEnvErr[$i] = False
			$__WV2_bCtlErr[$i] = False
			$__WV2_bNavDone[$i] = False
			$__WV2_bNavOK[$i] = False
			$__WV2_iWebErr[$i] = 0
			$__WV2_iHR[$i] = 0
			$__WV2_sUser[$i] = ""
			$__WV2_bTempUser[$i] = False
			$__WV2_sVersion[$i] = ""
			$__WV2_sNavFilter[$i] = ""
			$__WV2_sDlFilter[$i] = ""
			$__WV2_sDlFolder[$i] = ""
			$__WV2_iEvtHead[$i] = 0
			$__WV2_iEvtCount[$i] = 0
			$__WV2_iEvtDrop[$i] = 0
			For $j = 1 To $__WV2_SLOT_COUNT
				$__WV2_pObj[$i][$j] = 0
				$__WV2_iTok[$i][$j] = 0
				$__WV2_bOpDone[$i][$j] = False
				$__WV2_iOpHR[$i][$j] = 0
				$__WV2_sOpOut[$i][$j] = ""
			Next
			Return $i
		EndIf
	Next
	Return 0
EndFunc   ;==>__WV2_Alloc

Func __WV2_Free($i)
	__WV2_FreeHandlers($i)
	If $__WV2_bTempUser[$i] And $__WV2_sUser[$i] <> "" Then DirRemove($__WV2_sUser[$i], 1)
	$__WV2_aUsed[$i] = 0
	$__WV2_bReady[$i] = False
	$__WV2_bCtl[$i] = False
	$__WV2_bEnv[$i] = False
EndFunc   ;==>__WV2_Free

Func __WV2_Teardown($i)
	Local $j
	For $j = 1 To $__WV2_SLOT_COUNT
		__WV2_Detach($i, $j)
	Next
	; The versions of the interface asked for through QueryInterface go first: they are references to
	; the same object as the view, and an interface must outlive the pointers taken from it.
	For $j = 1 To $__WV2_IF_7
		If $__WV2_pWvIf[$i][$j] <> 0 Then
			__WV2_ReleaseExternal($__WV2_pWvIf[$i][$j])
			$__WV2_pWvIf[$i][$j] = 0
		EndIf
	Next
	If IsObj($__WV2_oSettings[$i]) Then
		$__WV2_oSettings[$i].Release()
		$__WV2_oSettings[$i] = 0
	EndIf
	If IsObj($__WV2_oWv[$i]) Then $__WV2_oWv[$i].Release()
	$__WV2_oWv[$i] = 0
	$__WV2_pWv[$i] = 0
	If IsObj($__WV2_oCtl[$i]) Then
		$__WV2_iLastHR = $__WV2_oCtl[$i].Close()
		$__WV2_oCtl[$i].Release()
	EndIf
	$__WV2_oCtl[$i] = 0
	$__WV2_pCtl[$i] = 0
	__WV2_Pump(100)
	If IsObj($__WV2_oEnv[$i]) Then $__WV2_oEnv[$i].Release()
	$__WV2_oEnv[$i] = 0
	__WV2_Pump(100)
EndFunc   ;==>__WV2_Teardown

Func __WV2_Fail($i)
	__WV2_Teardown($i)
	__WV2_Free($i)
EndFunc   ;==>__WV2_Fail

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_Valid / __WV2_Guard / __WV2_GuardCtl
; Description ...: Precondition checks. Each one leaves @error style state in the globals when it
;                  refuses, so every public function reports the same way.
; ===============================================================================================================================
Func __WV2_Valid($i)
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	If Not IsNumber($i) Or $i <> Int($i) Or $i < 1 Or $i > $__WV2_MAX Or Not $__WV2_aUsed[$i] Then
		$__WV2_iLastError = $WV2_ERR_HANDLE
		Return False
	EndIf
	Return True
EndFunc   ;==>__WV2_Valid

Func __WV2_Guard($i)
	If Not __WV2_Valid($i) Then Return False
	If Not $__WV2_bReady[$i] Then
		$__WV2_iLastError = $WV2_ERR_NOT_READY
		Return False
	EndIf
	Return True
EndFunc   ;==>__WV2_Guard

Func __WV2_GuardCtl($i)
	If Not __WV2_Valid($i) Then Return False
	If Not $__WV2_bCtl[$i] Then
		$__WV2_iLastError = $WV2_ERR_NOT_READY
		Return False
	EndIf
	Return True
EndFunc   ;==>__WV2_GuardCtl

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_BeginNavigation / __WV2_Result / __WV2_BoolMethod
; Description ...: Shared bodies of the thin wrappers around ICoreWebView2.
; Remarks .......: __WV2_Result only records the outcome, it cannot hand an @error to the caller of
;                  the public function that uses it: SetError applies to the function that calls it.
;                  Every public wrapper therefore ends with its own
;                  "Return SetError($__WV2_iLastError, $__WV2_iLastHR, ...)" read from these globals.
; ===============================================================================================================================
Func __WV2_BeginNavigation($i)
	$__WV2_bNavDone[$i] = False
	$__WV2_bNavOK[$i] = False
	$__WV2_iWebErr[$i] = 0
EndFunc   ;==>__WV2_BeginNavigation

Func __WV2_Result($hr, $sLabel)
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, $sLabel)
		Return 0
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	Return 1
EndFunc   ;==>__WV2_Result

Func __WV2_BoolMethod($iHandle, $sMethod, $sLabel)
	$__WV2_iLastError = $WV2_ERR_NONE
	$__WV2_iLastHR = 0
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	Local $iV = 0
	Local $hr = 0
	If $sMethod = "get_CanGoBack" Then
		$hr = $__WV2_oWv[$iHandle].get_CanGoBack($iV)
	ElseIf $sMethod = "get_CanGoForward" Then
		$hr = $__WV2_oWv[$iHandle].get_CanGoForward($iV)
	Else
		__WV2_SetErr($WV2_ERR_ARG, 0, $sLabel)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	EndIf
	If $hr <> 0 Then
		__WV2_SetErr($WV2_ERR_CALL, $hr, $sLabel)
		Return SetError($__WV2_iLastError, $__WV2_iLastHR, -1)
	EndIf
	$__WV2_iLastError = $WV2_ERR_NONE
	Return SetError(0, 0, $iV ? 1 : 0)
EndFunc   ;==>__WV2_BoolMethod

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_SetErr / __WV2_ErrText
; Description ...: Error reporting shared by every public function.
; ===============================================================================================================================
Func __WV2_SetErr($iErr, $iHR, $sFunc)
	$__WV2_iLastError = $iErr
	$__WV2_iLastHR = Number($iHR)
	$__WV2_sLastFunc = $sFunc
EndFunc   ;==>__WV2_SetErr

Func __WV2_ErrText($iErr)
	Switch $iErr
		Case $WV2_ERR_NONE
			Return "No error"
		Case $WV2_ERR_HANDLE
			Return "Invalid handle"
		Case $WV2_ERR_ARG
			Return "Invalid argument"
		Case $WV2_ERR_RUNTIME
			Return "WebView2 runtime not found"
		Case $WV2_ERR_COM
			Return "COM failure"
		Case $WV2_ERR_ENV
			Return "Environment creation failed"
		Case $WV2_ERR_CONTROLLER
			Return "Controller creation failed"
		Case $WV2_ERR_NOT_READY
			Return "Instance not ready"
		Case $WV2_ERR_CALL
			Return "Method call failed"
		Case $WV2_ERR_TIMEOUT
			Return "Timeout"
		Case $WV2_ERR_FULL
			Return "Too many instances"
		Case $WV2_ERR_FILE
			Return "File could not be written"
		Case Else
			Return "Unknown error"
	EndSwitch
EndFunc   ;==>__WV2_ErrText

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_ClientSize
; Description ...: Reads the client size of a window into the scratch globals.
; ===============================================================================================================================
Func __WV2_ClientSize($hWnd)
	Local Static $tRc = DllStructCreate("long left;long top;long right;long bottom")
	DllCall("user32.dll", "bool", "GetClientRect", "hwnd", $hWnd, "ptr", DllStructGetPtr($tRc))
	$__WV2_iClientW = DllStructGetData($tRc, "right") - DllStructGetData($tRc, "left")
	$__WV2_iClientH = DllStructGetData($tRc, "bottom") - DllStructGetData($tRc, "top")
	Return $__WV2_iClientW > 0 And $__WV2_iClientH > 0
EndFunc   ;==>__WV2_ClientSize

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __WV2_IIDString
; Description ...: Reads a GUID at an address and formats it the AutoIt way, "{XXXXXXXX-XXXX-...}".
; ===============================================================================================================================
Func __WV2_IIDString($pIID)
	Return StringUpper("{" & __WV2_RevHex($pIID, 4) & "-" & __WV2_RevHex($pIID + 4, 2) & "-" & __WV2_RevHex($pIID + 6, 2) & "-" & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 8), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 9), 1), 2) & "-" & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 10), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 11), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 12), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 13), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 14), 1), 2) & _
			Hex(DllStructGetData(DllStructCreate("byte", $pIID + 15), 1), 2) & "}")
EndFunc   ;==>__WV2_IIDString

Func __WV2_RevHex($p, $iN)
	Local $i
	Local $s = ""
	For $i = $iN - 1 To 0 Step -1
		$s &= Hex(DllStructGetData(DllStructCreate("byte", $p + $i), 1), 2)
	Next
	Return $s
EndFunc   ;==>__WV2_RevHex
