; ============================================================
;  A browser with a toolbar that follows the window
;  Back, Forward, Reload, an address field and a status line.
; ============================================================
#include <GUIConstantsEx.au3>
#include "WebView2.au3"

Opt("MustDeclareVars", 1)

; The toolbar band is never covered by the browser.
Global Const $TOOLBAR = 40

Global $g_hGui = 0, $g_hView = 0
Global $g_idBack = 0, $g_idForward = 0, $g_idReload = 0
Global $g_idUrl = 0, $g_idGo = 0, $g_idStatus = 0

$g_hGui = GUICreate("Mini browser", 1000, 700)
$g_idBack = GUICtrlCreateButton("Back", 8, 8, 64, 24)
$g_idForward = GUICtrlCreateButton("Forward", 80, 8, 64, 24)
$g_idReload = GUICtrlCreateButton("Reload", 152, 8, 64, 24)
$g_idUrl = GUICtrlCreateInput("", 232, 8, 560, 24)
$g_idGo = GUICtrlCreateButton("Go", 800, 8, 48, 24)
$g_idStatus = GUICtrlCreateLabel("Ready", 860, 12, 130, 20)
GUISetState(@SW_SHOW, $g_hGui)

; The view starts below the toolbar, on the first client size.
Global $aClient = WinGetClientSize($g_hGui)
$g_hView = _WV2_Create($g_hGui, 0, $TOOLBAR, $aClient[0], $aClient[1] - $TOOLBAR)
If $g_hView = 0 Then
	MsgBox(16, "WebView2", "The view could not be created: " & _WV2_GetLastErrorMessage())
	Exit 1
EndIf

; A local page with an anchor, so Back has somewhere to go.
Global $sHtml = _
		"<html><body style='font-family:Segoe UI;background:#FAF4E8;color:#2E251C'>" & _
		"<div style='padding:40px'>" & _
		"<h1 style='color:#9E4B1F'>Mini browser</h1>" & _
		"<p>Type any address in the field above, then press Go.</p>" & _
		"<p><a href='#details'>Jump to the details</a></p>" & _
		"<div style='height:900px'></div>" & _
		"<h2 id='details'>The details</h2>" & _
		"<p>Back returns to the top of this page.</p>" & _
		"</div></body></html>"
_WV2_NavigateToString($g_hView, $sHtml)
_WV2_WaitNavigation($g_hView)

While 1
	Switch GUIGetMsg()
		Case $GUI_EVENT_CLOSE
			ExitLoop
		Case $GUI_EVENT_RESIZED, $GUI_EVENT_MAXIMIZE, $GUI_EVENT_RESTORE
			_Layout()
		Case $g_idBack
			_WV2_GoBack($g_hView)
		Case $g_idForward
			_WV2_GoForward($g_hView)
		Case $g_idReload
			_WV2_Reload($g_hView)
		Case $g_idGo
			_Go()
	EndSwitch
	_DrainEvents()
WEnd

_WV2_Destroy($g_hView)
GUIDelete($g_hGui)

; Fits the browser to the new client area after a resize.
Func _Layout()
	Local $aSize = WinGetClientSize($g_hGui)
	If Not IsArray($aSize) Or $aSize[0] <= 0 Then Return
	_WV2_SetBounds($g_hView, 0, $TOOLBAR, $aSize[0], $aSize[1] - $TOOLBAR)
EndFunc

; Reads the address field and asks the view to load it.
Func _Go()
	Local $sUrl = StringStripWS(GUICtrlRead($g_idUrl), 3)
	If $sUrl <> "" Then _WV2_Navigate($g_hView, $sUrl)
EndFunc

; Keeps the status line in step with the navigations.
Func _DrainEvents()
	Local $sData = "", $iValue = 0
	While 1
		Local $iEvent = _WV2_GetEvent($g_hView, $sData, $iValue)
		If $iEvent <= 0 Then ExitLoop
		If $iEvent = $WV2_EVENT_NAVIGATION_COMPLETED Then
			If $iValue = 1 Then
				GUICtrlSetData($g_idStatus, "Loaded")
			Else
				GUICtrlSetData($g_idStatus, "Error " & $iValue)
			EndIf
		EndIf
	WEnd
EndFunc
