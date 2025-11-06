# TStringList Properties (System.Classes.TStringList)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList_Properties).

## `System.Classes.TStringList.CaseSensitive`

```pascal
property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
```

## Description

Controls whether strings are located, sorted, and identified as duplicates in a case-sensitive or case-insensitive manner.

Use [CaseSensitive]() to indicate whether strings in the list should be compared in a case-sensitive or case-insensitive manner. Set [CaseSensitive]() to True to make the string list locate, check for duplicates, and sort its strings in a case-sensitive manner. Set [CaseSensitive]() to False to make the string list perform these operations case-insensitively. 

> 
**Note:**  By default, the [CaseSensitive]() property is set to **False**. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive)

---

## `System.Classes.TStringList.Duplicates`

```pascal
property Duplicates: TDuplicates read FDuplicates write FDuplicates;
```

## Description

Specifies whether duplicate strings can be added to sorted lists.

Set [Duplicates]() to specify what should happen when an attempt is made to add a duplicate string to a sorted list. The [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) property controls whether two strings are considered duplicates if they are identical except for differences in case.

The value of [Duplicates]() should be one of the following.

| **Value** | **Meaning** |
| --- | --- |
| dupIgnore | Ignore attempts to add duplicate strings to the list. |
| dupError | Raise an EStringListError exception when an attempt is made to add duplicate strings to the sorted list. |
| dupAccept | Permit duplicate strings in the sorted list. |

Set [Duplicates]() before adding any strings to the list. Setting [Duplicates]() to dupIgnore or dupError does nothing about duplicate strings that are already in the list.

> 
**Note:**  [Duplicates]() does nothing if the list is not sorted.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Duplicates)

---

## `System.Classes.TStringList.OwnsObjects`

```pascal
property OwnsObjects: Boolean read FOwnsObject write FOwnsObject;
```

## Description

Specifies whether the string list owns the objects it contains.

The [OwnsObjects]() property specifies whether the string list owns the stored objects or not. If the [OwnsObjects]() property is set to **True**, then the [Destroy](/Libraries/Sydney/en/System.Classes.TStringList.Destroy) destructor will free up the memory allocated for those objects.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.OwnsObjects)

---

## `System.Classes.TStringList.Sorted`

```pascal
property Sorted: Boolean read FSorted write SetSorted;
```

## Description

Specifies whether the strings in the list should be automatically sorted.

Set [Sorted]() to true to cause the strings in the list to be automatically sorted in ascending order. Set [Sorted]() to false to allow strings to remain where they are inserted. When [Sorted]() is false, the strings in the list can be put in ascending order at any time by calling the [Sort](/Libraries/Sydney/en/System.Classes.TStringList.Sort) method.

When [Sorted]() is true, do not use [Insert](/Libraries/Sydney/en/System.Classes.TStringList.Insert) to add strings to the list. Instead, use [Add](/Libraries/Sydney/en/System.Classes.TStringList.Add), which will insert the new strings in the appropriate position. When [Sorted]() is false, use [Insert](/Libraries/Sydney/en/System.Classes.TStringList.Insert) to add strings to an arbitrary position in the list, or [Add](/Libraries/Sydney/en/System.Classes.TStringList.Add) to add strings to the end of the list.

> 
**Note:**  The [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) property controls whether the strings in the list are sorted based on a case-sensitive or case-insensitive comparison. The sort order takes into account the locale of the system on which the application is running. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Sorted)

---

# TStringList Methods (System.Classes.TStringList)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList_Methods).

## `System.Classes.TStringList.Add`

```pascal
function Add(const S: string): Integer; override;
```

## Description

[Adds]() a new string to the list.

Call [Add]() to add the string S to the list. If the list is sorted, S is added to the appropriate position in the sort order. If the list is not sorted, S is added to the end of the list. [Add]() returns the position of the item in the list, where the first item in the list has a value of 0.

