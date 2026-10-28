#cs ----------------------------------------------------------------------------
    build_guide — generates WebView2_Developer_Guide.pdf with PDFX itself.

    Editorial layout: warm paper, terracotta ink, numbered chapter badges,
    vector figures and dark code cards. The guide is built twice. The first
    pass records the page on which each chapter starts and the total page
    count; the second pass writes both into the table of contents and the
    footer. Chapter layouts do not depend on those numbers, so the two passes
    paginate identically.

    Author: Numeric1 — https://www.autoitscript.com/forum/profile/118605-numeric1/
    Typeset with PDFX 1.4.0 — https://www.autoitscript.com/forum/topic/213930-udf-pdfx/
#ce ----------------------------------------------------------------------------

; Local tool, not part of the released kit. Drop PDFX.au3 next to this file to rebuild the guide.
#include "PDFX.au3"

Global $g_Doc = 0
Global $g_Pass = 1
Global $g_Total = 0
Global $g_Ch = 0
Global $g_Y = 0
Global $g_Section = ""
Global $g_PageNo[10]
Global $g_ChapterY[10]
Global $g_FigNo = 0
Global $g_FigTop = 0

Global $g_X = 0
Global $g_W = 0
Global $g_Top = 0
Global $g_Bottom = 0
Global $g_PageW = 0
Global $g_PageH = 0

; ---------------------------------------------------------------- palette
Global Const $G_PAPER = 0xFAF4E8
Global Const $G_PANEL = 0xFFFBF2
Global Const $G_INK = 0x2E251C
Global Const $G_BODY = 0x4C4236
Global Const $G_TERRA = 0x9E4B1F
Global Const $G_TERRA_D = 0x7B3712
Global Const $G_CREAM = 0xF8E6C6
Global Const $G_SAND = 0xF0E1C8
Global Const $G_SAND_D = 0xE4D0B2
Global Const $G_RULE = 0xE1D1B9
Global Const $G_MUTED = 0x8D7B64
Global Const $G_CODEBG = 0x2B2018
Global Const $G_CODETXT = 0xF2E5CF
Global Const $G_WARNBG = 0xF7E3DA
Global Const $G_WARN = 0xA6461F
Global Const $G_WHITE = 0xFFFDF8

Global Const $G_URL_PDFX = "https://www.autoitscript.com/forum/topic/213930-udf-pdfx/"
Global Const $G_URL_PROFILE = "https://www.autoitscript.com/forum/profile/118605-numeric1/"

Global $g_Titles[9][2] = [ _
	["01", "The COM model in AutoIt"], _
	["02", "Handler objects in a global heap"], _
	["03", "Vtable ranks and WebView2.h"], _
	["04", "x86 and x64: put_Bounds"], _
	["05", "Adding a method in six steps"], _
	["06", "Diagnosing a failure"], _
	["07", "Threading and the message pump"], _
	["08", "Limits, pitfalls, references"]]

; ================================================================== driver
Global $sOut = @ScriptDir & "\..\WebView2_Developer_Guide.pdf"
If $CmdLine[0] >= 1 Then $sOut = $CmdLine[1]

ConsoleWrite("Pass 1: layout, page numbers and total..." & @CRLF)
_G_Build(1)
$g_Total = _PDFX_PageCount($g_Doc)
_PDFX_Close($g_Doc)

ConsoleWrite("Pass 2: final document..." & @CRLF)
_G_Build(2)
If Not _PDFX_Save($g_Doc, $sOut) Then
	ConsoleWrite("! Save failed, @error=" & @error & @CRLF)
	Exit 1
EndIf
Global $iPages = _PDFX_PageCount($g_Doc)
_PDFX_Close($g_Doc)

ConsoleWrite("OK " & $sOut & " (" & FileGetSize($sOut) & " bytes, " & $iPages & " pages)" & @CRLF)

; ================================================================== document
Func _G_Build($iPass)
	$g_Pass = $iPass
	$g_Ch = 0
	$g_Y = 0
	$g_Section = ""
	$g_FigNo = 0
	$g_Doc = _PDFX_New("A4", "P", 17)

	$g_X = _PDFX_Mm(17)
	$g_PageW = _PDFX_PageWidth($g_Doc)
	$g_PageH = _PDFX_PageHeight($g_Doc)
	$g_W = $g_PageW - 2 * $g_X
	$g_Top = 74
	$g_Bottom = 782

	_PDFX_SetMeta($g_Doc, "WebView2 UDF - Developer guide", "Numeric1", _
			"Embedding the Edge engine in AutoIt without a loader: the COM model, the ABI traps, the diagnostics", _
			"webview2;autoit;com;vtable;guide")
	_PDFX_SetCompression($g_Doc, 6)
	_PDFX_SetPageMode($g_Doc, "UseOutlines")
	_PDFX_SetPageLayout($g_Doc, "SinglePage")

	_G_Cover()
	_G_Toc()
	_G_Ch01()
	_G_EndChapter()
	_G_Ch02()
	_G_EndChapter()
	_G_Ch03()
	_G_EndChapter()
	_G_Ch04()
	_G_EndChapter()
	_G_Ch05()
	_G_EndChapter()
	_G_Ch06()
	_G_EndChapter()
	_G_Ch07()
	_G_EndChapter()
	_G_Ch08()
EndFunc

; Closes a chapter at the foot of its last page. Skipped when the page is too
; full to hold the rule without crowding the prose above it.
Func _G_EndChapter()
	If $g_Ch >= 8 Then Return
	If $g_Y > 736 Then Return
	Local $fY = $G_Bottom - 18
	_G_Rule($fY, $G_RULE, 0.5, $g_X, $g_X + $g_W)
	_G_Tracked($g_X, $fY + 7, "NEXT CHAPTER", 6.4, $G_MUTED, "Helvetica", "B", 1.2)
	_G_TrackedRight($g_X + $g_W, $fY + 6, $g_Titles[$g_Ch][0] & "  " & $g_Titles[$g_Ch][1], 7.4, $G_TERRA, "Helvetica", "B", 1)
	$g_Y = $g_Bottom
EndFunc

; ================================================================== text tools
Func _G_Push(ByRef $aArray, $vValue)
	Local $iCount = UBound($aArray)
	ReDim $aArray[$iCount + 1]
	$aArray[$iCount] = $vValue
EndFunc

Func _G_FitCount($sLine, $fWidth, $iSize)
	Local $iCount = StringLen($sLine)
	While $iCount > 1 And _PDFX_TextWidth($g_Doc, StringLeft($sLine, $iCount), $iSize) > $fWidth
		$iCount -= 1
	WEnd
	Return $iCount
EndFunc

Func _G_W($sText, $iSize, $sFam = "Helvetica", $sStyle = "")
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	Return _PDFX_TextWidth($g_Doc, $sText, $iSize)
EndFunc

Func _G_TrackWidth($sText, $iSize, $sFam, $sStyle, $fTrack)
	If $sText = "" Then Return 0
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	Return _PDFX_TextWidth($g_Doc, $sText, $iSize) + $fTrack * (StringLen($sText) - 1)
EndFunc

; Wraps a paragraph; $fWFirst is the width of its first line, $fWNext of the others.
Func _G_Wrap($sText, $fWFirst, $fWNext, $iSize, $sFam = "Helvetica", $sStyle = "")
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	Local $aOut[0]
	Local $aParas = StringSplit(StringReplace(StringReplace($sText, @CRLF, @LF), @CR, @LF), @LF, 2)
	For $iPara = 0 To UBound($aParas) - 1
		Local $sPara = $aParas[$iPara]
		If $sPara = "" Then
			_G_Push($aOut, "")
			ContinueLoop
		EndIf
		Local $aWords = StringSplit($sPara, " ", 2)
		Local $sLine = ""
		Local $fLimit = $fWFirst
		For $iWord = 0 To UBound($aWords) - 1
			Local $sWord = $aWords[$iWord]
			If $sLine = "" Then
				$sLine = $sWord
			ElseIf _PDFX_TextWidth($g_Doc, $sLine & " " & $sWord, $iSize) <= $fLimit Then
				$sLine &= " " & $sWord
			Else
				_G_Push($aOut, $sLine)
				$sLine = $sWord
				$fLimit = $fWNext
			EndIf
			While _PDFX_TextWidth($g_Doc, $sLine, $iSize) > $fLimit And StringLen($sLine) > 1
				Local $iCut = _G_FitCount($sLine, $fLimit, $iSize)
				_G_Push($aOut, StringLeft($sLine, $iCut))
				$sLine = StringMid($sLine, $iCut + 1)
				$fLimit = $fWNext
			WEnd
		Next
		_G_Push($aOut, $sLine)
	Next
	Return $aOut
EndFunc

Func _G_SetFont($sFam, $iSize, $sStyle = "")
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
EndFunc

Func _G_Text($fX, $fY, $sText, $iSize, $vColor, $sFam = "Helvetica", $sStyle = "")
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	_PDFX_SetFill($g_Doc, $vColor)
	_PDFX_Text($g_Doc, $fX, $fY, $sText, $iSize)
EndFunc

Func _G_TextCentre($fX, $fY, $fWidth, $sText, $iSize, $vColor, $sFam = "Helvetica", $sStyle = "")
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	_PDFX_SetFill($g_Doc, $vColor)
	_PDFX_TextAlign($g_Doc, $fX, $fY, $fWidth, $sText, "C", $iSize)
EndFunc

; Letter-spaced small caps: one text operator per glyph.
Func _G_Tracked($fX, $fY, $sText, $iSize, $vColor, $sFam = "Helvetica", $sStyle = "B", $fTrack = 1.2)
	If $sText = "" Then Return
	_PDFX_SetFont($g_Doc, $sFam, $iSize, $sStyle)
	_PDFX_SetFill($g_Doc, $vColor)
	Local $fCursor = $fX
	For $iChar = 1 To StringLen($sText)
		Local $sChar = StringMid($sText, $iChar, 1)
		_PDFX_Text($g_Doc, $fCursor, $fY, $sChar, $iSize)
		$fCursor += _PDFX_TextWidth($g_Doc, $sChar, $iSize) + $fTrack
	Next
EndFunc

Func _G_TrackedCentre($fY, $sText, $iSize, $vColor, $sFam, $sStyle, $fTrack)
	Local $fWidth = _G_TrackWidth($sText, $iSize, $sFam, $sStyle, $fTrack)
	_G_Tracked(($g_PageW - $fWidth) / 2, $fY, $sText, $iSize, $vColor, $sFam, $sStyle, $fTrack)
EndFunc

Func _G_TrackedRight($fRight, $fY, $sText, $iSize, $vColor, $sFam, $sStyle, $fTrack)
	Local $fWidth = _G_TrackWidth($sText, $iSize, $sFam, $sStyle, $fTrack)
	_G_Tracked($fRight - $fWidth, $fY, $sText, $iSize, $vColor, $sFam, $sStyle, $fTrack)
EndFunc

Func _G_Rule($fY, $vColor = $G_RULE, $fWidth = 0.6, $fX1 = -1, $fX2 = -1)
	If $fX1 < 0 Then $fX1 = $g_X
	If $fX2 < 0 Then $fX2 = $g_X + $g_W
	_PDFX_SetStroke($g_Doc, $vColor)
	_PDFX_SetLineWidth($g_Doc, $fWidth)
	_PDFX_Line($g_Doc, $fX1, $fY, $fX2, $fY)
EndFunc

