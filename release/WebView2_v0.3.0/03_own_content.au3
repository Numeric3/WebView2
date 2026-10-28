; ============================================================
;  Your own content: HTML from a string, answers from JavaScript
; ============================================================
#include <GUIConstantsEx.au3>
#include "WebView2.au3"
Opt("MustDeclareVars", 1)

Global $hGui = GUICreate("Own content", 900, 620)
Global $idRead = GUICtrlCreateButton("Read the result", 12, 588, 150, 24)
Global $idInfo = GUICtrlCreateLabel("Change the numbers, then read.", 176, 593, 700, 20)
GUISetState(@SW_SHOW, $hGui)
Global $hView = _WV2_Create($hGui, 0, 0, -1, 580)
If $hView = 0 Then
	MsgBox(16, "WebView2", "The view could not be created: " & _WV2_GetLastErrorMessage())
	Exit 1
EndIf
; The page is a small form. JavaScript does the work; AutoIt
; only asks for the answer when its button is clicked.
Global $sHtml = _
		"<html><body style='font-family:Segoe UI;background:#FAF4E8;color:#2E251C'>" & _
		"<div style='padding:40px'>" & _
		"<h1 style='color:#9E4B1F'>Do the maths in the page</h1>" & _
		"<input id='a' type='number' value='20' style='font-size:18px;width:90px'>" & _
		" + <input id='b' type='number' value='22' style='font-size:18px;width:90px'>" & _
		" = <b id='res' style='font-size:22px'>42</b>" & _
		"<p>What the page shows, AutoIt can read back.</p>" & _
		"<script>" & _
		"function add() {" & _
		"  var a = Number(document.getElementById('a').value);" & _
		"  var b = Number(document.getElementById('b').value);" & _
		"  document.getElementById('res').textContent = a + b;" & _
		"}" & _
		"document.getElementById('a').oninput = add;" & _
		"document.getElementById('b').oninput = add;" & _
		"</script></div></body></html>"
_WV2_NavigateToString($hView, $sHtml)

While 1
	Switch GUIGetMsg()
		Case $GUI_EVENT_CLOSE
			ExitLoop
		Case $idRead
			_ReadResult()
	EndSwitch
WEnd

_WV2_Destroy($hView)
GUIDelete($hGui)

; ExecuteScript runs JavaScript and brings back the value of
; the last expression as JSON text. Number(...) makes it a
; bare number: 42, without quotes.
Func _ReadResult()
	Local $sJson = ""
	If _WV2_ExecuteScript($hView, _
			"Number(document.getElementById('res').textContent)", $sJson) Then
		GUICtrlSetData($idInfo, "The page computed " & $sJson)
	Else
		GUICtrlSetData($idInfo, "Failed: " & _WV2_GetLastErrorMessage())
	EndIf
EndFunc
