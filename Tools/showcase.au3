#cs ----------------------------------------------------------------------------
    showcase.au3 -- the window used on the kit's forum post.

    A designed frame around the WebView2 view: custom caption, address pill,
    status band, painted with GDI+ on the parent window. The browser itself is
    one _WV2_Create() call and one _WV2_Navigate(); everything else is chrome,
    which is the point -- the view is a child window and takes whatever space
    the host gives it.

    AutoIt3.exe showcase.au3            run it
    AutoIt3.exe showcase.au3 --shot     load the page, save ..\WebView2_Showcase.png, exit
#ce ----------------------------------------------------------------------------

#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <WinAPI.au3>
#include <GDIPlus.au3>
#include <ScreenCapture.au3>
#include "..\WebView2.au3"

Opt("MustDeclareVars", 1)

; ------------------------------------------------------------------ geometry
Global Const $UI_W = 1200
Global Const $UI_H = 700
Global Const $UI_CAP = 44     ; caption band
Global Const $UI_BAR = 58     ; toolbar band
Global Const $UI_STA = 28     ; status band
Global Const $UI_TOP = $UI_CAP + $UI_BAR
Global Const $UI_VIEW = $UI_H - $UI_TOP - $UI_STA

; -------------------------------------------------------------------- palette
Global Const $C_INK = 0xFF2E251C
Global Const $C_BODY = 0xFF4C4236
Global Const $C_MUTED = 0xFF8D7B64
Global Const $C_RULE = 0xFFE7E2D9
Global Const $C_CAP = 0xFF26201B
Global Const $C_CAPFG = 0xFFA2958A
Global Const $C_TOOL = 0xFFFBFAF8
Global Const $C_FIELD = 0xFFF1EEE9
Global Const $C_LINE = 0xFFDCD6CB
Global Const $C_TERRA = 0xFFB85C33
Global Const $C_BADGE = 0xFFF7E5DB
Global Const $C_BADGEF = 0xFF9E4B1F
Global Const $C_STATUS = 0xFFF7F4EF
Global Const $C_DIS = 0xFFBFB5A8
Global Const $C_BORDER = 0xFFD9D2C7
Global Const $C_WHITE = 0xFFFFFFFF

Global $g_hGui = 0
Global $g_iView = 0
Global $g_bRun = True
Global $g_bShot = ($CmdLine[0] >= 1 And $CmdLine[1] = "--shot")
Global $g_sUrl = "en.wikipedia.org/wiki/AutoIt"
Global $g_sTitle = "Starting the engine..."
Global $g_sStatus = "WebView2 0.3.0"
Global $g_sBrand = "AutoIt" & ChrW(160) & ChrW(183) & ChrW(160) & "WebView2"

Global $g_hFamUi = 0, $g_hFamSb = 0, $g_hFamIc = 0
Global $g_hFTitle = 0, $g_hFUrl = 0, $g_hFSmall = 0, $g_hFSmallB = 0
Global $g_hFIcon = 0, $g_hFNav = 0, $g_hFWm = 0, $g_hFLock = 0

__Fonts()
$g_hGui = GUICreate("AutoIt + WebView2", $UI_W, $UI_H, 83, 14, BitOR($WS_POPUP, $WS_CLIPCHILDREN))
GUIRegisterMsg($WM_PAINT, "WM_PAINT")
GUIRegisterMsg($WM_NCHITTEST, "WM_NCHITTEST")
GUIRegisterMsg($WM_LBUTTONUP, "WM_LBUTTONUP")
GUISetState(@SW_SHOW, $g_hGui)
If $g_bShot Then WinSetOnTop($g_hGui, "", 1)
__Draw()

$g_iView = _WV2_Create($g_hGui, 0, $UI_TOP, $UI_W, $UI_VIEW)
If $g_iView = 0 Then
	$g_sTitle = "Cannot start WebView2: " & _WV2_GetLastErrorMessage()
	__Draw()
	Sleep(3000)
	__Quit(1)
EndIf
_WV2_EnableEvent($g_iView, $WV2_EVENT_NAVIGATION_COMPLETED)
_WV2_Navigate($g_iView, "https://" & $g_sUrl)

; The first load is the only blocking step; everything after it lives in the loop.
Local $tEnd = TimerInit(), $sData = "", $iValue = 0
While TimerDiff($tEnd) < 45000
	If _WV2_WaitEvent($g_iView, $WV2_EVENT_NAVIGATION_COMPLETED, 1000, $sData, $iValue) Then
		If StringInStr($sData, "wikipedia.org") Then ExitLoop
	EndIf
	If Not $g_bRun Then __Quit(0)