; ================================================================== page chrome
Func _G_Chrome()
	Local $iPage = _PDFX_PageCount($g_Doc)
	Local $fRight = $g_PageW - $g_X

	_PDFX_SetFill($g_Doc, $G_PAPER)
	_PDFX_Rect($g_Doc, 0, 0, $g_PageW, $g_PageH, $PDFX_FILL)

	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_RoundRect($g_Doc, $g_X, 28, 17, 17, 4, $PDFX_FILL)
	_G_TextCentre($g_X, 31.4, 17, "W", 9, 0xFFF8EA, "Helvetica", "B")
	_G_Tracked($g_X + 25, 31.4, "WEBVIEW2", 7.4, $G_INK, "Helvetica", "B", 0.9)

	_G_TrackedCentre(31.8, "DEVELOPER GUIDE", 7.1, $G_MUTED, "Helvetica", "B", 1.5)

	If $g_Section <> "" Then _G_TrackedRight($fRight, 31.8, $g_Section, 7.1, $G_TERRA, "Helvetica", "B", 1.2)

	_G_Rule(52, $G_RULE, 0.6)

	_G_Rule(800, $G_RULE, 0.6)
	_G_Tracked($g_X, 806, "NUMERIC1", 7, $G_MUTED, "Helvetica", "B", 0.9)
	_G_Text($g_X + 47, 806, "WebView2 0.3  -  MIT", 7.2, $G_MUTED)
	Local $sPage = StringFormat("%02d", $iPage)
	If $g_Total > 0 Then $sPage &= "  /  " & StringFormat("%02d", $g_Total)
	_G_TrackedRight($fRight, 805.6, $sPage, 7.6, $G_TERRA, "Helvetica", "B", 0.8)
EndFunc

Func _G_NewPage()
	_PDFX_AddPage($g_Doc)
	_G_Chrome()
	$g_Y = $g_Top
EndFunc

Func _G_Ensure($fNeed)
	If $g_Y + $fNeed > $g_Bottom Then _G_NewPage()
EndFunc

; ================================================================== blocks
Func _G_P($sText, $iSize = 9.6, $fLeading = 14.2, $vColor = $G_BODY, $fIndent = 0, $sStyle = "", $sFam = "Helvetica")
	Local $aLines = _G_Wrap($sText, $g_W - $fIndent, $g_W - $fIndent, $iSize, $sFam, $sStyle)
	For $iLine = 0 To UBound($aLines) - 1
		If $g_Y + $fLeading > $g_Bottom Then _G_NewPage()
		_G_Text($g_X + $fIndent, $g_Y, $aLines[$iLine], $iSize, $vColor, $sFam, $sStyle)
		$g_Y += $fLeading
	Next
	$g_Y += 6
EndFunc

; Paragraph in a fixed column, independent of the flow cursor; returns the next y.
Func _G_Para($fX, $fY, $fWidth, $sText, $iSize, $fLeading, $vColor = $G_BODY, $sStyle = "", $sFam = "Helvetica")
	Local $aLines = _G_Wrap($sText, $fWidth, $fWidth, $iSize, $sFam, $sStyle)
	For $iLine = 0 To UBound($aLines) - 1
		_G_Text($fX, $fY, $aLines[$iLine], $iSize, $vColor, $sFam, $sStyle)
		$fY += $fLeading
	Next
	Return $fY
EndFunc

Func _G_Badge($fX, $fY, $fSize, $sText)
	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_RoundRect($g_Doc, $fX, $fY, $fSize, $fSize, 7, $PDFX_FILL)
	_G_TextCentre($fX, $fY + ($fSize - $fSize * 0.42 * 0.72) / 2, $fSize, $sText, $fSize * 0.42, 0xFFF8EA, "Helvetica", "B")
EndFunc

Func _G_Chapter($sNum, $sSection, $sEyebrow, $sTitle, $sDeck)
	_PDFX_AddPage($g_Doc)
	$g_Section = $sNum & "  -  " & $sSection
	_G_Chrome()
	$g_Y = 78
	$g_Ch += 1

	_G_Badge($g_X, $g_Y - 2, 31, $sNum)
	_G_Tracked($g_X + 46, $g_Y + 2, $sEyebrow, 7.2, $G_TERRA, "Helvetica", "B", 1.7)

	Local $iSize = 26
	While $iSize > 19 And _G_W($sTitle, $iSize, "Helvetica", "B") > $g_W - 46
		$iSize -= 1
	WEnd
	_G_Text($g_X + 46, $g_Y + 15, $sTitle, $iSize, $G_INK, "Helvetica", "B")
	If $g_Pass = 1 Then
		$g_PageNo[$g_Ch] = _PDFX_PageCount($g_Doc)
		$g_ChapterY[$g_Ch] = $g_Y
	EndIf
	_PDFX_AddBookmark($g_Doc, $sTitle, 0, _PDFX_PageCount($g_Doc), $g_Y)

	$g_Y += 15 + $iSize * 1.12 + 8
	If $sDeck <> "" Then _G_P($sDeck, 10.4, 15.4, 0x5B4C3D, 46)
	$g_Y += 2
EndFunc

Func _G_H2($sTitle, $bBookmark = True)
	_G_Ensure(96)
	$g_Y += 9
	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_Rect($g_Doc, $g_X, $g_Y + 4, 4.2, 4.2, $PDFX_FILL)
	_G_Text($g_X + 11, $g_Y, $sTitle, 13.4, $G_INK, "Helvetica", "B")
	If $bBookmark Then _PDFX_AddBookmark($g_Doc, $sTitle, 1, _PDFX_PageCount($g_Doc), $g_Y)
	$g_Y += 18
	_G_Rule($g_Y, 0xEADCC6, 0.5, $g_X + 11, $g_X + $g_W)
	$g_Y += 8
EndFunc

Func _G_H3($sTitle, $bBookmark = False)
	_G_Ensure(64)
	$g_Y += 5
	_G_Text($g_X, $g_Y, $sTitle, 10.2, $G_TERRA_D, "Helvetica", "B")
	If $bBookmark Then _PDFX_AddBookmark($g_Doc, $sTitle, 2, _PDFX_PageCount($g_Doc), $g_Y)
	$g_Y += 15
EndFunc

; Items are "Lead|rest" or "rest".
Func _G_Bullets($aItems, $iSize = 9.5, $fLeading = 13.8)
	For $iItem = 0 To UBound($aItems) - 1
		Local $sLead = ""
		Local $sRest = $aItems[$iItem]
		Local $iBar = StringInStr($sRest, "|")
		If $iBar > 0 Then
			$sLead = StringLeft($sRest, $iBar - 1)
			$sRest = StringMid($sRest, $iBar + 1)
		EndIf
		Local $fLeadW = 0
		If $sLead <> "" Then $fLeadW = _G_W($sLead & "  ", $iSize, "Helvetica", "B")
		Local $aLines = _G_Wrap($sRest, $g_W - 12 - $fLeadW, $g_W - 12, $iSize)
		If $g_Y + $fLeading > $g_Bottom Then _G_NewPage()
		_PDFX_SetFill($g_Doc, $G_TERRA)
		_PDFX_Circle($g_Doc, $g_X + 3.2, $g_Y + 4.6, 1.3, $PDFX_FILL)
		If $sLead <> "" Then _G_Text($g_X + 12, $g_Y, $sLead, $iSize, $G_INK, "Helvetica", "B")
		For $iLine = 0 To UBound($aLines) - 1
			If $g_Y + $fLeading > $g_Bottom Then _G_NewPage()
			Local $fOff = 12
			If $iLine = 0 Then $fOff += $fLeadW
			_G_Text($g_X + $fOff, $g_Y, $aLines[$iLine], $iSize, $G_BODY)
			$g_Y += $fLeading
		Next
		$g_Y += 3
	Next
	$g_Y += 4
EndFunc

Func _G_Steps($aItems, $iSize = 9.5, $fLeading = 13.8)
	For $iItem = 0 To UBound($aItems) - 1
		Local $sLead = ""
		Local $sRest = $aItems[$iItem]
		Local $iBar = StringInStr($sRest, "|")
		If $iBar > 0 Then
			$sLead = StringLeft($sRest, $iBar - 1)
			$sRest = StringMid($sRest, $iBar + 1)
		EndIf
		Local $fLeadW = 0
		If $sLead <> "" Then $fLeadW = _G_W($sLead & "  ", $iSize, "Helvetica", "B")
		Local $aLines = _G_Wrap($sRest, $g_W - 20 - $fLeadW, $g_W - 20, $iSize)
		If $g_Y + $fLeading > $g_Bottom Then _G_NewPage()

		_PDFX_SetFill($g_Doc, $G_SAND)
		_PDFX_Circle($g_Doc, $g_X + 8, $g_Y + 5, 7.6, $PDFX_FILL)
		_G_TextCentre($g_X + 0.4, $g_Y + 2.2, 15.2, String($iItem + 1), 7.6, $G_TERRA_D, "Helvetica", "B")

		If $sLead <> "" Then _G_Text($g_X + 20, $g_Y, $sLead, $iSize, $G_INK, "Helvetica", "B")
		For $iLine = 0 To UBound($aLines) - 1
			If $g_Y + $fLeading > $g_Bottom Then _G_NewPage()
			Local $fOff = 20
			If $iLine = 0 Then $fOff += $fLeadW
			_G_Text($g_X + $fOff, $g_Y, $aLines[$iLine], $iSize, $G_BODY)
			$g_Y += $fLeading
		Next
		$g_Y += 3
	Next
	$g_Y += 4
EndFunc

Func _G_Code($sCode, $sCaption = "")
	Local $sNorm = StringReplace(StringReplace($sCode, @CRLF, @LF), @CR, @LF)
	$sNorm = StringReplace($sNorm, @TAB, "    ")
	Local $aLines = StringSplit($sNorm, @LF, 2)
	Local $fLead = 10.4
	Local $fSize = 7.5
	Local $iStart = 0

	While $iStart < UBound($aLines)
		Local $fAvailable = $g_Bottom - $g_Y - 14
		Local $iFit = Int(($fAvailable - 18) / $fLead)
		If $iFit < 5 Then
			_G_NewPage()
			ContinueLoop
		EndIf
		Local $iCount = UBound($aLines) - $iStart
		If $iCount > $iFit Then $iCount = $iFit
		Local $fHeight = $iCount * $fLead + 16

		_PDFX_SetFill($g_Doc, $G_CODEBG)
		_PDFX_RoundRect($g_Doc, $g_X, $g_Y, $g_W, $fHeight, 6, $PDFX_FILL)
		_PDFX_SetFill($g_Doc, $G_TERRA)
		_PDFX_Rect($g_Doc, $g_X + 10, $g_Y + 6, 1.6, $fHeight - 12, $PDFX_FILL)

		_PDFX_SetFont($g_Doc, "Courier", $fSize)
		_PDFX_SetFill($g_Doc, $G_CODETXT)
		For $iLine = 0 To $iCount - 1
			_PDFX_Text($g_Doc, $g_X + 18, $g_Y + 8 + $iLine * $fLead, $aLines[$iStart + $iLine], $fSize)
		Next

		$g_Y += $fHeight + 5
		$iStart += $iCount
		If $iStart < UBound($aLines) Then _G_NewPage()
	WEnd
	If $sCaption <> "" Then
		_G_P($sCaption, 7.8, 11.4, $G_MUTED, 0, "I")
	Else
		$g_Y += 4
	EndIf
EndFunc

Func _G_Note($sTitle, $sText, $sKind = "note")
	Local $vBg = $G_SAND
	Local $vBar = $G_TERRA
	Local $vTitle = $G_TERRA_D
	If $sKind = "warn" Then
		$vBg = $G_WARNBG
		$vBar = $G_WARN
		$vTitle = $G_WARN
	EndIf
	Local $aLines = _G_Wrap($sText, $g_W - 30, $g_W - 30, 8.9)
	Local $fHeight = 24 + UBound($aLines) * 12.2 + 8
	_G_Ensure($fHeight + 10)

	_PDFX_SetFill($g_Doc, $vBg)
	_PDFX_RoundRect($g_Doc, $g_X, $g_Y, $g_W, $fHeight, 5, $PDFX_FILL)
	_PDFX_SetFill($g_Doc, $vBar)
	_PDFX_Rect($g_Doc, $g_X, $g_Y + 5, 3.6, $fHeight - 10, $PDFX_FILL)

	_G_Tracked($g_X + 13, $g_Y + 9, StringUpper($sTitle), 6.9, $vTitle, "Helvetica", "B", 1.1)
	_PDFX_SetFont($g_Doc, "Helvetica", 8.9)
	_PDFX_SetFill($g_Doc, 0x3F3529)
	For $iLine = 0 To UBound($aLines) - 1
		_PDFX_Text($g_Doc, $g_X + 13, $g_Y + 21 + $iLine * 12.2, $aLines[$iLine], 8.9)
	Next
	$g_Y += $fHeight + 12
