# TDirectory Methods (System.IOUtils.TDirectory)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory_Methods).

## `System.IOUtils.TDirectory.Copy`

```pascal
class procedure Copy(const SourceDirName, DestDirName: string); static;
```

## Description

Copies a directory and its contents.

Use [Copy]() to copy a directory and its contents from a given path to another path. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `SourceDirName` | The path of the source directory that will be copied. |
| `DestDirName` | The destination path to which the directory will be copied. |

> 
**Note:**  [Copy]() raises an exception if the given paths are invalid, do not exist, or cannot be accessed. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.Copy)

---

## `System.IOUtils.TDirectory.CreateDirectory`

```pascal
class procedure CreateDirectory(const Path: string); static;
```

## Description

Creates a new directory at the given path.

Use [CreateDirectory]() to create a new directory at the given path. If the directories given in the path do not yet exist, [CreateDirectory]() attempts to create them. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory being created. |

> 
**Note:**  [CreateDirectory]() raises an exception if the given `Path` is invalid or contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.CreateDirectory)

---

## `System.IOUtils.TDirectory.Delete`

```pascal
class procedure Delete(const Path: string); overload; inline; static;
class procedure Delete(const Path: string; const Recursive: Boolean);  overload; static;
```

## Description

Deletes a directory at the given path.

Use [Delete]() to delete a directory at the given path. The following table lists the parameters this method expects: 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory being deleted. |
| `Recursive` | The deletion is recursive. If this parameter is **false**, nonempty directories will not be deleted. |

The second version of [Delete]() does not expect a `Recursive` parameter; it is considered to be **false**. This means that the second version of [Delete]() will fail on nonempty directories. Neither version of [Delete]() reports whether the deletion operation succeeded. 

> 
**Note:**  [Delete]() raises an exception if the given `Path` is invalid or contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.Delete)

---

## `System.IOUtils.TDirectory.Exists`

```pascal
class function Exists(const Path: string; FollowLink: Boolean = True): Boolean; inline; static;
```

## Description

Checks whether a given directory exists.

Use [Exists]() to check whether a given directory exists. [Exists]() returns **True** if the given path exists and is a directory, and **False** otherwise. 

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Path` | Path of the directory being checked |
| `FollowLink` | Specifies whether the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is used. |

> 
**Note:**  If the given path is invalid, the [Exists]() method simply returns **False**. 

> 
**Note:** If the `Path` parameter is a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) and the `FollowLink` parameter is set to **True**, the method is performed on the [target directory](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec.TargetName). If the first condition is **True**, but the `FollowLink` parameter is set to **False**, the method will be performed on the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec). If the link is broken, the method will always return **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.Exists)

---

## `System.IOUtils.TDirectory.GetAttributes`

```pascal
class function GetAttributes(const Path: string; FollowLink: Boolean = True): TFileAttributes; inline; static;
```

## Description

Returns the directory attributes.

Call [GetAttributes]() to obtain the attributes for a given directory. The return value of [GetAttributes]() is a set of [TFileAttribute](/Libraries/Sydney/en/System.IOUtils.TFileAttribute) values; each value of the set represents a file attribute. 

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Path` | The path to the directory for which the attributes are obtained. |
| `FollowLink` | Specifies whether the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is used. |

> 
**Note:** [GetAttributes]() raises an exception if the directory cannot be accessed or the path is invalid. 

> 
**Note:** If the `Path` parameter is a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) and the `FollowLink` parameter is set to **True**, the method is performed on the [target directory](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec.TargetName). If the first condition is **True**, but the `FollowLink` parameter is set to **False**, the method will be performed on the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec). If the link is broken, the method will always return **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetAttributes)

---

## `System.IOUtils.TDirectory.GetCreationTime`

```pascal
class function GetCreationTime(const Path: string): TDateTime; static;
```

## Description

Returns the creation time of a directory.

Use [GetCreationTime]() to obtain the creation time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the creation time is obtained. |

> 
**Note:**  [GetCreationTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetCreationTime)

---

## `System.IOUtils.TDirectory.GetCreationTimeUtc`

```pascal
class function GetCreationTimeUtc(const Path: string): TDateTime; static;
```

## Description

Returns the creation time of a directory in UTC (Coordinated Universal Time) time zone.

Use [GetCreationTimeUtc]() to obtain the creation time of a directory in UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the creation time is obtained. |

> 
**Note:**  [GetCreationTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetCreationTimeUtc)

---

## `System.IOUtils.TDirectory.GetCurrentDirectory`

```pascal
class function GetCurrentDirectory: string; {$IFDEF MSWINDOWS} inline; {$ENDIF} static;
```

