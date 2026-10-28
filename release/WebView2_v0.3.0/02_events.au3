; ============================================================
;  Events and messages: page -> AutoIt, AutoIt -> page
; ============================================================
#include <GUIConstantsEx.au3>
#include "WebView2.au3"

Opt("MustDeclareVars", 1)

; The window: a browser on top, 40 pixels for our own controls.
Global $hGui = GUICreate("Events and messages", 900, 620)
Global $idPing = GUICtrlCreateButton("Ping the page", 12, 588, 150, 24)
Global $idInfo = GUICtrlCreateLabel("Waiting for the page...", 176, 593, 700, 20)
GUISetState(@SW_SHOW, $hGui)

Global $hView = _WV2_Create($hGui, 0, 0, -1, 580)
If $hView = 0 Then
	MsgBox(16, "WebView2", "The view could not be created: " & _WV2_GetLastErrorMessage())
	Exit 1
EndIf

; Ask for the events we care about, before loading the page.
; NAVIGATION_COMPLETED is already on; every other event is off.
_WV2_EnableEvent($hView, $WV2_EVENT_TITLE_CHANGED)
_WV2_EnableEvent($hView, $WV2_EVENT_WEB_MESSAGE)

; The page: one button that posts, one listener that receives.
Global $sHtml = _
		"<html><head><title>Two directions</title></head>" & _
		"<body style='font-family:Segoe UI;background:#FAF4E8;color:#2E251C'>" & _
		"<div style='padding:40px'>" & _
		"<h1 style='color:#9E4B1F'>Two directions</h1>" & _
		"<button style='font-size:16px;padding:8px 14px' " & _
		"onclick=""chrome.webview.postMessage('hello from the page')"">" & _
		"Send a message to AutoIt</button>" & _
		"<p id='out' style='margin-top:28px;font-size:18px'>" & _
		"No message from AutoIt yet.</p>" & _
		"<script>" & _
		"chrome.webview.addEventListener('message', function (e) {" & _
		"  document.getElementById('out').textContent = 'AutoIt says: ' + e.data;" & _
		"});" & _
		"</script></div></body></html>"
_WV2_NavigateToString($hView, $sHtml)

; The loop: GUI messages first, then the event queue.
While 1
	Switch GUIGetMsg()
		Case $GUI_EVENT_CLOSE
			ExitLoop
		Case $idPing
			; AutoIt -> page: the text arrives in event.data.
			_WV2_PostWebMessageAsString($hView, "ping at " & @HOUR & ":" & @MIN)
	EndSwitch
	_DrainEvents()
WEnd

_WV2_Destroy($hView)
GUIDelete($hGui)

; Page -> AutoIt: take everything that arrived since the last
; pass. 0 = queue empty, -1 = invalid handle.
Func _DrainEvents()
	Local $sData = "", $iValue = 0
	While 1
		Local $iEvent = _WV2_GetEvent($hView, $sData, $iValue)
		If $iEvent <= 0 Then ExitLoop
		Switch $iEvent
			Case $WV2_EVENT_TITLE_CHANGED
				WinSetTitle($hGui, "", $sData & " - WebView2")
			Case $WV2_EVENT_WEB_MESSAGE
				; $iValue = 1 for a plain string, 0 for JSON.
				GUICtrlSetData($idInfo, "Page says: " & $sData)
		EndSwitch
	WEnd
EndFunc
