; ============================================================
;  My first WebView2 window
;  AutoIt 3.3.16+  -  no network, no extra file
; ============================================================
#include <GUIConstantsEx.au3>
#include "WebView2.au3"

Opt("MustDeclareVars", 1)

; 1. An ordinary AutoIt window. Nothing special yet.
Global $hGui = GUICreate("My first WebView2", 900, 620)
GUISetState(@SW_SHOW, $hGui)

; 2. Put the browser inside it. 0, 0, -1, -1 means "from the
;    top left corner, take all the rest of the client area".
Global $hView = _WV2_Create($hGui, 0, 0, -1, -1)
If $hView = 0 Then
	; Always test the handle: a window without a browser is useless.
	MsgBox(16, "WebView2", "The view could not be created." & @CRLF & @CRLF & _
			"@error = " & @error & "   @extended = " & @extended & @CRLF & _
			_WV2_GetLastErrorMessage())
	Exit 1
EndIf

; 3. Give it a page. The HTML travels with the script, so this
;    works offline and leaves no file behind.
Global $sHtml = _
		"<html><body style='font-family:Segoe UI;background:#FAF4E8;color:#2E251C'>" & _
		"<div style='padding:48px'>" & _
		"<h1 style='color:#9E4B1F'>Hello from the Edge engine</h1>" & _
		"<p>This page is drawn by the same engine as Microsoft Edge,</p>" & _
		"<p>inside an AutoIt window, with one include and no installer.</p>" & _
		"</div></body></html>"
_WV2_NavigateToString($hView, $sHtml)

; 4. Wait for the page. 1 = the navigation finished, 0 = it
;    never did; @extended = 0 when the page loaded correctly,
;    otherwise the web error code. Messages keep flowing.
Global $iDone = _WV2_WaitNavigation($hView)
If $iDone = 0 Or @extended <> 0 Then
	MsgBox(16, "WebView2", "The page did not load. @extended = " & @extended & @CRLF & _
			_WV2_GetLastErrorMessage())
EndIf

; 5. The message loop. WebView2 needs it as much as the window:
;    without it nothing is painted and the window freezes.
While 1
	If GUIGetMsg() = $GUI_EVENT_CLOSE Then ExitLoop
WEnd

; 6. Close the browser before the window that hosts it.
_WV2_Destroy($hView)
GUIDelete($hGui)
