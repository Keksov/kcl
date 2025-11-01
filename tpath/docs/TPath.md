# TPath Properties (System.IOUtils) — RAD Studio 10.4 Sydney

This document lists the properties of the `TPath` record defined in the `System.IOUtils` unit, along with their descriptions and default values for POSIX platforms (Linux, macOS, iOS, Android).
Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath_Properties).

---

## Table of Properties

| Property | Description | Default Value (POSIX) |
|-----------|--------------|------------------------|
| **AltDirectorySeparatorChar** | Specifies the alternate character used to separate directory levels in a path string. | `/` |
| **DirectorySeparatorChar** | Specifies the primary character used to separate directory levels in a path string. Both `AltDirectorySeparatorChar` and `DirectorySeparatorChar` are valid in a path string. | `/` |
| **ExtensionSeparatorChar** | Specifies the character used to separate the file name from its extension. | `.` |
| **PathSeparator** | Specifies the character used to separate individual paths in environment variables (such as the `PATH` variable). | `:` |
| **VolumeSeparatorChar** | Specifies the character used to separate the drive letter from the rest of the path. On POSIX platforms, volumes are not used, so this character is effectively `/`. | `/` (no actual volume concept) |

---

## Notes

- On POSIX systems, directory hierarchies are represented with `/` and do not have drive letters or volumes.
- These constants are defined in the `System.IOUtils` unit and are platform-dependent.
- For Windows, the corresponding default values are typically:
  - `AltDirectorySeparatorChar` = `/`
  - `DirectorySeparatorChar` = `\`
  - `ExtensionSeparatorChar` = `.`
  - `PathSeparator` = `;`
  - `VolumeSeparatorChar` = `:`

---

**Reference:**  
[Embarcadero DocWiki — System.IOUtils.TPath Properties (RAD Studio 10.4 Sydney)](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath_Properties)


# TPath Methods — Full Documentation

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath_Methods).

## `System.IOUtils.TPath.ChangeExtension`

```pascal
class function ChangeExtension(const Path, Extension: string): string; static;
```

## Description

Changes the extension of a file or directory indicated by the given path.

[ChangeExtension]() takes the given file or directory name passed in the `Path` parameter and changes its extension to the extension passed in the `Extension` parameter. The new specified extension can include the initial period. [ChangeExtension]() does not rename the actual file, it just creates a new file name string. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The file or directory path for which the extension is changed. |
| `Extension` | The new extension applied to the given path. |

> 
**Note:** [ChangeExtension]() raises an exception if the given path or extension contain invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.ChangeExtension)

---

## `System.IOUtils.TPath.Combine`

```pascal
class function Combine(const Path1, Path2: string): string; inline; static;
```

## Description

Combines two paths strings.

Call [Combine]() to obtain a new combined path from two distinct paths. If the second path is absolute, [Combine]() returns it directly; otherwise [Combine]() returns the first path concatenated with the second one. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path1` | The first path. `Path1` is used as root for `Path2`. |
| `Path2` | The path that is concatenated with `Path1`. |

> 
**Note:** [Combine]() raises an exception if the given paths contain invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.Combine)

---

## `System.IOUtils.TPath.DriveExists`

```pascal
class function DriveExists(const Path: string): Boolean; static;
```

## Description

Checks whether the drive letter used in the given path actually exists.

Call [DriveExists]() to check whether a path's drive letter identifies a valid Windows drive. [DriveExists]() returns **True** if the path's root is a drive letter that identifies a valid drive, or **False** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified path |

> 
**Note:** On **POSIX**, [DriveExists]() will always returns false. 

> 
**Note:** [DriveExists]() raises an exception if the given paths contain invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.DriveExists)

---

## `System.IOUtils.TPath.GetAlarmsPath`

```pascal
class function GetAlarmsPath: string; static;
```

## Description

