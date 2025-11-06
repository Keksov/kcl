# TFile Methods (System.IOUtils.TFile)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile_Methods).

## `System.IOUtils.TFile.AppendAllText`

```pascal
class procedure AppendAllText(const Path, Contents: string); overload; static;
class procedure AppendAllText(const Path, Contents: string;  const Encoding: TEncoding); overload; static;
```

## Description

Appends a given text to a file.

Use [AppendAllText]() to append a given text to a file. If the file specified by the `Path` parameter exists, the text is appended to it; otherwise, the file is created and filled with the given text. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file. |
| `Contents` | The string containing the text to be appended. |
| `Encoding` | The encoding used for the appended text. |

> 
**Note:**  [AppendAllText]() raises an exception if the file cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.AppendAllText)

---

## `System.IOUtils.TFile.AppendText`

```pascal
class function AppendText(const Path: string): TStreamWriter; static;
```

## Description

Opens a file in append mode.

Use [AppendText]() to open a file containing textual information in append mode. [AppendText]() opens the file if it exists and seeks to the end of the file; otherwise, [AppendText]() creates a new file. [AppendText]() returns a [TStreamWriter](/Libraries/Sydney/en/System.Classes.TStreamWriter) instance associated with the file opened file. After you finish using the [TStreamWriter](/Libraries/Sydney/en/System.Classes.TStreamWriter) instance, make sure you destroy it. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be opened or created. |

> 
**Note:**  [AppendText]() raises an exception if the file cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.AppendText)

---

## `System.IOUtils.TFile.Copy`

```pascal
class procedure Copy(const SourceFileName, DestFileName: string);  overload; inline; static;
class procedure Copy(const SourceFileName, DestFileName: string;  const Overwrite: Boolean); overload; static;
```

## Description

Copies a file to a given path.

Use [Copy]() to make a copy of a file. The first form of [Copy]() only accepts a source and destination paths. If the destination path points to an already existing file, [Copy]() raises an exception. The second form of [Copy]() accepts an optional `Overwrite` parameter. If set to **true**, the parameter forces the copy operation to continue even if the destination file already exists. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `SourceFileName` | The path to the file that is copied. |
| `DestFileName` | The destination path to which the file is copied. |
| `Overwrite` | Specifies whether the copy operation should proceed even if another one is at the `DestFileName` path. |

**Note:** [Copy]() raises an exception if the source file does not exist, the paths are invalid, or the user does not have enough privileges to perform the copy operation. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Copy)

---

## `System.IOUtils.TFile.Create`

```pascal
class function Create(const Path: string): TFileStream; overload; inline; static;
class function Create(const Path: string; const BufferSize: Integer): TFileStream; overload; static;
```

## Description

Creates a new file and returns a stream associated with that file.

Use [Create]() to create a new file and obtain a [TFileStream](/Libraries/Sydney/en/System.Classes.TFileStream) instance. [Create]() creates a new file at the given path and then creates a [TFileStream](/Libraries/Sydney/en/System.Classes.TFileStream) instance associated with that file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be created. |
| `BufferSize` | The size of the file operation buffer. |

> 
**Note:**  [Create]() raises an exception if the file cannot be created or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Create)

---

## `System.IOUtils.TFile.CreateSymLink`

```pascal
class function CreateSymLink(const Link, Target: string): Boolean; static;
```

## Description

[CreateSymLink]() creates a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec).