WEnd
Sleep(1800)
__Refresh()

If $g_bShot Then
	Sleep(600)
	_ScreenCapture_CaptureWnd(@ScriptDir & "\..\WebView2_Showcase.png", $g_hGui, 0, 0, -1, -1, False)
	__Quit(0)
EndIf

While $g_bRun
	Switch GUIGetMsg()
		Case $GUI_EVENT_CLOSE
			$g_bRun = False
	EndSwitch
	Sleep(15)
WEnd
__Quit(0)

; #FUNCTION# ====================================================================================================================
; Name ..........: __Fonts
; Description ...: GDI+ families and faces, built once. Sizes are pixels at 96 dpi.
; ===============================================================================================================================
Func __Fonts()
	_GDIPlus_Startup()
	$g_hFamUi = _GDIPlus_FontFamilyCreate("Segoe UI")
	$g_hFamSb = _GDIPlus_FontFamilyCreate("Segoe UI Semibold")
	$g_hFamIc = _GDIPlus_FontFamilyCreate("Segoe MDL2 Assets")
	$g_hFTitle = _GDIPlus_FontCreate($g_hFamSb, 13)
	$g_hFUrl = _GDIPlus_FontCreate($g_hFamUi, 13)
	$g_hFSmall = _GDIPlus_FontCreate($g_hFamUi, 11)
	$g_hFSmallB = _GDIPlus_FontCreate($g_hFamSb, 11)
	$g_hFWm = _GDIPlus_FontCreate($g_hFamSb, 12)
	$g_hFIcon = _GDIPlus_FontCreate($g_hFamIc, 12)
	$g_hFNav = _GDIPlus_FontCreate($g_hFamIc, 15)
	$g_hFLock = _GDIPlus_FontCreate($g_hFamIc, 11)
EndFunc   ;==>__Fonts

; #FUNCTION# ====================================================================================================================
; Name ..........: __Refresh
; Description ...: Reads back what the view publishes and repaints the chrome.
; ===============================================================================================================================
Func __Refresh()
	Local $sText = "", $sVer = ""
	If _WV2_GetTitle($g_iView, $sText) And $sText <> "" Then $g_sTitle = $sText
	If _WV2_GetSource($g_iView, $sText) And $sText <> "" Then
		$g_sUrl = StringReplace($sText, "https://", "")
		$g_sUrl = StringReplace($g_sUrl, "http://", "")
		$g_sUrl = StringReplace($g_sUrl, "www.", "")
	EndIf
	If Not _WV2_GetBrowserVersion($g_iView, $sVer) Then $sVer = "unknown"
	$g_sStatus = "WebView2 0.3.0" & ChrW(160) & "  " & ChrW(183) & "  engine " & $sVer
	__Draw()
EndFunc   ;==>__Refresh

; #FUNCTION# ====================================================================================================================
; Name ..........: __Quit
; Description ...: Tears the view down before GDI+, then leaves with a code.
; ===============================================================================================================================
Func __Quit($iCode)
	If $g_iView Then _WV2_Destroy($g_iView)
	_GDIPlus_FontDispose($g_hFTitle)
	_GDIPlus_FontDispose($g_hFUrl)
	_GDIPlus_FontDispose($g_hFSmall)
	_GDIPlus_FontDispose($g_hFSmallB)
	_GDIPlus_FontDispose($g_hFWm)
	_GDIPlus_FontDispose($g_hFIcon)
	_GDIPlus_FontDispose($g_hFNav)
	_GDIPlus_FontDispose($g_hFLock)
	_GDIPlus_FontFamilyDispose($g_hFamUi)
	_GDIPlus_FontFamilyDispose($g_hFamSb)
	_GDIPlus_FontFamilyDispose($g_hFamIc)
	_GDIPlus_Shutdown()
	Exit $iCode
EndFunc   ;==>__Quit

; --------------------------------------------------------------------- paint
Func WM_PAINT($hWnd, $iMsg, $wParam, $lParam)
	#forceref $iMsg, $wParam, $lParam
	If $hWnd = $g_hGui Then __Draw()
	Return $GUI_RUNDEFMSG
EndFunc   ;==>WM_PAINT

