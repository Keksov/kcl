# TList Properties (System.Classes.TList)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList_Properties).

## `System.Classes.TList.Capacity`

```pascal
property Capacity: Integer read FCapacity write SetCapacity;
```

## Description

Specifies the allocated size of the array of pointers maintained by the [TList](/Libraries/Sydney/en/System.Classes.TList) object.

Set [Capacity]() to the number of pointers the list will need to contain. When setting the [Capacity]() property, an EOutOfMemory exception occurs if there is not enough memory to expand the list to its new size.

Read [Capacity]() to learn number of objects the list can hold without reallocating memory. Do not confuse [Capacity]() with the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property, which is the number of entries in the list that are in use. The value of [Capacity]() is always greater than or equal to the value of [Count](/Libraries/Sydney/en/System.Classes.TList.Count). When [Capacity]() is greater than [Count](/Libraries/Sydney/en/System.Classes.TList.Count), the unused memory can be reclaimed by setting [Capacity]() to [Count](/Libraries/Sydney/en/System.Classes.TList.Count).

When an object is added to a list that is already filled to capacity, the [Capacity]() property is automatically increased. Setting [Capacity]() before adding objects can reduce the number of memory reallocations and thereby improve performance. For example,

> 
**Note:**  Delphi example:

List.Clear;
List.Capacity := Count;
for I := 1 to Count do List.Add(...);

> 
**Note:**  C++ example:

List->Clear();
List->Capacity = Count;
for (int I = 0; I < Count; I++)
  List->Add(...);

The assignment to [Capacity]() before the for loop ensures that each of the following [Add](/Libraries/Sydney/en/System.Classes.TList.Add) operations doesn't cause the list to be reallocated. Avoiding reallocations on the calls to [Add](/Libraries/Sydney/en/System.Classes.TList.Add) improves performance and ensures that the [Add](/Libraries/Sydney/en/System.Classes.TList.Add) operations never raise an exception.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Capacity)

---

## `System.Classes.TList.Count`

```pascal
property Count: Integer read FCount write SetCount;
```

## Description

Indicates the number of entries in the list that are in use.

Read [Count]() to determine the number of entries in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Increasing the size of [Count]() will add the necessary number of nil (Delphi) or NULL (C++) pointers to the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. Decreasing the size of [Count]() will remove the necessary number of entries from the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[Count]() is not always the same as the number of objects referenced in the list. Some of the entries in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array may contain nil (Delphi) or NULL (C++) pointers. To remove the nil (Delphi) or NULL (C++) pointers and set [Count]() to the number of entries that contain references to objects, call the [Pack](/Libraries/Sydney/en/System.Classes.TList.Pack) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Count)

---

## `System.Classes.TList.Items`

```pascal
property Items[Index: Integer]: Pointer read Get write Put; default;
```

## Description

Lists the object references.

Use [Items]() to obtain a pointer to a specific object in the array. The `Index` parameter indicates the index of the object, where 0 is the index of the first object, 1 is the index of the second object, and so on. Set [Items]() to change the reference at a specific location.

Use [Items]() with the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property to iterate through all of the objects in the list.

Not all of the entries in the [Items]() array need to contain references to objects. Some of the entries may be nil (Delphi) or NULL (C++) pointers. To remove the nil (Delphi) or NULL (C++) pointers and reduce the size of the [Items]() array to the number of objects, call the [Pack](/Libraries/Sydney/en/System.Classes.TList.Pack) method.

> 
**Note:**  [Items]() is the default property for [TList](/Libraries/Sydney/en/System.Classes.TList). This means you can omit the property name. Thus, instead of MyList.[Items]()[i], you can write MyList[i].

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Items)

---

## `System.Classes.TList.List`

```pascal
property List: TPointerList read FList;
```

## Description

Specifies the array of pointers that make up the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Use [List]() to gain direct access to the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.List)

---

# TList Methods (System.Classes.TList)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList_Methods).

## `System.Classes.TList.Add`

```pascal
function Add(Item: Pointer): Integer;
```

## Description

Inserts a new item at the end of the list.

Call [Add]() to insert a new object at the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. [Add]() returns the index of the new item, where the first item in the list has an index of 0.

[Add]() increments [Count](/Libraries/Sydney/en/System.Classes.TList.Count) and, if necessary, allocates memory by increasing the value of [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity).

