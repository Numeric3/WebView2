# WebView2 UDF — Developer guide

How the UDF talks to the Edge engine, why each layer is shaped the way it is, and how to
extend it without a debugger.

- Author: Numeric1 — <https://www.autoitscript.com/forum/profile/118605-numeric1/>
- Version: 0.3.0 (2026-10-28)
- Requires: AutoIt 3.3.16.1, Windows 10 or later with the Microsoft Edge WebView2 Runtime
- License: MIT, Copyright (c) 2026 Numeric1
- Typeset (PDF edition) with PDFX — <https://www.autoitscript.com/forum/topic/213930-udf-pdfx/>

---

## Contents

1. The minimal COM model in AutoIt
2. Handler objects: fake vtables in a global heap
3. Vtable ranks, verified against `WebView2.h`
4. ABI traps: x86 against x64, with `put_Bounds` as the case study
5. Adding an interface method in six steps
6. Diagnosing: `@error`, HRESULT, and a crash that prints nothing
7. Threading, the message pump, and teardown order
8. Runtime limits, pitfalls, references

---

## 1. The minimal COM model in AutoIt

Everything in this UDF rests on one fact: a COM interface pointer is the address of a
pointer to a table of function pointers. Calling a method is calling `table[slot]` with
the interface pointer as the first argument.

```
pInterface ──► pVTable ──► [0] QueryInterface
                           [1] AddRef
                           [2] Release
                           [3] first method the interface declares
                           [4] second method …
```

AutoIt gives you two ways to walk that table.

**`ObjCreateInterface($p, $sIID, $sTag, $bCreate)`** builds a wrapper object whose
methods you call with normal AutoIt syntax. The tag lists the methods in vtable order,
starting at slot 0, separated by `;`. That is the pleasant path — and it is what the UDF
uses for the four interfaces it speaks to constantly:

```autoit
$__WV2_oCtl[$i] = ObjCreateInterface($pCtl, $WV2_IID_CTL, $__WV2_TAG_CTL, False)
; later, plain AutoIt:
Local $hr = $__WV2_oCtl[$i].put_ZoomFactor($fZoom)
```

The fourth argument is the one that matters most here. With `$bCreate = False` the
wrapper does **not** add a reference and does not own the pointer: it is a view of a
reference somebody else holds. Every pointer the runtime hands to a callback is borrowed
in exactly this way, which is why every wrapper in the UDF is built with `False`.

**`DllCallAddress("long", $pFn, "ptr", $pObj, …)`** calls a raw slot. `$pFn` comes from:

```autoit
Func __WV2_VtFn($pObj, $iSlot)
	If $pObj = 0 Or $iSlot < 0 Then Return 0
	If $__WV2_iPtrSize = 0 Then $__WV2_iPtrSize = DllStructGetSize(DllStructCreate("ptr"))
	Local $pVTable = DllStructGetData(DllStructCreate("ptr", $pObj), 1)
	If @Error Or $pVTable = 0 Then Return 0
	Local $pFn = DllStructGetData(DllStructCreate("ptr", $pVTable + $iSlot * $__WV2_iPtrSize), 1)
	If @Error Or $pFn = 0 Then Return 0
	Return $pFn
EndFunc   ;==>__WV2_VtFn
```

Reading a vtable is three lines: dereference the object, add `slot × sizeof(pointer)`,
read the entry. The UDF uses this for two different jobs:

- methods that exist only on a newer version of an interface (chapter 3 and 5);
- `Release` on pointers owned by the operating system, because wrapping those with
  `ObjCreateInterface` crashed the process in this exact build.

### The environment is not created through COM

There is no `CoCreateInstance` in this UDF. The environment is built by a plain export of
the runtime's own DLL, called through `DllCall`:

```autoit
Local $aCE = DllCall($sDll, "long", "CreateWebViewEnvironmentWithOptionsInternal", _
		"bool", 1, "int", 0, "wstr", $sUserDataFolder, "ptr", 0, "ptr", $__WV2_pObj[$i][$__WV2_H_ENV])
```