The [CreateSymLink]() method creates a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec).

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Link` | The name of the symbolic link |
| `Target` | The string containing the symbolic link |

> 
**Note:** The target file or directory must exist when calling [CreateSymLink]().

> 
**Note:** [CreateSymLink]() can be used on **Windows Vista** and later versions of Windows.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.CreateSymLink)

---

## `System.IOUtils.TFile.CreateText`

```pascal
class function CreateText(const Path: string): TStreamWriter; static;
```

## Description

Creates a new textual file and returns a text writer associated with that file.

Use [CreateText]() to create a new textual file and obtain a [TStreamWriter](/Libraries/Sydney/en/System.Classes.TStreamWriter) instance. [CreateText]() creates a new empty textual file at the given path and then creates a [TStreamWriter](/Libraries/Sydney/en/System.Classes.TStreamWriter) instance associated with that file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be created. |

> 
**Note:**  [CreateText]() raises an exception if the file cannot be created or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.CreateText)

---

## `System.IOUtils.TFile.Decrypt`

```pascal
class procedure Decrypt(const Path: string); static;
```

## Description

Decrypts a file at a given path.

Use [Decrypt]() to decrypt a given file using the operating system-provided facilities. The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that is to be decrypted. |

> 
**Note:** [Decrypt]() raises an exception if the source file does not exist, the paths are invalid, or the user does not have enough privileges to perform the decryption. 

> 
**Note:** [Decrypt]() is present only on the **Windows** platform, and can be used only on files that reside on **NTFS (New Technology File System)** partitions.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Decrypt)

---

## `System.IOUtils.TFile.Delete`

```pascal
class procedure Delete(const Path: string); static;
```

## Description

Deletes a file at the given path.

Use [Delete]() to delete a file at the given path. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the directory being deleted. |

> 
**Note:**  [Delete]() raises an exception if the given `Path` is invalid or is not a file. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Delete)

---

## `System.IOUtils.TFile.Encrypt`

```pascal
class procedure Encrypt(const Path: string); static;
```

## Description

Encrypts a file at a given path.

Use [Encrypt]() to encrypt a given file using the operating system-provided facilities. The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that is to be encrypted. |

> 
**Note:** [Encrypt]() raises an exception if the source file does not exist, the paths are invalid, or the user does not have enough privileges to perform the encryption. 

> 
**Note:** [Encrypt]() is present only on the **Windows** platform, and can be used only on files that reside on **NTFS (New Technology File System)** partitions.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Encrypt)

---

## `System.IOUtils.TFile.Exists`

```pascal
class function Exists(const Path: string; FollowLink: Boolean = True): Boolean; inline; static;
```

## Description

Checks whether a given file exists.

Use [Exists]() to check whether a given file exists. [Exists]() returns **True** if the given path exists and is a file and **False** otherwise. 

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Path` | Path of the file being checked |
| `FollowLink` | Specifies whether the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is used. |

> 
**Note:** If the given path is invalid, the [Exists]() method simply returns **False**. 

> 
**Note:** If the `Path` parameter is a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) and the `FollowLink` parameter is set to **True**, the method is performed on the [target file](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec.TargetName). If the first condition is **True**, but the `FollowLink` parameter is set to **False**, the method will be performed on the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec). If the link is broken, the method will always return **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Exists)

---

## `System.IOUtils.TFile.FileAttributesToInteger`

```pascal
class function FileAttributesToInteger(const Attributes: TFileAttributes): Integer; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.FileAttributesToInteger)

---

## `System.IOUtils.TFile.GetAttributes`

```pascal
class function GetAttributes(const Path: string; FollowLink: Boolean = True): TFileAttributes; inline; static;
```

## Description

Returns the file attributes.

Call [GetAttributes]() to obtain the attributes for a given file. The return value of [GetAttributes]() is a set of [TFileAttribute](/Libraries/Sydney/en/System.IOUtils.TFileAttribute) values; each value of the set represents a file attribute. 

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Path` | The path to the file for which the attributes are obtained. |
| `FollowLink` | Specifies whether the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is used. |

> 
**Note:** [GetAttributes]() raises an exception if the file cannot be accessed or the path is invalid. 

> 
**Note:** If the `Path` parameter is a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) and the `FollowLink` parameter is set to **True**, the method is performed on the [target file](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec.TargetName). If the first condition is **True** and the `FollowLink` parameter is set to **False**, the method will be performed on the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec). If the link is broken, the method will always return **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetAttributes)

---

## `System.IOUtils.TFile.GetCreationTime`

```pascal
class function GetCreationTime(const Path: string): TDateTime; inline; static;
```

## Description

Returns the creation time of a file.

Use [GetCreationTime]() to obtain the creation time of a file. 

On **POSIX** and **Mac**, a file system entry does not have a Creation Time defined. The only information that is available is the last modified and last accessed time.

> 
**Note:** [GetCreationTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetCreationTime)

---

## `System.IOUtils.TFile.GetCreationTimeUtc`

```pascal
class function GetCreationTimeUtc(const Path: string): TDateTime; inline; static;
```

## Description

Returns the creation time of a file in UTC (Coordinated Universal Time) time zone.

