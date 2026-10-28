; ------------------------------------------------------------------------------
;  Quick start content: cover, contents, six chapters.
;  Included by build_tutorial.au3; uses the layout helpers of that builder.
; ------------------------------------------------------------------------------

; ================================================================== samples
Func _T_SamplePath($sFile)
	Return @ScriptDir & "\samples\" & $sFile
EndFunc

Func _T_CodeFile($sFile)
	Local $hFile = FileOpen(_T_SamplePath($sFile), 0)
	If $hFile = -1 Then
		ConsoleWrite("! missing sample: " & _T_SamplePath($sFile) & @CRLF)
		Exit 1
	EndIf
	Local $sCode = StringStripWS(FileRead($hFile), 2)
	FileClose($hFile)
	_G_Code($sCode)
EndFunc

; ================================================================== cover
Func _T_Cover()
	Local $fPanel = 372
	Local $fRightX = 388
	Local $fRightW = $g_X + $g_W - $fRightX
	Local $i

	_PDFX_SetFill($g_Doc, $G_PAPER)
	_PDFX_Rect($g_Doc, 0, 0, $g_PageW, $g_PageH, $PDFX_FILL)

	; left terracotta panel with a faint 24 pt grid
	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_Rect($g_Doc, 0, 0, $fPanel, $g_PageH, $PDFX_FILL)
	_PDFX_SetAlpha($g_Doc, 0.33, 0.33)
	_PDFX_SetStroke($g_Doc, 0x6E2F10)
	_PDFX_SetLineWidth($g_Doc, 0.4)
	For $i = 24 To $fPanel - 1 Step 24
		_PDFX_Line($g_Doc, $i, 0, $i, $g_PageH)
	Next
	For $i = 24 To $g_PageH - 1 Step 24
		_PDFX_Line($g_Doc, 0, $i, $fPanel, $i)
	Next
	_PDFX_SetAlpha($g_Doc, 1, 1)

	; masthead
	_PDFX_SetFill($g_Doc, 0xF6E2C2)
	_PDFX_RoundRect($g_Doc, 48, 54, 26, 26, 6, $PDFX_FILL)
	_G_TextCentre(48, 59.5, 26, "W", 13, $G_TERRA_D, "Helvetica", "B")
	_G_Tracked(82, 63, "WEBVIEW2", 10, 0xFFF6E6, "Helvetica", "B", 1.8)

	_G_Tracked(48, 118, "AUTOIT UDF  -  QUICK START", 7.6, 0xF2CFA2, "Helvetica", "B", 1.9)

	_G_Text(48, 144, "WebView2", 50, 0x35190A, "Helvetica", "B")
	_G_Text(48, 198, "in ten minutes", 34, 0xFBE9CA, "Helvetica", "B")

	_PDFX_SetStroke($g_Doc, 0xF0C795)
	_PDFX_SetLineWidth($g_Doc, 1.2)
	_PDFX_Line($g_Doc, 48, 252, 138, 252)

	_G_Para(48, 268, 276, "From an empty script to a browser you can drive: four short programs, " & _
			"every line commented, nothing to install and nothing to download.", 10.4, 14.6, 0xF7E0BE)

	; chips
	_G_Chip(48, 332, "AutoIt 3.3.16+")
	_G_Chip(48 + _G_ChipWidth("AutoIt 3.3.16+") + 8, 332, "No installer")
	_G_Chip(48, 356, "No network")
	_G_Chip(48 + _G_ChipWidth("No network") + 8, 356, "4 programs")
	_G_Chip(48 + _G_ChipWidth("No network") + _G_ChipWidth("4 programs") + 16, 356, "40 functions")

	; code card
	_PDFX_SetFill($g_Doc, 0x2E2116)
	_PDFX_RoundRect($g_Doc, 48, 392, 276, 150, 7, $PDFX_FILL)
	Local $aCode[14] = [ _
			'#include <GUIConstantsEx.au3>', _
			'#include "WebView2.au3"', _
			'', _
			'Local $hGui  = GUICreate("Window", 900, 620)', _
			'GUISetState(@SW_SHOW, $hGui)', _
			'', _
			'Local $hView = _WV2_Create($hGui, 0, 0, -1, -1)', _
			'_WV2_NavigateToString($hView, "<h1>Hello</h1>")', _
			'', _
			'While GUIGetMsg() <> $GUI_EVENT_CLOSE', _
			'WEnd', _
			'', _
			'_WV2_Destroy($hView)', _
			'GUIDelete($hGui)']
	_PDFX_SetFont($g_Doc, "Courier", 7)
	_PDFX_SetFill($g_Doc, 0xF1E2C9)
	For $i = 0 To 13
		_PDFX_Text($g_Doc, 60, 402 + $i * 9.4, $aCode[$i], 7)
	Next

	_G_Text(48, 558, "One include. That is the whole setup.", 9.4, 0xFBE9CA, "Helvetica", "I")
	_G_Tracked(48, 574, "THE WHOLE DEPENDENCY LIST", 6.6, 0xE8BA8C, "Helvetica", "B", 1.4)

	; left footer metadata
	_PDFX_SetStroke($g_Doc, 0xD89A6B)
	_PDFX_SetLineWidth($g_Doc, 0.6)
	_PDFX_Line($g_Doc, 48, 720, 324, 720)
	_G_Tracked(48, 734, "VERSION", 6.4, 0xE8BA8C, "Helvetica", "B", 1.2)
	_G_Text(48, 746, "0.3.0", 9.2, 0xFFF6E6, "Helvetica", "B")
	_G_Tracked(140, 734, "RUNTIME", 6.4, 0xE8BA8C, "Helvetica", "B", 1.2)
	_G_Text(140, 746, "AutoIt 3.3.16+", 9.2, 0xFFF6E6, "Helvetica", "B")
	_G_Tracked(244, 734, "LICENCE", 6.4, 0xE8BA8C, "Helvetica", "B", 1.2)
	_G_Text(244, 746, "MIT", 9.2, 0xFFF6E6, "Helvetica", "B")

	; ---------------------------------------------------------------- right column
	_G_Tracked($fRightX, 62, "WHAT YOU NEED", 7, $G_TERRA, "Helvetica", "B", 1.3)

	_G_Box($fRightX, 80, $fRightW, 44, "Windows 10 or 11", "WebView2 runtime included", $G_WHITE, $G_RULE)
	_G_TriDown($fRightX + $fRightW / 2, 127)
	_G_Box($fRightX, 136, $fRightW, 44, "AutoIt 3.3.16+", "x86 and x64 supported", $G_WHITE, $G_RULE)
	_G_TriDown($fRightX + $fRightW / 2, 183)
	_G_Box($fRightX, 192, $fRightW, 44, "WebView2.au3", "next to your script", $G_WHITE, $G_RULE)

	_G_Tracked($fRightX, 274, "BY THE NUMBERS", 7, $G_TERRA, "Helvetica", "B", 1.3)
	Local $aNum[5][2] = [ _
			["public functions", "40"], _
			["complete programs", "4"], _
			["installers to run", "0"], _
			["network calls", "0"], _
			["files to register", "0"]]
	For $i = 0 To 4
		Local $fRowY = 290 + $i * 21
		_G_Text($fRightX, $fRowY + 3, $aNum[$i][0], 7.8, $G_MUTED)
		_G_TextAlignRight($fRightX + $fRightW, $fRowY, $aNum[$i][1], 10.6, $G_TERRA, "Helvetica", "B")
		_G_Rule($fRowY + 16, 0xEADCC6, 0.45, $fRightX, $fRightX + $fRightW)
	Next

	_G_Para($fRightX, 396, $fRightW, "Every program in this booklet was run before it was printed: " & _
			"local pages only, no network, no leftover file.", 8.2, 12, 0x6A5A48, "I")

	; the four programs, in reading order
	_G_Tracked($fRightX, 462, "THE FOUR PROGRAMS", 7, $G_TERRA, "Helvetica", "B", 1.3)
	Local $aProg[4][2] = [ _
			["01", "Your first window|hello from the engine"], _
			["02", "Events and messages|the page and the host talk"], _
			["03", "Your own content|JavaScript answers"], _
			["04", "Fitting the window|a toolbar that follows"]]
	For $i = 0 To 3
		Local $fPY = 480 + $i * 30
		Local $aProgText = StringSplit($aProg[$i][1], "|", 2)
		_G_Text($fRightX, $fPY + 1, $aProg[$i][0], 7.2, $G_TERRA, "Courier", "B")
		_G_Text($fRightX + 22, $fPY, $aProgText[0], 8.2, $G_INK, "Helvetica", "B")
		_G_Text($fRightX + 22, $fPY + 11, $aProgText[1], 7.2, $G_MUTED)
	Next

	; colophon
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.6)
	_PDFX_Line($g_Doc, $fRightX, 640, $fRightX + $fRightW, 640)
	_G_Tracked($fRightX, 652, "COLOPHON", 6.6, $G_TERRA, "Helvetica", "B", 1.3)
	_G_Para($fRightX, 666, $fRightW, "Typeset with PDFX 1.4.0, the author's other UDF.", 7.8, 11, $G_BODY)
	_G_Text($fRightX, 692, "PDFX - forum topic 213930", 7.4, $G_TERRA_D, "Helvetica", "B")
	_PDFX_Link($g_Doc, $fRightX, 691, $fRightW, 11, $G_URL_PDFX)
	_G_Text($fRightX, 708, "Numeric1 - forum profile 118605", 7.4, $G_TERRA_D, "Helvetica", "B")
	_PDFX_Link($g_Doc, $fRightX, 707, $fRightW, 11, $G_URL_PROFILE)
	_G_Text($fRightX, 770, "Version 0.3.0  -  October 2026", 7, $G_MUTED)

	_PDFX_AddBookmark($g_Doc, "Cover", 0, 1, 0)
	$g_Y = $g_Bottom