Five arguments: *shouldCreateFeedbackHandler*, *options*, the user data folder, a reserved
pointer, and the address of the callback object that will receive the environment. This is
the call the official `WebView2Loader.dll` makes on your behalf. Calling it directly is
what removes the last file from your distribution — and it is the one undocumented thing
in the package. Only this one line depends on it.

### Anatomy of `_WV2_Create`

Seven steps, in this order, and the order is not negotiable:

1. Validate the parent window; take a free slot (1…16).
2. Locate the runtime: `_WV2_GetRuntimePath()` reads the registry key
   `Microsoft\EdgeUpdate\Clients\{F3017226-…}` then walks `EdgeWebView\Application`.
   Bitness matters: a 32-bit AutoIt loads the 32-bit DLL.
3. `CoInitializeEx(NULL, COINIT_APARTMENTTHREADED)`, once per script. The UDF never calls
   `CoUninitialize`, so a COM-aware script keeps working after a view is destroyed.
4. Build the fourteen handler objects of the slot (chapter 2).
5. Call `CreateWebViewEnvironmentWithOptionsInternal` and pump until the environment
   callback has answered (`__WV2_WaitFor`), with a 15 s default timeout.
6. The environment callback immediately asks for a controller, which arrives as a second
   callback; the controller is wrapped, `put_Bounds` and `put_IsVisible(1)` are sent.
7. Subscribe `NavigationCompleted`, read the browser version, mark the handle ready.

If any step fails, `__WV2_Fail` tears down whatever exists, the slot is returned to the
table, and `_WV2_Create` returns 0 with `@error` and `@extended` set. Nothing is left
half-alive.

---

## 2. Handler objects: fake vtables in a global heap

The runtime does not pull events. It calls an object you gave it: an
`ICoreWebView2XxxEventHandler` whose only real method is `Invoke`. AutoIt cannot create a
COM object, so the UDF manufactures one out of memory.

### The layout

One block of five pointers per (instance, slot):

```
offset 0       QueryInterface   ─┐
offset ptr     AddRef            │  vtable (four entries)
offset 2·ptr   Release           │
offset 3·ptr   Invoke           ─┘
offset 4·ptr   pointer back to offset 0     ← this is the object
```

The object address is `block + 4 × ptr`. Its first field is a pointer to the vtable that
begins at `block` — exactly what COM expects. `__WV2_BuildHandler` writes the five entries:

```autoit
Func __WV2_BuildHandler($i, $iSlot)
	Local $b = __WV2_BlockBase($i, $iSlot)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbQI), $b + 1)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbAddRef), $b + 2)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbRelease), $b + 3)
	DllStructSetData($__WV2_tHeap, "data", DllCallbackGetPtr($__WV2_hCbInv[$iSlot]), $b + 4)
	Local $pBase = DllStructGetPtr($__WV2_tHeap)
	DllStructSetData($__WV2_tHeap, "data", $pBase + $b * $__WV2_iPtrSize, $b + 5)
	$__WV2_pObj[$i][$iSlot] = $pBase + ($b + 4) * $__WV2_iPtrSize
EndFunc   ;==>__WV2_BuildHandler
```

One global `DllStruct` owns all the memory:

```autoit
$__WV2_tHeap = DllStructCreate("ptr data[" & ($__WV2_MAX * $__WV2_SLOT_COUNT * $__WV2_PTRS_PER_BLOCK) & "]")
```

16 instances × 14 slots × 5 pointers = **1120 pointers**, allocated once, on first use, and
never resized. A global struct has no copy semantics, so the addresses stay valid for the
life of the script — a callback running while AutoIt reallocates a local array would be a
use-after-free waiting to happen.

### One callback set, fourteen entry points

There is no per-instance AutoIt function. There is one `QueryInterface`, one `AddRef`, one
`Release`, and one `Invoke` per slot (`$__WV2_aInvFunc`), registered once with
`DllCallbackRegister`. The `Invoke` receives `$pThis`, and `__WV2_FindInst` maps that
pointer back to *(instance, slot)*:

```autoit
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
```

A linear scan of at most 224 comparisons, against a callback that fires on a user action —
the cost is irrelevant, and it buys a completely uniform callback set. This is also why the
`Invoke` signatures can differ per slot: the argument list is registered from
`$__WV2_aInvArgs`, so a two-argument completion handler (`this, hr`) and a three-argument
event handler (`this, sender, args`) coexist in the same block.

### QueryInterface is a gate, not a formality

Each slot answers for `IUnknown` and for the handler interface of **its own** slot, and
nothing else:

```autoit
If $bKnown And ($sIID = $WV2_IID_UNKNOWN Or $sIID = $__WV2_aInvIID[$iSlot]) Then $pOut = $pThis
DllStructSetData(DllStructCreate("ptr", $pPPV), 1, $pOut)
If $pOut = 0 Then Return $__WV2_HR_E_NOINTERFACE
Return 0
```

Claiming an interface whose vtable you do not carry is the fastest way to kill the process:
the runtime would call `Invoke` at a slot your object does not have. The `$__WV2_aInvIID`
table is what prevents that.

`AddRef` returns 1 and `Release` returns 0, both without touching memory. These objects
live in the UDF's heap and are freed by `__WV2_FreeHandlers`, never by the runtime. The
counters are deliberately meaningless: a fake object that "releases" itself would dangle
the moment the runtime kept a pointer. `__WV2_FindInst` failing is a normal outcome — a
late callback after teardown — and every `Invoke` returns early in that case.

### Subscribing: the token is the receipt

`add_Xxx(handler, ByRef token)` returns an `EventRegistrationToken` (`int64`) that
`remove_Xxx(token)` needs. `__WV2_Attach` / `__WV2_Detach` keep one token per
(instance, slot) and refuse to subscribe twice. The method name cannot be built at run
time in AutoIt, so each slot gets its own `Case` — a little repetition standing in for a
dispatch mechanism AutoIt does not have.

`NavigationCompleted` is subscribed by `_WV2_Create` itself: `_WV2_WaitNavigation` waits on
it, and a handle without it could never report that a page finished loading.

---

## 3. Vtable ranks, verified against `WebView2.h`

### The numbering rule

Slot 0 is `QueryInterface`, 1 is `AddRef`, 2 is `Release`. The first method an interface
declares is at slot 3. A versioned interface (`ICoreWebView2_4`, say) inherits the whole
chain: its first own method sits right after the last method of every earlier version.

```
slot(method) = 3 + number of methods declared before it in the whole chain
```

That count must be taken from the **official header**, never from memory, and never from a
summary page: the SDK's `WebView2.h` is the only authoritative order.

### The slots this UDF calls raw

| Constant | Slot | What it is |
|---|---:|---|
| `$__WV2_VT_QI` | 0 | `IUnknown::QueryInterface` |
| `$__WV2_VT_RELEASE` | 2 | `IUnknown::Release` |
| `$__WV2_VT_PUTBOUNDS` | 6 | `ICoreWebView2Controller::put_Bounds` (x64 path only) |
| `$__WV2_VT_GETCOOKIE` | 66 | `ICoreWebView2_2::get_CookieManager` |
| `$__WV2_VT_ADDDL` | 75 | `ICoreWebView2_4::add_DownloadStarting` |
| `$__WV2_VT_REMOVEDL` | 76 | `ICoreWebView2_4::remove_DownloadStarting` |
| `$__WV2_VT_PRINTTOPDF` | 80 | `ICoreWebView2_7::PrintToPdf` |
| `$__WV2_VT_DLA_OP` | 3 | `DownloadStartingEventArgs::get_DownloadOperation` |
| `$__WV2_VT_DLA_CANCEL` | 5 | `DownloadStartingEventArgs::put_Cancel` |
| `$__WV2_VT_DLA_PATH` | 6 | `DownloadStartingEventArgs::get_ResultFilePath` |
| `$__WV2_VT_DLA_PATHPUT` | 7 | `DownloadStartingEventArgs::put_ResultFilePath` |
| `$__WV2_VT_DLO_URI` | 9 | `DownloadOperation::get_Uri` |
| `$__WV2_VT_COOKIEDALL` | 10 | `ICoreWebView2CookieManager::DeleteAllCookies` |