Use [GetCreationTimeUtc]() to obtain the creation time of a file in UTC time zone.

On **POSIX** and **Mac**, a file system entry does not have a Creation Time defined. The only information that is available is the last modified and last accessed time. 

> 
**Note:** [GetCreationTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetCreationTimeUtc)

---

## `System.IOUtils.TFile.GetLastAccessTime`

```pascal
class function GetLastAccessTime(const Path: string): TDateTime; inline; static;
```

## Description

Returns the last access time of a file.

Use [GetLastAccessTime]() to obtain the last access time of a file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last access time is obtained. |

> 
**Note:**  [GetLastAccessTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetLastAccessTime)

---

## `System.IOUtils.TFile.GetLastAccessTimeUtc`

```pascal
class function GetLastAccessTimeUtc(const Path: string): TDateTime; inline; static;
```

## Description

Returns the last access time of a file in UTC (Coordinated Universal Time) time zone.

Use [GetLastAccessTimeUtc]() to obtain the last access time of a file in UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last access time is obtained. |

> 
**Note:**  [GetLastAccessTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetLastAccessTimeUtc)

---

## `System.IOUtils.TFile.GetLastWriteTime`

```pascal
class function GetLastWriteTime(const Path: string): TDateTime; inline; static;
```

## Description

Returns the last write time of a file.

Use [GetLastWriteTime]() to obtain the last write time of a file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last write time is obtained. |

> 
**Note:**  [GetLastWriteTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetLastWriteTime)

---

## `System.IOUtils.TFile.GetLastWriteTimeUtc`

```pascal
class function GetLastWriteTimeUtc(const Path: string): TDateTime; inline; static;
```

## Description

Returns the last write time of a file in UTC (Coordinated Universal Time) time zone.

Use [GetLastWriteTimeUtc]() to obtain the last write time of a file in UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last write time is obtained. |

> 
**Note:**  [GetLastWriteTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetLastWriteTimeUtc)

---

## `System.IOUtils.TFile.GetSymLinkTarget`

```pascal
class function GetSymLinkTarget(const FileName: string;  var SymLinkRec: TSymLinkRec): Boolean; overload; static;
class function GetSymLinkTarget(const FileName: string;  var TargetName: string): Boolean; overload; static;
```

## Description

[GetSymLinkTarget]() reads the content of a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec).

There are two overloads for the [GetSymLinkTarget]() method. The first overload reads the content of a symbolic link and the result is returned in the  symbolic link record given by the SymLinkRec parameter, while the second overload returns the target of the symbolic link given by the TargetName parameter.

The method returns **True** if the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is valid, **False** otherwise.

> 
**Note:** [GetSymLinkTarget]() can be used on **Windows Vista** and later.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.GetSymLinkTarget)

---

## `System.IOUtils.TFile.IntegerToFileAttributes`