EndFunc

; ================================================================== contents
Func _T_Toc()
	_PDFX_AddPage($g_Doc)
	$g_Section = "CONTENTS"
	_G_Chrome()
	$g_Y = 74

	_G_Tracked($g_X, $g_Y, "HOW TO USE THIS BOOKLET", 7.2, $G_TERRA, "Helvetica", "B", 1.8)
	_G_Text($g_X, 88, "Start here", 29, $G_INK, "Helvetica", "B")
	$g_Y = 122
	_G_P("Six chapters. The first one is already a working program; the next five add one idea at a time.", 9.6, 14, 0x5B4C3D)
	$g_Y = 146

	; left: chapter list
	Local $fListTop = 158
	Local $fStep = 48
	Local $iEntry, $iPage, $j
	For $iEntry = 1 To 6
		Local $fY = $fListTop + ($iEntry - 1) * $fStep
		$iPage = $g_PageNo[$iEntry]
		Local $sPage = "--"
		If $iPage > 0 Then $sPage = StringFormat("%02d", $iPage)

		_G_Text($g_X, $fY + 2, $g_Titles[$iEntry - 1][0], 8.4, $G_TERRA, "Courier", "B")
		_G_Text($g_X + 24, $fY, $g_Titles[$iEntry - 1][1], 10.2, $G_INK, "Helvetica", "B")
		Local $fNameW = _G_W($g_Titles[$iEntry - 1][1], 10.2, "Helvetica", "B")

		_PDFX_SetDash($g_Doc, 0.8, 2.2)
		Local $fLeader = $g_X + 26 + $fNameW
		If $fLeader < $g_X + 218 Then _G_Rule($fY + 7, 0xCBB89C, 0.55, $fLeader, $g_X + 222)
		_PDFX_SetDash($g_Doc, 0)

		_G_TextAlignRight($g_X + 238, $fY + 1, $sPage, 9.4, $G_TERRA, "Helvetica", "B")
		If $iPage > 0 Then
			_PDFX_LinkPage($g_Doc, $g_X - 2, $fY - 3, 240, 13, $iPage, $g_ChapterY[$iEntry])
		EndIf
	Next

	_G_Text($g_X, 442, "Every entry is clickable; every heading is also a bookmark.", 7.8, $G_MUTED, "Helvetica", "I")

	; what must be on disk first
	_G_Tracked($g_X, 470, "BEFORE YOU TYPE", 6.8, $G_TERRA, "Helvetica", "B", 1.4)
	Local $aNeed[3][2] = [ _
			["01", "Windows 10 or 11, with the WebView2 runtime - it is already there."], _
			["02", "AutoIt 3.3.16 or later - AutoIt3.exe and AutoIt3_x64.exe both work."], _
			["03", "WebView2.au3 next to your script - nothing to register."]]
	Local $fNY = 486
	For $iEntry = 0 To 2
		_G_Text($g_X, $fNY + 1, $aNeed[$iEntry][0], 7.2, $G_TERRA, "Courier", "B")
		Local $aNeedLines = _G_Wrap($aNeed[$iEntry][1], 238, 238, 8.4)
		For $j = 0 To UBound($aNeedLines) - 1
			_G_Text($g_X + 24, $fNY + $j * 11, $aNeedLines[$j], 8.4, $G_BODY)
		Next
		$fNY += UBound($aNeedLines) * 11 + 8
	Next

	; right column
	Local $fCX = 318
	Local $fCW = 229
	Local $fRY = $fListTop
	Local $i

	Local $aLines = _G_Wrap("Four complete programs. The snippets between them are pieces " & _
			"of those programs, not separate files.", $fCW - 28, $fCW - 28, 8.2)
	Local $fCardH = 38 + UBound($aLines) * 11.4
	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_RoundRect($g_Doc, $fCX, $fRY, $fCW, $fCardH, 7, $PDFX_FILL)
	_G_Tracked($fCX + 14, $fRY + 12, "THE SHAPE OF IT", 6.6, $G_TERRA_D, "Helvetica", "B", 1.2)
	_PDFX_SetFont($g_Doc, "Helvetica", 8.2)
	_PDFX_SetFill($g_Doc, 0x4C4236)
	For $i = 0 To UBound($aLines) - 1
		_PDFX_Text($g_Doc, $fCX + 14, $fRY + 30 + $i * 11.4, $aLines[$i], 8.2)
	Next
	$fRY += $fCardH + 14

	Local $aTiles[4][2] = [ _
			["40", "PUBLIC FUNCTIONS|one include"], _
			["4", "RUNNABLE PROGRAMS|commented"], _
			["0", "FILES TO REGISTER|nothing to install"], _
			["6", "CHAPTERS|in reading order"]]
	For $i = 0 To 3
		Local $fTX = $fCX + Mod($i, 2) * 118
		Local $fTY = $fRY + Int($i / 2) * 64
		_PDFX_SetFill($g_Doc, $G_WHITE)
		_PDFX_SetStroke($g_Doc, $G_RULE)
		_PDFX_SetLineWidth($g_Doc, 0.6)
		_PDFX_RoundRect($g_Doc, $fTX, $fTY, 111, 56, 6, $PDFX_BOTH)
		_G_Text($fTX + 10, $fTY + 8, $aTiles[$i][0], 19, $G_TERRA, "Helvetica", "B")
		Local $aTileText = StringSplit($aTiles[$i][1], "|", 2)
		_G_Tracked($fTX + 10, $fTY + 33, $aTileText[0], 5.8, $G_INK, "Helvetica", "B", 0.8)
		_G_Text($fTX + 10, $fTY + 42, $aTileText[1], 6.4, $G_MUTED)
	Next
	$fRY += 128 + 16

	_PDFX_SetFill($g_Doc, $G_PANEL)
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.6)
	_PDFX_RoundRect($g_Doc, $fCX, $fRY, $fCW, 90, 7, $PDFX_BOTH)
	_G_Tracked($fCX + 14, $fRY + 12, "READING PATHS", 6.6, $G_TERRA, "Helvetica", "B", 1.2)
	Local $aPaths[3][2] = [["First contact", "01"], _
			["A real application", "01 - 02 - 04"], _
			["Look something up", "05 - 06"]]
	For $i = 0 To 2
		_G_Text($fCX + 14, $fRY + 30 + $i * 18, $aPaths[$i][0], 7.8, $G_BODY)
		_G_TextAlignRight($fCX + $fCW - 14, $fRY + 30 + $i * 18, $aPaths[$i][1], 7.2, $G_TERRA, "Courier", "")
	Next
	$fRY += 90 + 18

	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_Rect($g_Doc, $fCX, $fRY + 2, 3.4, 3.4, $PDFX_FILL)
	_G_Text($fCX + 10, $fRY, "What this is not", 9, $G_INK, "Helvetica", "B")
	Local $aLines2 = _G_Wrap("Not the API reference. The 40 functions carry their own #FUNCTION# " & _
			"headers, and the Developer Guide explains the machinery under them.", $fCW, $fCW, 7.8)
	_PDFX_SetFont($g_Doc, "Helvetica", 7.8)
	_PDFX_SetFill($g_Doc, $G_BODY)
	For $i = 0 To UBound($aLines2) - 1
		_PDFX_Text($g_Doc, $fCX, $fRY + 15 + $i * 10.8, $aLines2[$i], 7.8)
	Next

	; three habits strip
	_PDFX_SetFill($g_Doc, $G_WHITE)
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $g_X, 596, $g_W, 96, 8, $PDFX_BOTH)
	_G_Tracked($g_X + 16, 610, "THREE HABITS", 6.6, $G_TERRA, "Helvetica", "B", 1.3)
	_G_Text($g_X + 106, 607, "that avoid most beginner problems", 10, $G_INK, "Helvetica", "B")

	Local $aHabits[3][2] = [ _
			["Keep a band free|The browser is a child window and covers controls under it."], _
			["Drain the queue|Call _WV2_GetEvent on every pass of the loop."], _
			["Destroy the view first|_WV2_Destroy before GUIDelete, on the same thread."]]
	Local $k
	For $i = 0 To 2
		Local $fHX = $g_X + 16 + $i * 158
		_PDFX_SetFill($g_Doc, $G_SAND)
		_PDFX_Circle($g_Doc, $fHX + 7, 638, 7, $PDFX_FILL)
		_G_TextCentre($fHX, 634.8, 14, String($i + 1), 7.2, $G_TERRA_D, "Helvetica", "B")
		Local $aHabit = StringSplit($aHabits[$i][0], "|", 2)
		_G_Text($fHX + 20, 631, $aHabit[0], 7.8, $G_INK, "Helvetica", "B")
		Local $aHabitLines = _G_Wrap($aHabit[1], 140, 140, 7.2)
		_PDFX_SetFont($g_Doc, "Helvetica", 7.2)
		_PDFX_SetFill($g_Doc, $G_BODY)
		For $k = 0 To UBound($aHabitLines) - 1
			_PDFX_Text($g_Doc, $fHX + 20, 643 + $k * 9.6, $aHabitLines[$k], 7.2)
		Next
	Next

	_PDFX_AddBookmark($g_Doc, "Contents", 0, 2, 74)
	$g_Y = $g_Bottom