Every number in that table was counted from the header, then confirmed at run time by
calling the slot and checking the HRESULT — and, for the ones with an observable effect, by
looking at the effect (chapter 4).

### A tag may stop early; it may not skip

`$__WV2_TAG_WV` stops at `get_DocumentTitle`. That is legal: a tag describes the methods
you intend to call, and an object only knows the ones you declared. What is **not** legal
is a tag that skips a method in the middle — the wrapper counts positions, so a missing
entry shifts everything after it by one and the call lands on the wrong function.

That is the whole reason `PrintToPdf` (slot 80) is not in a tag. A complete
`ICoreWebView2_7` tag would carry several hundred lines for one call, and the wrapper would
gain nothing: `DllCallAddress` needs the same three arguments and one constant.

### QI is the version check

Asking for `ICoreWebView2_7` on a runtime older than that interface returns
`E_NOINTERFACE` (`0x80004002`) — not a crash, not a silent failure:

```autoit
Func __WV2_ViewIf($i, $iIf)
	If $__WV2_pWvIf[$i][$iIf] <> 0 Then Return $__WV2_pWvIf[$i][$iIf]
	...
	$__WV2_pWvIf[$i][$iIf] = __WV2_QiView($i, $sIID)
	Return $__WV2_pWvIf[$i][$iIf]
EndFunc   ;==>__WV2_ViewIf
```

`__WV2_QiView` converts the textual IID with `CLSIDFromString` (the sixteen bytes
`QueryInterface` wants), calls slot 0 on the **raw** view pointer, and keeps the returned
pointer. It is asked once per version per instance and released with the view. The
distinction it makes matters:

- `E_NOINTERFACE` → `$WV2_ERR_CALL` with that HRESULT: the machine's runtime is older than
  the feature. The caller degrades; the UDF does not lie about it.
- any other failure → the UDF's own bookkeeping is wrong.

---

## 4. ABI traps: x86 against x64, with `put_Bounds` as the case study

### Two conventions, one tag

`ICoreWebView2Controller::put_Bounds` takes a `RECT` **by value**.

- **x86 (stdcall):** the four `long`s are pushed on the stack. The wrapper tag
  `put_Bounds hresult(long;long;long;long)` describes exactly that, and it works.
- **x64 (Microsoft calling convention):** the first four arguments travel in `RCX`, `RDX`,
  `R8`, `R9`. A structure that does not fit in eight bytes is **never** passed by value:
  the caller passes its address. The header still says "by value" — the wire says
  "pointer".

So on x64 the callee expects `RCX = this`, `RDX = address of the RECT`. Give it four longs
and it reads `left` as a pointer and dereferences it. That is the crash.

### What was measured

Four shapes were tried on the 64-bit runtime, in a scratch script that logged each step to
a file (a crash truncates the console, not a flushed file):

| Argument shape | Result |
|---|---|
| Four `long` in a tag (the correct x86 shape) | process terminates |
| Two `int64` (the sixteen bytes packed in two registers) | process terminates |
| AutoIt's by-value `"struct"` | process terminates |
| `ptr` to a `DllStruct` of four `long`, through the vtable | `hr = 0`, bounds applied |

The fourth becomes the only 64-bit path:

```autoit
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
```

No single tag can be correct on both bitnesses here, which is why the function branches
rather than carrying one declaration.

### `hr = 0` is not proof

The first version of the 64-bit fix returned `S_OK` and did nothing visible. `S_OK` only
means the call arrived; it says nothing about what the callee did with the arguments. The
fix was accepted only after three independent proofs:

- `GetPixel` on the parent window: inside the browser area the pixel is the page's colour,
  outside it is the GUI's background;
- the boundary moved when the window was resized and `_WV2_SetBounds` was called again;
- `get_Bounds` read back exactly the rectangle that had been sent.