> 
**Note:**  For sorted lists, [Add]() will raise an EListError exception if the string S already appears in the list and [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupError. If [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupIgnore, trying to add a duplicate string causes [Add]() to return the index of the existing entry.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Add)

---

## `System.Classes.TStringList.Add`

```pascal
function Add(const S: string): Integer; override;
```

## Description

[Adds]() a new string to the list.

Call [Add]() to add the string S to the list. If the list is sorted, S is added to the appropriate position in the sort order. If the list is not sorted, S is added to the end of the list. [Add]() returns the position of the item in the list, where the first item in the list has a value of 0.

> 
**Note:**  For sorted lists, [Add]() will raise an EListError exception if the string S already appears in the list and [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupError. If [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupIgnore, trying to add a duplicate string causes [Add]() to return the index of the existing entry.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Add)

---

## `System.Classes.TStringList.AddObject`

```pascal
function AddObject(const S: string; AObject: TObject): Integer; override;
```

## Description

Adds a string to the list, and associates an object with the string.

Call [AddObject]() to add a string and its associated object to the list. [AddObject]() returns the index of the new string and object.

> 
**Note:**  If the [OwnsObjects](/Libraries/Sydney/en/System.Classes.TStringList.OwnsObjects) property is set to **False**, the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object does not own the objects you add using [AddObject](). Objects added to the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object still exist even if the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) instance is destroyed. They must be explicitly destroyed by the application. If you want the objects to be automatically freed upon destroying the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object, you should set [OwnsObjects](/Libraries/Sydney/en/System.Classes.TStringList.OwnsObjects) to **True** or use the overloaded [Create](/Libraries/Sydney/en/System.Classes.TStringList.Create) constructor that accepts the Boolean OwnsObjects parameter, when creating the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object.

> 
**Note:**  For sorted lists, [AddObject]() raises an EListError exception if the string S already appears in the list and [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupError. If [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to dupIgnore, trying to add a duplicate string causes [AddObject]() to return the index of the existing entry.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.AddObject)

---

## `System.Classes.TStringList.AddStrings`

```pascal
procedure AddStrings(Strings: TStrings); override;
```

## Description

Adds the specified strings (and objects) to the current [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) object.

System.Classes.TStringList.AddStrings inherits from [System.Classes.TStrings.AddStrings](/Libraries/Sydney/en/System.Classes.TStrings.AddStrings). All content below this line refers to [System.Classes.TStrings.AddStrings](/Libraries/Sydney/en/System.Classes.TStrings.AddStrings).

Adds the specified strings (and objects) to the current [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) object.

[AddStrings](/Libraries/Sydney/en/System.Classes.TStrings.AddStrings), with the Strings parameter of the [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) type, [appends](/Libraries/Sydney/en/System.Classes.TStrings.AddObject) strings and associated objects from the Strings object at the end of the string list in the current [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) object.

[AddStrings](/Libraries/Sydney/en/System.Classes.TStrings.AddStrings) with the Strings parameter representing the [array](/Libraries/Sydney/en/System.TArray) of strings, [appends](/Libraries/Sydney/en/System.Classes.TStrings.Add) strings from Strings array at the end of the string list in the current [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) object.

[AddStrings](/Libraries/Sydney/en/System.Classes.TStrings.AddStrings), with two parameters, [appends](/Libraries/Sydney/en/System.Classes.TStrings.Add) strings from Strings array at the end of the string list in the current [TStrings](/Libraries/Sydney/en/System.Classes.TStrings) object and associates references to objects from Objects with their strings (having the same numbers in Strings and Objects arrays).
If the number of strings in Strings is not equal to the number of objects in Objects, then an exception is raised.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.AddStrings)

---

## `System.Classes.TStringList.Assign`

```pascal
procedure Assign(Source: TPersistent); override;
```

## Description

Sets, from a source object, the strings in the list and the possibly associated objects.

Use [Assign]() to set the value of the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object from another object. If Source is of type [TStringList](/Libraries/Sydney/en/System.Classes.TStringList), the list is set to the list of the source [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object, and if associated objects are supported, any associated objects are copied from Source as well. 

If Source is not of type [TStringList](/Libraries/Sydney/en/System.Classes.TStringList), the inherited [Assign]() method will set the value of the list from any object that supports [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) in its [AssignTo](/Libraries/Sydney/en/System.Classes.TPersistent.AssignTo) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Assign)

---

## `System.Classes.TStringList.Changed`

```pascal
procedure Changed; virtual;
```

## Description

Fires an [OnChange](/Libraries/Sydney/en/System.Classes.TStringList.OnChange) event.

The [Changed]() method fires an [OnChange](/Libraries/Sydney/en/System.Classes.TStringList.OnChange) event.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Changed)