## Description

Returns the current working directory.

Use [GetCurrentDirectory]() to get the current directory. [GetCurrentDirectory]() returns the path of the directory considered current for the application. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetCurrentDirectory)

---

## `System.IOUtils.TDirectory.GetDirectories`

```pascal
class function GetDirectories(const Path: string): TStringDynArray;
class function GetDirectories(const Path: string;  const Predicate: TFilterPredicate): TStringDynArray;
class function GetDirectories(const Path,  SearchPattern: string): TStringDynArray; overload; inline; static;
class function GetDirectories(const Path, SearchPattern: string;  const Predicate: TFilterPredicate): TStringDynArray;
class function GetDirectories(const Path, SearchPattern: string;  const SearchOption: TSearchOption): TStringDynArray; overload; static;
class function GetDirectories(const Path, SearchPattern: string;  const SearchOption: TSearchOption; const Predicate: TFilterPredicate): TStringDynArray; overload; static;
class function GetDirectories(const Path: string;  const SearchOption: TSearchOption; const Predicate: TFilterPredicate): TStringDynArray; overload; static;
```

## Description

Returns a list of subdirectories in a given directory.

Use [GetDirectories]() to obtain a list of subdirectories in a given directory. The return value of [GetDirectories]() is a dynamic array of strings in which each element stores the name of a subdirectory. 

There are three forms of the [GetDirectories]() method: 

The first form only accepts the path of the directory for which subdirectories are enumerated.
The second form includes a search pattern used when matching subdirectory names.
The third form includes an option specifying whether a recursive mode will be used while enumerating.

All the forms also accept an optional [TFilterPredicate](/Libraries/Sydney/en/System.IOUtils.TDirectory.TFilterPredicate) parameter, used to filter the results. 

The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path of the directory for which subdirectories are enumerated. |
| `SearchPattern` | The mask used when matching directory names (for example, "*app" matches all the directories ending with "app"). |
| `SearchOption` | The directory enumeration mode. Specifies whether the top-level or recursive enumeration mode will be used. |
| `Predicate` | A routine used to filter out undesired results. |

> 
**Note:**  [GetDirectories]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetDirectories)

---

## `System.IOUtils.TDirectory.GetDirectoryRoot`

```pascal
class function GetDirectoryRoot(const Path: string): string; static;
```

## Description

Returns the root directory for a given path.

Use [GetDirectoryRoot]() to obtain the root directory for a given path. Relative paths are considered relative to the application working directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path for which the root directory will be obtained. |

> 
**Note:**  [GetDirectoryRoot]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetDirectoryRoot)

---

## `System.IOUtils.TDirectory.GetFiles`

```pascal
class function GetFiles(const Path: string): TStringDynArray;
class function GetFiles(const Path: string;  const Predicate: TFilterPredicate): TStringDynArray;
class function GetFiles(const Path, SearchPattern: string): TStringDynArray;
class function GetFiles(const Path, SearchPattern: string;  const Predicate: TFilterPredicate): TStringDynArray;
class function GetFiles(const Path, SearchPattern: string;  const SearchOption: TSearchOption): TStringDynArray; overload; static;
class function GetFiles(const Path, SearchPattern: string;  const SearchOption: TSearchOption; const Predicate: TFilterPredicate): TStringDynArray; overload; static;
class function GetFiles(const Path: string;  const SearchOption: TSearchOption; const Predicate: TFilterPredicate): TStringDynArray; overload; static;
```

## Description

Returns a list of files in a given directory.

Use [GetFiles]() to obtain a list of files in a given directory. The return value of [GetFiles]() is a dynamic array of strings in which each element stores the name of a file. 

There are three forms of the [GetFiles]() method: 

The first form accepts only the path of the directory for which files are enumerated.
The second form includes a search pattern used when matching file names.
The third form includes an option specifying whether a recursive mode will be used while enumerating.

All the forms also accept an optional [TFilterPredicate](/Libraries/Sydney/en/System.IOUtils.TDirectory.TFilterPredicate) parameter, used to filter the results. 

The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path of the directory for which files are enumerated. |
| `SearchPattern` | The mask is used when matching file names (for example, "*.exe" matches all the executable files). You can also use [MatchesMask](/Libraries/Sydney/en/System.Masks.MatchesMask) when applying a SearchPattern argument. |
| `SearchOption` | The directory enumeration mode. Specifies whether the top-level or recursive enumeration mode will be used. |
| `Predicate` | A routine used to filter out undesired results. |

**Note:**  [GetFiles]() raises an exception if the given path is invalid or the directory does not exist.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetFiles)