Func WM_NCHITTEST($hWnd, $iMsg, $wParam, $lParam)
	#forceref $iMsg, $wParam, $lParam
	If $hWnd <> $g_hGui Then Return $GUI_RUNDEFMSG
	Local $tPt = _WinAPI_GetMousePos(True, $g_hGui)
	Local $iX = DllStructGetData($tPt, 1)
	Local $iY = DllStructGetData($tPt, 2)
	; The caption drags the window, except where the two buttons sit.
	If $iY >= 0 And $iY < $UI_CAP And $iX < $UI_W - 84 Then Return 2
	Return $GUI_RUNDEFMSG
EndFunc   ;==>WM_NCHITTEST

Func WM_LBUTTONUP($hWnd, $iMsg, $wParam, $lParam)
	#forceref $iMsg, $wParam
	If $hWnd <> $g_hGui Then Return $GUI_RUNDEFMSG
	Local $iX = BitAND($lParam, 0xFFFF)
	Local $iY = BitAND(BitShift($lParam, 16), 0xFFFF)
	If $iY < $UI_CAP Then
		If $iX >= $UI_W - 42 Then
			$g_bRun = False
		ElseIf $iX >= $UI_W - 84 Then
			GUISetState(@SW_MINIMIZE, $g_hGui)
		EndIf
	ElseIf $iY < $UI_TOP And $iX >= 88 And $iX < 118 Then
		_WV2_Reload($g_iView)
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc   ;==>WM_LBUTTONUP

; #FUNCTION# ====================================================================================================================
; Name ..........: __Draw
; Description ...: The whole chrome, in paint order, from the paper up.
; ===============================================================================================================================
Func __Draw()
	Local $hG = _GDIPlus_GraphicsCreateFromHWND($g_hGui)
	If $hG = 0 Then Return
	_GDIPlus_GraphicsSetSmoothingMode($hG, 4)
	_GDIPlus_GraphicsSetTextRenderingHint($hG, 5)

	Local $hB = _GDIPlus_BrushCreateSolid($C_WHITE)
	_GDIPlus_GraphicsFillRect($hG, 0, 0, $UI_W, $UI_H, $hB)
	_GDIPlus_BrushDispose($hB)

	; -- caption ------------------------------------------------------------
	Local $hSolid = _GDIPlus_BrushCreateSolid($C_CAP)
	_GDIPlus_GraphicsFillRect($hG, 0, 0, $UI_W, $UI_CAP, $hSolid)
	_GDIPlus_BrushDispose($hSolid)

	__Pill($hG, 14, 11, 22, 22, $C_TERRA, 0, 6)
	__Txt($hG, "W", $g_hFWm, $C_WHITE, 14, 11, 22, 22, 1)
	__Txt($hG, $g_sBrand, $g_hFTitle, $C_CAPFG, 46, 0, 320, $UI_CAP, 0)
	__Txt($hG, "AutoIt", $g_hFTitle, $C_WHITE, 46, 0, 320, $UI_CAP, 0)
	__Txt($hG, ChrW(0xE921), $g_hFIcon, $C_CAPFG, $UI_W - 84, 0, 42, $UI_CAP, 1)
	__Txt($hG, ChrW(0xE8BB), $g_hFIcon, $C_CAPFG, $UI_W - 42, 0, 42, $UI_CAP, 1)

	; -- toolbar ------------------------------------------------------------
	$hSolid = _GDIPlus_BrushCreateSolid($C_TOOL)
	_GDIPlus_GraphicsFillRect($hG, 0, $UI_CAP, $UI_W, $UI_BAR, $hSolid)
	_GDIPlus_BrushDispose($hSolid)
	$hSolid = _GDIPlus_BrushCreateSolid($C_RULE)
	_GDIPlus_GraphicsFillRect($hG, 0, $UI_TOP - 1, $UI_W, 1, $hSolid)
	_GDIPlus_BrushDispose($hSolid)

	__Txt($hG, ChrW(0xE72B), $g_hFNav, $C_DIS, 14, 58, 30, 30, 1)
	__Txt($hG, ChrW(0xE72A), $g_hFNav, $C_DIS, 51, 58, 30, 30, 1)
	__Txt($hG, ChrW(0xE72C), $g_hFNav, $C_BODY, 88, 58, 30, 30, 1)

	__Pill($hG, 130, 57, 914, 32, $C_FIELD, $C_LINE)
	__Txt($hG, ChrW(0xE72E), $g_hFLock, $C_MUTED, 145, 57, 16, 32, 1)
	__Txt($hG, $g_sUrl, $g_hFUrl, $C_BODY, 166, 57, 862, 32, 0)

	__Pill($hG, 1058, 61, 128, 24, $C_BADGE, 0)
	__Txt($hG, "WebView2 0.3.0", $g_hFSmallB, $C_BADGEF, 1058, 61, 128, 24, 1)

	; -- status -------------------------------------------------------------
	$hSolid = _GDIPlus_BrushCreateSolid($C_STATUS)
	_GDIPlus_GraphicsFillRect($hG, 0, $UI_H - $UI_STA, $UI_W, $UI_STA, $hSolid)
	_GDIPlus_BrushDispose($hSolid)
	$hSolid = _GDIPlus_BrushCreateSolid($C_RULE)
	_GDIPlus_GraphicsFillRect($hG, 0, $UI_H - $UI_STA, $UI_W, 1, $hSolid)
	_GDIPlus_BrushDispose($hSolid)
	__Txt($hG, $g_sTitle, $g_hFSmall, $C_BODY, 14, $UI_H - $UI_STA + 1, 700, $UI_STA - 1, 0)
	__Txt($hG, $g_sStatus, $g_hFSmall, $C_MUTED, $UI_W - 614, $UI_H - $UI_STA + 1, 600, $UI_STA - 1, 2)

	; -- edge ---------------------------------------------------------------
	Local $hPen = _GDIPlus_PenCreate($C_BORDER, 1)
	_GDIPlus_GraphicsDrawRect($hG, 0.5, 0.5, $UI_W - 1, $UI_H - 1, $hPen)
	_GDIPlus_PenDispose($hPen)
	_GDIPlus_GraphicsDispose($hG)