Apply that rule to every raw call you add: find an observable consequence and check it.

### The other shapes you will meet

| Value | AutoIt type | Note |
|---|---|---|
| `HRESULT` | `"long"` | negative failure values; `@extended` keeps it |
| `BOOL` | `"int"` / `hresult(int*)` | 32-bit, never `"bool"` (one byte) |
| `long` / `DWORD` | `"long"` | 32-bit on **both** bitnesses (LLP64 on x64) |
| `EventRegistrationToken` | `"int64"` | by value on `remove_*`, by pointer on `add_*` |
| `LPWSTR` returned by the runtime | `"wstr*"` | allocated with `CoTaskMemAlloc` |
| interface out-parameter | `"ptr*"` | carries its own reference |

A text returned by the runtime is copied and freed by `__WV2_WStrProp`; a returned
interface pointer is released with `__WV2_ReleaseExternal` unless it is wrapped and becomes
the UDF's property.

---

## 5. Adding an interface method in six steps

Worked example: `_WV2_ClearCookies`, which needs two calls that no tag in the UDF carries —
`ICoreWebView2_2::get_CookieManager` (slot 66) and
`ICoreWebView2CookieManager::DeleteAllCookies` (slot 10).

### Step 1 — Find the declaration

Open `WebView2.h` from the WebView2 SDK (MIT, on NuGet). Locate the interface that declares
the method: here `get_CookieManager` is on `ICoreWebView2_2`, `DeleteAllCookies` on
`ICoreWebView2CookieManager`. Note the exact parameter list and the return type of each
argument you need.

### Step 2 — Turn the position into a slot

Count every method declared before it in the whole inheritance chain, add 3. Record the
number as a named constant next to the others, with the interface name in the comment —
a bare `66` in the middle of a function is unreviewable:

```autoit
Global Const $__WV2_VT_GETCOOKIE = 66             ; ICoreWebView2_2::get_CookieManager
Global Const $__WV2_VT_COOKIEDALL = 10            ; ICoreWebView2CookieManager::DeleteAllCookies
```

### Step 3 — Ask the view for that interface version

```autoit
Local $p2 = __WV2_ViewIf($iHandle, $__WV2_IF_2)
If $p2 = 0 Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
```

If `$p2` is 0 because of `E_NOINTERFACE`, the runtime is older than the feature.
`__WV2_SetErr` has already recorded that, and the public function propagates it unchanged.

### Step 4 — Write the call shape

Four helpers cover most methods; anything else goes through `DllCallAddress` directly.

| Helper | Signature it calls |
|---|---|
| `__WV2_CallNoArg($pObj, $slot)` | `hr Method()` |
| `__WV2_CallBool($pObj, $slot, $v)` | `hr Method(BOOL)` |
| `__WV2_CallWStr($pObj, $slot, $s)` | `hr Method(LPCWSTR)` |
| `__WV2_WStrProp($pObj, $slot)` | `hr get_X(LPWSTR*)` — returns the text |

`get_CookieManager` is none of these: it returns an interface pointer, so it is written
out. Three checks follow every raw call — `@error`, the HRESULT, and a non-null pointer:

```autoit
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
```

### Step 5 — Own what comes back

An interface returned through an out-parameter carries its **own** reference;
`QueryInterface` and every getter that hands out an object do this. Either wrap it and
release it with the rest of the instance, or release it as soon as you are done:

```autoit
Local $hr = __WV2_CallNoArg($pCookie, $__WV2_VT_COOKIEDALL)
__WV2_ReleaseExternal($pCookie)
```

Text is different: it is `CoTaskMemAlloc`'d, so it is copied (`__WV2_CopyWStr`) and then
freed with `CoTaskMemFree` — never handed to the caller as-is.

### Step 6 — Wrap it, then prove it

The public function is guard, arguments, call, `__WV2_Result`, and a documented failure:

```autoit
Func _WV2_ClearCookies($iHandle)
	$__WV2_sLastFunc = "_WV2_ClearCookies"
	If Not __WV2_Guard($iHandle) Then Return SetError($__WV2_iLastError, $__WV2_iLastHR, 0)
	...
	Local $bOk = __WV2_Result($hr, "ICoreWebView2CookieManager::DeleteAllCookies")
	Return SetError($__WV2_iLastError, $__WV2_iLastHR, $bOk)
EndFunc   ;==>_WV2_ClearCookies
```

Then add a check to `WebView2_Example_GUI.au3` (`--auto`) that exercises the new call and
asserts its **effect**, not its return value. The existing suite is the specification of
what must keep working; a feature without a check there is a feature that will silently
break.

### When to extend a tag instead

If the interface is fully declared in the tag up to the method you need, and you expect to
call several of its methods, extending the tag is cheaper and type-checked by AutoIt's own
argument conversion. The rule of thumb: one call → raw slot; a family of calls → tag.

---

## 6. Diagnosing: `@error`, HRESULT, and a crash that prints nothing

### The error plumbing

Every failure goes through one function:

```autoit
Func __WV2_SetErr($iErr, $iHR, $sFunc)
	$__WV2_iLastError = $iErr
	$__WV2_iLastHR = Number($iHR)
	$__WV2_sLastFunc = $sFunc
EndFunc   ;==>__WV2_SetErr
```

The public function returns `SetError($__WV2_iLastError, $__WV2_iLastHR, <value>)`, so
`@error` carries the category and `@extended` the raw HRESULT. `_WV2_GetLastErrorMessage()`
turns both into one line:

```
Method call failed in ICoreWebView2_7::PrintToPdf (HRESULT 0x80070005)
```

Three habits make that usable:

- **Never `Return f()`.** `SetError` does not survive a plain `Return`; every public
  function sets `@error`/`@extended` explicitly. This was a real bug in an earlier version,
  invisible on success paths.
- **Set the label at the call site.** `"ICoreWebView2_7::PrintToPdf"` tells you which
  method failed; `"PrintToPdf"` does not.
- **The UDF never prints and never shows a dialog.** A script can run in a service, under
  a scheduler, with no console. Diagnostics are values, not output.

### Reading an HRESULT

| Value | Name | Usual cause here |
|---|---|---|
| `0x80004001` | `E_NOTIMPL` | the runtime does not implement this method |
| `0x80004002` | `E_NOINTERFACE` | runtime older than the interface version |
| `0x80004005` | `E_FAIL` | the call was made, the runtime refused |
| `0x80070002` | `ERROR_FILE_NOT_FOUND` | path handed to the runtime does not exist |
| `0x80070005` | `ERROR_ACCESS_DENIED` | profile or output folder not writable |
| `0x80070057` | `E_INVALIDARG` | wrong argument shape — suspect the ABI (chapter 4) |

### A crash that prints nothing

A wrong slot or a wrong argument shape does not return an HRESULT: the process
disappears. The console loses whatever was buffered, which makes "no output" look like an
early exit. Bisect like this:

1. Write a scratch script with `ConsoleWrite` **and** `FileWriteLine` on a handle opened
   with `$FO_APPEND`, flushed after each line.
2. Call the suspect method last, with everything else already proven.
3. Comment out the call: if the script completes, the call is the killer.
4. Vary one thing at a time — the slot, then each argument's type, then the order of the
   returned value and the release.
5. When a shape succeeds, do not stop: prove the effect (chapter 4).

Two less obvious traps:

- A **wrong-arity call to your own AutoIt function** is a runtime fatal, not a compile
  error: `Au3Check` passes, the script exits 1 with a truncated log. If a probe dies with
  no message, count the arguments before suspecting COM.
- `ObjCreateInterface` on a pointer the operating system owns crashed the process in this
  build. Reading `Release` from the vtable (`__WV2_ReleaseExternal`) does not. When a
  wrapper is not yours, do not wrap it.

### Asynchronous methods

`ExecuteScript`, `AddScriptToExecuteOnDocumentCreated`, `CapturePreview` and `PrintToPdf`
answer through a handler, later. The pattern is the same for all four:

```autoit
__WV2_BeginOp($iHandle, $__WV2_H_PRINT)      ; clear the state
Local $aCall = DllCallAddress(...)            ; start
__WV2_WaitOp($iHandle, $__WV2_H_PRINT, $iMs)  ; pump until the handler answered
Local $iDoneHR = $__WV2_iOpHR[$iHandle][$__WV2_H_PRINT]
```

`__WV2_WaitOp` pumps the message queue in 20 ms slices, so the GUI keeps repainting while
the script waits. Three distinct failures must stay distinguishable, and
`_WV2_PrintToPdf` shows all three:

- the call itself failed → `$WV2_ERR_CALL` with its HRESULT;
- the handler reported an HRESULT → `$WV2_ERR_CALL` with **that** HRESULT;
- the call succeeded and the handler answered `FALSE` → `$WV2_ERR_FILE`, because a PDF
  that was not written is not a method failure.

### The event queue

Events are pushed into a 64-entry ring per instance (`$__WV2_QCAP`) and dropped oldest-first
when the script does not drain them (`$__WV2_iEvtDrop` keeps the count). `_WV2_GetEvent`
on an empty queue returns 0 with `@error = 0`: **empty is not an error**, and a loop must
tell the two apart. `_WV2_WaitEvent` waits for one specific type, leaving the others in
the queue.

---

## 7. Threading, the message pump, and teardown order

### One apartment, one thread

`CoInitializeEx(NULL, COINIT_APARTMENTTHREADED)` runs once per script, on the thread that
called `_WV2_Create`. The browser is created in that apartment and delivers every event on
that thread, through the Windows message queue. Consequences:

- a view belongs to the thread that created it; calling it from another thread is
  undefined behaviour, and no marshalling is done;
- nothing arrives until messages are dispatched — no pump, no events, no completion
  handlers, no navigation progress;
- `_WV2_Create` and every waiter pump while they wait, which is why a script can block on
  a page load and still repaint.

### The pump

```autoit
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
EndFunc   ;==>__WV2_Pump
```

`PM_REMOVE` (1), every message, no filtering: the WebView2 runtime posts its work as
ordinary window messages, and filtering them out would starve it. `Sleep(2)` when the queue
is empty keeps a waiter from spinning a core.

### Inside a GUI loop

The pattern that works: do not wait inside `GUIGetMsg` handlers. Either wait before
entering the loop, or let the main loop pump (it already does) and read events with
`_WV2_GetEvent`. A long `_WV2_WaitNavigation` inside a button handler freezes the toolbar
for as long as the page takes — correctly, visibly, and avoidably.

### Teardown order

`_WV2_Destroy` is a strict sequence, because an interface must outlive every pointer taken
from it:

1. `remove_*` every handler subscription (needs the tokens);
2. release the `ICoreWebView2_2/_4/_7` pointers obtained by `QueryInterface`;
3. release the settings object;
4. release the web view;
5. `Close()` the controller, then release it;
6. release the environment;
7. return the slot to the table and drop the temporary profile folder.

Reversing 4 and 2 leaves the runtime holding an interface into freed memory; the crash
usually happens at exit, far from the cause.

### The browser is a window, not a control

`_WV2_Create($hParent, …)` puts a real child window inside `$hParent`. It covers every
AutoIt control whose rectangle overlaps its own, and `GUICtrlSetResizing` does not apply —
it has no control identifier. Either reserve a band of the client area for the toolbar, or
call `_WV2_FitToParent` / `_WV2_SetBounds` from the resize handler.

---

## 8. Runtime limits, pitfalls, references

### Limits of the wrapper

| Limit | Value | Where it comes from |
|---|---|---|
| Concurrent views | 16 | `$__WV2_MAX` |
| Handler objects per view | 14 | `$__WV2_SLOT_COUNT` |
| Queued events per view | 64 | `$__WV2_QCAP`, oldest dropped |
| Create timeout | 15 s | `$WV2_CREATE_TIMEOUT` |
| Navigation timeout | 30 s | `$WV2_NAV_TIMEOUT` |
| Script / print timeout | 5 s / 30 s | `$WV2_EXEC_TIMEOUT`, `$WV2_PRINT_TIMEOUT` |
| Zoom range | 0.2 … 10 | validated by `_WV2_SetZoom` |