EndFunc

; ================================================================== chapter 01
Func _T_Ch01()
	_G_Chapter("01", "YOUR FIRST WINDOW", "FROM ZERO TO A PAGE", "Your first window", _
			"One include, one window, one page. The program is complete: type it, run it, and you have a browser.")

	_G_P("A WebView2 view is a child window inside a normal AutoIt GUI. There is no ActiveX control " & _
			"and no file to register: the UDF builds the browser through the runtime Windows already " & _
			"carries, so the whole installation is one step - put WebView2.au3 next to your script.")

	_G_H2("What you need")
	Local $aNeed[3] = [ _
			"Windows 10 or 11.|The WebView2 runtime comes with Microsoft Edge and is present on any maintained machine. If it is ever missing, _WV2_Create returns 0 with @error = $WV2_ERR_RUNTIME (3); nothing is downloaded.", _
			"AutoIt 3.3.16 or later.|Both AutoIt3.exe and AutoIt3_x64.exe work. The programs in this booklet were checked on 3.3.16.1, x86.", _
			"WebView2.au3.|One file, next to your script. The example and the self test in the package are optional."]
	_G_Bullets($aNeed)

	_G_FigCard(118)
	Local $t = $g_FigTop
	_G_Box($g_X + 12, $t + 32, 138, 42, "MyScript.au3", "your code", $G_SAND, $G_SAND_D)
	_G_ArrowR($g_X + 154, $t + 53, $g_X + 176)
	_G_Box($g_X + 180, $t + 32, 138, 42, "WebView2.au3", "the UDF", $G_SAND, $G_SAND_D)
	_G_ArrowR($g_X + 322, $t + 53, $g_X + 344)
	_G_Box($g_X + 348, $t + 32, 138, 42, "WebView2 runtime", "part of Windows", $G_SAND, $G_SAND_D)
	_G_Text($g_X + 12, $t + 82, "calls the UDF", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 180, $t + 82, "calls the engine", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 348, $t + 82, "draws the page", 7, $G_MUTED, "Helvetica", "I")
	_G_FigCaption("Only the left box is yours. The UDF holds the COM plumbing; the engine is the part of Windows that renders the page.")

	_G_H2("The program")
	_G_P("Six numbered comments divide it. Nothing is hidden: this is the whole file, comments included.")
	_T_CodeFile("01_first_window.au3")

	_G_H2("What just happened")
	Local $aCols[2][2] = [["CALL", 2.4], ["WHAT IT DOES", 5.6]]
	Local $aRows[4][2] = [ _
			["_WV2_Create", "Returns a handle, 1 to 16. Every other call takes it first."], _
			["-1, -1", "Takes the rest of the client area from $iLeft, $iTop."], _
			["_WV2_WaitNavigation", "Waits and pumps messages; @extended is 0 or the web error."], _
			["_WV2_Destroy", "Releases the engine before GUIDelete, on the same thread."]]
	_G_Table($aCols, $aRows, 8.0, True)