---

## `System.IOUtils.TDirectory.GetFileSystemEntries`

```pascal
class function GetFileSystemEntries(const Path: string): TStringDynArray;
class function GetFileSystemEntries(const Path: string;  const Predicate: TFilterPredicate): TStringDynArray;
class function GetFileSystemEntries(const Path,  SearchPattern: string): TStringDynArray; overload; static;
class function GetFileSystemEntries(const Path, SearchPattern: string;  const Predicate: TFilterPredicate): TStringDynArray; overload; static;
class function GetFileSystemEntries(const Path: string;  const SearchOption: TSearchOption; const Predicate: TFilterPredicate): TStringDynArray; overload; static;
```

## Description

Returns a list of files and subdirectories in a given directory.

Use [GetFileSystemEntries]() to obtain a list of files and subdirectories in a given directory. The return value of [GetFileSystemEntries]() is a dynamic array of strings in which each element stores the name of a file or subdirectory. 

There are two forms of the [GetFileSystemEntries]() method: 

The first form accepts only the path of the directory for which files and subdirectories are enumerated.
The second form includes a search pattern used when matching subdirectory names.

All the forms also accept an optional [TFilterPredicate](/Libraries/Sydney/en/System.IOUtils.TDirectory.TFilterPredicate) parameter, used to filter the results. 

The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path of the directory for which subdirectories are enumerated. |
| `SearchPattern` | The mask used when matching directory names (for example, "*app" matches all the files and directories ending with "app"). |
| `Predicate` | A routine used to filter out undesired results. |

> 
**Note:**  [GetFileSystemEntries]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetFileSystemEntries)

---

## `System.IOUtils.TDirectory.GetLastAccessTime`

```pascal
class function GetLastAccessTime(const Path: string): TDateTime; static;
```

## Description

Returns the last access time of a directory.

Use [GetLastAccessTime]() to obtain the last access time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last access time is obtained. |

> 
**Note:**  [GetLastAccessTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetLastAccessTime)

---

## `System.IOUtils.TDirectory.GetLastAccessTimeUtc`

```pascal
class function GetLastAccessTimeUtc(const Path: string): TDateTime; static;
```

## Description

Returns the last access time of a directory in UTC (Coordinated Universal Time) time zone.

Use [GetLastAccessTimeUtc]() to obtain the last access time of a directory in UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last access time is obtained. |

> 
**Note:**  [GetLastAccessTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetLastAccessTimeUtc)

---

## `System.IOUtils.TDirectory.GetLastWriteTime`

```pascal
class function GetLastWriteTime(const Path: string): TDateTime; static;
```

## Description

Returns the last write time of a directory.

Use [GetLastWriteTime]() to obtain the last write time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last write time is obtained. |

> 
**Note:**  [GetLastWriteTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetLastWriteTime)

---

## `System.IOUtils.TDirectory.GetLastWriteTimeUtc`

```pascal
class function GetLastWriteTimeUtc(const Path: string): TDateTime; static;
```

## Description

Returns the last write time of a directory in UTC (Coordinated Universal Time) time zone.

Use [GetLastWriteTimeUtc]() to obtain the last write time of a directory in UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last write time is obtained. |

> 
**Note:**  [GetLastWriteTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetLastWriteTimeUtc)

---

## `System.IOUtils.TDirectory.GetLogicalDrives`

```pascal
class function GetLogicalDrives: TStringDynArray; static;
```

## Description

Returns a list of all logical drives present on this computer.

Use [GetLogicalDrives]() to get a list of all logical drives present on this computer. [GetLogicalDrives]() returns a dynamic array of strings in which each element is a character that identifies a logical drive. 

> 
**Note:** [GetLogicalDrives]() only returns a valid result on the **Windows** platform. On **POSIX**, it returns an empty array.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetLogicalDrives)

---

## `System.IOUtils.TDirectory.GetParent`

```pascal
class function GetParent(const Path: string): string; static;
```

## Description

Returns the parent directory of another directory.

Use [GetParent]() to obtain the parent directory for a given path. Relative paths are considered relative to the application working directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path for which the parent directory will be obtained. |

> 
**Note:**  [GetParent]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.GetParent)

---

## `System.IOUtils.TDirectory.IsEmpty`

```pascal
class function IsEmpty(const Path: string): Boolean; static;
```

## Description

Checks whether a given directory is empty.

Call [IsEmpty]() to check whether a given directory is empty. An empty directory is considered to have no files or other directories in it. [IsEmpty]() returns **true** if the directory is empty; **false** otherwise. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory being checked. |

> 
**Note:**  If the `Path` parameter is an empty string, [IsEmpty]() returns **false**. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.IsEmpty)