```pascal
class function IntegerToFileAttributes(const Attributes: Integer): TFileAttributes; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.IntegerToFileAttributes)

---

## `System.IOUtils.TFile.Move`

```pascal
class procedure Move(SourceFileName, DestFileName: string); static;
```

## Description

Moves a file from a given path to another path.

Use [Move]() to move a file from a given path to another path. [Move]() raises an exception if `DestFileName` indicates a file that already exists. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `SourceFileName` | The path of the source file that will be moved. |
| `DestFileName` | The destination path to which the file will be moved. |

> 
**Note:** In general, [Move]() has the same behavior on **Windows** and **POSIX**. But, for example, trying to move a "/user/file1" to "/usr/somedir/file1" may actually copy it. In **POSIX** "/usr/somedir", there may be a mount point for another partition, thus a copy is made.

> 
**Note:** [Move]() raises an exception if the given paths are invalid, do not exist, or cannot be accessed. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Move)

---

## `System.IOUtils.TFile.Open`

```pascal
class function Open(const Path: string;  const Mode: TFileMode): TFileStream; overload; inline; static;
class function Open(const Path: string;  const Mode: TFileMode; const Access: TFileAccess): TFileStream;
class function Open(const Path: string;  const Mode: TFileMode; const Access: TFileAccess; const Share: TFileShare): TFileStream; overload; static;
```

## Description

Opens a file and returns a stream associated with that file.

Call [Open]() to open a file. Depending on the [TFileMode](/Libraries/Sydney/en/System.IOUtils.TFileMode) value passed, the file is opened, created, or appended. Any way, a [TFileStream](/Libraries/Sydney/en/System.Classes.TFileStream) instance is returned. The instance can be used to read or write data. The optional `Access` parameter allows you to specify whether the file should be opened in read, write, or read-write mode. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be opened. |
| `Mode` | The mode in which the file will be opened. |
| `Access` | The desired file access. |

> 
**Note:**  [Open]() raises an exception if the file cannot be opened or the path is invalid. Depending on the `Mode` and `Access` parameter combinations, several exception conditions can appear. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Open)

---

## `System.IOUtils.TFile.OpenRead`

```pascal
class function OpenRead(const Path: string): TFileStream; static;
```

## Description

Opens a file for reading and returns a stream associated with that file.

Call [OpenRead]() to open a file for reading. [OpenRead]() returns a [TFileStream](/Libraries/Sydney/en/System.Classes.TFileStream) instance, which can be used only to read data. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be opened for reading. |

> 
**Note:**  [OpenRead]() raises an exception if the file cannot be opened, the path is invalid, or the user has insufficient privileges to carry out this operation. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.OpenRead)

---

## `System.IOUtils.TFile.OpenText`

```pascal
class function OpenText(const Path: string): TStreamReader; static;
```

## Description

Opens a textual file for reading and returns a stream associated with that file.

Call [OpenText]() to open a textual file for reading. [OpenText]() returns a [TStreamReader](/Libraries/Sydney/en/System.Classes.TStreamReader) instance, which can be used only to read textual data. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be opened for reading. |

> 
**Note:**  [OpenText]() raises an exception if the file cannot be opened, the path is invalid, or the user has insufficient privileges to carry out this operation. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.OpenText)

---

## `System.IOUtils.TFile.OpenWrite`

```pascal
class function OpenWrite(const Path: string): TFileStream; static;
```

## Description

Opens a file for writing and returns a stream associated with that file.

Call [OpenWrite]() to open a file for writing. [OpenWrite]() returns a [TFileStream](/Libraries/Sydney/en/System.Classes.TFileStream) instance, which can be used only to write data. The following table lists the parameters xpected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file that will be opened for writing. |

> 
**Note:**  [OpenWrite]() raises an exception if the file cannot be opened, the path is invalid, or the user has insufficient privileges to complete this operation. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.OpenWrite)

---

## `System.IOUtils.TFile.ReadAllBytes`

```pascal
class function ReadAllBytes(const Path: string): TBytes; static;
```

## Description

Reads the contents of the file into a byte array.

Use [ReadAllBytes]() to read the contents of a binary file. [ReadAllBytes]() returns a new byte array containing the file data. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file. |

> 
**Note:**  [ReadAllBytes]() raises an exception if the file cannot be opened or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.ReadAllBytes)

---

## `System.IOUtils.TFile.ReadAllLines`

```pascal
class function ReadAllLines(const Path: string): TStringDynArray;
class function ReadAllLines(const Path: string;  const Encoding: TEncoding): TStringDynArray; overload; static;
```

## Description

Returns the contents of a textual file as a [string array](/Libraries/Sydney/en/System.Types.TStringDynArray).

[ReadAllLines]() reads the contents of a textual file and returns a [string array](/Libraries/Sydney/en/System.Types.TStringDynArray) containing the retrieved text lines. 

[ReadAllLines](), with one parameter, first reads the preamble bytes from the beginning of the Path textual file. Then 
[ReadAllLines]() skips the preamble bytes and reads the contents of the textual file beginning from this offset. 
[ReadAllLines]() returns a [string array](/Libraries/Sydney/en/System.Types.TStringDynArray) containing the text lines retrieved from the file.
If the Path file does not contain a byte order mark for one of the standard encodings, the [Default](/Libraries/Sydney/en/System.SysUtils.TEncoding.Default) standard encoding is accepted and the corresponding number of bytes is skipped. 

[ReadAllLines](), with two parameters, first reads from the beginning of the Path textual file and skips the number of bytes corresponding to the preamble of the specified Encoding. Then [ReadAllText](/Libraries/Sydney/en/System.IOUtils.TFile.ReadAllText) reads the contents of the textual file beginning from this offset and returns a [string array](/Libraries/Sydney/en/System.Types.TStringDynArray) containing the text lines retrieved from the file.

[ReadAllLines]() has the following parameters:

Path is the path to the file.
Encoding is the encoding of the text contained within the Path file.
**Note:**  A preamble is a sequence of bytes that specifies the encoding used. It is known as [Byte Order Mark (BOM)](https://en.wikipedia.org/wiki/Byte_order_mark).
**Note:**   [ReadAllLines]() raises an exception if the file cannot be opened or the path is invalid. 
**Note:**   [**ReadAllLines**]()  may throw an **EEncodingError** exception when specifying the wrong encoding. 
For example, opening a file that contains extended ASCII characters encoded as ANSI but specifying UTF8 as encoding will likely result in an **EEcondingError** exception. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.ReadAllLines)

---

## `System.IOUtils.TFile.ReadAllText`

```pascal
class function ReadAllText(const Path: string): string; overload; inline; static;
class function ReadAllText(const Path: string;  const Encoding: TEncoding): string; overload; inline; static;
```

## Description

Returns the contents of a textual file as a string.

[ReadAllText]() reads the contents of a textual file and returns a string containing the text read from the file. 

[ReadAllText](), with one parameter, first reads the preamble bytes from the beginning of the Path textual file. Then [ReadAllText]() skips the preamble bytes and reads the contents of the textual file beginning from this offset. 
[ReadAllText]() returns a string containing the text read from the file. 
If the Path file does not contain a byte order mark for one of the standard encodings, the [Default](/Libraries/Sydney/en/System.SysUtils.TEncoding.Default) standard encoding is accepted and corresponding number of bytes is skipped. 

[ReadAllText](), with two parameters, first reads from the beginning of the Path textual file and skips the number of bytes corresponding to the preamble of the specified Encoding. Then [ReadAllText]() reads the contents of the textual file beginning from this offset and returns a string containing the text read from the file.  

[ReadAllText]() has the following parameters:

Path is the path to the file.
Encoding is the encoding of the text contained within the Path file.
**Notes:**  
A preamble is a sequence of bytes that specifies the encoding used. It is known as [Byte Order Mark (BOM)](https://en.wikipedia.org/wiki/Byte_order_mark).
[ReadAllText]() raises an exception if the file cannot be opened or the path is invalid.
If the specified encoding differs from the actual encoding of the file, the return value is undefined. In some cases, an EEncondingError exception is raised. For example, opening an ANSI file with accented characters as UTF8 returns an unpredictable string with garbage characters or generates an EEncondingError exception.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.ReadAllText)

---

## `System.IOUtils.TFile.Replace`

```pascal
class procedure Replace(const SourceFileName, DestinationFileName,  DestinationBackupFileName: string); overload; {$IFDEF MSWINDOWS}inline; {$ENDIF} static;
class procedure Replace(SourceFileName, DestinationFileName,  DestinationBackupFileName: string; const IgnoreMetadataErrors: Boolean); overload; static;
```

## Description

Replaces the contents of a file with the contents of another file.

Use [Replace]() to replace the contents of a file with the contents of another file. [Replace]() also makes a backup of the replaced file. The first form of [Replace]() does not fail if the file metadata cannot be merged. The second form of [Replace]() allows you to specify whether it should fail if metadata conflicts appear. On Windows operating systems, file metadata include ACLs (Access Control Lists) and other file-dependent information. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `SourceFileName` | The path of the file from which the contents are being copied. |
| `DestinationFileName` | The path of the file whose contents are replaced. |
| `DestinationBackupFileName` | The path of the backup file created before the replace operation occurs. |
| `IgnoreMetadataErrors` | Specifies whether metadata errors are ignored. |

> 
**Note:** [Replace]() raises an exception if the source or destination file does not exist, the paths are invalid, or the user does not have enough privileges to perform the replace operation. If the `IgnoreMetadataErrors` is set to **False**, an exception is raised if the metadata merging fails. 

> 
**Note:** [Replace]() is present only on the **Windows** platform, and can be used only on files that reside on **NTFS (New Technology File System)** partitions.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.Replace)

---

## `System.IOUtils.TFile.SetAttributes`

```pascal
class procedure SetAttributes(const Path: string;  const Attributes: TFileAttributes); inline; static;
```

## Description

Sets the file attributes.

Call [SetAttributes]() to apply a new set of attributes for a given file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file for which the attributes are obtained. |
| `Attributes` | The new set of attributes applied to the file. |

> 
**Note:**  [SetAttributes]() raises an exception if the file cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetAttributes)

---

## `System.IOUtils.TFile.SetCreationTime`

```pascal
class procedure SetCreationTime(const Path: string;  const CreationTime: TDateTime); inline; static;
```

## Description

Changes the creation time of a file.

Use [SetCreationTime]() to change the creation time of a file. The following table lists the parameters expected by this method: 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the creation time is changed. |
| `CreationTime` | The new creation time that will be applied to the file. |

On **POSIX** and **Mac**, [SetCreationTime]() will only update the last accessed time, because a Creation Time for a file system entry is not defined.

> 
**Note:** [SetCreationTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetCreationTime)

---

## `System.IOUtils.TFile.SetCreationTimeUtc`

```pascal
class procedure SetCreationTimeUtc(const Path: string;  const CreationTime: TDateTime); inline; static;
```

## Description

Changes the creation time of a file.

Use [SetCreationTimeUtc]() to change the creation time of a file. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the creation time is changed. |
| `CreationTime` | The new creation time that will be applied to the file. |

On **POSIX** and **Mac**, [SetCreationTimeUtc]() will only update the last accessed time, because a Creation Time for a file system entry is not defined.

> 
**Note:** [SetCreationTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetCreationTimeUtc)

---

## `System.IOUtils.TFile.SetLastAccessTime`

```pascal
class procedure SetLastAccessTime(const Path: string;  const LastAccessTime: TDateTime); inline; static;
```

## Description

Changes the last access time of a file.

Use [SetLastAccessTime]() to change the last access time of a file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last access time is changed. |
| `LastAccessTime` | The new last access time that will be applied to the file. |

> 
**Note:**  [SetLastAccessTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetLastAccessTime)

---

## `System.IOUtils.TFile.SetLastAccessTimeUtc`

```pascal
class procedure SetLastAccessTimeUtc(const Path: string;  const LastAccessTime: TDateTime); inline; static;
```

## Description

Changes the last access time of a file.

Use [SetLastAccessTimeUtc]() to change the last access time of a file. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last access time is changed. |
| `LastAccessTime` | The new last access time that will be applied to the file. |

> 
**Note:**  [SetLastAccessTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetLastAccessTimeUtc)

---

## `System.IOUtils.TFile.SetLastWriteTime`

```pascal
class procedure SetLastWriteTime(const Path: string;  const LastWriteTime: TDateTime); inline; static;
```

## Description

Changes the last write time of a file.

Use [SetLastWriteTime]() to change the last write time of a file. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last write time is changed. |
| `LastAccessTime` | The new last write time that will be applied to the file. |

> 
**Note:**  [SetLastWriteTime]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetLastWriteTime)

---

## `System.IOUtils.TFile.SetLastWriteTimeUtc`

```pascal
class procedure SetLastWriteTimeUtc(const Path: string;  const LastWriteTime: TDateTime); inline; static;
```

## Description

Changes the last write time of a file.

Use [SetLastWriteTimeUtc]() to change the last write time of a file. The new date-time value is considered to be in the UTC (Coordinated Universal Time) time zone. The following table lists the parameters expected by this method. 

| **Name** | **Meaning** |
| --- | --- |
| `Path` | Path of the file for which the last write time is changed. |
| `LastWriteTime` | The new last write time that will be applied to the file. |

> 
**Note:**  [SetLastWriteTimeUtc]() raises an exception if the given path is invalid or the file does not exist. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.SetLastWriteTimeUtc)

---

## `System.IOUtils.TFile.WriteAllBytes`

```pascal
class procedure WriteAllBytes(const Path: string; const Bytes: TBytes); static;
```

## Description

Writes a byte array to a file.

Use [WriteAllBytes]() to write a given array of bytes to a file. If the file specified by the `Path` parameter exists, it is overwritten; otherwise the file is created and filled with the given bytes. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file. |
| `Bytes` | The array of bytes to be written. |

> 
**Note:**  [WriteAllBytes]() raises an exception if the file cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TFile.WriteAllBytes)

---