EndFunc

; ================================================================== chapter 02
Func _T_Ch02()
	_G_Chapter("02", "EVENTS AND MESSAGES", "TWO DIRECTIONS, ONE QUEUE", "Events and messages", _
			"The page talks, AutoIt listens. AutoIt talks, the page listens. Neither side blocks.")

	_G_P("WebView2 never calls your script directly. It queues events, and your GUI loop reads that " & _
			"queue. The design keeps a slow handler from stalling the engine, but it also means the " & _
			"loop has to drain the queue on every pass.")

	_G_H2("The bridge, both ways")
	_G_P("In the page, the bridge is one object: chrome.webview. A script calls postMessage to send " & _
			"to AutoIt, and listens to the message event to receive.")
	_G_Code('// page -> AutoIt' & @LF & _
			'chrome.webview.postMessage("hello from the page");' & @LF & _
			'' & @LF & _
			'// AutoIt -> page' & @LF & _
			'chrome.webview.addEventListener("message", function (e) {' & @LF & _
			'    document.getElementById("out").textContent = e.data;' & @LF & _
			'})')
	_G_P("On the AutoIt side, both directions are single calls. A plain string is easier on both " & _
			"ends; JSON is there when a structure has to cross.")
	_G_Code('_WV2_EnableEvent($hView, $WV2_EVENT_WEB_MESSAGE)   ; before loading' & @LF & _
			'_WV2_PostWebMessageAsString($hView, "ping")        ; AutoIt -> page' & @LF & _
			'_WV2_PostWebMessage($hView, "{""x"": 1}")           ; JSON text')
	_G_P("Only NAVIGATION_COMPLETED is enabled by _WV2_Create. Every other event stays off until " & _
			"_WV2_EnableEvent, and enabling twice is harmless.")

	_G_H2("The event queue")
	_G_P("One call takes the oldest event and fills two variables. The table says what they hold.")
	Local $aCols[4][2] = [["CONSTANT", 3.2], ["$sData", 1.7], ["$iValue", 2.0], ["ON BY DEFAULT", 1.5]]
	Local $aRows[8][4] = [ _
			["$WV2_EVENT_NAVIGATION_STARTING", "the URI", "1 if the user started it", "no"], _
			["$WV2_EVENT_NAVIGATION_COMPLETED", "the URI", "1 on success, else the web error", "yes"], _
			["$WV2_EVENT_WEB_MESSAGE", "the message", "1 plain string, 0 JSON", "no"], _
			["$WV2_EVENT_TITLE_CHANGED", "the new title", "nothing", "no"], _
			["$WV2_EVENT_HISTORY_CHANGED", "nothing", "nothing", "no"], _
			["$WV2_EVENT_NEW_WINDOW", "the URI", "nothing", "no"], _
			["$WV2_EVENT_PROCESS_FAILED", "nothing", "$WV2_PROCFAIL_* 0 to 9", "no"], _
			["$WV2_EVENT_DOWNLOAD_STARTING", "the URI", "1 refused, 0 accepted", "no"]]
	_G_Table($aCols, $aRows, 8.0, True)

	_G_Note("Queue size", "Each view keeps 64 events. When the queue overflows the oldest is " & _
			"dropped, and _WV2_GetEvent reports how many were lost in @extended. Draining it on " & _
			"every pass is cheaper than sizing it.", "note")

	_G_Code('While 1' & @LF & _
			'    Switch GUIGetMsg()' & @LF & _
			'        Case $GUI_EVENT_CLOSE' & @LF & _
			'            ExitLoop' & @LF & _
			'        Case $idPing' & @LF & _
			'            _WV2_PostWebMessageAsString($hView, "ping")' & @LF & _
			'    EndSwitch' & @LF & _
			'' & @LF & _
			'    Local $sData = "", $iValue = 0' & @LF & _
			'    While 1' & @LF & _
			'        Local $iEvent = _WV2_GetEvent($hView, $sData, $iValue)' & @LF & _
			'        If $iEvent <= 0 Then ExitLoop   ; 0 = empty, -1 = bad handle' & @LF & _
			'        ; ... use $iEvent, $sData and $iValue here ...' & @LF & _
			'    WEnd' & @LF & _
			'WEnd')
	_G_P("_WV2_WaitEvent is the opposite: it pumps until one event of the type you name arrives, " & _
			"leaving the others in the queue. It is handy right after a navigation.")

	_G_H2("The program")
	_T_CodeFile("02_events.au3")
	_G_P("Click Send a message to AutoIt and the label updates; click Ping the page and the page " & _
			"text changes. The window title follows the page title, because TITLE_CHANGED is enabled.")

	_G_Note("The browser covers your controls", "A view is a real child window, drawn above the GUI. " & _
			"The 40 pixels kept at the bottom of this program are not decoration: any AutoIt control " & _
			"placed under the view would be invisible and unclickable. Chapter 4 builds a toolbar in " & _
			"that band.", "warn")