EndFunc

; ================================================================== tables
; A table that does not fit is cut between two rows and continues on the next
; page with its header band repeated, so a section heading never ends a page
; without the rows it introduces.
Func _G_Table($aCols, $aRows, $fFontSize = 8.3, $bBoldFirst = False)
	Local $iCols = UBound($aCols)
	Local $iRows = UBound($aRows)
	Local $fPad = 7.5
	Local $aWidths[$iCols]
	Local $fTotal = 0
	Local $i, $j

	For $i = 0 To $iCols - 1
		$fTotal += Number($aCols[$i][1])
	Next
	For $i = 0 To $iCols - 1
		$aWidths[$i] = Number($aCols[$i][1]) / $fTotal * $g_W
	Next

	Local $fHead = 21
	Local $aHeights[$iRows]
	For $i = 0 To $iRows - 1
		Local $iMaxLines = 1
		For $j = 0 To $iCols - 1
			Local $sStyle = ""
			If $bBoldFirst And $j = 0 Then $sStyle = "B"
			Local $aLines = _G_Wrap(String($aRows[$i][$j]), $aWidths[$j] - 2 * $fPad, $aWidths[$j] - 2 * $fPad, $fFontSize, "Helvetica", $sStyle)
			If UBound($aLines) > $iMaxLines Then $iMaxLines = UBound($aLines)
		Next
		$aHeights[$i] = $iMaxLines * ($fFontSize * 1.34) + 11
	Next

	_G_Ensure($fHead + $aHeights[0] + 10)
	Local $iFrom = 0
	While $iFrom < $iRows
		Local $iTo = $iFrom
		Local $fBlockH = $fHead
		While $iTo < $iRows And $g_Y + $fBlockH + $aHeights[$iTo] <= $g_Bottom
			$fBlockH += $aHeights[$iTo]
			$iTo += 1
		WEnd
		If $iTo = $iFrom Then
			$iTo = $iFrom + 1
			$fBlockH += $aHeights[$iFrom]
		EndIf
		_G_TableBlock($aCols, $aRows, $aWidths, $aHeights, $fFontSize, $bBoldFirst, $fPad, $iFrom, $iTo, $iTo = $iRows, $fHead, $fBlockH)
		$g_Y += $fBlockH
		$iFrom = $iTo
		If $iFrom < $iRows Then _G_NewPage()
	WEnd

	$g_Y += 15
EndFunc

Func _G_TableBlock($aCols, $aRows, $aWidths, $aHeights, $fFontSize, $bBoldFirst, $fPad, $iFrom, $iTo, $bLast, $fHead, $fBlockH)
	Local $iCols = UBound($aCols)
	Local $i, $j, $k

	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_RoundRect($g_Doc, $g_X, $g_Y, $g_W, $fHead + 5, 6, $PDFX_FILL)
	_PDFX_Rect($g_Doc, $g_X, $g_Y + $fHead - 1, $g_W, 6, $PDFX_FILL)
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $g_X, $g_Y, $g_W, $fBlockH, 6, $PDFX_STROKE)

	Local $fY = $g_Y
	Local $fColX = $g_X
	For $j = 0 To $iCols - 1
		Local $sHead = StringUpper(String($aCols[$j][0]))
		Local $sAlign = "L"
		If UBound($aCols, 2) >= 3 Then $sAlign = StringUpper(String($aCols[$j][2]))
		Local $fHeadW = _G_TrackWidth($sHead, 6.9, "Helvetica", "B", 0.7)
		If $sAlign = "R" Then
			_G_Tracked($fColX + $aWidths[$j] - $fPad - $fHeadW, $fY + 7, $sHead, 6.9, $G_TERRA_D, "Helvetica", "B", 0.7)
		Else
			_G_Tracked($fColX + $fPad, $fY + 7, $sHead, 6.9, $G_TERRA_D, "Helvetica", "B", 0.7)
		EndIf
		$fColX += $aWidths[$j]
	Next

	$fY += $fHead
	For $i = $iFrom To $iTo - 1
		Local $fCol = $g_X
		For $j = 0 To $iCols - 1
			Local $sRowStyle = ""
			If $bBoldFirst And $j = 0 Then $sRowStyle = "B"
			Local $aCell = _G_Wrap(String($aRows[$i][$j]), $aWidths[$j] - 2 * $fPad, $aWidths[$j] - 2 * $fPad, $fFontSize, "Helvetica", $sRowStyle)
			Local $sColAlign = "L"
			If UBound($aCols, 2) >= 3 Then $sColAlign = StringUpper(String($aCols[$j][2]))
			_PDFX_SetFont($g_Doc, "Helvetica", $fFontSize, $sRowStyle)
			_PDFX_SetFill($g_Doc, $G_BODY)
			For $k = 0 To UBound($aCell) - 1
				If $sColAlign = "R" Then
					_PDFX_TextAlign($g_Doc, $fCol + $fPad, $fY + 5.5 + $k * ($fFontSize * 1.34), $aWidths[$j] - 2 * $fPad, $aCell[$k], "R", $fFontSize)
				Else
					_PDFX_Text($g_Doc, $fCol + $fPad, $fY + 5.5 + $k * ($fFontSize * 1.34), $aCell[$k], $fFontSize)
				EndIf
			Next
			$fCol += $aWidths[$j]
		Next
		$fY += $aHeights[$i]
		If Not ($bLast And $i = $iTo - 1) Then _G_Rule($fY, 0xE8DAC4, 0.45, $g_X + 6, $g_X + $g_W - 6)
	Next
EndFunc

; ================================================================== figures
Func _G_FigCard($fHeight)
	_G_Ensure($fHeight + 30)
	_PDFX_SetFill($g_Doc, $G_PANEL)
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $g_X, $g_Y, $g_W, $fHeight, 7, $PDFX_BOTH)
	$g_FigTop = $g_Y
	$g_Y += $fHeight
	$g_FigNo += 1
EndFunc

Func _G_FigCaption($sCaption)
	Local $sLabel = "Figure " & $g_FigNo & "."
	Local $fLabelW = _G_W($sLabel & "  ", 7.6, "Helvetica", "B")
	Local $aLines = _G_Wrap($sCaption, $g_W - $fLabelW, $g_W, 7.8, "Helvetica", "I")
	$g_Y += 7
	_G_Text($g_X, $g_Y, $sLabel, 7.6, $G_TERRA, "Helvetica", "B")
	For $iLine = 0 To UBound($aLines) - 1
		Local $fOff = 0
		If $iLine = 0 Then $fOff = $fLabelW
		_G_Text($g_X + $fOff, $g_Y, $aLines[$iLine], 7.8, $G_MUTED, "Helvetica", "I")
		$g_Y += 11
	Next
	$g_Y += 9
EndFunc

Func _G_Box($fX, $fY, $fWidth, $fHeight, $sLabel, $sSub, $vFill = $G_SAND, $vStroke = $G_SAND_D, $vText = $G_INK, $iSize = 8.3)
	_PDFX_SetFill($g_Doc, $vFill)
	_PDFX_SetStroke($g_Doc, $vStroke)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $fX, $fY, $fWidth, $fHeight, 5, $PDFX_BOTH)
	If $sSub = "" Then
		_G_TextCentre($fX, $fY + ($fHeight - $iSize * 0.72) / 2, $fWidth, $sLabel, $iSize, $vText, "Helvetica", "B")
	Else
		_G_TextCentre($fX, $fY + $fHeight / 2 - 9, $fWidth, $sLabel, $iSize, $vText, "Helvetica", "B")
		_G_TextCentre($fX, $fY + $fHeight / 2 + 1.5, $fWidth, $sSub, 7, $G_MUTED)
	EndIf
EndFunc

Func _G_ArrowR($fX1, $fY, $fX2, $vColor = $G_TERRA, $fW = 1.1)
	_PDFX_SetStroke($g_Doc, $vColor)
	_PDFX_SetLineWidth($g_Doc, $fW)
	_PDFX_Line($g_Doc, $fX1, $fY, $fX2 - 2, $fY)
	_PDFX_Line($g_Doc, $fX2 - 6, $fY - 3, $fX2, $fY)
	_PDFX_Line($g_Doc, $fX2 - 6, $fY + 3, $fX2, $fY)
EndFunc

Func _G_ArrowD($fX, $fY1, $fY2, $vColor = $G_TERRA, $fW = 1.1)
	_PDFX_SetStroke($g_Doc, $vColor)
	_PDFX_SetLineWidth($g_Doc, $fW)
	_PDFX_Line($g_Doc, $fX, $fY1, $fX, $fY2 - 2)
	_PDFX_Line($g_Doc, $fX - 3, $fY2 - 6, $fX, $fY2)
	_PDFX_Line($g_Doc, $fX + 3, $fY2 - 6, $fX, $fY2)
EndFunc

Func _G_TriDown($fX, $fY, $vColor = $G_TERRA)
	Local $aPoints[3][2] = [[$fX - 3.5, $fY], [$fX + 3.5, $fY], [$fX, $fY + 4.5]]
	_PDFX_SetFill($g_Doc, $vColor)
	_PDFX_Polyline($g_Doc, $aPoints, True, $PDFX_FILL)
EndFunc

