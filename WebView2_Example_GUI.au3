; #INDEX# =======================================================================================================================
; Title .........: WebView2 UDF - example
; AutoIt Version : 3.3.16+
; Language .......: English
; Description ...: A small browser built with WebView2.au3: an address bar, history, zoom, JavaScript,
;                  a two way message bridge, page settings, page snapshots, a PDF export, and the
;                  downloads the page starts - all rendered inside the AutoIt window with no external
;                  dependency.
;                  Run with --auto to execute the self test instead of the interface.
; Author ........: Numeric1
; License .......: MIT, Copyright (c) 2026 Numeric1. Keep this header and the LICENSE file in any
;                  copy or redistribution.
; ===============================================================================================================================

#include <AutoItConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include "WebView2.au3"

Opt("MustDeclareVars", 1)

Global $g_hMain = 0
Global $g_hUrl = 0, $g_hGo = 0, $g_hBack = 0, $g_hFwd = 0, $g_hReload = 0, $g_hStop = 0
Global $g_hZoomOut = 0, $g_hZoomIn = 0, $g_hStatus = 0
Global $g_hJs = 0, $g_hShot = 0, $g_hPdf = 0
Global $g_iWV = 0
Global $g_iBarTop = 34 ; address bar
Global $g_iBarBot = 30 ; zoom buttons, JS, snapshot, PDF, status line
Global $g_iOk = 0, $g_iKo = 0
Global $g_iHold = 0 ; milliseconds a written message still owns the status line

If $CmdLine[0] >= 1 And ($CmdLine[1] = "--auto" Or $CmdLine[1] = "/auto") Then
	__AutoTest()
EndIf
__GuiDemo()

; #FUNCTION# ====================================================================================================================
; Name ..........: __GuiDemo
; Description ...: Interactive browser window.
; ===============================================================================================================================
Func __GuiDemo()
	$g_hMain = GUICreate("WebView2 UDF - demo", 960, 640, 120, 80, _
			BitOR($GUI_SS_DEFAULT_GUI, $WS_MAXIMIZEBOX))

	$g_hUrl = GUICtrlCreateInput("https://www.autoitscript.com/", 8, 6, 600, 22)
	$g_hGo = GUICtrlCreateButton("Go", 620, 5, 52, 24)
	$g_hBack = GUICtrlCreateButton("<", 676, 5, 30, 24)
	$g_hFwd = GUICtrlCreateButton(">", 710, 5, 30, 24)
	$g_hReload = GUICtrlCreateButton("Reload", 744, 5, 58, 24)
	$g_hStop = GUICtrlCreateButton("Stop", 806, 5, 44, 24)
	$g_hZoomOut = GUICtrlCreateButton("A-", 8, 8, 34, 22)
	$g_hZoomIn = GUICtrlCreateButton("A+", 44, 8, 34, 22)
	$g_hJs = GUICtrlCreateButton("JS", 82, 8, 34, 22)
	$g_hShot = GUICtrlCreateButton("Shot", 118, 8, 44, 22)
	$g_hPdf = GUICtrlCreateButton("PDF", 166, 8, 44, 22)
	$g_hStatus = GUICtrlCreateLabel("Starting the WebView2 runtime...", 216, 10, 700, 18, _
			BitOR($SS_LEFT, $SS_NOPREFIX))
	GUICtrlSetFont($g_hStatus, 8.5)
	GUISetState(@SW_SHOW, $g_hMain)

	Local $aClient = WinGetClientSize($g_hMain)
	__Layout($aClient[0], $aClient[1])

	$g_iWV = _WV2_Create($g_hMain, 0, $g_iBarTop, $aClient[0], _
			$aClient[1] - $g_iBarTop - $g_iBarBot)
	If $g_iWV = 0 Then
		__Status("Cannot start WebView2: " & _WV2_GetLastErrorMessage())
		While GUIGetMsg() <> $GUI_EVENT_CLOSE
			Sleep(50)
		WEnd
		Exit
	EndIf

	; Everything the loop below reacts to is an event the view has to publish.
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_NAVIGATION_STARTING)
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_WEB_MESSAGE)
	; A link with target=_blank raises NewWindowRequested: __DrainEvents() opens it in this same view.
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_NEW_WINDOW)
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_TITLE_CHANGED)
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_PROCESS_FAILED)
	; A download raised by the page is reported by __DrainEvents(); _WV2_SetDownloadFolder() would
	; choose where the file lands, or a filter would refuse it.
	_WV2_EnableEvent($g_iWV, $WV2_EVENT_DOWNLOAD_STARTING)
	_WV2_SettingWrite($g_iWV, "AreDevToolsEnabled", True)

	Local $sVer = ""
	_WV2_GetBrowserVersion($g_iWV, $sVer)
	__Status("WebView2 runtime " & $sVer & " - ready")
	__Go(GUICtrlRead($g_hUrl))

	While 1
		Local $m = GUIGetMsg()
		Switch $m
			Case $GUI_EVENT_CLOSE
				ExitLoop
			Case $GUI_EVENT_RESIZED, $GUI_EVENT_MAXIMIZE, $GUI_EVENT_RESTORE
				Local $aC = WinGetClientSize($g_hMain)
				If Not @Error And IsArray($aC) Then
					__Layout($aC[0], $aC[1])
					_WV2_SetBounds($g_iWV, 0, $g_iBarTop, $aC[0], $aC[1] - $g_iBarTop - $g_iBarBot)
				EndIf
			Case $g_hGo
				__Go(GUICtrlRead($g_hUrl))
			Case $g_hBack
				_WV2_GoBack($g_iWV)
			Case $g_hFwd
				_WV2_GoForward($g_iWV)
			Case $g_hReload
				_WV2_Reload($g_iWV)
			Case $g_hStop
				_WV2_Stop($g_iWV)
			Case $g_hZoomOut
				__Zoom(-0.1)
			Case $g_hZoomIn
				__Zoom(0.1)
			Case $g_hJs
				__RunJs()
			Case $g_hShot
				__Snapshot()
			Case $g_hPdf
				__ExportPdf()
		EndSwitch
		__DrainEvents()
		__PollTitle()
		Sleep(30)
	WEnd

	_WV2_Destroy($g_iWV)
	$g_iWV = 0
	Exit