---

## `System.Classes.TStringList.OnChange`

```pascal
property OnChange: TNotifyEvent read FOnChange write FOnChange;
```

## Description

Occurs immediately after the list of strings changes.

Write an [OnChange]() event handler to respond to changes in the list of strings. For example, if the string list is associated with a control, the [OnChange]() event handler could tell the control to repaint itself whenever the content of the list changes.

Whenever strings in the list are added, deleted, moved, or modified, the following events take place:

An [OnChanging](/Libraries/Sydney/en/System.Classes.TStringList.OnChanging) event occurs before the change.
The strings are added, deleted, moved, or modified.
An [OnChange]() event occurs.
> 
**Note:** [OnChange]() occurs for every change made to the list, regardless of whether the application calls [BeginUpdate](/Libraries/Sydney/en/System.Classes.TStrings.BeginUpdate) and [EndUpdate](/Libraries/Sydney/en/System.Classes.TStrings.EndUpdate) around a series of changes.

OnChange is an event handler of type [System.Classes.TNotifyEvent](/Libraries/Sydney/en/System.Classes.TNotifyEvent).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.OnChange)

---

## `System.Classes.TStringList.Changing`

```pascal
procedure Changing; virtual;
```

## Description

Fires an [OnChanging](/Libraries/Sydney/en/System.Classes.TStringList.OnChanging) event.

The [Changing]() method fires an [OnChanging](/Libraries/Sydney/en/System.Classes.TStringList.OnChanging) event.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Changing)

---

## `System.Classes.TStringList.OnChanging`

```pascal
property OnChanging: TNotifyEvent read FOnChanging write FOnChanging;
```

## Description

Occurs immediately before the list of strings changes.

Write an [OnChanging]() event handler to prepare for changes in the list of strings. For example, if the string list is associated with a control, the [OnChanging]() event handler could tell the control to disable repaints until the [OnChange](/Libraries/Sydney/en/System.Classes.TStringList.OnChange) event is triggered, notifying the control that the list has finished changing.

Whenever strings in the list are added, deleted, moved, or modified, the following events take place:

An [OnChanging]() event occurs.
The strings are added, deleted, moved, or modified.
An [OnChange](/Libraries/Sydney/en/System.Classes.TStringList.OnChange) event occurs after the changes are complete.
> 
**Note:** [OnChanging]() occurs for every change made to the list, regardless of whether the application calls [BeginUpdate](/Libraries/Sydney/en/System.Classes.TStrings.BeginUpdate) and [EndUpdate](/Libraries/Sydney/en/System.Classes.TStrings.EndUpdate) around a series of changes.

[OnChanging]() is an event handler of type [TNotifyEvent](/Libraries/Sydney/en/System.Classes.TNotifyEvent).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.OnChanging)

---

## `System.Classes.TStringList.Clear`

```pascal
procedure Clear; override;
```

## Description

Deletes all the strings from the list.

Call clear to empty the list of strings. All references to associated objects are also removed. If the list owns the objects, they are freed, otherwise not.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Clear)

---

## `System.Classes.TStringList.CompareStrings`

```pascal
function CompareStrings(const S1, S2: string): Integer; override;
```

## Description

Compares two strings.

The [CompareStrings]() method is used to compare the values of strings that appear in the list.

S1 and S2 are the strings to compare.

[CompareStrings]() returns a value less than 0 if S1 < S2, 0 if S1 = S2, and a value greater than 0 if S1 > S2.

As implemented in [TStringList](/Libraries/Sydney/en/System.Classes.TStringList), [CompareStrings]() uses the global [AnsiCompareText](/Libraries/Sydney/en/System.SysUtils.AnsiCompareText) function, which compares strings case-insensitively if the [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) property is set to **False**. Otherwise, the case-sensitive [AnsiCompareStr](/Libraries/Sydney/en/System.SysUtils.AnsiCompareStr) method is used.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.CompareStrings)

---

## `System.Classes.TStringList.Create`

```pascal
constructor Create; overload;
constructor Create(OwnsObjects: Boolean); overload;
constructor Create(QuoteChar, Delimiter: Char); overload;
constructor Create(QuoteChar, Delimiter: Char; Options: TStringsOptions); overload;
constructor Create(Duplicates: TDuplicates; Sorted: Boolean; CaseSensitive: Boolean); overload;
```