> 
**Note:**  [Add]() always inserts the Item pointer at the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array, even if the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array contains nil (Delphi) or NULL (C++) pointers.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Add)

---

## `System.Classes.TList.Assign`

```pascal
procedure Assign(ListA: TList; AOperator: TListAssignOp = laCopy; ListB: TList = nil);
```

## Description

Copies elements of one list to another.

Call [Assign]() to assign the elements of another list to this one. [Assign]() combines the source list with this one using the logical operator specified by the `AOperator` parameter.

If the `ListB` parameter is specified (Delphi) or not NULL (C++), then [Assign]() first replaces all the elements of this list with those in `ListA`, and then merges `ListB` into this list using the operator specified by `AOperator`.

If the `ListB` parameter is not specified (Delphi) or NULL (C++), then [Assign]() merges `ListA` into this list using the operator specified by `AOperator`.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Assign)

---

## `System.Classes.TList.Clear`

```pascal
procedure Clear; virtual;
```

## Description

Deletes all items from the list.

Call [Clear]() to empty the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array and set the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) to 0. [Clear]() also frees the memory used to store the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array and sets the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) to 0.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Clear)

---

## `System.Classes.TList.Create`

```pascal
/* TObject.Create */ inline __fastcall TList() : System::TObject() { }
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Create)

---

## `System.Classes.TList.Delete`

```pascal
procedure Delete(Index: Integer);
```

## Description

Removes the item at the position given by the `Index` parameter.

Call [Delete]() to remove the item at a specific position from the list. The index is zero-based, so the first item has an `Index` value of 0, the second item has an `Index` value of 1, and so on. Calling [Delete]() moves up all items in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array that follow the deleted item, and reduces the [Count](/Libraries/Sydney/en/System.Classes.TList.Count).

To remove the reference to an item without deleting the entry from the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array and changing the [Count](/Libraries/Sydney/en/System.Classes.TList.Count), set the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) property for `Index` to nil (Delphi) or NULL (C++).

> 
**Note:** [Delete]() does not free any memory associated with the item. The object can be freed by overriding the [Notify](/Libraries/Sydney/en/System.Classes.TList.Notify) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Delete)

---

## `System.Classes.TList.Destroy`

```pascal
destructor Destroy; override;
```

## Description

[Destroys]() an instance of [TList](/Libraries/Sydney/en/System.Classes.TList).

Do not call [Destroy]() directly. Instead, call Free. Free verifies that the [TList](/Libraries/Sydney/en/System.Classes.TList) reference is not nil, and only then calls [Destroy]().

[Destroy]() frees the memory used to store the list of items.

> 
**Note:**  [Destroy]() does not free the memory pointed to by the elements of the list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Destroy)

---

## `System.Classes.TList.Destroy`

```pascal
destructor Destroy; override;
```

## Description

[Destroys]() an instance of [TList](/Libraries/Sydney/en/System.Classes.TList).

Do not call [Destroy]() directly. Instead, call Free. Free verifies that the [TList](/Libraries/Sydney/en/System.Classes.TList) reference is not nil, and only then calls [Destroy]().

[Destroy]() frees the memory used to store the list of items.

> 
**Note:**  [Destroy]() does not free the memory pointed to by the elements of the list.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Destroy)

---

## `System.Classes.TList.Error`

```pascal
class procedure Error(const Msg: string; Data: NativeInt); overload; virtual;
class procedure Error(Msg: PResStringRec; Data: NativeInt); overload;
```

## Description

Raises an [EListError](/Libraries/Sydney/en/System.Classes.EListError) exception.

Call [Error]() to raise an exception when an error occurs while working with a [TList](/Libraries/Sydney/en/System.Classes.TList) object. [Error]() assembles an error message from the format string (or resource string) passed as the `Msg` parameter and the data value passed as the `Data` parameter, and then raises an [EListError](/Libraries/Sydney/en/System.Classes.EListError) exception. 

Call [Error]() rather than adding a line such as 

raise EListError.CreateFmt(MyMsg, iBadValue);

or

resourcestring sBadValueMessage = '%s not a valid list value';
  ...
EListError.Create(@sBadValueMessage, iBadValue);
throw EListError(MyMsg, iBadValue);

to reduce the code size of an application.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Error)

---

## `System.Classes.TList.Exchange`

```pascal
procedure Exchange(Index1, Index2: Integer);
```

## Description

Swaps the position of two items in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Call [Exchange]() to swap the positions of the items at positions `Index1` and `Index1` of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. The indexes are zero-based, so the first item in the list has an index value of 0, the second item has an index value of 1, and so on.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Exchange)

---

## `System.Classes.TList.Items`

```pascal
property Items[Index: Integer]: Pointer read Get write Put; default;
```

## Description

Lists the object references.

Use [Items]() to obtain a pointer to a specific object in the array. The `Index` parameter indicates the index of the object, where 0 is the index of the first object, 1 is the index of the second object, and so on. Set [Items]() to change the reference at a specific location.

Use [Items]() with the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property to iterate through all of the objects in the list.

Not all of the entries in the [Items]() array need to contain references to objects. Some of the entries may be nil (Delphi) or NULL (C++) pointers. To remove the nil (Delphi) or NULL (C++) pointers and reduce the size of the [Items]() array to the number of objects, call the [Pack](/Libraries/Sydney/en/System.Classes.TList.Pack) method.

> 
**Note:**  [Items]() is the default property for [TList](/Libraries/Sydney/en/System.Classes.TList). This means you can omit the property name. Thus, instead of MyList.[Items]()[i], you can write MyList[i].

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Items)

---

## `System.Classes.TList.Expand`

```pascal
function Expand: TList;
```

## Description

Increases the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) of the list.

Call [Expand]() to create more space for adding new items to the list. [Expand]() does nothing if the list is not already filled to [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity).

If [Count](/Libraries/Sydney/en/System.Classes.TList.Count) = [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity), [Expand]() increases the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) of the list as follows. If the value of [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) is greater than 8, [Expand]() increases the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) of the list by 16. If the value of [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) is greater than 4, but less than 9, the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) of the list increases by 8. If the value of [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) is less than 4, the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) of the list grows by 4.

The returned value is the expanded list object.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Expand)

---

## `System.Classes.TList.Capacity`

```pascal
property Capacity: Integer read FCapacity write SetCapacity;
```

## Description

Specifies the allocated size of the array of pointers maintained by the [TList](/Libraries/Sydney/en/System.Classes.TList) object.

Set [Capacity]() to the number of pointers the list will need to contain. When setting the [Capacity]() property, an EOutOfMemory exception occurs if there is not enough memory to expand the list to its new size.

Read [Capacity]() to learn number of objects the list can hold without reallocating memory. Do not confuse [Capacity]() with the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property, which is the number of entries in the list that are in use. The value of [Capacity]() is always greater than or equal to the value of [Count](/Libraries/Sydney/en/System.Classes.TList.Count). When [Capacity]() is greater than [Count](/Libraries/Sydney/en/System.Classes.TList.Count), the unused memory can be reclaimed by setting [Capacity]() to [Count](/Libraries/Sydney/en/System.Classes.TList.Count).

When an object is added to a list that is already filled to capacity, the [Capacity]() property is automatically increased. Setting [Capacity]() before adding objects can reduce the number of memory reallocations and thereby improve performance. For example,

> 
**Note:**  Delphi example:

List.Clear;
List.Capacity := Count;
for I := 1 to Count do List.Add(...);

> 
**Note:**  C++ example:

List->Clear();
List->Capacity = Count;
for (int I = 0; I < Count; I++)
  List->Add(...);

The assignment to [Capacity]() before the for loop ensures that each of the following [Add](/Libraries/Sydney/en/System.Classes.TList.Add) operations doesn't cause the list to be reallocated. Avoiding reallocations on the calls to [Add](/Libraries/Sydney/en/System.Classes.TList.Add) improves performance and ensures that the [Add](/Libraries/Sydney/en/System.Classes.TList.Add) operations never raise an exception.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Capacity)

---

## `System.Classes.TList.Extract`

```pascal
function Extract(Item: Pointer): Pointer; inline;
```

## Description

Removes a specified item from the list.

Call [Extract]() to remove an item from the list. After the item is removed, all the objects that follow it are moved up in index position and [Count](/Libraries/Sydney/en/System.Classes.TList.Count) is decremented.

To remove the reference to an item without deleting the entry from the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array and changing the [Count](/Libraries/Sydney/en/System.Classes.TList.Count), set the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) property for `Index` to nil (Delphi) or NULL (C++).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Extract)

---

## `System.Classes.TList.ExtractItem`

```pascal
function ExtractItem(Item: Pointer; Direction: TDirection): Pointer;
```

## Description

Removes a specified item from the list.

Call [ExtractItem]() to remove an item from a list. After the item is removed, the index positions of all the objects that follow it are moved up and [Count](/Libraries/Sydney/en/System.Classes.TList.Count) is decremented. 

In descendent classes, [ExtractItem]() also calls the notify method specifying the value of the removed item. This allows descendent classes to perform a proper cleanup with stored values. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.ExtractItem)

---

## `System.Classes.TList.First`

```pascal
function First: Pointer; inline;
```

## Description

Returns [Items](/Libraries/Sydney/en/System.Classes.TList.Items)[0].

Call [First]() to get the first pointer in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.First)

---

## `System.Classes.TList.Get`

```pascal
function Get(Index: Integer): Pointer;
```

## Description

Returns an item given its index in the list.

[Get]() is the getter method for the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) property. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Get)

---

## `System.Classes.TList.GetEnumerator`

```pascal
function GetEnumerator: TListEnumerator; inline;
```

## Description

Returns a TList enumerator.

[GetEnumerator]() returns a [TListEnumerator](/Libraries/Sydney/en/System.Classes.TListEnumerator) reference, which enumerates all items in the list. 

To do so, call the [TListEnumerator](/Libraries/Sydney/en/System.Classes.TListEnumerator) [GetCurrent](/Libraries/Sydney/en/System.Classes.TListEnumerator.GetCurrent) method within a While [MoveNext](/Libraries/Sydney/en/System.Classes.TListEnumerator.MoveNext) do loop. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.GetEnumerator)

---

## `System.Classes.TList.Grow`

```pascal
procedure Grow; virtual;
```

## Description

Increases the list capacity.

Call the [Grow]() method to increase the size of the [TList](/Libraries/Sydney/en/System.Classes.TList) list. Call the [SetCapacity](/Libraries/Sydney/en/System.Classes.TList.SetCapacity) method to set a new capacity for the list, otherwise [Grow]() will increase it with a default number of [Items](/Libraries/Sydney/en/System.Classes.TList.Items). 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Grow)

---

## `System.Classes.TList.IndexOf`

```pascal
function IndexOf(Item: Pointer): Integer;
```

## Description

Returns the index of the first entry in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array with a specified value.

Call [IndexOf]() to get the index for a pointer in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. Specify the pointer as the `Item` parameter. 

The first item in the array has index 0, the second item has index 1, and so on. If an item is not in the list, [IndexOf]() returns -1. If a pointer appears more than once in the array, [IndexOf]() returns the index of the first appearance.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.IndexOf)

---

## `System.Classes.TList.IndexOfItem`

```pascal
function IndexOfItem(Item: Pointer; Direction: TDirection): Integer;
```

## Description

Returns the item's index.

Call [IndexOfItem]() to determine the location of an item in the [TList](/Libraries/Sydney/en/System.Classes.TList) list, using a linear search. If the item is not found, -1 is returned. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.IndexOfItem)

---

## `System.Classes.TList.Insert`

```pascal
procedure Insert(Index: Integer; Item: Pointer);
```

## Description

Adds an object to the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array at the position specified by `Index`.

Call [Insert]() to add Item to the middle of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. The `Index` parameter is a zero-based index, so the first position in the array has an index of 0. [Insert]() adds the item at the indicated position, shifting the item that previously occupied that position, and all subsequent items, up. [Insert]() increments [Count](/Libraries/Sydney/en/System.Classes.TList.Count) and, if necessary, allocates memory by increasing the value of [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity).

To replace a nil (Delphi) or NULL (C++) pointer in the array with a new item, without growing the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array, set the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) property.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Insert)

---

## `System.Classes.TList.Last`

```pascal
function Last: Pointer;
```

## Description

Returns [Items](/Libraries/Sydney/en/System.Classes.TList.Items)[Count - 1].

Call [Last]() to retrieve the last pointer in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Last)

---

## `System.Classes.TList.Move`

```pascal
procedure Move(CurIndex, NewIndex: Integer);
```

## Description

Changes the position of an item in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Call [Move]() to move the item at the position `CurIndex` so that it occupies the position `NewIndex`. `CurIndex` and `NewIndex` are zero-based indexes into the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Move)

---

## `System.Classes.TList.Notify`

```pascal
procedure Notify(Ptr: Pointer; Action: TListNotification); virtual;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Notify)