Returns the path to the directory where user alarm sound files are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This function works the same as [GetMusicPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetMusicPath) except for the **Android** platform, where it returns the path to the folder where Android stores alarm sound files.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.music.read-only or com.apple.security.assets.music.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Music | [CSIDL_MYMUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Music | [FOLDERID_Music](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Alarms |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetAlarmsPath)

---

## `System.IOUtils.TPath.GetAttributes`

```pascal
class function GetAttributes(const Path: string; FollowLink: Boolean = True): TFileAttributes; inline; static;
```

## Description

Returns the file or directory attributes.

Call [GetAttributes]() to obtain the attributes of a given file or directory. The return value of [GetAttributes]() is a set of [TFileAttribute](/Libraries/Sydney/en/System.IOUtils.TFileAttribute) values; each value of the set represents a file attribute. 

The following table lists the parameters expected by this method:

| Name | Meaning |
| --- | --- |
| `Path` | The path to the file or directory for which the attributes are obtained. |
| `FollowLink` | Specifies whether the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) is used. |

> 
**Note:** [GetAttributes]() raises an exception if the file or directory cannot be accessed or the path is invalid. 

> 
**Note:** If the `Path` parameter is a [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec) and the `FollowLink` parameter is set to **True**, the method is performed on the [target file (or directory)](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec.TargetName). If the first condition is **True**, but the `FollowLink` parameter is set to **False**, the method will be performed on the [symbolic link](/Libraries/Sydney/en/System.SysUtils.TSymLinkRec). If the link is broken, the method will always return **False**.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetAttributes)

---

## `System.IOUtils.TPath.GetCachePath`

```pascal
class function GetCachePath: string; static;
```

## Description