EndFunc

; ================================================================== chapter 03
Func _T_Ch03()
	_G_Chapter("03", "YOUR OWN CONTENT", "HTML FROM A STRING", "Your own content", _
			"No server and no temporary file: the page travels inside the script, and JavaScript answers questions.")

	_G_P("_WV2_NavigateToString displays HTML you already hold. The UDF hands it to the engine as a " & _
			"data: URI, so scripts, styles and the message bridge all work. A file on disk works the " & _
			"same way, through a file:/// URL. One consequence matters: _WV2_GetSource returns the " & _
			"data: URI, not your original text, so keep the HTML in a variable or a file.")

	_G_H2("Ask the page a question")
	_G_P("_WV2_ExecuteScript runs JavaScript in the page and returns the value of the last expression " & _
			"as JSON text. The table below is the whole encoding for the types a beginner meets.")
	Local $aCols[3][2] = [["EXPRESSION", 3.0], ["$sResult", 2.4], ["WHY", 3.8]]
	Local $aRows[4][3] = [ _
			["2 + 2", "4", "a number is bare"], _
			["document.title", """My page""", "a string keeps its quotes"], _
			["({ answer: 42 })", "{""answer"":42}", "an object becomes JSON"], _
			["throw new Error()", "null", "a throw is not a failure"]]
	_G_Table($aCols, $aRows, 8.3)
	_G_P("Read $sResult as text. A number can be compared directly; a string arrives quoted; null " & _
			"means either a throw or no value. When a script can fail, return something you can test - " & _
			"Number(...) and String(...) make the type explicit, as the program below does.")
	_G_P("One script runs at a time per view, and the call pumps Windows messages while it waits. " & _
			"The timeout defaults to $WV2_EXEC_TIMEOUT, five seconds.")

	_G_H2("Before the page runs")
	_G_P("_WV2_AddScriptToExecuteOnDocumentCreated installs JavaScript that runs at the start of every " & _
			"document loaded afterwards, before the page's own code. That is where a helper object belongs.")
	_G_Code('Local $sId = ""' & @LF & _
			'_WV2_AddScriptToExecuteOnDocumentCreated($hView, _' & @LF & _
			'        "window.host = { version: ''0.3'', ping: function () { return ''pong''; } };", $sId)' & @LF & _
			'' & @LF & _
			'; later, when it is no longer wanted:' & @LF & _
			'_WV2_RemoveScriptToExecuteOnDocumentCreated($hView, $sId)')
	_G_P("Pages already loaded keep the script; removal only affects the next documents. The " & _
			"program below changes the two numbers in the page and presses Read the result: the label " & _
			"shows what Number(...) returned, not a quoted string.")

	; The listing is a full page: give it one, heading included.
	_G_NewPage()
	_G_H2("The program")
	_T_CodeFile("03_own_content.au3")