EndFunc   ;==>__Draw

; #FUNCTION# ====================================================================================================================
; Name ..........: __Txt
; Description ...: One string in a box, centred vertically; $iAlign 0 left, 1 centre, 2 right.
; ===============================================================================================================================
Func __Txt($hG, $sText, $hFont, $iColor, $fX, $fY, $fW, $fH, $iAlign)
	Local $hBrush = _GDIPlus_BrushCreateSolid($iColor)
	Local $tLayout = _GDIPlus_RectFCreate($fX, $fY, $fW, $fH)
	Local $hSF = _GDIPlus_StringFormatCreate(0)
	_GDIPlus_StringFormatSetAlign($hSF, $iAlign)
	_GDIPlus_StringFormatSetLineAlign($hSF, 1)
	_GDIPlus_GraphicsDrawStringEx($hG, $sText, $hFont, $tLayout, $hSF, $hBrush)
	_GDIPlus_StringFormatDispose($hSF)
	_GDIPlus_BrushDispose($hBrush)
EndFunc   ;==>__Txt

; #FUNCTION# ====================================================================================================================
; Name ..........: __Pill
; Description ...: Rounded box, radius $fR (half the height by default), fill and/or 1px outline.
; ===============================================================================================================================
Func __Pill($hG, $fX, $fY, $fW, $fH, $iFill, $iStroke = 0, $fR = -1)
	If $fR < 0 Then $fR = $fH / 2
	Local $hP, $hB, $hPen
	If $iFill <> 0 Then
		$hP = __RoundPath($fX, $fY, $fW, $fH, $fR)
		$hB = _GDIPlus_BrushCreateSolid($iFill)
		_GDIPlus_GraphicsFillPath($hG, $hP, $hB)
		_GDIPlus_BrushDispose($hB)
		_GDIPlus_PathDispose($hP)
	EndIf
	If $iStroke <> 0 Then
		$hP = __RoundPath($fX + 0.5, $fY + 0.5, $fW - 1, $fH - 1, $fR)
		$hPen = _GDIPlus_PenCreate($iStroke, 1)
		_GDIPlus_GraphicsDrawPath($hG, $hP, $hPen)
		_GDIPlus_PenDispose($hPen)
		_GDIPlus_PathDispose($hP)
	EndIf
EndFunc   ;==>__Pill

Func __RoundPath($fX, $fY, $fW, $fH, $fR)
	Local $hP = _GDIPlus_PathCreate()
	Local $fD = $fR * 2
	_GDIPlus_PathAddArc($hP, $fX, $fY, $fD, $fD, 180, 90)
	_GDIPlus_PathAddArc($hP, $fX + $fW - $fD, $fY, $fD, $fD, 270, 90)
	_GDIPlus_PathAddArc($hP, $fX + $fW - $fD, $fY + $fH - $fD, $fD, $fD, 0, 90)
	_GDIPlus_PathAddArc($hP, $fX, $fY + $fH - $fD, $fD, $fD, 90, 90)
	_GDIPlus_PathCloseFigure($hP)
	Return $hP
EndFunc   ;==>__RoundPath