## Description

[Creates]() an instance of a [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object.

The [Create]() constructor creates a new instance of the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object.

[Create]() has five overloaded methods:

Takes no parameters.
Accepts the OwnsObjects boolean parameter to specify whether the string list [owns the objects](/Libraries/Sydney/en/System.Classes.TStringList.OwnsObjects) or not.
Accepts the QuoteChar and Delimiter parameters to create a new string list with the specified [QuoteChar](/Libraries/Sydney/en/System.Classes.TStrings.QuoteChar) and [Delimiter](/Libraries/Sydney/en/System.Classes.TStrings.Delimiter) properties.
Accepts the QuoteChar, Delimiter and Options parameters to create a new string list with the specified [QuoteChar](/Libraries/Sydney/en/System.Classes.TStrings.QuoteChar), [Delimiter](/Libraries/Sydney/en/System.Classes.TStrings.Delimiter) and [Options](/Libraries/Sydney/en/System.Classes.TStrings.Options) properties.
Accepts the Duplicates, Sorted and CaseSensitive to create a new string list with the specified [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates), [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted), [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) properties.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Create)

---

## `System.Classes.TStringList.Create`

```pascal
constructor Create; overload;
constructor Create(OwnsObjects: Boolean); overload;
constructor Create(QuoteChar, Delimiter: Char); overload;
constructor Create(QuoteChar, Delimiter: Char; Options: TStringsOptions); overload;
constructor Create(Duplicates: TDuplicates; Sorted: Boolean; CaseSensitive: Boolean); overload;
```

## Description

[Creates]() an instance of a [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object.

The [Create]() constructor creates a new instance of the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object.

[Create]() has five overloaded methods:

Takes no parameters.
Accepts the OwnsObjects boolean parameter to specify whether the string list [owns the objects](/Libraries/Sydney/en/System.Classes.TStringList.OwnsObjects) or not.
Accepts the QuoteChar and Delimiter parameters to create a new string list with the specified [QuoteChar](/Libraries/Sydney/en/System.Classes.TStrings.QuoteChar) and [Delimiter](/Libraries/Sydney/en/System.Classes.TStrings.Delimiter) properties.
Accepts the QuoteChar, Delimiter and Options parameters to create a new string list with the specified [QuoteChar](/Libraries/Sydney/en/System.Classes.TStrings.QuoteChar), [Delimiter](/Libraries/Sydney/en/System.Classes.TStrings.Delimiter) and [Options](/Libraries/Sydney/en/System.Classes.TStrings.Options) properties.
Accepts the Duplicates, Sorted and CaseSensitive to create a new string list with the specified [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates), [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted), [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) properties.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Create)

---

## `System.Classes.TStringList.CustomSort`

```pascal
procedure CustomSort(Compare: TStringListSortCompare); virtual;
```

## Description

Sorts the strings in the list in a customized order.

Use [CustomSort]() to sort the strings in the list, where the sort order is defined by the Compare parameter. 

Supply a value for the Compare function that compares two strings in the string list. The `List` parameter provides access to the string list, while the Index1 and Index2 parameters identify the strings to be compared.

Do not pass nil (Delphi) or NULL (C++) as the value of the Compare parameter.

> 
**Note:**  You must explicitly call the [CustomSort]() method. Setting the [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted) property only sorts strings using ANSI (Windows) or UTF-8 (Linux) order, as implemented in the [Sort](/Libraries/Sydney/en/System.Classes.TStringList.Sort) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.CustomSort)

---

## `System.Classes.TStringList.Delete`

```pascal
procedure Delete(Index: Integer); override;
```

## Description

Removes the string specified by the `Index` parameter.

Call [Delete]() to remove a single string from the list. If an object is associated with the string, the reference to the object is removed as well. Index gives the position of the string, where 0 is the first string, 1 is the second string, and so on.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Delete)

---

## `System.Classes.TStringList.Destroy`

```pascal
destructor Destroy; override;
```

## Description

[Destroys]() an instance of [TStringList](/Libraries/Sydney/en/System.Classes.TStringList).

Do not call [Destroy]() directly in an application. Instead, call Free. Free verifies that the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) reference is not nil and only then calls [Destroy]().