---

## `System.Classes.TList.operator []`

```pascal
void * operator[](int Index) { return this->Items[Index]; }
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.operator_H5BH5D)

---

## `System.Classes.TList.Pack`

```pascal
procedure Pack;
```

## Description

Deletes all nil (Delphi) or NULL (C++) items from the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Call [Pack]() to move all non-nil (Delphi) or non-NULL (C++) items to the front of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array and reduce the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property to the number of items actually used. [Pack]() does not free up the memory used to store the nil (Delphi) or NULL (C++) pointers. To free up the memory for the unused entries removed by [Pack](), set the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) property to the new value of [Count](/Libraries/Sydney/en/System.Classes.TList.Count).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Pack)

---

## `System.Classes.TList.Put`

```pascal
procedure Put(Index: Integer; Item: Pointer);
```

## Description

Stores an item at a specified position in the list.

[Put]() is the protected write implementation of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) property. [Put]() replaces an item from the [TList](/Libraries/Sydney/en/System.Classes.TList) list with a specified item. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Put)

---

## `System.Classes.TList.Remove`

```pascal
function Remove(Item: Pointer): Integer; inline;
```

## Description

Deletes the first reference to the Item parameter from the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Call [Remove]() to remove a specific item from the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array when its index is unknown. The value returned is the index of the item in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array before it was removed. After an item is removed, all the items that follow it are moved up in index position and the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) is reduced by one.

If the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array contains more than one copy of the pointer, only the first copy is deleted.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Remove)

---

## `System.Classes.TList.RemoveItem`

```pascal
function RemoveItem(Item: Pointer; Direction: TDirection): Integer;
```

## Description

Removes an item from the list.

The [RemoveItem]() method removes a specified item from the list. Because the search of the item is linear, it is an O(n) operation on a list with n entries. If the item is not found, -1 is returned. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.RemoveItem)

---

## `System.Classes.TList.SetCapacity`

```pascal
procedure SetCapacity(NewCapacity: Integer);
```

## Description

Sets the value of the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) property.

[SetCapacity]() is the setter method for the [Capacity](/Libraries/Sydney/en/System.Classes.TList.Capacity) property. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.SetCapacity)

---

## `System.Classes.TList.SetCount`

```pascal
procedure SetCount(NewCount: Integer);
```

## Description

Sets the value of the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property.

[SetCount]() is the getter method for the [Count](/Libraries/Sydney/en/System.Classes.TList.Count) property. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.SetCount)

---

## `System.Classes.TList.Count`

```pascal
property Count: Integer read FCount write SetCount;
```

## Description

Indicates the number of entries in the list that are in use.

Read [Count]() to determine the number of entries in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

Increasing the size of [Count]() will add the necessary number of nil (Delphi) or NULL (C++) pointers to the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. Decreasing the size of [Count]() will remove the necessary number of entries from the end of the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array.

[Count]() is not always the same as the number of objects referenced in the list. Some of the entries in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array may contain nil (Delphi) or NULL (C++) pointers. To remove the nil (Delphi) or NULL (C++) pointers and set [Count]() to the number of entries that contain references to objects, call the [Pack](/Libraries/Sydney/en/System.Classes.TList.Pack) method.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Count)

---

## `System.Classes.TList.Sort`

```pascal
procedure Sort(Compare: TListSortCompare);
```

## Description

Performs a QuickSort on the list based on the comparison function Compare.

Call [Sort]() to sort the items in the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) array. Compare is a comparison function that indicates how the items are to be ordered. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.Sort)

---

## `System.Classes.TList.SortList`

```pascal
procedure SortList(const Compare: TListSortCompareFunc);
```

## Description

Performs a QuickSort on list of items.

Call [SortList]() to sort the [Items](/Libraries/Sydney/en/System.Classes.TList.Items) in the [TList](/Libraries/Sydney/en/System.Classes.TList) list. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.Classes.TList.SortList)

---

