#cs ----------------------------------------------------------------------------
    build_tutorial -- generates WebView2_Quick_Start.pdf with PDFX itself.

    Same editorial system as the developer guide, shorter: six chapters, four
    complete programs read straight from Tools\samples, and two passes so the
    contents page and the footer can carry page numbers. Chapter layouts do not
    depend on those numbers, so the two passes paginate identically.

    Author: Numeric1 -- https://www.autoitscript.com/forum/profile/118605-numeric1/
    Typeset with PDFX 1.4.0 -- https://www.autoitscript.com/forum/topic/213930-udf-pdfx/
#ce ----------------------------------------------------------------------------

; Local tool, not part of the released kit. Drop PDFX.au3 next to this file to rebuild the booklet.
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

Global $g_Titles[6][2] = [ _
	["01", "Your first window"], _
	["02", "Events and messages"], _
	["03", "Your own content"], _
	["04", "Fitting the window"], _
	["05", "Recipes"], _
	["06", "When it goes wrong"]]

; ================================================================== driver
Global $sOut = @ScriptDir & "\..\WebView2_Quick_Start.pdf"
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

	_PDFX_SetMeta($g_Doc, "WebView2 UDF - Quick start", "Numeric1", _
			"Embedding the Edge engine in AutoIt: four commented programs, from the first window to snapshots and PDF", _
			"webview2;autoit;tutorial;quick start")
	_PDFX_SetCompression($g_Doc, 6)
	_PDFX_SetPageMode($g_Doc, "UseOutlines")
	_PDFX_SetPageLayout($g_Doc, "SinglePage")

	_T_Cover()
	_T_Toc()
	_T_Ch01()
	_G_EndChapter()
	_T_Ch02()
	_G_EndChapter()
	_T_Ch03()
	_G_EndChapter()
	_T_Ch04()
	_G_EndChapter()
	_T_Ch05()
	_G_EndChapter()
	_T_Ch06()
EndFunc

; Closes a chapter at the foot of its last page. Skipped when the page is too
; full to hold the rule without crowding the prose above it.
Func _G_EndChapter()
	If $g_Ch >= 6 Then Return
	If $g_Y > 736 Then Return
	Local $fY = $G_Bottom - 18
	_G_Rule($fY, $G_RULE, 0.5, $g_X, $g_X + $g_W)
	_G_Tracked($g_X, $fY + 7, "NEXT CHAPTER", 6.4, $G_MUTED, "Helvetica", "B", 1.2)
	_G_TrackedRight($g_X + $g_W, $fY + 6, $g_Titles[$g_Ch][0] & "  " & $g_Titles[$g_Ch][1], 7.4, $G_TERRA, "Helvetica", "B", 1)
	$g_Y = $G_Bottom
EndFunc

; ================================================================== text tools
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

	_G_TrackedCentre(31.8, "QUICK START", 7.1, $G_MUTED, "Helvetica", "B", 1.5)

	If $g_Section <> "" Then _G_TrackedRight($fRight, 31.8, $g_Section, 7.1, $G_TERRA, "Helvetica", "B", 1.2)

	_G_Rule(52, $G_RULE, 0.6)

	_G_Rule(800, $G_RULE, 0.6)
	_G_Tracked($g_X, 806, "NUMERIC1", 7, $G_MUTED, "Helvetica", "B", 0.9)
	_G_Text($g_X + 47, 806, "WebView2 Quick Start  -  MIT", 7.2, $G_MUTED)
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

; ================================================================== content
#include "tutorial_content.au3"