### Pitfalls worth knowing before they cost a day

- **The loaderless entry point is undocumented.** `CreateWebViewEnvironmentWithOptionsInternal`
  is stable in practice and confined to one `DllCall` in `_WV2_Create`. If a future
  runtime ever moved it, the fallback is to ship `WebView2Loader.dll` and change that one
  call — nothing else in the UDF touches it.
- **A temporary profile lives longer than the view.** The browser process holds the folder
  for a few seconds after `_WV2_Destroy`, which cannot always delete it; the next
  `_WV2_Create` on the same slot does. Pass your own `$sUserDataFolder` when the profile
  must survive or be audited.
- **Cookies need an origin.** A `file://` page or `NavigateToString` has a null origin and
  cannot store a cookie: `document.cookie` stays empty by design, and this is not a bug in
  the bridge.
- **`_WV2_ClearCookies` clears cookies only.** Cache, history and localStorage need
  `ICoreWebView2Profile2::ClearBrowsingData`, which the view does not expose.
- **Chromium allows one automatic download per page.** A second scripted download is
  dropped silently and raises no event. A redirected download reaches the disk 0–3 s after
  `DownloadStarting` — wait for the file instead of concluding it failed.
- **`_WV2_SetNavigationFilter` needs `$WV2_EVENT_NAVIGATION_STARTING` enabled.** The filter
  is applied by that handler; without the subscription there is nothing to cancel.
- **`_WV2_ExecuteScript` returns JSON.** `document.title` comes back as `"Hello"` (quotes
  included), a number as `42`, and a script that throws as `null` with `@error = 0`. Test
  for `"null"` rather than for failure.
- **`BOOL` is four bytes.** `"bool"` in a `DllCall` is one byte and will corrupt the stack
  on the way back. Every `BOOL` in this UDF is `"int"`.

### Testing

`WebView2_Example_GUI.au3 /auto` runs 111 checks over the whole API without network access
(`file://` and `NavigateToString` pages) and leaves nothing on disk. It passed on AutoIt
3.3.16.1 in x86 and x64. Use it as the regression gate for any change described in
chapter 5, and add the new check **before** the implementation when you can.

### References

- WebView2 API reference — <https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/>
- `ICoreWebView2Controller` — <https://learn.microsoft.com/microsoft-edge/webview2/reference/win32/icorewebview2controller>
- `WebView2.h` in the WebView2 SDK (NuGet, MIT) — the authoritative vtable order
- Microsoft x64 calling convention — <https://learn.microsoft.com/cpp/build/x64-calling-convention>
- Forum thread *Microsoft Edge - WebView2* — <https://www.autoitscript.com/forum/topic/204362-microsoft-edge-webview2/>
- Ralle1976/Autoit-WebView2-UDF — <https://github.com/Ralle1976/Autoit-WebView2-UDF>
- Author profile — <https://www.autoitscript.com/forum/profile/118605-numeric1/>
- PDFX, the UDF that typeset this guide — <https://www.autoitscript.com/forum/topic/213930-udf-pdfx/>

### License

MIT, Copyright (c) 2026 Numeric1. Keep the `LICENSE` file and the `Author` / `License`
lines of every source header in any copy or redistribution.

WebView2 itself is Microsoft's. The interface identifiers and vtable layout used here follow
their SDK, which is MIT-licensed; no Microsoft code is reproduced in this package.

### Colophon

The PDF edition of this guide is typeset with **PDFX 1.4.0**, the author's other UDF:
<https://www.autoitscript.com/forum/topic/213930-udf-pdfx/>. Contents, bookmarks, internal
links and the cover are generated by PDFX; the PDF contains no image and every figure is
drawn with its vector primitives.

Numeric1 on the AutoIt forum:
<https://www.autoitscript.com/forum/profile/118605-numeric1/>.