; ================================================================== cover
Func _G_Cover()
	Local $fPanel = 372
	Local $fRightX = 388
	Local $fRightW = $g_X + $g_W - $fRightX

	_PDFX_SetFill($g_Doc, $G_PAPER)
	_PDFX_Rect($g_Doc, 0, 0, $g_PageW, $g_PageH, $PDFX_FILL)

	; left terracotta panel with a faint 24 pt grid
	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_Rect($g_Doc, 0, 0, $fPanel, $g_PageH, $PDFX_FILL)
	_PDFX_SetAlpha($g_Doc, 0.33, 0.33)
	_PDFX_SetStroke($g_Doc, 0x6E2F10)
	_PDFX_SetLineWidth($g_Doc, 0.4)
	Local $i
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

	_G_Tracked(48, 118, "AUTOIT UDF  -  DEVELOPER GUIDE", 7.6, 0xF2CFA2, "Helvetica", "B", 1.9)

	_G_Text(48, 144, "WebView2", 50, 0x35190A, "Helvetica", "B")
	_G_Text(48, 198, "developer guide", 36, 0xFBE9CA, "Helvetica", "B")

	_PDFX_SetStroke($g_Doc, 0xF0C795)
	_PDFX_SetLineWidth($g_Doc, 1.2)
	_PDFX_Line($g_Doc, 48, 252, 138, 252)

	_G_Para(48, 268, 276, "Chromium inside an AutoIt window, with no file to ship: the COM model, " & _
			"the ABI traps and the diagnostics, explained from the source.", 10.4, 14.6, 0xF7E0BE)
	$g_Y = 300

	; chips
	_G_Chip(48, 350, "AutoIt 3.3.16+")
	_G_Chip(48 + _G_ChipWidth("AutoIt 3.3.16+") + 8, 350, "No loader to ship")
	_G_Chip(48, 374, "40 functions")
	_G_Chip(48 + _G_ChipWidth("40 functions") + 8, 374, "111 checks")
	_G_Chip(48 + _G_ChipWidth("40 functions") + _G_ChipWidth("111 checks") + 16, 374, "14 handlers")

	; code card
	_PDFX_SetFill($g_Doc, 0x2E2116)
	_PDFX_RoundRect($g_Doc, 48, 414, 276, 92, 7, $PDFX_FILL)
	Local $aCode[7] = [ _
			'#include "WebView2.au3"', _
			'', _
			'Local $hView = _WV2_Create($hGui)', _
			'_WV2_Navigate($hView, "https://example.com")', _
			'_WV2_WaitNavigation($hView)', _
			'', _
			'Local $sTitle = _WV2_ExecuteScript($hView, "document.title")']
	_PDFX_SetFont($g_Doc, "Courier", 7)
	_PDFX_SetFill($g_Doc, 0xF1E2C9)
	For $i = 0 To 6
		_PDFX_Text($g_Doc, 60, 424 + $i * 9.8, $aCode[$i], 7)
	Next

	_G_Text(48, 520, "One .au3 file. No DLL, no OCX, no installer.", 9.4, 0xFBE9CA, "Helvetica", "I")
	_G_Tracked(48, 536, "THE WHOLE DEPENDENCY LIST", 6.6, 0xE8BA8C, "Helvetica", "B", 1.4)

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
	_G_Tracked($fRightX, 62, "THE STACK", 7, $G_TERRA, "Helvetica", "B", 1.3)

	_G_Box($fRightX, 80, $fRightW, 44, "AutoIt script", "GUI or --auto suite", $G_WHITE, $G_RULE)
	_G_TriDown($fRightX + $fRightW / 2, 127)
	_G_Box($fRightX, 136, $fRightW, 44, "WebView2.au3", "40 functions, pure AutoIt", $G_WHITE, $G_RULE)
	_G_TriDown($fRightX + $fRightW / 2, 183)
	_G_Box($fRightX, 192, $fRightW, 44, "EmbeddedBrowserWebView.dll", "part of Windows", $G_WHITE, $G_RULE)
	_G_TriDown($fRightX + $fRightW / 2, 239)
	_G_Box($fRightX, 248, $fRightW, 44, "Edge WebView2 runtime", "already installed", $G_WHITE, $G_RULE)

	_G_Tracked($fRightX, 322, "BY THE NUMBERS", 7, $G_TERRA, "Helvetica", "B", 1.3)
	Local $aNum[5][2] = [ _
			["public functions", "40"], _
			["self-test checks", "111"], _
			["handler slots", "14"], _
			["concurrent views", "16"], _
			["files to ship", "0"]]
	For $i = 0 To 4
		Local $fRowY = 338 + $i * 21
		_G_Text($fRightX, $fRowY + 3, $aNum[$i][0], 7.8, $G_MUTED)
		_G_TextAlignRight($fRightX + $fRightW, $fRowY, $aNum[$i][1], 10.6, $G_TERRA, "Helvetica", "B")
		_G_Rule($fRowY + 16, 0xEADCC6, 0.45, $fRightX, $fRightX + $fRightW)
	Next

	_G_Para($fRightX, 500, $fRightW, "The runtime is already on the machine. This package ships no browser, " & _
			"no DLL, no installer: one include, and the engine Windows carries.", 8.2, 12, 0x6A5A48, "I")

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

Func _G_ChipWidth($sText)
	Return _G_W($sText, 8.2, "Helvetica", "") + 16
EndFunc

Func _G_Chip($fX, $fY, $sText)
	Local $fWidth = _G_ChipWidth($sText)
	_PDFX_SetStroke($g_Doc, 0xE8BE90)
	_PDFX_SetLineWidth($g_Doc, 0.8)
	_PDFX_RoundRect($g_Doc, $fX, $fY, $fWidth, 17, 8.5, $PDFX_STROKE)
	_G_Text($fX + 8, $fY + 4.4, $sText, 8.2, 0xFBE9CA)
EndFunc

Func _G_TextAlignRight($fRight, $fY, $sText, $iSize, $vColor, $sFam, $sStyle)
	Local $fWidth = _G_W($sText, $iSize, $sFam, $sStyle)
	_G_Text($fRight - $fWidth, $fY, $sText, $iSize, $vColor, $sFam, $sStyle)
EndFunc

; ================================================================== contents
Func _G_Toc()
	_PDFX_AddPage($g_Doc)
	$g_Section = "CONTENTS"
	_G_Chrome()
	$g_Y = 74

	_G_Tracked($g_X, $g_Y, "HOW TO USE THIS DOCUMENT", 7.2, $G_TERRA, "Helvetica", "B", 1.8)
	_G_Text($g_X, 88, "Contents & bearings", 29, $G_INK, "Helvetica", "B")
	$g_Y = 122
	_G_P("Eight chapters. Read 1 to 4 to understand the machinery, 5 to 8 to change it " & _
			"without breaking what already works.", 9.6, 14, 0x5B4C3D)
	$g_Y = 146

	; left: chapter list
	Local $fListTop = 160
	Local $fStep = 46
	Local $iEntry, $iPage
	For $iEntry = 1 To 8
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

	_G_Text($g_X, 545, "Every entry is clickable; every heading is also a bookmark.", 7.8, $G_MUTED, "Helvetica", "I")

	; right column
	Local $fCX = 318
	Local $fCW = 229
	Local $fRY = $fListTop
	Local $i

	Local $aLines = _G_Wrap("One AutoIt file embeds the Edge engine that Windows already " & _
			"carries: 40 functions, no DLL, no OCX, no installer. This guide is its " & _
			"maintenance manual.", $fCW - 28, $fCW - 28, 8.2)
	Local $fCardH = 38 + UBound($aLines) * 11.4
	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_RoundRect($g_Doc, $fCX, $fRY, $fCW, $fCardH, 7, $PDFX_FILL)
	_G_Tracked($fCX + 14, $fRY + 12, "THE PACKAGE IN BRIEF", 6.6, $G_TERRA_D, "Helvetica", "B", 1.2)
	_PDFX_SetFont($g_Doc, "Helvetica", 8.2)
	_PDFX_SetFill($g_Doc, 0x4C4236)
	For $i = 0 To UBound($aLines) - 1
		_PDFX_Text($g_Doc, $fCX + 14, $fRY + 30 + $i * 11.4, $aLines[$i], 8.2)
	Next
	$fRY += $fCardH + 14

	Local $aTiles[4][2] = [ _
			["40", "PUBLIC FUNCTIONS|pure AutoIt, no loader"], _
			["111", "SELF-TEST CHECKS|no network, no leftovers"], _
			["14", "HANDLER SLOTS|one fake vtable each"], _
			["0", "FILES TO SHIP|nothing to register"]]
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
	Local $aPaths[3][2] = [["Understand the machinery", "01 - 02 - 03 - 04"], _
			["Extend the wrapper", "05 - 06"], _
			["Ship and maintain", "07 - 08"]]
	For $i = 0 To 2
		_G_Text($fCX + 14, $fRY + 30 + $i * 18, $aPaths[$i][0], 7.8, $G_BODY)
		_G_TextAlignRight($fCX + $fCW - 14, $fRY + 30 + $i * 18, $aPaths[$i][1], 7.2, $G_TERRA, "Courier", "")
	Next
	$fRY += 90 + 20

	_PDFX_SetFill($g_Doc, $G_TERRA)
	_PDFX_Rect($g_Doc, $fCX, $fRY + 2, 3.4, 3.4, $PDFX_FILL)
	_G_Text($fCX + 10, $fRY, "What this document is not", 9, $G_INK, "Helvetica", "B")
	Local $aLines2 = _G_Wrap("Neither an API reference nor a beginner's tutorial. It is the maintenance " & _
			"manual of the UDF: the machinery, the traps, and the checks that keep both honest.", $fCW, $fCW, 7.8)
	_PDFX_SetFont($g_Doc, "Helvetica", 7.8)
	_PDFX_SetFill($g_Doc, $G_BODY)
	For $i = 0 To UBound($aLines2) - 1
		_PDFX_Text($g_Doc, $fCX, $fRY + 15 + $i * 10.8, $aLines2[$i], 7.8)
	Next

	; three rules strip
	_PDFX_SetFill($g_Doc, $G_WHITE)
	_PDFX_SetStroke($g_Doc, $G_RULE)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $g_X, 640, $g_W, 92, 8, $PDFX_BOTH)
	_G_Tracked($g_X + 16, 654, "THREE RULES", 6.6, $G_TERRA, "Helvetica", "B", 1.3)
	_G_Text($g_X + 94, 651, "before touching the code", 10, $G_INK, "Helvetica", "B")

	Local $aRules[3][2] = [ _
			["Measure, do not assume|The header says by value; the 64-bit wire says pointer. Test the shape, then read the effect."], _
			["The header is the fact|Slot numbers come from WebView2.h, never from memory or a summary page."], _
			["hr = 0 is not proof|S_OK says the call arrived. Find an observable consequence before believing it."]]
	For $i = 0 To 2
		Local $fRX = $g_X + 16 + $i * 158
		_PDFX_SetFill($g_Doc, $G_SAND)
		_PDFX_Circle($g_Doc, $fRX + 7, 682, 7, $PDFX_FILL)
		_G_TextCentre($fRX, 678.8, 14, String($i + 1), 7.2, $G_TERRA_D, "Helvetica", "B")
		Local $aRule = StringSplit($aRules[$i][0], "|", 2)
		_G_Text($fRX + 20, 675, $aRule[0], 7.8, $G_INK, "Helvetica", "B")
		Local $aRuleLines = _G_Wrap($aRule[1], 140, 140, 7.2)
		_PDFX_SetFont($g_Doc, "Helvetica", 7.2)
		_PDFX_SetFill($g_Doc, $G_BODY)
		Local $k
		For $k = 0 To UBound($aRuleLines) - 1
			_PDFX_Text($g_Doc, $fRX + 20, 687 + $k * 9.6, $aRuleLines[$k], 7.2)
		Next
	Next

	_PDFX_AddBookmark($g_Doc, "Contents", 0, 2, 74)
	$g_Y = $g_Bottom
EndFunc