EndFunc

; ================================================================== chapter 04
Func _T_Ch04()
	_G_Chapter("04", "GEOMETRY", "BOUNDS, RESIZE, ZOOM", "Fitting the window", _
			"The browser is a child window with its own rectangle. Place it once, then keep it in step.")

	_G_P("_WV2_Create places the view at a fixed rectangle, or fills the rest of the client area when " & _
			"width and height are -1. The view never follows the window by itself: you decide when it " & _
			"moves. Four calls cover every layout.")
	Local $aCols[2][2] = [["SITUATION", 3.3], ["CALL", 6.0]]
	Local $aRows[4][2] = [ _
			["A fixed rectangle", "_WV2_Create($hGui, 0, 40, 900, 600)"], _
			["The rest of the area", "_WV2_Create($hGui, 0, 40, -1, -1)"], _
			["Follow a toolbar", "_WV2_SetBounds($hView, 0, 40, $w, $h - 40)"], _
			["Cover everything", "_WV2_FitToParent($hView)"]]
	_G_Table($aCols, $aRows, 8.3)

	_G_H2("Follow the window")
	_G_P("AutoIt tells your loop when the client area changed. Get the new size, then hand the view " & _
			"the rectangle below the toolbar. Keep the toolbar height in one constant, so the two " & _
			"numbers cannot drift apart.")
	_G_Code('Case $GUI_EVENT_RESIZED, $GUI_EVENT_MAXIMIZE, $GUI_EVENT_RESTORE' & @LF & _
			'    _Layout()' & @LF & _
			'' & @LF & _
			'Func _Layout()' & @LF & _
			'    Local $aSize = WinGetClientSize($g_hGui)' & @LF & _
			'    _WV2_SetBounds($g_hView, 0, $TOOLBAR, $aSize[0], $aSize[1] - $TOOLBAR)' & @LF & _
			'EndFunc')

	_G_H2("Zoom, hide, show")
	_G_Code('_WV2_SetZoom($hView, 1.25)        ; 0.2 to 10; _WV2_GetZoom reads it back' & @LF & _
			'_WV2_SetVisible($hView, False)    ; hide the browser, keep the window' & @LF & _
			'_WV2_FitToParent($hView)          ; fill the whole client area')
	_G_P("A hidden view keeps running, but its snapshot is empty or black: pixels exist only once " & _
			"the engine has painted. Capture after the page has loaded and the view is visible.")

	_G_NewPage()
	_G_H2("The program")
	_T_CodeFile("04_toolbar.au3")
	_G_P("Back and Forward go straight to the engine, Reload asks for the same document, Go reads " & _
			"the address field. The status line follows NAVIGATION_COMPLETED.")
EndFunc

; ================================================================== chapter 05
Func _T_Ch05()
	_G_Chapter("05", "RECIPES", "FIVE THINGS YOU WILL WANT", "Recipes", _
			"Snapshot, PDF, downloads, cookies and settings: each one is a short call with one trap worth knowing.")

	_G_Ensure(150)
	_G_H2("1. Save what the page shows")
	_G_Code('Local $sFile = @ScriptDir & "\page.png"' & @LF & _
			'If _WV2_CapturePreview($hView, $sFile) Then' & @LF & _
			'    MsgBox(64, "Snapshot", "Saved " & $sFile)' & @LF & _
			'EndIf' & @LF & _
			'_WV2_CapturePreview($hView, @ScriptDir & "\page.jpg", $WV2_IMAGE_JPEG)')
	_G_P("The image is built in memory by the engine and written by the UDF; no temporary file is " & _
			"involved. A view that is hidden or has never painted gives an empty or black image, which " & _
			"is what Chromium reports. Capture after _WV2_WaitNavigation.")

	_G_Ensure(150)
	_G_H2("2. Print the page to PDF")
	_G_Code('Local $sPdf = @ScriptDir & "\page.pdf"' & @LF & _
			'If _WV2_PrintToPdf($hView, $sPdf) Then' & @LF & _
			'    MsgBox(64, "PDF", "Saved " & $sPdf)' & @LF & _
			'Else' & @LF & _
			'    MsgBox(16, "PDF", _WV2_GetLastErrorMessage())' & @LF & _
			'EndIf')
	_G_P("Defaults: portrait, the page's own paper size, no header or footer, backgrounds left out. " & _
			"The call pumps messages while the engine prints. A missing folder is $WV2_ERR_FILE; a " & _
			"refusal from the runtime is $WV2_ERR_CALL, with the HRESULT in @extended.")

	_G_Ensure(150)
	_G_H2("3. Choose where downloads land")
	_G_Code('Local $sFolder = @ScriptDir & "\downloads"' & @LF & _
			'If Not FileExists($sFolder) Then DirCreate($sFolder)' & @LF & _
			'_WV2_SetDownloadFolder($hView, $sFolder)      ; the folder must exist' & @LF & _
			'_WV2_SetDownloadFilter($hView, "\.exe$")      ; matching URIs are refused')
	_G_P("Both calls enable $WV2_EVENT_DOWNLOAD_STARTING by themselves. Every download then reaches " & _
			"the queue: _WV2_GetEvent gives the URI, with $iValue = 1 when the filter refused it. A " & _
			"refused download never reaches the disk; the engine is told before a byte is written. The " & _
			"file keeps the name chosen by the server - only the folder changes.")

	_G_Ensure(150)
	_G_H2("4. Start from a clean cookie jar")
	_G_Code('_WV2_ClearCookies($hView)' & @LF & _
			'_WV2_Reload($hView)          ; the page keeps what it already read')
	_G_P("Cookies live in the user data folder. With no sixth argument, _WV2_Create opens a private " & _
			"profile under %TEMP% and deletes it when the view is destroyed; a folder you pass is left " & _
			"alone, and views started with the same folder share the jar. Only cookies are cleared - " & _
			"cache, history and localStorage stay.")

	_G_Ensure(150)
	_G_H2("5. Turn settings off, DevTools on")
	_G_Code('_WV2_SettingWrite($hView, "AreDevToolsEnabled", True)' & @LF & _
			'_WV2_SettingWrite($hView, "AreDefaultContextMenusEnabled", False)' & @LF & _
			'Local $bJs = _WV2_SettingRead($hView, "IsScriptEnabled")   ; 1 or 0')
	_G_P("Nine names are accepted, in any case and with or without spaces: IsScriptEnabled, " & _
			"IsWebMessageEnabled, AreDefaultScriptDialogsEnabled, IsStatusBarEnabled, " & _
			"AreDevToolsEnabled, AreDefaultContextMenusEnabled, AreHostObjectsAllowed, " & _
			"IsZoomControlEnabled, IsBuiltInErrorPageEnabled. A name outside the list is $WV2_ERR_ARG.")
	_G_P("With DevTools enabled, F12 opens the inspector inside the view. Disable it before handing " & _
			"the program to someone who should not see the page's internals.")