---

## `System.IOUtils.TDirectory.IsRelativePath`

```pascal
class function IsRelativePath(const Path: string): Boolean; inline; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.IsRelativePath)

---

## `System.IOUtils.TDirectory.Move`

```pascal
class procedure Move(const SourceDirName, DestDirName: string); static;
```

## Description

Moves or renames a directory and its contents.

Use [Move]() to move or rename a directory and its contents from a given path to another path. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `SourceDirName` | The path of the source directory that will be moved. |
| `DestDirName` | The destination path to which the directory will be moved. |

> 
**Note:**  [Move]() raises an exception if the given paths are invalid, do not exist, or cannot be accessed. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.Move)

---

## `System.IOUtils.TDirectory.SetAttributes`

```pascal
class procedure SetAttributes(const Path: string;  const Attributes: TFileAttributes); inline; static;
```

## Description

Sets the directory attributes.

Call [SetAttributes]() to apply a new set of attributes to a given directory. 

The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the directory for which the attributes are obtained. |
| `Attributes` | The new set of attributes applied to the directory. |

> 
**Note:**  [SetAttributes]() raises an exception if the directory cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetAttributes)

---

## `System.IOUtils.TDirectory.SetCreationTime`

```pascal
class procedure SetCreationTime(const Path: string;  const CreationTime: TDateTime); static;
```

## Description

Changes the creation time of a directory.

Use [SetCreationTime]() to change the creation time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the creation time is changed. |
| `CreationTime` | The new creation time that will be applied to the directory. |

> 
**Note:**  [SetCreationTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetCreationTime)

---

## `System.IOUtils.TDirectory.SetCreationTimeUtc`

```pascal
class procedure SetCreationTimeUtc(const Path: string;  const CreationTime: TDateTime); static;
```

## Description

Changes the creation time of a directory.

Use [SetCreationTime](/Libraries/Sydney/en/System.IOUtils.TDirectory.SetCreationTime) to change the creation time of a directory. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the creation time is changed. |
| `CreationTime` | The new creation time that will be applied to the directory. |

> 
**Note:**  [SetCreationTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetCreationTimeUtc)

---

## `System.IOUtils.TDirectory.SetCurrentDirectory`

```pascal
class procedure SetCurrentDirectory(const Path: string); static;
```

## Description

Sets the current directory.

Use [SetCurrentDirectory]() to set the current working directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory that will be set as current. |

> 
**Note:**  [SetCurrentDirectory]() raises an exception if the given path is either invalid or cannot be set as current. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetCurrentDirectory)

---

## `System.IOUtils.TDirectory.SetLastAccessTime`

```pascal
class procedure SetLastAccessTime(const Path: string;  const LastAccessTime: TDateTime); static;
```

## Description

Changes the last access time of a directory.

Use [SetLastAccessTime]() to change the last access time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last access time is changed. |
| `LastAccessTime` | The new last access time that will be applied to the directory. |

> 
**Note:**  [SetLastAccessTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetLastAccessTime)

---

## `System.IOUtils.TDirectory.SetLastAccessTimeUtc`

```pascal
class procedure SetLastAccessTimeUtc(const Path: string;  const LastAccessTime: TDateTime); static;
```

## Description

Changes the last access time of a directory.

Use [SetLastAccessTimeUtc]() to change the last access time of a directory. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last access time is changed. |
| `LastAccessTime` | The new last access time that will be applied to the directory. |

> 
**Note:**  [SetLastAccessTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetLastAccessTimeUtc)

---

## `System.IOUtils.TDirectory.SetLastWriteTime`

```pascal
class procedure SetLastWriteTime(const Path: string;  const LastWriteTime: TDateTime); static;
```

## Description

Changes the last write time of a directory.

Use [SetLastWriteTime]() to change the last write time of a directory. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last write time is changed. |
| `LastAccessTime` | The new last write time that will be applied to the directory. |

> 
**Note:**  [SetLastWriteTime]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetLastWriteTime)

---

## `System.IOUtils.TDirectory.SetLastWriteTimeUtc`

```pascal
class procedure SetLastWriteTimeUtc(const Path: string;  const LastWriteTime: TDateTime); static;
```

## Description

Changes the last write time of a directory.

Use [SetLastWriteTimeUtc]() to change the last write time of a directory. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory for which the last write time is changed. |
| `LastWriteTime` | The new last write time that will be applied to the directory. |

> 
**Note:**  [SetLastWriteTimeUtc]() raises an exception if the given path is invalid or the directory does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TDirectory.SetLastWriteTimeUtc)

---