EndFunc   ;==>__GuiDemo

; Place the AutoIt controls around a client area of known size. The web view owns everything between
; the address bar and the status bar, so both bars have to stay outside of it.
Func __Layout($iW, $iH)
	Local $iTopRight = $iW - 8 - 230
	GUICtrlSetPos($g_hUrl, 8, 6, $iTopRight - 14, 22)
	GUICtrlSetPos($g_hGo, $iTopRight, 5, 52, 24)
	GUICtrlSetPos($g_hBack, $iTopRight + 56, 5, 30, 24)
	GUICtrlSetPos($g_hFwd, $iTopRight + 90, 5, 30, 24)
	GUICtrlSetPos($g_hReload, $iTopRight + 124, 5, 58, 24)
	GUICtrlSetPos($g_hStop, $iTopRight + 186, 5, 44, 24)
	Local $iBottom = $iH - $g_iBarBot
	GUICtrlSetPos($g_hZoomOut, 8, $iBottom + 4, 34, 22)
	GUICtrlSetPos($g_hZoomIn, 44, $iBottom + 4, 34, 22)
	GUICtrlSetPos($g_hJs, 82, $iBottom + 4, 34, 22)
	GUICtrlSetPos($g_hShot, 118, $iBottom + 4, 44, 22)
	GUICtrlSetPos($g_hPdf, 166, $iBottom + 4, 44, 22)
	GUICtrlSetPos($g_hStatus, 216, $iBottom + 6, $iW - 224, 18)
EndFunc   ;==>__Layout

Func __Go($sUrl)
	$sUrl = StringStripWS($sUrl, 3)
	If $sUrl = "" Then Return
	If Not StringRegExp($sUrl, "^[a-zA-Z][a-zA-Z0-9+.-]*:") Then $sUrl = "https://" & $sUrl
	GUICtrlSetData($g_hUrl, $sUrl)
	If _WV2_Navigate($g_iWV, $sUrl) Then
		__Status("Navigating to " & $sUrl & "...")
	Else
		__Status("Navigation refused: " & _WV2_GetLastErrorMessage())
	EndIf
EndFunc   ;==>__Go

Func __Zoom($d)
	If $g_iWV = 0 Then Return
	Local $z = _WV2_GetZoom($g_iWV)
	If $z < 0.25 Then $z = 1
	_WV2_SetZoom($g_iWV, $z + $d)
EndFunc   ;==>__Zoom

; Reads a value out of the page, which is what a settings panel or a form would do.
Func __RunJs()
	Local $sOut = ""
	If Not _WV2_ExecuteScript($g_iWV, "JSON.stringify({title:document.title,links:document.links.length,scroll:Math.round(window.scrollY)})", $sOut) Then
		__Status("Script failed: " & _WV2_GetLastErrorMessage())
	Else
		__Status("Page answers " & $sOut)
	EndIf
EndFunc   ;==>__RunJs