Returns the path to the directory where your application can store cache files.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS** and **Android**, it points to an application-specific, user-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\Local Settings\Application Data | [CSIDL_LOCAL_APPDATA](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\AppData\Local | [FOLDERID_LocalAppData](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Library/Caches | [NSCachesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_25) |
| **iOS Device** | /var/mobile/Containers/Data/Application/<application ID>/Library/Caches |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Library/Caches |
| **Android** | /data/data/<application ID>/cache | [Context.getCacheDir](https://developer.android.com/reference/android/content/Context.html#getCacheDir%28%29) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetCachePath)

---

## `System.IOUtils.TPath.GetCameraPath`

```pascal
class function GetCameraPath: string; static;
```

## Description

Returns the path to the directory where user pictures taken with a camera are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This function works the same as [GetPicturesPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetPicturesPath) except for the **Android** platform, where it returns the path to the folder where Android stores photos and videos taken with the device camera.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.pictures.read-only or com.apple.security.assets.pictures.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Pictures | [CSIDL_MYPICTURES](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Pictures | [FOLDERID_Pictures](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Pictures | [NSPicturesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_31) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Pictures | [NSPicturesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_31) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/DCIM |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetCameraPath)

---

## `System.IOUtils.TPath.GetDirectoryName`

```pascal
class function GetDirectoryName(FileName: string): string; static;
```

## Description

Extracts drive and directory parts of a file name.

[GetDirectoryName]() extracts the drive and directory parts of the given file name. The resulting string is empty if FileName contains no drive or directory parts. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `FileName` | The file name from which the drive and directory are extracted. |

> 
**Note:** [GetDirectoryName]() raises an exception if the given file name contains invalid characters. 

**Example (Delphi):**

WriteLn(TPath.GetDirectoryName('D:\Projects\HelloWorld.exe'));

**Example (C++):**

printf("%s \n", TPath::GetDirectoryName("D:\Projects\HelloWorld.exe"));

> 
**Note:** The code output: "D:\Projects". The path name does not include the last delimiter.  

> 
**Note:** On **Linux**, [GetDirectoryName]() is identical to [ExtractFileDir](/Libraries/Sydney/en/System.SysUtils.ExtractFileDir).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetDirectoryName)

---

## `System.IOUtils.TPath.GetDocumentsPath`

```pascal
class function GetDocumentsPath: string; static;
```

## Description

Returns the path to the directory where user documents are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS** and **Android**, it points to an application-specific, user-agnostic directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents | [CSIDL_MYDOCUMENTS](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx)[CSIDL_PERSONAL](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Documents | [FOLDERID_Documents](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Documents | [NSDocumentDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_21) |
| **iOS Device** | /var/mobile/Containers/Data/Application/<application ID>/Documents |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Documents |
| **Android** | /data/data/<application ID>/files | [Context.getFilesDir](https://developer.android.com/reference/android/content/Context.html#getFilesDir%28%29) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetDocumentsPath)

---

## `System.IOUtils.TPath.GetDownloadsPath`

```pascal
class function GetDownloadsPath: string; static;
```

## Description

Returns the path to the directory where user stores downloaded files.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.downloads.read-only or com.apple.security.assets.downloads.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\Local Settings\Application Data | [CSIDL_LOCAL_APPDATA](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\AppData\Local | [FOLDERID_LocalAppData](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Downloads | [NSDownloadsDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_27) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Downloads | [NSDownloadsDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_27) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Download |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetDownloadsPath)

---

## `System.IOUtils.TPath.GetExtendedPrefix`

```pascal
class function GetExtendedPrefix(const Path: string): TPathPrefixType; static;
```

## Description

Returns the extended prefix type for a given path.

Call [GetExtendedPrefix]() to obtain a [TPathPrefixType](/Libraries/Sydney/en/System.IOUtils.TPathPrefixType) specifying the extended prefix type for a given path. 

Paths prefixed with `\\?\` or `\\?\UNC\` are **Windows**-specific and can be of very big lengths and not restricted to 255 characters (MAX_PATH). It is a common case today to manage paths longer than 255 characters. Prefixing those with `\\?\` solves the problem.

For example, in file I/O, the `\\?\` tells the Windows APIs to disable all string parsing and to send the string that follows it to the file system. Therefore, you can exceed the **MAX_PATH** limits that are enforced by Windows APIs.

On **POSIX**, [GetExtendedPrefix]() always returns [TPathPrefixType](/Libraries/Sydney/en/System.IOUtils.TPathPrefixType).pptNoPrefix.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetExtendedPrefix)

---

## `System.IOUtils.TPath.GetExtension`

```pascal
class function GetExtension(const FileName: string): string; static;
```

## Description

Extracts the extension part of a file name.

[GetExtension]() extracts the extension part of the given file name. The resulting string also includes the dot that separates the extension from the path. If `FileName` has no extension, the resulting string is empty. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `FileName` | The file name from which the extension is extracted. |

> 
**Note:** [GetExtension]() raises an exception if the given file name contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetExtension)

---

## `System.IOUtils.TPath.GetFileName`

```pascal
class function GetFileName(const FileName: string): string; inline; static;
```

## Description

Extracts and returns the name and extension parts of a file name specified in FileName.

[GetFileName]() extracts the name and extension parts of the file name given in FileName. The resulting string consists of the characters of FileName, starting with the first character after the colon or backslash that separates the path information from the file name and extension. The resulting string is equal to FileName if FileName contains no drive and directory parts. 

FileName The file name from which the name and extension parts should be extracted.

> 
**Note:** [GetFileName]() raises an exception if the given FileName contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetFileName)

---

## `System.IOUtils.TPath.GetFileNameWithoutExtension`

```pascal
class function GetFileNameWithoutExtension(const FileName: string): string; static;
```

## Description

Extracts the name part of a file name, without extension.

[GetFileNameWithoutExtension]() extracts the name part of the given file name, omitting the extension. The resulting string consists of the leftmost characters of FileName, starting with the first character after the colon or backslash that separates the path information from the name and up to the period that is part of the extension, but not including either the dot or the extension itself. If there are more than one period, [GetFileNameWithoutExtension]() stops just before the last one that is considered part of the extension.

For instance,

  Writeln(TPath.GetFileNameWithoutExtension('D:\Testing\MyApp.exe'));
  Writeln(TPath.GetFileNameWithoutExtension('D:\Testing\MyApp.exe.config'));

produces

  MyApp
  MyApp.exe

The resulting string is equal to FileName if FileName contains no drive, directory, and extension parts. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| FileName | The file name from which the name is extracted. |

> 
**Note:** [GetFileNameWithoutExtension]() raises an exception if the given file name contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetFileNameWithoutExtension)

---

## `System.IOUtils.TPath.GetFullPath`

```pascal
class function GetFullPath(const Path: string): string; static;
```

## Description

Returns the absolute path for a given path.

[GetFullPath]() returns the full, absolute path for a given relative path. If the given path is absolute, [GetFullPath]() simply returns it; otherwise, [GetFullPath]() uses the current working directory as a root for the given `Path`. The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The relative path |

> 
**Note:** [GetFullPath]() raises an exception if the given path contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetFullPath)

---

## `System.IOUtils.TPath.GetGUIDFileName`

```pascal
class function GetGUIDFileName(const UseSeparator: Boolean = False): string; static;
```

## Description

Generates a new GUID that can be used as a unique file name.

Call [GetGUIDFileName]() to generate a new GUID suitable as a unique name for a file or directory. [GetGUIDFileName]() only generates a file name and does not create a real file. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `UseSeparator` | Indicates whether the GUID separator char (the minus sign) is preserved in the generated name. |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetGUIDFileName)

---

## `System.IOUtils.TPath.GetHomePath`

```pascal
class function GetHomePath: string; static;
```

## Description

Returns either the home path of the user or the application's writable scratch directory or storage. Call [GetHomePath]() to obtain the user's home path on the [supported target platforms](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Supported_Target_Platforms).

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

You should use [GetHomePath]() to store settings per user. For example:

TFile.WriteAllText(TPath.GetHomePath() + TPath.DirectorySeparatorChar + 'sample.txt', 'This is my sample text.');

[GetHomePath]() points to the following locations on the various platforms:

On **Windows**, it points to the userâs application data folder.
On **Linux** and **OS X**, it points to the userâs home folder, as defined by the $(HOME) environment variable.
On **iOS** and **Android**, it points to the device-specific location of the sandbox for the application; the iOS home location is individually defined for each application instance and for each iOS device.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\Application Data | [CSIDL_APPDATA](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\AppData\Roaming | [FOLDERID_RoamingAppData](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username> | [NSUserDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_19) |
| **iOS Device** | /private/var/mobile/Containers/Data/Application/<application ID> |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID> |
| **Android** | /data/data/<application ID>/files | [Context.getFilesDir](https://developer.android.com/reference/android/content/Context.html#getFilesDir%28%29) |
| **Linux** | /home/<username> | [Home Folder](https://help.ubuntu.com/community/HomeFolder) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetHomePath)

---

## `System.IOUtils.TPath.GetInvalidFileNameChars`

```pascal
class function GetInvalidFileNameChars: TCharArray; inline; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetInvalidFileNameChars)

---

## `System.IOUtils.TPath.GetInvalidPathChars`

```pascal
class function GetInvalidPathChars: TCharArray; inline; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetInvalidPathChars)

---

## `System.IOUtils.TPath.GetLibraryPath`

```pascal
class function GetLibraryPath: string; static;
```

## Description

Returns the path to a directory to store any data that your application needs store, regardless of the user, such as files, caches, resources, and preferences.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

[GetLibraryPath]() points to the following locations on the various platforms:

On **Windows**, it points to the folder that contains the executable file.
On **OS X** and **iOS**, it points to the library directory.
On **Android**, it points to the device-specific location of the sandbox for the application; the iOS home location is individually defined for each application instance and for each iOS device.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows** | C:\Program Files\<application folder> |  |
| **OS X** | /Users/<username>/Library | [NSLibraryDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_17) |
| **iOS Device** | /var/mobile/Containers/Data/Application/<application ID>/Library |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Library |
| **Android** | /data/app-lib/<application ID> | [ApplicationInfo.nativeLibraryDir](https://developer.android.com/reference/android/content/pm/ApplicationInfo.html#nativeLibraryDir) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetLibraryPath)

---

## `System.IOUtils.TPath.GetMoviesPath`

```pascal
class function GetMoviesPath: string; static;
```

## Description

Returns the path to the directory where user movies are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.movies.read-only or com.apple.security.assets.movies.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Videos | [CSIDL_MYVIDEO](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Videos | [FOLDERID_Videos](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Movies | [NSMoviesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_29) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Movies | [NSMoviesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_29) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Movies |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetMoviesPath)

---

## `System.IOUtils.TPath.GetMusicPath`

```pascal
class function GetMusicPath: string; static;
```

## Description

Returns the path to the directory where user music is stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.music.read-only or com.apple.security.assets.music.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Music | [CSIDL_MYMUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Music | [FOLDERID_Music](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Music |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetMusicPath)

---

## `System.IOUtils.TPath.GetPathRoot`

```pascal
class function GetPathRoot(const Path: string): string; static;
```

## Description

Gets the root of the specified path.

[GetPathRoot]() extracts and returns the root of the path specified in Path.

If the given path is empty or contains wrong path characters, [GetPathRoot]() raises an [EArgumentException](/Libraries/Sydney/en/System.SysUtils.EArgumentException).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetPathRoot)

---

## `System.IOUtils.TPath.GetPicturesPath`

```pascal
class function GetPicturesPath: string; static;
```

## Description

Returns the path to the directory where user pictures are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.pictures.read-only or com.apple.security.assets.pictures.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Pictures | [CSIDL_MYPICTURES](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Pictures | [FOLDERID_Pictures](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Pictures | [NSPicturesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_31) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Pictures | [NSPicturesDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_31) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Pictures |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetPicturesPath)

---

## `System.IOUtils.TPath.GetPublicPath`

```pascal
class function GetPublicPath: string; static;
```

## Description

Returns the path to the directory where you can store application data that can be shared with other applications.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to an application-specific, user-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Application Data | [CSIDL_COMMON_APPDATA](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\ProgramData | [FOLDERID_ProgramData](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files | [Context.getExternalFilesDir](https://developer.android.com/reference/android/content/Context.html#getExternalFilesDir%28java.lang.String%29) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetPublicPath)

---

## `System.IOUtils.TPath.GetRandomFileName`

```pascal
class function GetRandomFileName: string; static;
```

## Description

Generates a new random file name.

Call [GetRandomFileName]() to generate a new random file name. [GetRandomFileName]() does not guarantee a unique file name. If a unique file name is desired, use [GetGUIDFileName](/Libraries/Sydney/en/System.IOUtils.TPath.GetGUIDFileName) method instead. To generate a real uniquely-named temporary file, use the [GetTempFileName](/Libraries/Sydney/en/System.IOUtils.TPath.GetTempFileName) method. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetRandomFileName)

---

## `System.IOUtils.TPath.GetRingtonesPath`

```pascal
class function GetRingtonesPath: string; static;
```

## Description

Returns the path to the directory where user ring tones are stored.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This function works the same as [GetMusicPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetMusicPath) except for the **Android** platform, where it returns the path to the folder where Android stores ring tones.

On **Windows** and **OS X**, it points to a user-specific, application-agnostic directory.
**Note:** On **OS X**, for Sand-box mode, to access this path you have to add com.apple.security.assets.music.read-only or com.apple.security.assets.music.read-write to the **[Entitlement List](https://docwiki.embarcadero.com/RADStudio/Sydney/en/Entitlement_List)**.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\<username>\My Documents\My Music | [CSIDL_MYMUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\<username>\Music | [FOLDERID_Music](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Music | [NSMusicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_30) |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/Ringtones |  |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetRingtonesPath)

---

## `System.IOUtils.TPath.GetSharedAlarmsPath`

```pascal
class function GetSharedAlarmsPath: string; static;
```

## Description

Returns the path to the directory where user shared alarm sound files are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This function works the same as [GetSharedMusicPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedMusicPath) except for the **Android** platform, where it returns the path to the folder where Android stores alarm sound files.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Music | [CSIDL_COMMON_MUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Music | [FOLDERID_PublicMusic](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Alarms | [Environment.DIRECTORY_ALARMS](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_ALARMS) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedAlarmsPath)

---

## `System.IOUtils.TPath.GetSharedCameraPath`

```pascal
class function GetSharedCameraPath: string; static;
```

## Description

Returns the path to the directory where user shared pictures taken with a camera are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This function works the same as [GetPicturesPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetPicturesPath) except for the **Android** platform, where it returns the path to the folder where Android stores photos and videos taken with the device camera.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Pictures | [CSIDL_COMMON_PICTURES](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Pictures | [FOLDERID_PublicPictures](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/DCIM | [Environment.DIRECTORY_DCIM](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_DCIM) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedCameraPath)

---

## `System.IOUtils.TPath.GetSharedDocumentsPath`

```pascal
class function GetSharedDocumentsPath: string; static;
```

## Description

Returns the path to the directory where documents shared between users are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, an empty string is returned, as shared document folders are not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents | [CSIDL_COMMON_DOCUMENTS](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Documents | [FOLDERID_PublicDocuments](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Documents | [Context.getExternalFilesDir](https://developer.android.com/reference/android/content/Context.html#getExternalFilesDir%28java.lang.String%29) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedDocumentsPath)

---

## `System.IOUtils.TPath.GetSharedDownloadsPath`

```pascal
class function GetSharedDownloadsPath: string; static;
```

## Description

Returns the path to the directory where user stores shared downloaded files.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Application Data | [CSIDL_COMMON_APPDATA](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\ProgramData | [FOLDERID_ProgramData](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Download | [Environment.DIRECTORY_DOWNLOADS](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_RINGTONES) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedDownloadsPath)

---

## `System.IOUtils.TPath.GetSharedMoviesPath`

```pascal
class function GetSharedMoviesPath: string; static;
```

## Description

Returns the path to the directory where user shared movies are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Videos | [CSIDL_COMMON_VIDEO](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Videos | [FOLDERID_PublicVideos](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Movies | [Environment.DIRECTORY_MOVIES](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_MOVIES) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedMoviesPath)

---

## `System.IOUtils.TPath.GetSharedMusicPath`

```pascal
class function GetSharedMusicPath: string; static;
```

## Description

Returns the path to the directory where user shared music is stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Music | [CSIDL_COMMON_MUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Music | [FOLDERID_PublicMusic](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Music | [Environment.DIRECTORY_MUSIC](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_MUSIC) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedMusicPath)

---

## `System.IOUtils.TPath.GetSharedPicturesPath`

```pascal
class function GetSharedPicturesPath: string; static;
```

## Description

Returns the path to the directory where user shared pictures are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Pictures | [CSIDL_COMMON_PICTURES](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Pictures | [FOLDERID_PublicPictures](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Pictures | [Environment.DIRECTORY_PICTURES](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_PICTURES) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedPicturesPath)

---

## `System.IOUtils.TPath.GetSharedRingtonesPath`

```pascal
class function GetSharedRingtonesPath: string; static;
```

## Description

Returns the path to the directory where user shared ring tones are stored.

**Note:** In desktop applications, "shared" means "shared between different users". In mobile applications, "shared" means "shared between different applications".

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

This functions works the same as [GetSharedMusicPath](/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedMusicPath) except for the **Android** platform, where it returns the path to the folder where Android stores ring tones.

On **Windows** and **Android**, it points to a system-wide directory.
On **OS X**, it points to a user-specific, application-agnostic directory.
On **iOS Device**, it returns an empty string as this directory is currently not supported.
On **iOS Simulator**, it points to an application-specific directory.
| Platform | Sample path | Path ID |
| --- | --- | --- |
| **Windows XP** | C:\Documents and Settings\All Users\Documents\My Music | [CSIDL_COMMON_MUSIC](http://msdn.microsoft.com/en-us/library/windows/desktop/bb762494(v=vs.85).aspx) |
| **Windows Vista** or later | C:\Users\Public\Music | [FOLDERID_PublicMusic](http://msdn.microsoft.com/en-us/library/windows/desktop/dd378457(v=vs.85).aspx) |
| **OS X** | /Users/<username>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **iOS Device** |  |  |
| **iOS Simulator** | /Users/<username>/Library/Developer/CoreSimulator/Devices/<Device ID>/data/Containers/Data/Application/<application ID>/Public | [NSSharedPublicDirectory](https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html#jumpTo_33) |
| **Android** | /storage/emulated/0/Ringtones | [Environment.DIRECTORY_RINGTONES](https://developer.android.com/reference/android/os/Environment.html#DIRECTORY_RINGTONES) |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetSharedRingtonesPath)

---

## `System.IOUtils.TPath.GetTempFileName`

```pascal
class function GetTempFileName: string; static;
```

## Description

Generates a unique temporary file.

Call [GetTempFileName]() to generate a new uniquely-named temporary file. [GetTempFileName]() actually creates a zero-sized file in a temporary location and returns its name. The caller must delete the file after it is not used anymore. 

> 
**Note:**  [GetTempFileName]() raises an exception if the user has no access to the system's temporary directory. 

On **Linux**, it creates a new file which name is based on **GUID** in the following format: 'File_%8x%4x%4x%16x_tmp':

 %8x stands for GUID.D1
 %4x stands for GUID.D2
 %4x stands for GUID.D3
 %16x stands for GUID.D4

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetTempFileName)

---

## `System.IOUtils.TPath.GetTempPath`

```pascal
class function GetTempPath: string; static;
```

## Description

Returns the path to a directory to store temporary files. This directory is a system-managed location; files saved here may be deleted between application sessions or system restarts.

If the system running your application does not support the requested folder, or if the requested folder does not exist in the system, this function returns an empty string instead.

[GetTempPath]() points to the following locations on the various platforms:

On **Windows**, **OS X**, and **Linux** it points to a system-wide directory.
On **iOS** and **Android**, it points to a user-specific, application-specific directory.
| Platform | Sample path |
| --- | --- |
| **Windows XP** | C:\Documents and Settings\<User name>\Local Settings\Temp |
| **Windows Vista** or later | C:\Users\<User name>\AppData\Local\Temp |
| **OS X** | /var/folders/<random folder name> |
| **iOS Device** | /private/var/mobile/Applications/<application ID>/tmp |
| **iOS Simulator** | /Users/<username>/Library/Application Support/iPhone Simulator/<SDK version>/Applications/<application ID>/tmp |
| **Android** | /storage/emulated/0/Android/data/<application ID>/files/tmp |
| **Linux** | /tmp |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.GetTempPath)

---

## `System.IOUtils.TPath.HasExtension`

```pascal
class function HasExtension(const Path: string): Boolean; static;
```

## Description

Checks whether a given file name has an extension part.

Call [HasExtension]() to check whether a given file name has an extension part. [HasExtension]() returns **true** if the file name has an extension; **false** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified file or directory name |

> 
**Note:** [HasExtension]() raises an exception if the given path contains invalid characters. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.HasExtension)

---

## `System.IOUtils.TPath.HasValidFileNameChars`

```pascal
class function HasValidFileNameChars(const FileName: string;  const UseWildcards: Boolean): Boolean; static;
```

## Description

Checks whether a given file name contains only allowed characters.

Call [HasValidFileNameChars]() to check whether a given file name contains only allowed characters. [HasValidFileNameChars]() returns **true** if the string contains only allowed characters; **false** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified file name string. |
| `UseWildcards` | Specifies whether the mask characters are treated as valid file name characters (e.g. asterisk or question mark). |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.HasValidFileNameChars)

---

## `System.IOUtils.TPath.HasValidPathChars`

```pascal
class function HasValidPathChars(const Path: string;  const UseWildcards: Boolean): Boolean; static;
```

## Description

Checks whether a given path string contains only allowed characters.

Call [HasValidPathChars]() to check whether the given path string contains only allowed characters. [HasValidPathChars]() returns **true** if the string contains only allowed characters; **false** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified path string. |
| `UseWildcards` | Specifies whether the mask characters are treated as valid path characters (e.g. asterisk or question mark). |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.HasValidPathChars)

---

## `System.IOUtils.TPath.IsDriveRooted`

```pascal
class function IsDriveRooted(const Path: string): Boolean; static;
```

## Description

Checks whether a given path is absolute and starts with a drive letter.

Call [IsDriveRooted]() to check whether a path is absolute and starts with a drive letter. A drive-rooted path is prefixed with a drive letter and a colon (for example, `"C:\folder"`). [IsDriveRooted]() returns **True** if the path's root is a drive letter, or **False** otherwise. 

On **POSIX**, [IsDriveRooted]() always returns false since there are no drive roots.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsDriveRooted)

---

## `System.IOUtils.TPath.IsExtendedPrefixed`

```pascal
class function IsExtendedPrefixed(const Path: string): Boolean; inline; static;
```

## Description

Checks whether a given path has an extended prefix.

Call [IsExtendedPrefixed]() to check whether the given path contains an extension prefix. 

Paths prefixed with `\\?\` or `\\?\UNC\` are **Windows**-specific and can be of very big lengths and not restricted to 255 characters (MAX_PATH). It is a common case today to manage paths longer than 255 characters. Prefixing those with `\\?\` solves the problem.

For example, in file I/O, the `\\?\` tells the Windows APIs to disable all string parsing and to send the string that follows it to the file system. Therefore, you can exceed the **MAX_PATH** limits that are enforced by Windows APIs.

On **POSIX**, [IsExtendedPrefixed]() always returns false, since there are no extended prefixes. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsExtendedPrefixed)

---

## `System.IOUtils.TPath.IsPathRooted`

```pascal
class function IsPathRooted(const Path: string): Boolean; inline; static;
```

## Description

Checks whether a given path is relative or absolute.

Call [IsPathRooted]() to check whether the given path is relative or absolute. [IsPathRooted]() returns **true** if the path is absolute; **false** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified path |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsPathRooted)

---

## `System.IOUtils.TPath.IsRelativePath`

```pascal
class function IsRelativePath(const Path: string): Boolean; static;
```

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsRelativePath)

---

## `System.IOUtils.TPath.IsUNCPath`

```pascal
class function IsUNCPath(const Path: string): Boolean; inline; static;
```

## Description

Checks whether a given path is in UNC (Universal Naming Convention) format.

Call [IsUNCPath]() to check whether the given path is in UNC format. A UNC path is prefixed with two backslash characters (e.g. `"\\computer\folder"`). [IsUNCPath]() returns **true** if the path is in UNC format; **false** otherwise. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The verified path |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsUNCPath)

---

## `System.IOUtils.TPath.IsUNCRooted`

```pascal
class function IsUNCRooted(const Path: string): Boolean; static;
```

## Description

Checks whether the given path is UNC-rooted, where UNC stands for Universal Naming Convention.

Call [IsUNCRooted]() to check whether the given path is UNC-rooted. A UNC path is prefixed with two backslash characters (for example, `"\\computer\folder"`). [IsUNCRooted]() returns **True** if the path is UNC-rooted, or **False** otherwise. 

On **POSIX**, [IsUNCRooted]() always returns false.

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsUNCRooted)

---

## `System.IOUtils.TPath.IsValidFileNameChar`

```pascal
class function IsValidFileNameChar(const AChar: Char): Boolean; inline; static;
```

## Description

Checks whether a given character is allowed in a file name.

Call [IsValidFileNameChar]() to check whether a given character is allowed in a file name string. [IsValidFileNameChar]() returns **True** if the character is allowed, and **False** if the character is not allowed. 

The following table lists the parameters this method expects:

| **Name** | **Meaning** |
| --- | --- |
| <code">AChar | The verified character |

### Invalid Characters

|  |
|
| MacOS, iOS, Android, and Linux | #0, #1, #2, #3, #4, #5, #6, #7, #8, #9, #10, #11, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #31, '/' and '~'. |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsValidFileNameChar)

---

## `System.IOUtils.TPath.IsValidPathChar`

```pascal
class function IsValidPathChar(const AChar: Char): Boolean; inline; static;
```

## Description

Checks whether a given character is allowed in a path string.

Call [IsValidPathChar]() to check whether a given character is allowed in a path string. [IsValidPathChar]() returns **true** if the character is allowed; **false** otherwise. The following table lists the parameters expected by this method.

| **Name** | **Meaning** |
| --- | --- |
| `AChar` | The verified character |

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.IsValidPathChar)

---

## `System.IOUtils.TPath.MatchesPattern`

```pascal
class function MatchesPattern(const FileName, Pattern: string;  const CaseSensitive: Boolean): Boolean; static;
```

## Description

Returns True if the FileName matches the specified Pattern.

The [MatchesPattern]() method returns True if the FileName matches the specified Pattern, and False if the file name does not match the pattern. If the given file name contains any [invalid character](/Libraries/Sydney/en/System.IOUtils.TPath.IsValidFileNameChar), the [MatchesPattern]() method raises an [EArgumentException](/Libraries/Sydney/en/System.SysUtils.EArgumentException).

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.MatchesPattern)

---

## `System.IOUtils.TPath.SetAttributes`

```pascal
class procedure SetAttributes(const Path: string;  const Attributes: TFileAttributes); inline; static;
```

## Description

Sets the file or directory attributes.

Call [SetAttributes]() to apply a new set of attributes to a given file or directory. 

The following table lists the parameters expected by this method:

| **Name** | **Meaning** |
| --- | --- |
| `Path` | The path to the file or directory for which the attributes are obtained. |

> 
**Note:** [SetAttributes]() raises an exception if the file or directory cannot be accessed or the path is invalid. 

[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.IOUtils.TPath.SetAttributes)

---