; ================================================================== chapter 01
Func _G_Ch01()
	_G_Chapter("01", "THE COM MODEL", "THE MINIMAL COM MODEL", "The COM model in AutoIt", _
			"One pointer, one table of function pointers, and two ways to call them.")

	_G_P("Everything in this UDF rests on one fact: a COM interface pointer is the address of " & _
			"a pointer to a table of function pointers. Calling a method is calling table[slot] with " & _
			"the interface pointer as the first argument.")

	_G_FigCard(196)
	Local $t = $g_FigTop
	_G_Box($g_X + 22, $t + 58, 88, 40, "pInterface", "the object", $G_SAND, $G_SAND_D)
	_G_ArrowR($g_X + 114, $t + 78, $g_X + 152)
	_G_Box($g_X + 156, $t + 58, 88, 40, "pVTable", "its table", $G_SAND, $G_SAND_D)
	_G_ArrowR($g_X + 248, $t + 78, $g_X + 286)

	Local $x0 = $g_X + 300
	Local $y0 = $t + 34
	Local $aRows[5][1] = [ _
			["[0]  QueryInterface"], _
			["[1]  AddRef"], _
			["[2]  Release"], _
			["[3]  first method declared"], _
			["[4]  second method ..."]]
	_PDFX_SetFill($g_Doc, $G_WHITE)
	_PDFX_SetStroke($g_Doc, $G_SAND_D)
	_PDFX_SetLineWidth($g_Doc, 0.7)
	_PDFX_RoundRect($g_Doc, $x0, $y0, 176, 112, 5, $PDFX_BOTH)
	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_Rect($g_Doc, $x0 + 1, $y0 + 67, 174, 22, $PDFX_FILL)
	_PDFX_SetFont($g_Doc, "Courier", 7.4)
	_PDFX_SetFill($g_Doc, $G_BODY)
	For $i = 0 To 4
		_PDFX_Text($g_Doc, $x0 + 10, $y0 + 8 + $i * 22, $aRows[$i][0], 7.4)
	Next
	_G_Text($g_X + 22, $t + 112, "the object", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 156, $t + 112, "its vtable", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($x0, $t + 158, "one entry per method, in declaration order", 7, $G_MUTED, "Helvetica", "I")
	_PDFX_SetStroke($g_Doc, $G_TERRA)
	_PDFX_SetLineWidth($g_Doc, 0.9)
	_PDFX_Line($g_Doc, $g_X + 22, $t + 126, $g_X + 106, $t + 126)
	_PDFX_Line($g_Doc, $g_X + 156, $t + 126, $g_X + 240, $t + 126)
	_G_FigCaption("Two dereferences: the object points at a table, the table points at code. " & _
			"Slot 3 is the first real method; slots 0 to 2 are always QueryInterface, AddRef and Release.")

	_G_H2("Two ways to walk the table")
	_G_P("ObjCreateInterface($p, $sIID, $sTag, $bCreate) builds a wrapper object whose methods you " & _
			"call with normal AutoIt syntax. The tag lists the methods in vtable order, starting at " & _
			"slot 0. That is the pleasant path, and it is what the UDF uses for the interfaces it " & _
			"speaks to constantly:")

	_G_Code('$__WV2_oCtl[$i] = ObjCreateInterface($pCtl, $WV2_IID_CTL, $__WV2_TAG_CTL, False)' & @LF & _
			'; later, plain AutoIt:' & @LF & _
			'Local $hr = $__WV2_oCtl[$i].put_ZoomFactor($fZoom)')

	_G_P("The fourth argument is the one that matters most. With $bCreate = False the wrapper does " & _
			"not add a reference and does not own the pointer: it is a view of a reference somebody " & _
			"else holds. Every pointer the runtime hands to a callback is borrowed in exactly that " & _
			"way, which is why every wrapper here is built with False.")

	_G_P("DllCallAddress(""long"", $pFn, ""ptr"", $pObj, ...) calls a raw slot, with $pFn read out " & _
			"of the table:")

	_G_Code('Func __WV2_VtFn($pObj, $iSlot)' & @LF & _
			'    If $pObj = 0 Or $iSlot < 0 Then Return 0' & @LF & _
			'    If $__WV2_iPtrSize = 0 Then' & @LF & _
			'        $__WV2_iPtrSize = DllStructGetSize(DllStructCreate("ptr"))' & @LF & _
			'    Local $pVTable = DllStructGetData(DllStructCreate("ptr", $pObj), 1)' & @LF & _
			'    If @Error Or $pVTable = 0 Then Return 0' & @LF & _
			'    Local $pFn = DllStructGetData( _' & @LF & _
			'            DllStructCreate("ptr", $pVTable + $iSlot * $__WV2_iPtrSize), 1)' & @LF & _
			'    If @Error Or $pFn = 0 Then Return 0' & @LF & _
			'    Return $pFn' & @LF & _
			'EndFunc')

	_G_P("Reading a vtable is three lines: dereference the object, add slot times sizeof(pointer), " & _
			"read the entry. The UDF uses it for two jobs: methods that exist only on a newer version " & _
			"of an interface (chapters 3 and 5), and Release on pointers owned by the operating " & _
			"system, because wrapping those with ObjCreateInterface crashed the process in this build.")

	_G_H2("The environment is not created through COM")
	_G_P("There is no CoCreateInstance in this UDF. The environment is built by a plain export of " & _
			"the runtime's own DLL, called through DllCall:")

	_G_Code('Local $aCE = DllCall($sDll, "long", _' & @LF & _
			'        "CreateWebViewEnvironmentWithOptionsInternal", _' & @LF & _
			'        "bool", 1, "int", 0, "wstr", $sUserDataFolder, "ptr", 0, _' & @LF & _
			'        "ptr", $__WV2_pObj[$i][$__WV2_H_ENV])')

	_G_P("Five arguments: should the runtime create a feedback handler, an options word, the user " & _
			"data folder, a reserved pointer, and the address of the callback object that will receive " & _
			"the environment. This is the call the official WebView2Loader.dll makes on your behalf. " & _
			"Making it directly is what removes the last file from the distribution - and it is the " & _
			"one undocumented thing in the package. Only this line depends on it.")

	_G_H2("Anatomy of _WV2_Create")
	_G_P("Seven steps, in this order, and the order is not negotiable:")
	Local $aSteps[7] = [ _
			"Parent window|Validate it, then take a free slot (1 to 16).", _
			"Runtime|Locate it: the registry key Microsoft\EdgeUpdate\Clients\{F3017226-...}, then EdgeWebView\Application. Bitness matters: a 32-bit AutoIt loads the 32-bit DLL.", _
			"Apartment|CoInitializeEx(NULL, COINIT_APARTMENTTHREADED), once per script. The UDF never calls CoUninitialize, so a COM-aware script keeps working after a view is destroyed.", _
			"Handlers|Build the fourteen handler objects of the slot (chapter 2).", _
			"Environment|Call CreateWebViewEnvironmentWithOptionsInternal and pump until the environment callback answers, with a 15 s default timeout.", _
			"Controller|The environment callback immediately asks for a controller, which arrives as a second callback; the controller is wrapped, put_Bounds and put_IsVisible(1) are sent.", _
			"Ready|Subscribe NavigationCompleted, read the browser version, mark the handle ready."]
	_G_Steps($aSteps)

	_G_P("If any step fails, __WV2_Fail tears down whatever exists, the slot returns to the table, " & _
			"and _WV2_Create returns 0 with @error and @extended set. Nothing is left half-alive.")
EndFunc

; ================================================================== chapter 02
Func _G_Ch02()
	_G_Chapter("02", "HANDLER OBJECTS", "FAKE VTABLES IN MEMORY", "Handler objects in a global heap", _
			"The runtime does not pull events: it calls back. AutoIt has to grow an object.")

	_G_P("The runtime calls an ICoreWebView2XxxEventHandler whose only real method is Invoke. " & _
			"AutoIt cannot create a COM object, so the UDF manufactures one out of memory: one block " & _
			"of five pointers per instance and per slot.")

	_G_FigCard(198)
	Local $t = $g_FigTop
	Local $aCells[5][3] = [ _
			["QI", "offset 0"], _
			["AddRef", "1 ptr"], _
			["Release", "2 ptr"], _
			["Invoke", "3 ptr"], _
			["-> vtable", "4 ptr"]]
	Local $fCellW = 78
	Local $fGap = 8
	Local $fStartX = $g_X + 34
	For $i = 0 To 4
		Local $fCX = $fStartX + $i * ($fCellW + $fGap)
		_G_Box($fCX, $t + 50, $fCellW, 46, $aCells[$i][0], "", $G_SAND, $G_SAND_D)
		_G_Text($fCX + 6, $t + 33, $aCells[$i][1], 6.6, $G_MUTED, "Courier", "")
	Next
	_PDFX_SetStroke($g_Doc, $G_TERRA)
	_PDFX_SetLineWidth($g_Doc, 0.9)
	_PDFX_Line($g_Doc, $fStartX, $t + 108, $fStartX + 5 * ($fCellW + $fGap) - $fGap, $t + 108)
	_G_Text($g_X + 34, $t + 118, "16 instances x 14 slots x 5 pointers = 1120 pointers, in one global DllStruct", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 34, $t + 150, "object address = block + 4 pointers", 7.8, $G_TERRA_D, "Courier", "B")
	_G_FigCaption("The object is the last cell; its one field points back at the first, which is the " & _
			"vtable. That is exactly the layout COM expects, built with DllStructSetData.")

	_G_P("The object address is block + 4 pointers. Its first field points at the vtable that begins " & _
			"at block, which is exactly what COM expects. __WV2_BuildHandler writes the five entries:")

	_G_Code('Func __WV2_BuildHandler($i, $iSlot)' & @LF & _
			'    Local $b = __WV2_BlockBase($i, $iSlot)' & @LF & _
			'    DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbQI), $b + 1)' & @LF & _
			'    DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbAddRef), $b + 2)' & @LF & _
			'    DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbRelease), $b + 3)' & @LF & _
			'    DllStructSetData($__WV2_tHeap, "data", _' & @LF & _
			'            DllCallbackGetPtr($__WV2_hCbInv[$iSlot]), $b + 4)' & @LF & _
			'    Local $pBase = DllStructGetPtr($__WV2_tHeap)' & @LF & _
			'    DllStructSetData($__WV2_tHeap, "data", $pBase + $b * $__WV2_iPtrSize, $b + 5)' & @LF & _
			'    $__WV2_pObj[$i][$iSlot] = $pBase + ($b + 4) * $__WV2_iPtrSize' & @LF & _
			'EndFunc')

	_G_Note("Why a global struct", "One global DllStruct owns all the memory: 1120 pointers, allocated once on " & _
			"first use and never resized. A global struct has no copy semantics, so the addresses stay " & _
			"valid for the life of the script - a callback running while AutoIt reallocated a local " & _
			"array would be a use-after-free waiting to happen.")

	_G_H2("One callback set, fourteen entry points")
	_G_P("There is no per-instance AutoIt function. There is one QueryInterface, one AddRef, one " & _
			"Release and one Invoke per slot, registered once with DllCallbackRegister. The Invoke " & _
			"receives $pThis, and __WV2_FindInst maps that pointer back to (instance, slot):")

	_G_Code('Func __WV2_FindInst($pThis)' & @LF & _
			'    Local $i, $j' & @LF & _
			'    For $i = 1 To $__WV2_MAX' & @LF & _
			'        If $__WV2_aUsed[$i] Then' & @LF & _
			'            For $j = 1 To $__WV2_SLOT_COUNT' & @LF & _
			'                If $__WV2_pObj[$i][$j] = $pThis Then Return SetError(0, $j, $i)' & @LF & _
			'            Next' & @LF & _
			'        EndIf' & @LF & _
			'    Next' & @LF & _
			'    Return SetError(1, 0, 0)' & @LF & _
			'EndFunc')

	_G_P("A linear scan of at most 224 comparisons, against a callback that fires on a user " & _
			"action: the cost is irrelevant, and it buys a completely uniform callback set. It also " & _
			"lets the Invoke signatures differ per slot, because the argument list is registered from " & _
			"$__WV2_aInvArgs: a two-argument completion handler (this, hr) and a three-argument event " & _
			"handler (this, sender, args) live in the same block.")

	_G_H2("QueryInterface is a gate, not a formality")
	_G_P("Each slot answers for IUnknown and for the handler interface of its own slot, and nothing " & _
			"else. Claiming an interface whose vtable you do not carry is the fastest way to kill the " & _
			"process: the runtime would call Invoke at a slot your object does not have.")

	_G_Code('If $bKnown And ($sIID = $WV2_IID_UNKNOWN _' & @LF & _
			'        Or $sIID = $__WV2_aInvIID[$iSlot]) Then $pOut = $pThis' & @LF & _
			'DllStructSetData(DllStructCreate("ptr", $pPPV), 1, $pOut)' & @LF & _
			'If $pOut = 0 Then Return $__WV2_HR_E_NOINTERFACE' & @LF & _
			'Return 0')

	_G_P("AddRef returns 1 and Release returns 0, both without touching memory. These objects live " & _
			"in the UDF heap and are freed by __WV2_FreeHandlers, never by the runtime. The counters " & _
			"are deliberately meaningless: a fake object that released itself would dangle the moment " & _
			"the runtime kept a pointer. __WV2_FindInst failing is a normal outcome - a late callback " & _
			"after teardown - and every Invoke returns early in that case.")

	_G_H2("Subscribing: the token is the receipt")
	_G_P("add_Xxx(handler, ByRef token) returns an EventRegistrationToken (int64) that remove_Xxx " & _
			"needs. __WV2_Attach and __WV2_Detach keep one token per instance and slot and refuse to " & _
			"subscribe twice. The method name cannot be built at run time in AutoIt, so each slot gets " & _
			"its own Case: a little repetition standing in for a dispatch mechanism AutoIt does not " & _
			"have. NavigationCompleted is subscribed by _WV2_Create itself, because " & _
			"_WV2_WaitNavigation waits on it.")
EndFunc

; ================================================================== chapter 03
Func _G_Ch03()
	_G_Chapter("03", "VTABLE RANKS", "COUNTED FROM THE HEADER", "Vtable ranks and WebView2.h", _
			"Slot 3 is the first real method; everything after it is a count.")

	_G_H2("The numbering rule")
	_G_P("Slot 0 is QueryInterface, 1 is AddRef, 2 is Release. The first method an interface " & _
			"declares is at slot 3. A versioned interface inherits the whole chain: its first own " & _
			"method sits right after the last method of every earlier version.")

	_G_Code('slot(method) = 3 + number of methods declared before it in the chain')

	_G_FigCard(170)
	Local $t = $g_FigTop
	Local $aChain[4][2] = [ _
			["ICoreWebView2", "base interface"], _
			["ICoreWebView2_2", "+ cookie manager"], _
			["ICoreWebView2_4", "+ downloads"], _
			["ICoreWebView2_7", "+ print to PDF"]]
	Local $fStartX = $g_X + 26
	For $i = 0 To 3
		Local $fCX = $fStartX + $i * 112
		_G_Box($fCX, $t + 40, 96, 44, $aChain[$i][0], $aChain[$i][1], $G_SAND, $G_SAND_D, $G_INK, 7.2)
		If $i < 3 Then _G_ArrowR($fCX + 98, $t + 62, $fCX + 110)
	Next
	Local $aLabels[3][2] = [["66", 1], ["75", 2], ["80", 3]]
	For $i = 0 To 2
		Local $fLblX = $fStartX + $aLabels[$i][1] * 112 + 48
		_G_TextCentre($fLblX - 30, $t + 92, 60, "slot " & $aLabels[$i][0], 7.4, $G_TERRA_D, "Courier", "B")
		_PDFX_SetStroke($g_Doc, $G_TERRA)
		_PDFX_SetLineWidth($g_Doc, 0.8)
		_PDFX_Line($g_Doc, $fLblX, $t + 86, $fLblX, $t + 90)
	Next
	_G_Text($g_X + 26, $t + 120, "Each version adds methods after the previous one: the chain is counted, never guessed.", 7.2, $G_MUTED, "Helvetica", "I")
	_G_FigCaption("The three ranks this UDF calls raw, and the interface version that carries each one.")

	_G_P("That count must be taken from the official header - never from memory, never from a " & _
			"summary page. The SDK's WebView2.h is the only authoritative order.")

	_G_H2("The slots this UDF calls raw")
	Local $aCols[3][3] = [["Constant", 0.36, "L"], ["Slot", 0.10, "R"], ["What it is", 0.54, "L"]]
	Local $aRows[13][3] = [ _
			["$__WV2_VT_QI", "0", "IUnknown::QueryInterface"], _
			["$__WV2_VT_RELEASE", "2", "IUnknown::Release"], _
			["$__WV2_VT_PUTBOUNDS", "6", "ICoreWebView2Controller::put_Bounds (x64)"], _
			["$__WV2_VT_GETCOOKIE", "66", "ICoreWebView2_2::get_CookieManager"], _
			["$__WV2_VT_ADDDL", "75", "ICoreWebView2_4::add_DownloadStarting"], _
			["$__WV2_VT_REMOVEDL", "76", "ICoreWebView2_4::remove_DownloadStarting"], _
			["$__WV2_VT_PRINTTOPDF", "80", "ICoreWebView2_7::PrintToPdf"], _
			["$__WV2_VT_DLA_OP", "3", "DownloadStartingEventArgs::get_DownloadOperation"], _
			["$__WV2_VT_DLA_CANCEL", "5", "DownloadStartingEventArgs::put_Cancel"], _
			["$__WV2_VT_DLA_PATH", "6", "DownloadStartingEventArgs::get_ResultFilePath"], _
			["$__WV2_VT_DLA_PATHPUT", "7", "DownloadStartingEventArgs::put_ResultFilePath"], _
			["$__WV2_VT_DLO_URI", "9", "DownloadOperation::get_Uri"], _
			["$__WV2_VT_COOKIEDALL", "10", "ICoreWebView2CookieManager::DeleteAllCookies"]]
	_G_Table($aCols, $aRows, 8, True)

	_G_P("Every number in that table was counted from the header, then confirmed at run time by " & _
			"calling the slot and checking the HRESULT - and, where the method has an observable " & _
			"effect, by looking at the effect (chapter 4).")

	_G_H2("A tag may stop early; it may not skip")
	_G_P("$__WV2_TAG_WV stops at get_DocumentTitle. That is legal: a tag describes the methods you " & _
			"intend to call, and a wrapper only knows the ones you declared. What is not legal is a " & _
			"tag that skips a method in the middle: the wrapper counts positions, so a missing entry " & _
			"shifts everything after it by one and the call lands on the wrong function.")

	_G_P("That is the whole reason PrintToPdf, at slot 80, is not in a tag. A complete " & _
			"ICoreWebView2_7 tag would carry hundreds of lines for one call, and the wrapper would " & _
			"gain nothing: DllCallAddress needs the same arguments and one constant.")

	_G_H2("QI is the version check")
	_G_P("Asking for ICoreWebView2_7 on a runtime older than that interface returns E_NOINTERFACE " & _
			"(0x80004002) - not a crash, not a silent failure. __WV2_QiView converts the textual IID " & _
			"with CLSIDFromString, calls slot 0 on the raw view pointer, and keeps the answer; " & _
			"__WV2_ViewIf asks once per version per instance, and the pointers are released with the " & _
			"view. The distinction it makes matters:")
	Local $aQi[2] = [ _
			"E_NOINTERFACE|becomes $WV2_ERR_CALL with that HRESULT: the machine's runtime is older than the feature. The caller degrades; the UDF does not lie about it.", _
			"Any other failure|becomes a COM error: the UDF's own bookkeeping is wrong."]
	_G_Bullets($aQi)
EndFunc

; ================================================================== chapter 04
Func _G_Ch04()
	_G_Chapter("04", "X86 AND X64", "THE ABI TRAP", "x86 and x64: put_Bounds", _
			"The header says by value. The 64-bit runtime reads a pointer. One function carries the difference.")

	_G_P("ICoreWebView2Controller::put_Bounds takes a RECT by value. On x86 (stdcall) the four " & _
			"longs are pushed on the stack, and the wrapper tag " & _
			"put_Bounds hresult(long;long;long;long) describes exactly that. It works.")

	_G_P("On x64 the first four arguments travel in RCX, RDX, R8 and R9, and a structure that does " & _
			"not fit in eight bytes is never passed by value: the caller passes its address. The " & _
			"header still says by value; the wire says pointer. Give the callee four longs and it reads " & _
			"left as a pointer and dereferences it - that is the crash.")

	_G_FigCard(212)
	Local $t = $g_FigTop
	_G_Box($g_X + 22, $t + 34, 206, 148, "", "", $G_SAND, $G_SAND_D)
	_G_Box($g_X + 268, $t + 34, 206, 148, "", "", $G_WHITE, $G_RULE)
	_G_Tracked($g_X + 34, $t + 44, "X86  -  STDCALL", 6.8, $G_TERRA_D, "Helvetica", "B", 1.2)
	_G_Tracked($g_X + 280, $t + 44, "X64  -  ONE POINTER", 6.8, $G_TERRA_D, "Helvetica", "B", 1.2)
	Local $aStack[4] = ["bottom", "right", "top", "left"]
	For $i = 0 To 3
		Local $fBY = $t + 62 + $i * 20
		_PDFX_SetFill($g_Doc, $G_WHITE)
		_PDFX_SetStroke($g_Doc, $G_SAND_D)
		_PDFX_SetLineWidth($g_Doc, 0.5)
		_PDFX_RoundRect($g_Doc, $g_X + 40, $fBY, 120, 16, 3, $PDFX_BOTH)
		_G_Text($g_X + 48, $fBY + 3.6, $aStack[$i], 7.2, $G_BODY, "Courier", "")
	Next
	_G_Text($g_X + 176, $t + 78, "stack", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 176, $t + 92, "4 longs", 7, $G_MUTED, "Helvetica", "I")
	_G_Text($g_X + 40, $t + 148, "the tag describes this shape", 7, $G_MUTED, "Helvetica", "I")

	_PDFX_SetFill($g_Doc, $G_SAND)
	_PDFX_RoundRect($g_Doc, $g_X + 282, $t + 66, 110, 18, 3, $PDFX_FILL)
	_G_Text($g_X + 290, $t + 69.5, "RCX = &RECT", 7.2, $G_TERRA_D, "Courier", "B")
	Local $aRect[4] = ["left", "top", "right", "bottom"]
	For $i = 0 To 3
		Local $fRectY = $t + 94 + $i * 15
		_PDFX_SetFill($g_Doc, $G_SAND)
		_PDFX_Rect($g_Doc, $g_X + 330, $fRectY, 46, 11, $PDFX_FILL)
		_G_Text($g_X + 334, $fRectY + 2, $aRect[$i], 5.6, $G_BODY, "Courier", "")
	Next
	_G_Text($g_X + 282, $t + 148, "four longs in memory", 7, $G_MUTED, "Helvetica", "I")
	_G_TextCentre($g_X + 232, $t + 100, 32, "vs", 8, $G_TERRA, "Helvetica", "I")
	_G_FigCaption("The same declaration, two wire formats. Giving the callee four longs on x64 makes " & _
			"it dereference the first one as an address: the process terminates.")

	_G_H2("What was measured")
	_G_P("Four shapes were tried on the 64-bit runtime, in a scratch script that logged each step " & _
			"to a file, because a crash truncates the console but not a flushed file:")
	Local $aCols[2][3] = [["Argument shape", 0.62, "L"], ["Result", 0.38, "L"]]
	Local $aRows[4][2] = [ _
			["Four long in a tag (the correct x86 shape)", "process terminates"], _
			["Two int64 (the sixteen bytes in two registers)", "process terminates"], _
			["AutoIt's by-value struct", "process terminates"], _
			["ptr to a DllStruct of four long, through the vtable", "hr = 0, bounds applied"]]
	_G_Table($aCols, $aRows, 8)

	_G_P("The fourth becomes the only 64-bit path:")
	_G_Code('Func __WV2_PutBounds($i, $iLeft, $iTop, $iRight, $iBottom)' & @LF & _
			'    If Not @AutoItX64 Then' & @LF & _
			'        Return __WV2_Result( _' & @LF & _
			'            $__WV2_oCtl[$i].put_Bounds($iLeft, $iTop, $iRight, $iBottom), _' & @LF & _
			'            "ICoreWebView2Controller::put_Bounds")' & @LF & @LF & _
			'    Local $pFn = __WV2_VtFn($__WV2_pCtl[$i], $__WV2_VT_PUTBOUNDS)' & @LF & _
			'    If $pFn = 0 Then' & @LF & _
			'        __WV2_SetErr($WV2_ERR_COM, 0, "__WV2_VtFn")' & @LF & _
			'        Return 0' & @LF & _
			'    EndIf' & @LF & _
			'    Local $tRc = DllStructCreate("long l; long t; long r; long b")' & @LF & _
			'    DllStructSetData($tRc, "l", $iLeft)' & @LF & _
			'    DllStructSetData($tRc, "t", $iTop)' & @LF & _
			'    DllStructSetData($tRc, "r", $iRight)' & @LF & _
			'    DllStructSetData($tRc, "b", $iBottom)' & @LF & _
			'    Local $aCall = DllCallAddress("long", $pFn, "ptr", $__WV2_pCtl[$i], _' & @LF & _
			'            "ptr", DllStructGetPtr($tRc))' & @LF & _
			'    If @Error Or Not IsArray($aCall) Then' & @LF & _
			'        __WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2Controller::put_Bounds")' & @LF & _
			'        Return 0' & @LF & _
			'    EndIf' & @LF & _
			'    Return __WV2_Result($aCall[0], "ICoreWebView2Controller::put_Bounds")' & @LF & _
			'EndFunc')

	_G_P("No single tag can be correct on both bitnesses here, which is why the function branches " & _
			"instead of carrying one declaration.")

	_G_H2("hr = 0 is not proof")
	_G_P("The first version of the 64-bit fix returned S_OK and did nothing visible. S_OK only " & _
			"means the call arrived; it says nothing about what the callee did with the arguments. " & _
			"The fix was accepted only after three independent proofs:")
	Local $aProof[3] = [ _
			"Pixel|GetPixel on the parent window: inside the browser area the pixel is the page colour, outside it is the GUI background.", _
			"Resize|The boundary moved when the window was resized and _WV2_SetBounds was called again.", _
			"Read back|get_Bounds returned exactly the rectangle that had been sent."]
	_G_Bullets($aProof)
	_G_P("Apply that rule to every raw call you add: find an observable consequence and check it.")

	_G_H2("The other shapes you will meet")
	Local $aCols2[3][3] = [["Value", 0.30, "L"], ["AutoIt type", 0.26, "L"], ["Note", 0.44, "L"]]
	Local $aRows2[6][3] = [ _
			["HRESULT", "long", "negative failure values; @extended keeps it"], _
			["BOOL", "int", "32-bit, never bool (one byte)"], _
			["long / DWORD", "long", "32-bit on both bitnesses (LLP64 on x64)"], _
			["EventRegistrationToken", "int64", "by value on remove_*, by pointer on add_*"], _
			["LPWSTR returned", "wstr*", "allocated with CoTaskMemAlloc"], _
			["interface out-parameter", "ptr*", "carries a reference of its own"]]
	_G_Table($aCols2, $aRows2, 8)

	_G_P("A text returned by the runtime is copied and freed by __WV2_WStrProp. A returned " & _
			"interface pointer is released with __WV2_ReleaseExternal unless it is wrapped and " & _
			"becomes the UDF's property.")
EndFunc

; ================================================================== chapter 05
Func _G_Ch05()
	_G_Chapter("05", "ADDING A METHOD", "A WORKED EXAMPLE", "Adding a method in six steps", _
			"Worked example: the two calls behind _WV2_ClearCookies.")

	_G_P("get_CookieManager lives on ICoreWebView2_2 at slot 66; DeleteAllCookies lives on " & _
			"ICoreWebView2CookieManager at slot 10. Neither is in a tag, and the six steps that " & _
			"brought them into the UDF are the same for any other method.")

	_G_H2("1. Find the declaration")
	_G_P("Open WebView2.h from the SDK and locate the interface that declares the method. Note the " & _
			"exact parameter list and the return type of every argument. A method found on a " & _
			"documentation page is a hint; the header is the fact.")

	_G_H2("2. Turn the position into a slot")
	_G_P("Count every method declared before it in the whole inheritance chain, add 3. Record the " & _
			"number as a named constant next to the others, with the interface name in the comment: " & _
			"a bare 66 in the middle of a function is unreviewable.")

	_G_Code('Global Const $__WV2_VT_GETCOOKIE = 66' & @LF & _
			'Global Const $__WV2_VT_COOKIEDALL = 10')

	_G_H2("3. Ask the view for that interface version")
	_G_Code('Local $p2 = __WV2_ViewIf($iHandle, $__WV2_IF_2)' & @LF & _
			'If $p2 = 0 Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)')
	_G_P("If $p2 is 0 because of E_NOINTERFACE, the runtime is older than the feature. " & _
			"__WV2_SetErr has already recorded that, and the public function propagates it unchanged.")

	_G_H2("4. Write the call shape")
	_G_P("Four helpers cover most methods; anything else goes through DllCallAddress directly.")
	Local $aCols[2][3] = [["Helper", 0.44, "L"], ["Signature it calls", 0.56, "L"]]
	Local $aRows[4][2] = [ _
			["__WV2_CallNoArg($pObj, $slot)", "hr Method()"], _
			["__WV2_CallBool($pObj, $slot, $v)", "hr Method(BOOL)"], _
			["__WV2_CallWStr($pObj, $slot, $s)", "hr Method(LPCWSTR)"], _
			["__WV2_WStrProp($pObj, $slot)", "hr get_X(LPWSTR*) - returns the text"]]
	_G_Table($aCols, $aRows, 8)

	_G_P("get_CookieManager is none of these: it returns an interface pointer, so it is written " & _
			"out. Three checks follow every raw call - @error, the HRESULT, and a non-null pointer:")
	_G_Code('Local $tOut = DllStructCreate("ptr")' & @LF & _
			'Local $aCall = DllCallAddress("long", $pFn, "ptr", $p2, _' & @LF & _
			'        "ptr", DllStructGetPtr($tOut))' & @LF & _
			'If @Error Or Not IsArray($aCall) Then' & @LF & _
			'    __WV2_SetErr($WV2_ERR_COM, 0, "ICoreWebView2_2::get_CookieManager")' & @LF & _
			'    Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)' & @LF & _
			'EndIf' & @LF & _
			'If $aCall[0] <> 0 Then' & @LF & _
			'    __WV2_SetErr($WV2_ERR_CALL, $aCall[0], "ICoreWebView2_2::get_CookieManager")' & @LF & _
			'    Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)' & @LF & _
			'EndIf' & @LF & _
			'Local $pCookie = DllStructGetData($tOut, 1)')

	_G_H2("5. Own what comes back")
	_G_P("An interface returned through an out-parameter carries its own reference; QueryInterface " & _
			"and every getter that hands out an object do this. Either wrap it and release it with " & _
			"the rest of the instance, or release it as soon as you are done:")
	_G_Code('Local $hr = __WV2_CallNoArg($pCookie, $__WV2_VT_COOKIEDALL)' & @LF & _
			'__WV2_ReleaseExternal($pCookie)')
	_G_P("Text is different: it is CoTaskMemAlloc'd, so it is copied (__WV2_CopyWStr) and then " & _
			"freed with CoTaskMemFree - never handed to the caller as-is.")

	_G_H2("6. Wrap it, then prove it")
	_G_Code('Func _WV2_ClearCookies($iHandle)' & @LF & _
			'    $__WV2_sLastFunc = "_WV2_ClearCookies"' & @LF & _
			'    If Not __WV2_Guard($iHandle) Then' & @LF & _
			'        Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)' & @LF & _
			'    ...' & @LF & _
			'    Local $bOk = __WV2_Result($hr, _' & @LF & _
			'            "ICoreWebView2CookieManager::DeleteAllCookies")' & @LF & _
			'    Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)' & @LF & _
			'EndFunc')

	_G_P("Then add a check to WebView2_Example_GUI.au3 (--auto) that exercises the new call and " & _
			"asserts its effect, not its return value. The suite is the specification of what must " & _
			"keep working; a feature without a check there is a feature that will silently break.")

	_G_H2("When to extend a tag instead")
	_G_P("If the interface is fully declared in the tag up to the method you need, and you expect " & _
			"to call several of its methods, extending the tag is cheaper and type-checked by " & _
			"AutoIt's own argument conversion. The rule of thumb: one call, raw slot; a family of " & _
			"calls, tag.")
EndFunc

; ================================================================== chapter 06
Func _G_Ch06()
	_G_Chapter("06", "DIAGNOSING", "TWO INTEGERS AND A LABEL", "Diagnosing a failure", _
			"Two integers and a label; a crash that prints nothing; four asynchronous methods.")

	_G_H2("The error plumbing")
	_G_P("Every failure goes through one function: __WV2_SetErr stores the category, the raw " & _
			"HRESULT and the label. The public function returns " & _
			"SetError($__WV2_iLastError, $__WV2_iLastHR, value), so @error carries the category and " & _
			"@extended the HRESULT. _WV2_GetLastErrorMessage turns both into one line:")

	_G_Code('Method call failed in ICoreWebView2_7::PrintToPdf (HRESULT 0x80070005)')

	_G_P("Three habits make that usable:")
	Local $aHabits[3] = [ _
			"Never Return f().|SetError does not survive a plain Return; every public function sets @error and @extended explicitly. This was a real bug in an earlier version, invisible on the success paths.", _
			"Label the call site|ICoreWebView2_7::PrintToPdf tells you which method failed; PrintToPdf does not.", _
			"No output|The UDF never prints and never shows a dialog. A script can run in a service or under a scheduler with no console. Diagnostics are values, not output."]
	_G_Bullets($aHabits)

	_G_H2("Reading an HRESULT")
	Local $aCols[3][3] = [["Value", 0.24, "L"], ["Name", 0.26, "L"], ["Usual cause here", 0.50, "L"]]
	Local $aRows[6][3] = [ _
			["0x80004001", "E_NOTIMPL", "the runtime does not implement this method"], _
			["0x80004002", "E_NOINTERFACE", "runtime older than the interface version"], _
			["0x80004005", "E_FAIL", "the call was made, the runtime refused"], _
			["0x80070002", "ERROR_FILE_NOT_FOUND", "a path handed to the runtime does not exist"], _
			["0x80070005", "ERROR_ACCESS_DENIED", "profile or output folder not writable"], _
			["0x80070057", "E_INVALIDARG", "wrong argument shape - suspect the ABI"]]
	_G_Table($aCols, $aRows, 8)

	_G_H2("A crash that prints nothing")
	_G_P("A wrong slot or a wrong argument shape does not return an HRESULT: the process " & _
			"disappears, and the console loses whatever was buffered. Bisect like this:")
	Local $aBisect[5] = [ _
			"Flush|Write a scratch script with ConsoleWrite and FileWriteLine on a handle opened with $FO_APPEND, flushed after each line.", _
			"Last call|Call the suspect method last, with everything else already proven.", _
			"Remove it|Comment out the call: if the script completes, the call is the killer.", _
			"One variable|Vary one thing at a time - the slot, then each argument type, then the order of the returned value and the release.", _
			"Prove it|When a shape succeeds, do not stop: prove the effect."]
	_G_Bullets($aBisect)

	_G_P("Two less obvious traps. A wrong-arity call to your own AutoIt function is a runtime " & _
			"fatal, not a compile error: Au3Check passes and the script exits 1 with a truncated log, " & _
			"so count the arguments before suspecting COM. And ObjCreateInterface on a pointer the " & _
			"operating system owns crashed the process in this build, while reading Release from the " & _
			"vtable does not: when a wrapper is not yours, do not wrap it.")

	_G_H2("Asynchronous methods")
	_G_P("ExecuteScript, AddScriptToExecuteOnDocumentCreated, CapturePreview and PrintToPdf " & _
			"answer through a handler, later. The pattern is the same for all four:")
	_G_Code('__WV2_BeginOp($iHandle, $__WV2_H_PRINT)       ; clear the state' & @LF & _
			'Local $aCall = DllCallAddress(...)             ; start' & @LF & _
			'__WV2_WaitOp($iHandle, $__WV2_H_PRINT, $iMs)   ; pump until it answers' & @LF & _
			'Local $iDoneHR = $__WV2_iOpHR[$iHandle][$__WV2_H_PRINT]')

	_G_P("__WV2_WaitOp pumps the message queue in 20 ms slices, so the GUI keeps repainting while " & _
			"the script waits. Three distinct failures must stay distinguishable, and _WV2_PrintToPdf " & _
			"shows all three: the call itself fails (WV2_ERR_CALL with its HRESULT), the handler " & _
			"reports an HRESULT (WV2_ERR_CALL with that HRESULT), or the call succeeds and the handler " & _
			"answers FALSE (WV2_ERR_FILE, because a PDF that was not written is not a method failure).")

	_G_H2("The event queue")
	_G_P("Events are pushed into a 64-entry ring per instance and dropped oldest-first when the " & _
			"script does not drain them; $__WV2_iEvtDrop keeps the count. _WV2_GetEvent on an empty " & _
			"queue returns 0 with @error = 0: empty is not an error, and a loop must tell the two " & _
			"apart. _WV2_WaitEvent waits for one specific type and leaves the others in the queue.")
EndFunc

; ================================================================== chapter 07
Func _G_Ch07()
	_G_Chapter("07", "THREADING", "ONE APARTMENT, ONE PUMP", "Threading and the message pump", _
			"One apartment, one thread, and nothing happens without a pump.")

	_G_H2("One apartment, one thread")
	_G_P("CoInitializeEx(NULL, COINIT_APARTMENTTHREADED) runs once per script, on the thread that " & _
			"called _WV2_Create. The browser is created in that apartment and delivers every event on " & _
			"that thread, through the Windows message queue. Consequences:")
	Local $aThread[3] = [ _
			"One thread|A view belongs to the thread that created it. Calling it from another thread is undefined behaviour; no marshalling is done.", _
			"No pump, no events|Nothing arrives until messages are dispatched: no pump, no events, no completion handlers, no navigation progress.", _
			"Waiting still paints|_WV2_Create and every waiter pump while they wait, which is why a script can block on a page load and still repaint."]
	_G_Bullets($aThread)

	_G_H2("The pump")
	_G_Code('Func __WV2_Pump($iMs)' & @LF & _
			'    Local Static $tMsg = DllStructCreate( _' & @LF & _
			'        "ptr hwnd;uint message;ptr wParam;ptr lParam;dword time;long x;long y")' & @LF & _
			'    Local $tEnd = TimerInit()' & @LF & _
			'    While TimerDiff($tEnd) < $iMs' & @LF & _
			'        Local $aPM = DllCall("user32.dll", "bool", "PeekMessageW", _' & @LF & _
			'            "ptr", DllStructGetPtr($tMsg), "ptr", 0, _' & @LF & _
			'            "dword", 0, "dword", 0, "dword", 1)' & @LF & _
			'        If @Error Or Not $aPM[0] Then' & @LF & _
			'            Sleep(2)' & @LF & _
			'        Else' & @LF & _
			'            DllCall("user32.dll", "bool", "TranslateMessage", _' & @LF & _
			'                "ptr", DllStructGetPtr($tMsg))' & @LF & _
			'            DllCall("user32.dll", "lresult", "DispatchMessageW", _' & @LF & _
			'                "ptr", DllStructGetPtr($tMsg))' & @LF & _
			'        EndIf' & @LF & _
			'    WEnd' & @LF & _
			'EndFunc')

	_G_P("PM_REMOVE (1), every message, no filtering: the runtime posts its work as ordinary " & _
			"window messages, and filtering them out would starve it. Sleep(2) when the queue is " & _
			"empty keeps a waiter from spinning a core.")

	_G_H2("Inside a GUI loop")
	_G_P("The pattern that works: do not wait inside GUIGetMsg handlers. Either wait before " & _
			"entering the loop, or let the main loop pump - it already does - and read events with " & _
			"_WV2_GetEvent. A long _WV2_WaitNavigation inside a button handler freezes the toolbar " & _
			"for as long as the page takes: correctly, visibly, and avoidably.")

	_G_H2("Teardown order")
	_G_P("_WV2_Destroy is a strict sequence, because an interface must outlive every pointer taken " & _
			"from it:")

	_G_FigCard(198)
	Local $t = $g_FigTop
	Local $aOrder[6] = ["remove_*", "release _2/_4/_7", "release settings", "release web view", "Close + release ctl", "release environment"]
	Local $j
	For $j = 0 To 5
		Local $fBX
		Local $fBY
		If $j < 3 Then
			$fBX = $g_X + 20 + $j * 156
			$fBY = $t + 40
		Else
			$fBX = $g_X + 20 + ($j - 3) * 156
			$fBY = $t + 118
		EndIf
		_PDFX_SetFill($g_Doc, $G_SAND)
		_PDFX_SetStroke($g_Doc, $G_SAND_D)
		_PDFX_SetLineWidth($g_Doc, 0.6)
		_PDFX_RoundRect($g_Doc, $fBX, $fBY, 130, 40, 5, $PDFX_BOTH)
		_PDFX_SetFill($g_Doc, $G_TERRA)
		_PDFX_Circle($g_Doc, $fBX + 16, $fBY + 14, 6, $PDFX_FILL)
		_G_TextCentre($fBX + 10, $fBY + 11.2, 12, String($j + 1), 6.4, 0xFFF8EA, "Helvetica", "B")
		_G_Text($fBX + 28, $fBY + 9, $aOrder[$j], 7.4, $G_INK, "Helvetica", "B")
		_G_Text($fBX + 28, $fBY + 22, "step " & ($j + 1), 6.4, $G_MUTED)
		If $j < 2 Then _G_ArrowR($fBX + 132, $fBY + 20, $fBX + 150)
		If $j >= 3 And $j < 5 Then _G_ArrowR($fBX + 132, $fBY + 20, $fBX + 150)
	Next
	_PDFX_SetDash($g_Doc, 2, 2)
	_PDFX_SetStroke($g_Doc, $G_TERRA)
	_PDFX_SetLineWidth($g_Doc, 0.9)
	_PDFX_Line($g_Doc, $g_X + 397, $t + 82, $g_X + 397, $t + 96)
	_PDFX_Line($g_Doc, $g_X + 397, $t + 96, $g_X + 85, $t + 96)
	_PDFX_Line($g_Doc, $g_X + 85, $t + 96, $g_X + 85, $t + 106)
	_PDFX_SetDash($g_Doc, 0)
	_G_ArrowD($g_X + 85, $t + 98, $t + 116)
	_G_Text($g_X + 20, $t + 170, "an interface must outlive every pointer taken from it", 7.4, $G_MUTED, "Helvetica", "I")
	_G_FigCaption("The six steps of _WV2_Destroy, in order. Reversing the fourth and the second leaves the " & _
			"runtime holding an interface into freed memory.")

	_G_P("Reversing the fourth and the second leaves the runtime holding an interface into freed " & _
			"memory; the crash usually happens at exit, far from the cause.")

	_G_H2("The browser is a window, not a control")
	_G_P("_WV2_Create($hParent, ...) puts a real child window inside $hParent. It covers every " & _
			"AutoIt control whose rectangle overlaps its own, and GUICtrlSetResizing does not apply - " & _
			"it has no control identifier. Either reserve a band of the client area for the toolbar, or " & _
			"call _WV2_FitToParent or _WV2_SetBounds from the resize handler.")
EndFunc

; ================================================================== chapter 08
Func _G_Ch08()
	_G_Chapter("08", "LIMITS AND REFERENCES", "WHAT IT COSTS, WHERE TO LOOK", "Limits, pitfalls, references", _
			"What the wrapper bounds, what the runtime decides, and where to read more.")

	_G_H2("Limits of the wrapper")
	Local $aCols[3][3] = [["Limit", 0.34, "L"], ["Value", 0.22, "L"], ["Where it comes from", 0.44, "L"]]
	Local $aRows[7][3] = [ _
			["Concurrent views", "16", "$__WV2_MAX"], _
			["Handler objects per view", "14", "$__WV2_SLOT_COUNT"], _
			["Queued events per view", "64", "$__WV2_QCAP, oldest dropped"], _
			["Create timeout", "15 s", "$WV2_CREATE_TIMEOUT"], _
			["Navigation timeout", "30 s", "$WV2_NAV_TIMEOUT"], _
			["Script / print timeout", "5 s / 30 s", "$WV2_EXEC_TIMEOUT, $WV2_PRINT_TIMEOUT"], _
			["Zoom range", "0.2 to 10", "validated by _WV2_SetZoom"]]
	_G_Table($aCols, $aRows, 8, True)

	_G_H2("Pitfalls worth knowing before they cost a day")
	Local $aPitfalls[8] = [ _
			"Undocumented entry point|The loaderless call is stable in practice and confined to one DllCall in _WV2_Create. If a future runtime ever moved it, the fallback is to ship WebView2Loader.dll and change that one call - nothing else touches it.", _
			"A profile outlives the view|The browser process holds the folder for a few seconds after _WV2_Destroy, which cannot always delete it; the next _WV2_Create on the same slot does. Pass your own folder when the profile must survive or be audited.", _
			"Cookies need an origin|A file:// page or NavigateToString has a null origin and cannot store a cookie: document.cookie stays empty by design, and that is not a bug in the bridge.", _
			"Cookies only|_WV2_ClearCookies clears cookies. Cache, history and localStorage need ICoreWebView2Profile2::ClearBrowsingData, which the view does not expose.", _
			"One download per page|Chromium allows one automatic download per page. A second scripted download is dropped silently and raises no event. A redirected download reaches the disk 0 to 3 s after DownloadStarting: wait for the file instead of concluding it failed.", _
			"Filter needs the event|_WV2_SetNavigationFilter needs $WV2_EVENT_NAVIGATION_STARTING enabled. The filter is applied by that handler; without the subscription there is nothing to cancel.", _
			"ExecuteScript returns JSON|document.title comes back as ""Hello"" with quotes, a number as 42, and a script that throws as null with @error = 0. Test for ""null"" rather than for failure.", _
			"BOOL is four bytes|bool in a DllCall is one byte and corrupts the stack on the way back. Every BOOL in this UDF is int."]
	_G_Bullets($aPitfalls, 9.2, 13.4)

	_G_H2("Testing")
	_G_P("WebView2_Example_GUI.au3 /auto runs 111 checks over the whole API without network access " & _
			"(file:// and NavigateToString pages) and leaves nothing on disk. It passed on AutoIt " & _
			"3.3.16.1 in x86 and x64. Use it as the regression gate for any change described in " & _
			"chapter 5, and add the new check before the implementation when you can.")

	_G_H2("References")
	Local $aRefs[8][2] = [ _
			["WebView2 API reference", "https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/"], _
			["ICoreWebView2Controller", "https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/icorewebview2controller"], _
			["WebView2.h, WebView2 SDK (NuGet, MIT)", "the authoritative vtable order"], _
			["Microsoft x64 calling convention", "https://learn.microsoft.com/cpp/build/x64-calling-convention"], _
			["Forum thread: Microsoft Edge - WebView2", "https://www.autoitscript.com/forum/topic/204362-microsoft-edge-webview2/"], _
			["Ralle1976/Autoit-WebView2-UDF", "https://github.com/Ralle1976/Autoit-WebView2-UDF"], _
			["Numeric1 on the AutoIt forum", $G_URL_PROFILE], _
			["PDFX, the UDF that typeset this guide", $G_URL_PDFX]]
	For $i = 0 To UBound($aRefs) - 1
		_G_Ensure(28)
		_PDFX_SetFill($g_Doc, $G_TERRA)
		_PDFX_Circle($g_Doc, $g_X + 3.2, $g_Y + 4.6, 1.2, $PDFX_FILL)
		_G_Text($g_X + 12, $g_Y, $aRefs[$i][0], 9.2, $G_INK, "Helvetica", "B")
		Local $sUrl = $aRefs[$i][1]
		If StringLeft($sUrl, 4) = "http" Then
			_G_Text($g_X + 12, $g_Y + 11.5, $sUrl, 7.6, $G_TERRA_D)
			Local $fUrlW = _G_W($sUrl, 7.6)
			_PDFX_Link($g_Doc, $g_X + 12, $g_Y + 10.5, $fUrlW + 2, 10, $sUrl)
			$g_Y += 26
		Else
			_G_Text($g_X + 12, $g_Y + 11.5, $sUrl, 7.8, $G_MUTED, "Helvetica", "I")
			$g_Y += 25
		EndIf
	Next
	$g_Y += 4

	_G_H2("License")
	_G_P("MIT, Copyright (c) 2026 Numeric1. Keep the LICENSE file and the Author / License lines " & _
			"of every source header in any copy or redistribution.")
	_G_P("WebView2 itself is Microsoft's. The interface identifiers and vtable layout used here " & _
			"follow their SDK, which is MIT-licensed; no Microsoft code is reproduced in this package.")

	_G_Note("Colophon", "This PDF is typeset with PDFX 1.4.0, the author's other UDF: contents, " & _
			"bookmarks, links, the cover and every figure are generated with it. Full URLs are listed " & _
			"in the References above and are clickable.")
EndFunc