[Destroy]() frees the memory allocated to hold the list of strings and object references before calling the inherited destructor.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Destroy)

---

## `System.Classes.TStringList.Destroy`

```pascal
destructor Destroy; override;
```

## Description

[Destroys]() an instance of [TStringList](/Libraries/Sydney/en/System.Classes.TStringList).

Do not call [Destroy]() directly in an application. Instead, call Free. Free verifies that the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) reference is not nil and only then calls [Destroy]().

[Destroy]() frees the memory allocated to hold the list of strings and object references before calling the inherited destructor.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Destroy)

---

## `System.Classes.TStringList.Exchange`

```pascal
procedure Exchange(Index1, Index2: Integer); override;
```

## Description

Swaps the position of two strings in the list.

Call [Exchange]() to rearrange the strings in the list. The strings are specified by their index values in the Index1 and Index2 parameters. Indexes are zero-based, so the first string in the list has an index value of 0, the second has an index value of 1, and so on.

If either string has an associated object, [Exchange]() changes the index of the object as well.

> 
**Warning:**  Do not call [Exchange]() on a sorted list except to swap two identical strings with different associated objects. [Exchange]() does not check whether the list is sorted, and can destroy the sort order of a sorted list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Exchange)

---

## `System.Classes.TStringList.ExchangeItems`