Func __Snapshot()
	Local $sFile = @TempDir & "\wv2_shot_" & @AutoItPID & ".png"
	If _WV2_CapturePreview($g_iWV, $sFile) Then
		; Only the name is shown: the status line is visible on screenshots, the temp folder is not.
		__Status("Snapshot saved in the temp folder as " & StringTrimLeft($sFile, StringInStr($sFile, "\", 0, -1)))
	Else
		__Status("Snapshot failed: " & _WV2_GetLastErrorMessage())
	EndIf
EndFunc   ;==>__Snapshot

; Same as the snapshot, except that the page is printed to a real PDF file by the runtime itself.
Func __ExportPdf()
	Local $sFile = @TempDir & "\wv2_page_" & @AutoItPID & ".pdf"
	If _WV2_PrintToPdf($g_iWV, $sFile) Then
		__Status("PDF saved in the temp folder as " & StringTrimLeft($sFile, StringInStr($sFile, "\", 0, -1)))
	Else
		__Status("PDF export failed: " & _WV2_GetLastErrorMessage())
	EndIf
EndFunc   ;==>__ExportPdf

; Every queued event is read here. A real application would only enable what it needs.
Func __DrainEvents()
	If $g_iWV = 0 Then Return
	Local $sData = "", $iValue = 0
	While 1
		Local $iType = _WV2_GetEvent($g_iWV, $sData, $iValue)
		If $iType <= 0 Then ExitLoop
		Switch $iType
			Case $WV2_EVENT_NEW_WINDOW
				__Go($sData)
			Case $WV2_EVENT_WEB_MESSAGE
				__Status("Page says: " & $sData)
				_WV2_PostWebMessageAsString($g_iWV, "host received " & $iValue)
			Case $WV2_EVENT_NAVIGATION_STARTING
				If $iValue = 1 Then __Status("User navigation to " & $sData)
			Case $WV2_EVENT_TITLE_CHANGED
				__Status("Title is now " & $sData)
			Case $WV2_EVENT_PROCESS_FAILED
				__Status("A browser process failed (kind " & $iValue & ")")
			Case $WV2_EVENT_DOWNLOAD_STARTING
				If $iValue = 1 Then
					__Status("Download refused: " & __UriLabel($sData))
				Else
					__Status("Download started: " & __UriLabel($sData))
				EndIf
		EndSwitch
	WEnd
EndFunc   ;==>__DrainEvents

; A file:// address, or the blob: address of a page built file, would print the user's own folders in
; the status line, so only its kind is shown there.
Func __UriLabel($sUri)
	If StringInStr($sUri, "file:") > 0 Then Return "a file on this computer"
	Return $sUri
EndFunc   ;==>__UriLabel

Func __PollTitle()
	If $g_iWV = 0 Then Return
	; The page line is refreshed every round of the loop, so a message written by a button would be
	; gone before it could be read: the status line is left alone while a message holds it.
	If $g_iHold > 0 Then
		$g_iHold -= 30
		Return
	EndIf
	Local $sT = "", $sU = ""
	_WV2_GetTitle($g_iWV, $sT)
	_WV2_GetSource($g_iWV, $sU)
	Local $iNav = _WV2_IsNavigationComplete($g_iWV)
	Local $iWebErr = @extended

	Local $s = ($sT = "" ? "(no title)" : $sT)
	If $iNav <> 1 Then
		$s &= "  -  loading..."
	ElseIf $iWebErr <> 0 Then
		$s &= "  -  web error " & $iWebErr
	EndIf
	; A file:// address would print the user's own folders in the title bar, so only its name is shown.
	If StringLeft($sU, 8) = "file:///" Then $sU = "local file"
	GUICtrlSetData($g_hStatus, $s & @TAB & @TAB & $sU)
EndFunc   ;==>__PollTitle

; Writes the status line and keeps it readable for a few seconds, see __PollTitle.
Func __Status($s)
	GUICtrlSetData($g_hStatus, $s)
	$g_iHold = 4000
EndFunc   ;==>__Status

; #FUNCTION# ====================================================================================================================
; Name ..........: __AutoTest
; Description ...: Self test of every public function. Exits 0 when all checks passed, 1 otherwise.
; ===============================================================================================================================
Func __AutoTest()
	$g_hMain = GUICreate("WebView2 UDF self test", 700, 500, 40, 40)
	GUISetState(@SW_SHOW, $g_hMain)

	__Say("1. runtime located")
	Local $sDll = _WV2_GetRuntimePath()
	__Check($sDll <> "" And StringInStr($sDll, "EmbeddedBrowserWebView.dll") > 0, _
			"dll: " & StringLeft($sDll, StringInStr($sDll, "\", 2, -2)))

	__Say("2. create")
	$g_iWV = _WV2_Create($g_hMain, 0, 0, 640, 420)
	__Check($g_iWV > 0, _WV2_GetLastErrorMessage())
	If $g_iWV = 0 Then __Finish()

	__Say("3. handle reported ready")
	__Check(_WV2_IsReady($g_iWV) = 1)

	__Say("4. browser version")
	Local $sVer = ""
	Local $bVer = _WV2_GetBrowserVersion($g_iWV, $sVer)
	__Check($bVer = 1 And StringRegExp($sVer, "^\d+\.\d+\.\d+\.\d+$") = 1, $sVer)

	__Say("5. NavigateToString")
	_WV2_NavigateToString($g_iWV, __Page("WV2 PAGE ONE"))
	__WaitOk(15000)
	Local $sT = ""
	_WV2_GetTitle($g_iWV, $sT)
	__Check($sT = "WV2 PAGE ONE", "title [" & $sT & "]")

	__Say("6. Navigate to a local file")
	Local $sFile = @TempDir & "\wv2_selftest_" & @AutoItPID & ".html"
	Local $hF = FileOpen($sFile, 2)
	FileWrite($hF, __Page("WV2 FILE PAGE"))
	FileClose($hF)
	__Check(_WV2_Navigate($g_iWV, "file:///" & StringReplace($sFile, "\", "/")) = 1, _WV2_GetLastErrorMessage())
	__WaitOk(15000)
	_WV2_GetTitle($g_iWV, $sT)
	__Check($sT = "WV2 FILE PAGE", "title [" & $sT & "]")

	__Say("7. history")
	__Check(_WV2_CanGoBack($g_iWV) = 1)
	_WV2_GoBack($g_iWV)
	__WaitOk(15000)
	_WV2_GetTitle($g_iWV, $sT)
	__Check($sT = "WV2 PAGE ONE", "title after GoBack [" & $sT & "]")
	__Check(_WV2_CanGoForward($g_iWV) = 1)
	_WV2_GoForward($g_iWV)
	_WV2_WaitNavigation($g_iWV, 15000)

	__Say("8. bounds")
	__Check(_WV2_SetBounds($g_iWV, 12, 20, 300, 200) = 1, _WV2_GetLastErrorMessage())
	Local $iL, $iT, $iW, $iH
	_WV2_GetBounds($g_iWV, $iL, $iT, $iW, $iH)
	__Check($iL = 12 And $iT = 20 And $iW = 300 And $iH = 200, "read back " & $iL & "," & $iT & " " & $iW & "x" & $iH)
	__Check(_WV2_FitToParent($g_iWV) = 1)
	_WV2_GetBounds($g_iWV, $iL, $iT, $iW, $iH)
	__Check($iL = 0 And $iT = 0 And $iW > 0 And $iH > 0, "fitted " & $iW & "x" & $iH)

	__Say("9. zoom and visibility")
	__Check(_WV2_SetZoom($g_iWV, 1.5) = 1, _WV2_GetLastErrorMessage())
	Local $z = _WV2_GetZoom($g_iWV)
	__Check(Abs($z - 1.5) < 0.001, "zoom " & $z)
	__Check(_WV2_SetVisible($g_iWV, False) = 1)
	__Check(_WV2_SetVisible($g_iWV, True) = 1)
	__Check(_WV2_Stop($g_iWV) = 1)

	__Say("10. invalid arguments refused")
	__Check(_WV2_Navigate($g_iWV, "") = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_Navigate(99, "https://example.com/") = 0 And @error = $WV2_ERR_HANDLE)
	__Check(_WV2_SetZoom($g_iWV, 50) = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_SetBounds(0, 0, 0, 10, 10) = 0 And @error = $WV2_ERR_HANDLE)

	__Say("11. ExecuteScript")
	_WV2_NavigateToString($g_iWV, __Page("WV2 SCRIPTS"))
	__WaitOk(15000)
	Local $sOut = ""
	__Check(_WV2_ExecuteScript($g_iWV, "21 * 2", $sOut) = 1, _WV2_GetLastErrorMessage())
	__Check($sOut = "42", "number came back as [" & $sOut & "]")
	__Check(_WV2_ExecuteScript($g_iWV, "document.title", $sOut) = 1)
	__Check($sOut = '"WV2 SCRIPTS"', "string came back as [" & $sOut & "]")
	__Check(_WV2_ExecuteScript($g_iWV, "({a:1,b:[2,3]})", $sOut) = 1 And $sOut = '{"a":1,"b":[2,3]}', "object came back as [" & $sOut & "]")
	; A script that throws is not an error for the runtime: it answers with a null result, which is
	; what the page is asked to test for when a script may fail.
	__Check(_WV2_ExecuteScript($g_iWV, "throw new Error('boom')", $sOut) = 1 And $sOut = "null", "a thrown script answers null")
	__Check(_WV2_ExecuteScript($g_iWV, "", $sOut) = 0 And @error = $WV2_ERR_ARG)

	__Say("12. AddScriptToExecuteOnDocumentCreated")
	Local $sId = ""
	__Check(_WV2_AddScriptToExecuteOnDocumentCreated($g_iWV, 'window.__wv2injected = "injected";', $sId) = 1 And $sId <> "", _WV2_GetLastErrorMessage())
	_WV2_NavigateToString($g_iWV, __Page("WV2 INJECTED"))
	__WaitOk(15000)
	__Check(_WV2_ExecuteScript($g_iWV, "String(window.__wv2injected)", $sOut) = 1 And $sOut = '"injected"', "page sees [" & $sOut & "]")
	__Check(_WV2_RemoveScriptToExecuteOnDocumentCreated($g_iWV, $sId) = 1, _WV2_GetLastErrorMessage())
	_WV2_NavigateToString($g_iWV, __Page("WV2 AFTER REMOVE"))
	__WaitOk(15000)
	__Check(_WV2_ExecuteScript($g_iWV, "String(window.__wv2injected)", $sOut) = 1 And $sOut = '"undefined"', "removed: [" & $sOut & "]")

	__Say("13. web message from the page")
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_WEB_MESSAGE) = 1, _WV2_GetLastErrorMessage())
	_WV2_NavigateToString($g_iWV, __BridgePage())
	Local $sData = "", $iValue = 0
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_WEB_MESSAGE, 15000, $sData, $iValue) = 1, _WV2_GetLastErrorMessage())
	__Check($sData = "page says hello" And $iValue = 1, "message [" & $sData & "] plain " & $iValue)

	__Say("14. web message to the page")
	__Check(_WV2_PostWebMessageAsString($g_iWV, "host ping") = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_WEB_MESSAGE, 5000, $sData, $iValue) = 1 And $sData = "host ping heard", "page answered [" & $sData & "]")
	__Check(_WV2_PostWebMessage($g_iWV, '{"cmd":"refresh","n":7}') = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_ExecuteScript($g_iWV, "String(window.__lastJson)", $sOut, 8000) = 1 And $sOut = '"refresh:7"', "JSON reached the page [" & $sOut & "]")
	__Check(_WV2_PostWebMessage($g_iWV, "not json at all") = 0 And @error = $WV2_ERR_CALL, "malformed JSON refused")

	__Say("15. page settings")
	Local $iWas = _WV2_SettingRead($g_iWV, "AreDevToolsEnabled")
	__Check($iWas = 0 Or $iWas = 1, "read back " & $iWas)
	__Check(_WV2_SettingWrite($g_iWV, "AreDevToolsEnabled", Not ($iWas = 1)) = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_SettingRead($g_iWV, "AreDevToolsEnabled") = ($iWas = 1 ? 0 : 1), "changed and read")
	__Check(_WV2_SettingWrite($g_iWV, "IsStatusBarEnabled", False) = 1 And _WV2_SettingRead($g_iWV, "IsStatusBarEnabled") = 0)
	__Check(_WV2_SettingWrite($g_iWV, "isbuiltinerrorpageenabled", True) = 1, "name matched without regard to case")
	__Check(_WV2_SettingRead($g_iWV, "NoSuchSetting") = -1 And @error = $WV2_ERR_ARG)

	__Say("16. navigation filter")
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_NAVIGATION_STARTING) = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_SetNavigationFilter($g_iWV, "^https://blocked\.example/") = 1)
	_WV2_Navigate($g_iWV, "https://blocked.example/secret")
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_NAVIGATION_STARTING, 8000, $sData, $iValue) = 1 And _
			StringInStr($sData, "blocked.example") > 0, "intercepted [" & $sData & "]")
	_WV2_GetTitle($g_iWV, $sT)
	__Check($sT = "WV2 BRIDGE", "cancelled page never loaded, title [" & $sT & "]")
	; The refused navigation is finished with the cancellation status. Waiting for it here also keeps
	; its late completion out of the navigation started below.
	__Check(_WV2_WaitNavigation($g_iWV, 8000) = 1 And @extended = 14, "refused navigation ends cancelled, web error " & @extended)
	__Check(_WV2_SetNavigationFilter($g_iWV, "") = 1)
	_WV2_NavigateToString($g_iWV, __BridgePage())
	__WaitOk(15000)

	__Say("17. new window request")
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_NEW_WINDOW) = 1, _WV2_GetLastErrorMessage())
	_WV2_ExecuteScript($g_iWV, "window.open('https://www.example.org/'); true", $sOut)
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_NEW_WINDOW, 8000, $sData, $iValue) = 1 And _
			StringInStr($sData, "example.org") > 0, "popup URL handed to the host [" & $sData & "]")

	__Say("18. title, history and empty queue")
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_TITLE_CHANGED) = 1, _WV2_GetLastErrorMessage())
	_WV2_NavigateToString($g_iWV, __Page("WV2 TITLE EVENT"))
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_TITLE_CHANGED, 15000, $sData, $iValue) = 1 And $sData = "WV2 TITLE EVENT", "title event [" & $sData & "]")
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_HISTORY_CHANGED) = 1, _WV2_GetLastErrorMessage())
	; A page loaded over file:// adds a history entry, which a NavigateToString page does not: this is
	; what makes the mask published by the view change here.
	__Check(_WV2_Navigate($g_iWV, "file:///" & StringReplace($sFile, "\", "/")) = 1, _WV2_GetLastErrorMessage())
	__WaitOk(15000)
	; The mask is bit 1 for CanGoBack and bit 2 for CanGoForward, and several of them can be queued by
	; one navigation: the last one is the only that has to agree with the view as it stands.
	Local $iLastMask = -1
	While _WV2_WaitEvent($g_iWV, $WV2_EVENT_HISTORY_CHANGED, 2000, $sData, $iValue) = 1
		$iLastMask = $iValue
	WEnd
	Local $iMask = BitAND(_WV2_CanGoBack($g_iWV), 1) + 2 * BitAND(_WV2_CanGoForward($g_iWV), 1)
	__Check($iLastMask >= 0 And $iLastMask = $iMask, "last history mask " & $iLastMask & ", view says " & $iMask)
	; Reading past the end of the queue is a normal answer, not an error.
	Local $iDrained = 0
	While _WV2_GetEvent($g_iWV, $sData, $iValue) > 0
		$iDrained += 1
	WEnd
	$iValue = -1
	__Check(_WV2_GetEvent($g_iWV, $sData, $iValue) = 0 And @error = 0, "queue empty after " & $iDrained & " events")
	__Check(_WV2_EnableEvent($g_iWV, 999) = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_PROCESS_FAILED, 50, $sData, $iValue) = 0 And @error = $WV2_ERR_ARG, "waiting for a disabled event is refused")

	__Say("19. snapshot of the page")
	Local $sShot = @TempDir & "\wv2_shot_" & @AutoItPID & ".png"
	__Check(_WV2_CapturePreview($g_iWV, $sShot) = 1, _WV2_GetLastErrorMessage())
	Local $bShot = __ReadBin($sShot)
	__Check(BinaryLen($bShot) > 1000 And BinaryMid($bShot, 1, 4) = Binary("0x89504E47"), "png of " & BinaryLen($bShot) & " bytes")
	FileDelete($sShot)
	__Check(_WV2_CapturePreview($g_iWV, $sShot, $WV2_IMAGE_JPEG) = 1, _WV2_GetLastErrorMessage())
	$bShot = __ReadBin($sShot)
	__Check(BinaryMid($bShot, 1, 3) = Binary("0xFFD8FF"), "jpeg of " & BinaryLen($bShot) & " bytes")
	FileDelete($sShot)
	__Check(_WV2_CapturePreview($g_iWV, "") = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_CapturePreview($g_iWV, $sShot, 7) = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_CapturePreview($g_iWV, "Z:\no\such\folder\shot.png") = 0 And @error = $WV2_ERR_FILE, "unwritable target reported")

	__Say("20. export the page as a PDF")
	Local $sPdf = @TempDir & "\wv2_page_" & @AutoItPID & ".pdf"
	__Check(_WV2_PrintToPdf($g_iWV, $sPdf) = 1, _WV2_GetLastErrorMessage())
	Local $bPdf = __ReadBin($sPdf)
	; The end marker is looked for in the last bytes only: a PDF holds binary streams, and a binary is
	; only decoded up to the first zero byte.
	__Check(BinaryLen($bPdf) > 1000 And BinaryMid($bPdf, 1, 5) = Binary("0x255044462D") And _
			StringInStr(BinaryToString(BinaryMid($bPdf, BinaryLen($bPdf) - 15, 16)), "%%EOF") > 0, _
			"pdf of " & BinaryLen($bPdf) & " bytes, printed by the runtime")
	FileDelete($sPdf)
	__Check(_WV2_PrintToPdf($g_iWV, "") = 0 And @error = $WV2_ERR_ARG)
	__Check(_WV2_PrintToPdf($g_iWV, "Z:\no\such\folder\page.pdf") = 0 And @error = $WV2_ERR_FILE, "target checked before the call")
	__Check(_WV2_PrintToPdf(99, $sPdf) = 0 And @error = $WV2_ERR_HANDLE)

	__Say("21. downloads raised by the page")
	Local $sDlDir = @TempDir & "\wv2_dl_" & @AutoItPID
	DirRemove($sDlDir, 1)
	DirCreate($sDlDir)
	Local $sDlPage = @TempDir & "\wv2_dlpage_" & @AutoItPID & ".html"
	Local $hDl = FileOpen($sDlPage, 2)
	FileWrite($hDl, __DownloadPage())
	FileClose($hDl)
	Local $sDlUrl = "file:///" & StringReplace($sDlPage, "\", "/")
	; The folder belongs to the host: a page cannot write into the Downloads folder of the user.
	__Check(_WV2_SetDownloadFolder($g_iWV, $sDlDir) = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_Navigate($g_iWV, $sDlUrl) = 1, _WV2_GetLastErrorMessage())
	__WaitOk(15000)
	__Check(_WV2_ExecuteScript($g_iWV, "go(1)", $sOut) = 1 And $sOut = "1", _WV2_GetLastErrorMessage())
	Local $sDlTxt = $sDlDir & "\wv2-payload.txt"
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_DOWNLOAD_STARTING, 15000, $sData, $iValue) = 1 And $iValue = 0, _
			"the host let this download through [" & $sData & "]")
	; The file is written a moment after the event, so the folder is polled for it.
	__Check(__WaitFile($sDlTxt, 15000), "the file landed in the folder chosen by the host")
	Local $sBody = FileRead($sDlTxt)
	__Check($sBody = "payload 1 end", "content [" & $sBody & "]")

	; The refused download needs a page of its own: the runtime only allows the first automatic
	; download of a page, so this one is a fresh load of the same file.
	__Check(_WV2_SetDownloadFilter($g_iWV, "^blob:") = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_Navigate($g_iWV, $sDlUrl) = 1, _WV2_GetLastErrorMessage())
	__WaitOk(15000)
	__Check(_WV2_ExecuteScript($g_iWV, "go(2)", $sOut) = 1 And $sOut = "1", _WV2_GetLastErrorMessage())
	__Check(_WV2_WaitEvent($g_iWV, $WV2_EVENT_DOWNLOAD_STARTING, 15000, $sData, $iValue) = 1 And $iValue = 1, _
			"the filter refused this download [" & $sData & "]")
	__Check(__CountFiles($sDlDir) = 1, "a refused download leaves nothing on disk, files " & __CountFiles($sDlDir))
	__Check(_WV2_SetDownloadFolder($g_iWV, "Z:\no\such\folder") = 0 And @error = $WV2_ERR_ARG, "an unknown folder is refused")
	__Check(_WV2_SetDownloadFilter($g_iWV, "") = 1)
	__Check(_WV2_EnableEvent($g_iWV, $WV2_EVENT_DOWNLOAD_STARTING, False) = 1, _WV2_GetLastErrorMessage())
	DirRemove($sDlDir, 1)
	FileDelete($sDlPage)

	__Say("22. clear the cookies of the profile")
	; Neither a file:// nor a NavigateToString page can hold a cookie, so this self test has no cookie
	; to watch disappear without a real site. What it checks is the interface chain itself, which
	; answers 1 only when the profile carried out the call.
	__Check(_WV2_ClearCookies($g_iWV) = 1, _WV2_GetLastErrorMessage())
	__Check(_WV2_ClearCookies(99) = 0 And @error = $WV2_ERR_HANDLE)

	__Say("23. destroy")
	__Check(_WV2_Destroy($g_iWV) = 1)
	__Check(_WV2_IsReady($g_iWV) = 0)
	__Check(_WV2_Destroy($g_iWV) = 0 And @error = $WV2_ERR_HANDLE)
	__Check(_WV2_ExecuteScript($g_iWV, "1", $sOut) = 0 And @error = $WV2_ERR_HANDLE)
	$g_iWV = 0

	__Say("24. a second view after destroy")
	$g_iWV = _WV2_Create($g_hMain, 0, 0, 400, 300)
	__Check($g_iWV > 0, _WV2_GetLastErrorMessage())
	If $g_iWV > 0 Then
		_WV2_NavigateToString($g_iWV, __Page("WV2 SECOND VIEW"))
		__WaitOk(15000)
		_WV2_GetTitle($g_iWV, $sT)
		__Check($sT = "WV2 SECOND VIEW", "title [" & $sT & "]")
		__Check(_WV2_SettingRead($g_iWV, "IsScriptEnabled") = 1, "settings work on the second view too")
		__Check(_WV2_Destroy($g_iWV) = 1)
		$g_iWV = 0
	EndIf

	FileDelete($sFile)
	__Finish()
EndFunc   ;==>__AutoTest

Func __Page($sTitle)
	Return '<html><head><title>' & $sTitle & '</title></head><body style="font:16px Segoe UI;margin:24px">' & _
			'<h2>' & $sTitle & '</h2><p>Rendered by the Microsoft Edge WebView2 runtime, driven by pure AutoIt.</p>' & _
			'<p id="t"></p><script>document.getElementById("t").textContent="JavaScript works: " + new Date().toLocaleTimeString();</script>' & _
			'</body></html>'
EndFunc   ;==>__Page

; The page used by the message tests: it talks to the host as soon as it is ready and answers back
; with whatever the host sends it, which is what makes the round trip verifiable from AutoIt.
Func __BridgePage()
	Return '<html><head><title>WV2 BRIDGE</title></head><body style="font:16px Segoe UI;margin:24px">' & _
			'<h2>Bridge between AutoIt and JavaScript</h2><p id="log">waiting for the host...</p>' & _
			'<script>' & _
			'window.__last = ""; window.__lastJson = "";' & _
			'function note(s){ document.getElementById("log").textContent = s; }' & _
			'window.chrome.webview.addEventListener("message", function(e) {' & _
			'  var d = e.data;' & _
			'  if (d === "host ping") { window.__last = d; note("host asked for a ping"); window.chrome.webview.postMessage("host ping heard"); }' & _
			'  else if (d && d.cmd) { window.__lastJson = d.cmd + ":" + d.n; note("host sent JSON " + window.__lastJson); }' & _
			'  else { window.__last = String(d); note("host said " + window.__last); }' & _
			'});' & _
			'window.chrome.webview.postMessage("page says hello");' & _
			'</script></body></html>'
EndFunc   ;==>__BridgePage

; The page used by the download tests: go(n) hands the host a small file built in memory, which is
; what a page does when it offers a generated document for download.
Func __DownloadPage()
	Return '<html><head><title>WV2 DOWNLOAD</title></head><body style="font:16px Segoe UI;margin:24px">' & _
			'<h2>A page that starts a download</h2>' & _
			'<a id="d" download="wv2-payload.txt">download</a><script>' & _
			'window.go=function(n){' & _
			'var b=new Blob(["payload " + n + " end"],{type:"text/plain"});' & _
			'var a=document.getElementById("d");' & _
			'a.download="wv2-payload.txt";a.href=URL.createObjectURL(b);a.click();return 1;};' & _
			'</script></body></html>'
EndFunc   ;==>__DownloadPage

; Waits until a file exists, which is how a finished download is seen: the runtime writes it some
; time after it announced it.
Func __WaitFile($sPath, $iMs)
	Local $i = 0
	For $i = 0 To Int($iMs / 100)
		If FileExists($sPath) Then Return True
		Sleep(100)
	Next
	Return FileExists($sPath)
EndFunc   ;==>__WaitFile

Func __CountFiles($sDir)
	Local $i = 0
	Local $h = FileFindFirstFile($sDir & "\*")
	If $h = -1 Then Return 0
	While 1
		; Only @Error and @Extended are read here: @Extended 1 means the entry is a folder.
		FileFindNextFile($h)
		If @Error Then ExitLoop
		If @Extended <> 1 Then $i += 1
	WEnd
	FileClose($h)
	Return $i
EndFunc   ;==>__CountFiles

; One navigation wait, checked for both the completion and a web level error.
Func __WaitOk($iMs)
	Local $b = _WV2_WaitNavigation($g_iWV, $iMs)
	Local $iWebErr = @extended
	If $b = 0 Then
		__Check(False, "wait failed: " & _WV2_GetLastErrorMessage())
	Else
		__Check($iWebErr = 0, $iWebErr = 0 ? "navigation complete" : "web error " & $iWebErr)
	EndIf
EndFunc   ;==>__WaitOk

; Reads a whole file as binary. FileOpen with flag 16 is the only byte exact way to do it.
Func __ReadBin($sPath)
	Local $h = FileOpen($sPath, 16)
	If $h = -1 Then Return Binary("")
	Local $b = FileRead($h)
	FileClose($h)
	Return $b
EndFunc   ;==>__ReadBin

Func __Check($b, $sExtra = "")
	If $b Then
		$g_iOk += 1
		ConsoleWrite("  OK   " & $sExtra & @CRLF)
	Else
		$g_iKo += 1
		ConsoleWrite("  FAIL " & $sExtra & @CRLF)
	EndIf
EndFunc   ;==>__Check

Func __Say($s)
	ConsoleWrite($s & @CRLF)
EndFunc   ;==>__Say

Func __Finish()
	ConsoleWrite("passed=" & $g_iOk & " failed=" & $g_iKo & @CRLF)
	If $g_iWV <> 0 Then _WV2_Destroy($g_iWV)
	Exit($g_iKo = 0 ? 0 : 1)
EndFunc   ;==>__Finish