EndFunc

; ================================================================== chapter 06
Func _T_Ch06()
	_G_Chapter("06", "TROUBLESHOOTING", "ERRORS, TRAPS, LOOKUP", "When it goes wrong", _
			"Every failure is a return value. The UDF never shows a dialog and never writes to the console.")

	_G_P("The UDF reports; your script decides. A failed call returns 0 or -1, sets @error to a " & _
			"$WV2_ERR_* code, and often puts the raw HRESULT in @extended. _WV2_GetLastErrorMessage() " & _
			"turns the last failure into a sentence such as Method call failed in " & _
			"ICoreWebView2::Navigate (HRESULT 0x80070057).")

	_G_H2("Twelve codes")
	Local $aCols[3][2] = [["CONSTANT", 3.1], ["VALUE", 1.1], ["MEANING", 5.8]]
	Local $aRows[12][3] = [ _
			["$WV2_ERR_NONE", "0", "no error"], _
			["$WV2_ERR_HANDLE", "1", "invalid or destroyed handle"], _
			["$WV2_ERR_ARG", "2", "bad argument for this call"], _
			["$WV2_ERR_RUNTIME", "3", "WebView2 runtime not found on this machine"], _
			["$WV2_ERR_COM", "4", "COM initialisation or interface wrapper failed"], _
			["$WV2_ERR_ENV", "5", "environment creation failed"], _
			["$WV2_ERR_CONTROLLER", "6", "controller creation failed"], _
			["$WV2_ERR_NOT_READY", "7", "instance not usable yet"], _
			["$WV2_ERR_CALL", "8", "a WebView2 method returned a failure HRESULT"], _
			["$WV2_ERR_TIMEOUT", "9", "the operation did not finish in time"], _
			["$WV2_ERR_FULL", "10", "sixteen live views already"], _
			["$WV2_ERR_FILE", "11", "a file given to the UDF could not be written"]]
	_G_Table($aCols, $aRows, 8.0, True)

	_G_Note("The one you cannot fix in code", "$WV2_ERR_RUNTIME means the machine has no WebView2 " & _
			"runtime. The UDF never installs or downloads anything; the README says where the runtime " & _
			"comes from and how to check for it.", "warn")

	_G_H2("Five traps")
	Local $aTraps[5] = [ _
			"Blocking the loop.|Events are delivered by the message loop. A long Sleep or a modal dialog stops the engine just as it stops your window: use _WV2_WaitEvent, _WV2_WaitNavigation or _WV2_ExecuteScript, which pump while they wait.", _
			"Controls under the browser.|A view is a child window and covers AutoIt controls that overlap it. Reserve a band (chapter 4).", _
			"Creating on one thread, destroying on another.|The apartment is initialised by _WV2_Create in the calling thread. Keep the whole life of the view there.", _
			"Expecting a string from ExecuteScript.|The result is JSON text: a string keeps its quotes, a number is bare, a throw gives null.", _
			"Reading -1 as a size.|In _WV2_Create, -1 means the rest of the client area, not the size of the parent window and not a default."]
	_G_Bullets($aTraps)

	_G_H2("Cheat sheet")
	_G_P("All forty functions, in the order you are likely to need them. Full signatures, parameters " & _
			"and remarks are in the #FUNCTION# header of each one in WebView2.au3.")

	_G_H3("Window and lifecycle")
	Local $aCo[2][2] = [["FUNCTION", 4.2], ["WHAT IT DOES", 5.4]]
	Local $aRw[6][2] = [ _
			["_WV2_Create", "Creates a view in a GUI; returns a handle from 1 to 16"], _
			["_WV2_Destroy", "Releases the engine objects; call it before GUIDelete"], _
			["_WV2_IsReady", "1 when the view can be used"], _
			["_WV2_GetRuntimePath", "Full path of the runtime DLL, empty when it is missing"], _
			["_WV2_GetBrowserVersion", "Version of the engine behind this view"], _
			["_WV2_GetLastErrorMessage", "Text of the last failure, empty after a success"]]
	_G_Table($aCo, $aRw, 7.8, True)

	_G_H3("Navigation")
	Local $aRn[9][2] = [ _
			["_WV2_Navigate", "Loads a URL; the navigation itself is asynchronous"], _
			["_WV2_NavigateToString", "Loads HTML carried by the script"], _
			["_WV2_WaitNavigation", "Pumps until the navigation ends; @extended is the web error"], _
			["_WV2_IsNavigationComplete", "Polls the same state without waiting"], _
			["_WV2_Reload", "Reloads the current document"], _
			["_WV2_GoBack", "Moves one entry back in history"], _
			["_WV2_GoForward", "Moves one entry forward"], _
			["_WV2_Stop", "Stops the current navigation"], _
			["_WV2_SetNavigationFilter", "PCRE; matching URLs are refused"]]
	_G_Table($aCo, $aRn, 7.8, True)

	_G_H3("History, bounds, zoom")
	Local $aRg[8][2] = [ _
			["_WV2_CanGoBack", "1 if Back would move"], _
			["_WV2_CanGoForward", "1 if Forward would move"], _
			["_WV2_SetBounds", "Places the view in the parent client area"], _
			["_WV2_GetBounds", "Reads its rectangle, by reference"], _
			["_WV2_FitToParent", "Covers the whole client area"], _
			["_WV2_SetVisible", "Shows or hides the browser"], _
			["_WV2_SetZoom", "Zoom factor, 0.2 to 10"], _
			["_WV2_GetZoom", "Current zoom factor"]]
	_G_Table($aCo, $aRg, 7.8, True)

	_G_H3("Page, scripts, events")
	Local $aRp[10][2] = [ _
			["_WV2_GetTitle", "Document title, by reference"], _
			["_WV2_GetSource", "Current URL, by reference"], _
			["_WV2_ExecuteScript", "Runs JavaScript; returns the value as JSON text"], _
			["_WV2_AddScriptToExecuteOnDocumentCreated", "Installs a script for the next documents"], _
			["_WV2_RemoveScriptToExecuteOnDocumentCreated", "Removes it by the id it returned"], _
			["_WV2_EnableEvent", "Subscribes to one event type"], _
			["_WV2_GetEvent", "Takes the oldest queued event; 0 when empty"], _
			["_WV2_WaitEvent", "Waits for one event type, pumping messages"], _
			["_WV2_PostWebMessage", "Sends JSON text to the page"], _
			["_WV2_PostWebMessageAsString", "Sends a plain string to the page"]]
	_G_Table($aCo, $aRp, 7.8, True)

	_G_H3("Files, downloads, settings")
	Local $aRf[7][2] = [ _
			["_WV2_CapturePreview", "Writes the visible page as PNG or JPEG"], _
			["_WV2_PrintToPdf", "Writes the page as PDF"], _
			["_WV2_SetDownloadFolder", "Folder where downloads land; it must exist"], _
			["_WV2_SetDownloadFilter", "PCRE; matching downloads are refused"], _
			["_WV2_ClearCookies", "Empties the cookie jar of the profile"], _
			["_WV2_SettingRead", "Reads one of the nine page settings"], _
			["_WV2_SettingWrite", "Writes one of the nine page settings"]]
	_G_Table($aCo, $aRf, 7.8, True)

	; Closing page: the booklet hands over to the package and to the forum.
	_G_NewPage()
	_PDFX_AddBookmark($g_Doc, "Where to go next", 1, _PDFX_PageCount($g_Doc), 74)
	_G_Tracked($g_X, 92, "THE REST OF THE PACKAGE", 7.2, $G_TERRA, "Helvetica", "B", 1.8)
	_G_Text($g_X, 106, "You are ready", 29, $G_INK, "Helvetica", "B")
	$g_Y = 152
	_G_P("Everything past this point is a variation on the four programs: the same handle, the " & _
			"same message loop, and the same rule that a failure is a return value, never a dialog.")
	Local $fCardY = $g_Y
	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_RoundRect($g_Doc, $g_X, $fCardY, $g_W, 104, 7, $PDFX_FILL)
	_G_Tracked($g_X + 16, $fCardY + 14, "IN THE PACKAGE", 6.6, $G_TERRA_D, "Helvetica", "B", 1.2)
	Local $aNext[4][2] = [ _
			["README.md", "installation, the API in one page, the limits"], _
			["WebView2_Developer_Guide.pdf", "the COM machinery under this API"], _
			["WebView2_Example_GUI.au3", "a complete browser, with a self test"], _
			["WebView2.au3", "every function carries a #FUNCTION# header"]]
	Local $i
	For $i = 0 To 3
		_G_Text($g_X + 16, $fCardY + 32 + $i * 17, $aNext[$i][0], 8.8, $G_INK, "Helvetica", "B")
		_G_Text($g_X + 176, $fCardY + 32 + $i * 17, $aNext[$i][1], 8.0, $G_BODY)
	Next
	$g_Y = $fCardY + 104 + 20

	_G_P("Questions, bug reports and updates belong in the forum thread for this UDF. The README " & _
			"repeats the API on one page; the Developer Guide explains what runs underneath it.")
	_G_P("_WV2_GetLastErrorMessage() is the first thing to print when a call fails: it names the " & _
			"method and carries the HRESULT that @extended shows as a number.", 9.0, 13.4)

	; The lifecycle, once, as a closing figure.
	_G_FigCard(92)
	Local $t = $g_FigTop
	Local $aStep[4][2] = [ _
			["_WV2_Create", "a handle"], _
			["Navigate", "a string or a URL"], _
			["Loop", "drain the queue"], _
			["_WV2_Destroy", "before GUIDelete"]]
	For $i = 0 To 3
		Local $fBX = $g_X + 12 + $i * 122
		_G_Box($fBX, $t + 24, 104, 44, $aStep[$i][0], $aStep[$i][1], $G_SAND, $G_SAND_D, $G_INK, 7.8)
		If $i < 3 Then _G_ArrowR($fBX + 106, $t + 46, $fBX + 120)
	Next
	_G_FigCaption("Every program in this booklet is this sequence. What changes between them is " & _
			"what happens in the middle: a message, a script, a download, a page printed to PDF.")

	; The closing block sits at the foot of the last page, whatever is above it.
	$g_Y = 690
	_G_Rule($g_Y, $G_RULE, 0.6)
	$g_Y += 10
	_G_Tracked($g_X, $g_Y, "END OF THE QUICK START", 6.8, $G_TERRA, "Helvetica", "B", 1.6)
	_G_Text($g_X + 170, $g_Y - 1, "WebView2 UDF 0.3.0  -  Numeric1  -  MIT", 8.4, $G_MUTED)
	$g_Y += 16
	_G_Text($g_X, $g_Y, "Everything here was measured on Windows 10 with AutoIt 3.3.16.1; the four programs are next to the UDF in the zip and run as printed.", 7.8, $G_MUTED, "Helvetica", "I")
EndFunc