```pascal
procedure ExchangeItems(Index1, Index2: Integer);
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.ExchangeItems)

---

## `System.Classes.TStringList.Find`

```pascal
function Find(const S: string; var Index: Integer): Boolean; virtual;
```

## Description

Locates the index for a string in a sorted list and indicates whether a string with that value already exists in the list.

Use [Find]() to obtain the index in a sorted list where the string S should be added. If the string S, or a string that differs from S only in case when [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) is false, already exists in the list, [Find]() returns true. If the list does not contain a string that matches S, [Find]() returns false. The index where S should go is returned in the `Index` parameter. The value of `Index` is zero-based, where the first string has the index 0, the second string has the index 1, and so on.

> 
**Note:** Only use [Find]() with sorted lists. For unsorted lists, use the [IndexOf](/Libraries/Sydney/en/System.Classes.TStringList.IndexOf) method instead.

> 
**Tip:** If the S string is not found (thus return value of [Find]() is **False**) then Index is set to the index of the first string in the list that sorts immediately before or after S.

var
  Index: Integer;
  LStringList: TStringList;

begin
  LStringList := TStringList.Create;
  LStringList.Add('first string');
  LStringList.Add('second string');

  LStringList.Find('first string', Index); // Index = 0 because 'first string' is at index 0
  LStringList.Find('third string', Index); // Index = 2 because 'third string' sorts after 'second string'
  LStringList.Find('great string', Index); // Index = 1 because 'great string' would sort after 'first string', if it existed

  LStringList.Free;
end;

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Find)

---

## `System.Classes.TStringList.Get`

```pascal
function Get(Index: Integer): string; override;
```

## Description

Returns a string, given its index.

The [Get]() method is used to return the string with the specified Index.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Get)

---

## `System.Classes.TStringList.GetCapacity`

```pascal
function GetCapacity: Integer; override;
```

## Description

Returns the currently allocated size of the strings list.

The [GetCapacity]() method returns the currently allocated size of the strings list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.GetCapacity)

---

## `System.Classes.TStringList.GetCount`

```pascal
function GetCount: Integer; override;
```

## Description

Returns the number of strings in the list.

The [GetCount]() method is used to return the number of strings that have been added to the list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.GetCount)

---

## `System.Classes.TStringList.GetObject`

```pascal
function GetObject(Index: Integer): TObject; override;
```

## Description

Returns the object associated with the string at a specified index.

[GetObject]() is the protected read implementation of the [Objects](/Libraries/Sydney/en/System.Classes.TStrings.Objects) property. The method returns the object associated with the string at a specified index.

Index is the index of the string with which the object is associated.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.GetObject)

---

## `System.Classes.TStringList.IndexOf`

```pascal
function IndexOf(const S: string): Integer; override;
```

## Description

Returns the position of a [string](/Libraries/Sydney/en/System.String) in the list.

Call [IndexOf]() to obtain the position of the first occurrence of a string that matches `S`. A string matches `S` if it is identical to `S` or, if [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) is **False**, if they differ only in case.

[IndexOf]() will work in this way on the condition that [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted) is set to **False** and [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to `dupIgnore` or `dupError`. This reflects the internal definition of [IndexOf](), which calls [Find](/Libraries/Sydney/en/System.Classes.TStringList.Find) if `Sorted` is set to **True** and will locate any string in the list that matches the parameter `S`. Consequently, if [Duplicates](/Libraries/Sydney/en/System.Classes.TStringList.Duplicates) is set to `dupAccept`, the result will not always be the first string matching the parameter `S`.

Note that [IndexOf]() returns the 0-based index of the string. Thus, if `S` matches the first string in the list, [IndexOf]() returns 0, if `S` is the second string, [IndexOf]() returns 1, and so on. If the string does not have a match in the string list, [IndexOf]() returns -1. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.IndexOf)

---

## `System.Classes.TStringList.IndexOfName`

```pascal
function IndexOfName(const Name: string): Integer; override;
```

## Description

Returns the position of the first name-value pair with the specified name.

System.Classes.TStringList.IndexOfName inherits from [System.Classes.TStrings.IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName). All content below this line refers to [System.Classes.TStrings.IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName).

Returns the position of the first name-value pair with the specified name.

Call [IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName) to locate the first occurrence of a name-value pair where the name part is equal to the `Name` parameter or differs only in case. [IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName) returns the 0-based index of the string. If no string in the list has the indicated name, [IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName) returns -1.

> 
**Note:**  If there is more than one name-value pair with a name portion matching the `Name` parameter, [IndexOfName](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfName) returns the position of the first such string.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.IndexOfName)

---

## `System.Classes.TStringList.IndexOfObject`

```pascal
function IndexOfObject(AObject: TObject): Integer; override;
```

## Description

Returns the index of the first string in the list associated with a given object.

System.Classes.TStringList.IndexOfObject inherits from [System.Classes.TStrings.IndexOfObject](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfObject). All content below this line refers to [System.Classes.TStrings.IndexOfObject](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfObject).

Returns the index of the first string in the list associated with a given object.

Call [IndexOfObject](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfObject) to locate the first string in the list associated with the object AObject. Specify the object you want to locate as the value of the AObject parameter. [IndexOfObject](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfObject) returns the 0-based index of the string and object. If the object is not associated with any of the strings, [IndexOfObject](/Libraries/Sydney/en/System.Classes.TStrings.IndexOfObject) returns -1.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.IndexOfObject)

---

## `System.Classes.TStringList.Insert`

```pascal
procedure Insert(Index: Integer; const S: string); override;
```

## Description

[Inserts]() a string to the list at the position specified by `Index`.

Call [Insert]() to add the string S to the list at the position specified by `Index`. If `Index` is 0, the string is inserted at the beginning of the list. If `Index` is 1, the string is put in the second position of the list, and so on.

If the string has an associated object, use the [InsertObject](/Libraries/Sydney/en/System.Classes.TStringList.InsertObject) method instead.

> 
**Note:** If the list is sorted, calling [Insert]() or [InsertObject](/Libraries/Sydney/en/System.Classes.TStringList.InsertObject) will raise an [EListError](/Libraries/Sydney/en/System.Classes.EListError) exception. Use [Add](/Libraries/Sydney/en/System.Classes.TStringList.Add) or [AddObject](/Libraries/Sydney/en/System.Classes.TStringList.AddObject) with sorted lists.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Insert)

---

## `System.Classes.TStringList.Insert`

```pascal
procedure Insert(Index: Integer; const S: string); override;
```

## Description

[Inserts]() a string to the list at the position specified by `Index`.

Call [Insert]() to add the string S to the list at the position specified by `Index`. If `Index` is 0, the string is inserted at the beginning of the list. If `Index` is 1, the string is put in the second position of the list, and so on.

If the string has an associated object, use the [InsertObject](/Libraries/Sydney/en/System.Classes.TStringList.InsertObject) method instead.

> 
**Note:** If the list is sorted, calling [Insert]() or [InsertObject](/Libraries/Sydney/en/System.Classes.TStringList.InsertObject) will raise an [EListError](/Libraries/Sydney/en/System.Classes.EListError) exception. Use [Add](/Libraries/Sydney/en/System.Classes.TStringList.Add) or [AddObject](/Libraries/Sydney/en/System.Classes.TStringList.AddObject) with sorted lists.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Insert)

---

## `System.Classes.TStringList.InsertItem`

```pascal
procedure InsertItem(Index: Integer; const S: string; AObject: TObject); virtual;
```

## Description

Internally used by the [AddObject](/Libraries/Sydney/en/System.Classes.TStrings.AddObject) method.

The [InsertItem]() method is used internally by the [AddObject](/Libraries/Sydney/en/System.Classes.TStrings.AddObject) method to add a string and its associated object to the list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.InsertItem)

---

## `System.Classes.TStringList.InsertObject`

```pascal
procedure InsertObject(Index: Integer; const S: string;  AObject: TObject); override;
```

## Description

Inserts a string into the list at the specified position, and associates it with an object.

Call [InsertObject]() to insert the string S into the list at the position identified by `Index`, and associate it with the object AObject. If `Index` is 0, the string is inserted at the beginning of the list. If `Index` is 1, the string is put in the second position of the list, and so on.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.InsertObject)

---

## `System.Classes.TStringList.Put`

```pascal
procedure Put(Index: Integer; const S: string); override;
```

## Description

Changes the value of the string with a specified index.

[Put]() is the protected write implementation of the [Strings](/Libraries/Sydney/en/System.Classes.TStrings.Strings) property.

[Put]() changes the value of the string with the index specified by `Index` to S. [Put]() does not change the object at the specified position. That is, any object associated with the previous string becomes associated with the new string.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Put)

---

## `System.Classes.TStringList.PutObject`

```pascal
procedure PutObject(Index: Integer; AObject: TObject); override;
```

## Description

Changes the object associated with the string at a specified index.

[PutObject]() is the protected write implementation of the [Objects](/Libraries/Sydney/en/System.Classes.TStrings.Objects) property and is used to provide support for associating objects with the strings in the list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.PutObject)

---

## `System.Classes.TStringList.SetCapacity`

```pascal
procedure SetCapacity(NewCapacity: Integer); override;
```

## Description

Changes the amount of memory allocated to hold strings in the list.

[SetCapacity]() changes the number of strings that the list can hold. 

> 
**Note:** Assigning a value smaller than [Count](/Libraries/Sydney/en/System.Classes.TStrings.Count) removes strings from the end of the list. Assigning a value greater than [Count](/Libraries/Sydney/en/System.Classes.TStrings.Count) allocates space for more strings to be added.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.SetCapacity)

---

## `System.Classes.TStringList.SetUpdateState`

```pascal
procedure SetUpdateState(Updating: Boolean); override;
```

## Description

Performs internal adjustments before or after a series of updates.

[SetUpdateState]() is called at the beginning or end of a series of updates. When the [BeginUpdate](/Libraries/Sydney/en/System.Classes.TStrings.BeginUpdate) method is first called and if the [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) object is not already in the middle of an update, [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) calls [SetUpdateState]() internally, with `Updating` set to **True**. When the [EndUpdate](/Libraries/Sydney/en/System.Classes.TStrings.EndUpdate) method is called and it cancels out the last unmatched call to [BeginUpdate](/Libraries/Sydney/en/System.Classes.TStrings.BeginUpdate), [TStringList](/Libraries/Sydney/en/System.Classes.TStringList) calls [SetUpdateState]() internally, with `Updating` set to **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.SetUpdateState)

---

## `System.Classes.TStringList.Sort`

```pascal
procedure Sort; virtual;
```

## Description

Sorts the strings in the list in ascending order.

Call [Sort]() to sort the strings in a list that has the [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted) property set to false. String lists with the [Sorted](/Libraries/Sydney/en/System.Classes.TStringList.Sorted) property set to true are automatically sorted.

> 
**Note:**  [Sort]() uses AnsiCompareStr to sort the strings when [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) is true and AnsiCompareText when [CaseSensitive](/Libraries/Sydney/en/System.Classes.TStringList.CaseSensitive) is false. To provide your own comparison operator instead, use the [CustomSort](/Libraries/Sydney/en/System.Classes.TStringList.CustomSort) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TStringList.Sort)

---

