Automatically extracted from [freepascal.org](https://www.freepascal.org/docs-html/fcl/custapp/tcustomapplication.html).

## Methods

### `Create`

**Type:** constructor

**Declaration:**

```pascal
public constructor TCustomApplication.Create(); override;
```

**Arguments:**


**Description:**
`Create` creates a new instance of the `TCustomApplication` class. It sets some defaults for the various properties.

**See also:**

| [TCustomApplication.Destroy](../custapp/tcustomapplication.destroy.html) |    | Destroys the `TCustomApplication` instance. |
| --- | --- | --- |

---

### `Destroy`

**Type:** destructor

**Declaration:**

```pascal
public destructor TCustomApplication.Destroy; override;
```

**Description:**

`Destroy` simply calls the inherited `Destroy` .

**See also:**

| [TCustomApplication.Create](../custapp/tcustomapplication.create.html) |    | Create a new instance of the `TCustomApplication` class |
| --- | --- | --- |

---

### `HandleException`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.HandleException(
  Sender: TObject
); virtual;
```

**Arguments:**

| Sender |    | Sender class calling this routine |
| --- | --- | --- |

**Description:**

`HandleException` is called (or can be called) to handle the exception `Sender` . If the exception is not of class `Exception` then the default handling of exceptions in theSysUtilsunit is called.

If the exception is of class `Exception` and the[OnException](../custapp/tcustomapplication.onexception.html)handler is set, the handler is called with the exception object and `Sender` argument.

If the `OnException` handler is not set, then the exception is passed to the[ShowException](../custapp/tcustomapplication.showexception.html)routine, which can be overridden by descendent application classes to show the exception in a way that is fit for the particular class of application. (a GUI application might show the exception in a message dialog.

When the exception is handled in the above manner, and the[StopOnException](../custapp/tcustomapplication.stoponexception.html)property is set to `True` , the[Terminated](../custapp/tcustomapplication.terminated.html)property is set to `True` , which will cause the[Run](../custapp/tcustomapplication.run.html)loop to stop, and the application will exit.

**See also:**

| [ShowException](../custapp/tcustomapplication.showexception.html) |    | Show an exception to the user |
| --- | --- | --- |
| [StopOnException](../custapp/tcustomapplication.stoponexception.html) |    | Should the program loop stop on an exception |
| [Terminated](../custapp/tcustomapplication.terminated.html) |    | Was `Terminate` called or not |
| [Run](../custapp/tcustomapplication.run.html) |    | Runs the application. |

---

### `Initialize`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.Initialize; virtual;
```

**Description:**

`Initialize` can be overridden by descendent applications to perform any initialization after the class was created. It can be used to react to properties being set at program startup. End-user code should call `Initialize` prior to calling `Run`

In `TCustomApplication` , `Initialize` sets `Terminated` to `False` .

**See also:**

| [TCustomApplication.Run](../custapp/tcustomapplication.run.html) |    | Runs the application. |
| --- | --- | --- |
| [TCustomApplication.Terminated](../custapp/tcustomapplication.terminated.html) |    | Was `Terminate` called or not |

---

### `Run`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.Run;
```

**See also:**

| [TCustomApplication.HandleException](../custapp/tcustomapplication.handleexception.html) |    | Handle an exception. |
| --- | --- | --- |
| [TCustomApplication.StopOnException](../custapp/tcustomapplication.stoponexception.html) |    | Should the program loop stop on an exception |

---

### `ShowException`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.ShowException(
  E: Exception
); virtual;
```

**Arguments:**

| E |    | Exception object to show |
| --- | --- | --- |

**Description:**

`ShowException` should be overridden by descendent classes to show an exception message to the user. The default behaviour is to call the[ShowException](../../rtl/sysutils/showexception.html)procedure in theSysUtilsunit.

Descendent classes should do something appropriate for their context: GUI applications can show a message box, daemon applications can write the exception message to the system log, web applications can send a 500 error response code.

**See also:**

| [ShowException](../../rtl/sysutils/showexception.html) |
| --- |
| [TCustomApplication.HandleException](../custapp/tcustomapplication.handleexception.html) |    | Handle an exception. |
| [TCustomApplication.StopOnException](../custapp/tcustomapplication.stoponexception.html) |    | Should the program loop stop on an exception |

---

### `Terminate`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.Terminate; virtual;procedure TCustomApplication.Terminate(
  AExitCode: Integer
); virtual;
```

**Arguments:**

| AExitCode |    | Exit code for the program |
| --- | --- | --- |

**Description:**

`Terminate` sets the `Terminated` property to `True` . By itself, this does not terminate the application. Instead, descendent classes should in their `DoRun` method, check the value of the[Terminated](../custapp/tcustomapplication.terminated.html)property and properly shut down the application if it is set to `True` .

When `AExitCode` is specified, it will passed to[System.ExitCode](../../rtl/system/exitcode.html), and when the program is halted, that is the exit code of the program as returned to the OS. If the application is terminated due to an exception,[ExceptionExitCode](../custapp/tcustomapplication.exceptionexitcode.html)will be used as the value for this argument.

**See also:**

| [TCustomApplication.Terminated](../custapp/tcustomapplication.terminated.html) |    | Was `Terminate` called or not |
| --- | --- | --- |
| [TCustomApplication.Run](../custapp/tcustomapplication.run.html) |    | Runs the application. |
| [ExceptionExitCode](../custapp/tcustomapplication.exceptionexitcode.html) |    | ExitCode to use then terminating the program due to an exception |
| [System.ExitCode](../../rtl/system/exitcode.html) |

---

### `FindOptionIndex`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.FindOptionIndex(
  const S: string;
  var Longopt: Boolean;
  StartAt: Integer = - 1
):Integer;
```

**Arguments:**

| S |    | Short option to search for. |
| --- | --- | --- |
| Longopt |    | Long option to search for. |
| StartAt |    | Index to start searching for option. |

**Description:**

`FindOptionIndex` will return the index of the option `S` or the long option `LongOpt` . Neither of them should include the switch character. If no such option was specified, -1 is returned. If either the long or short option was specified, then the position on the command-line is returned.

Depending on the value of the[CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html)property, the search is performed case sensitive or case insensitive.

Options are identified as command-line parameters which start with[OptionChar](../custapp/tcustomapplication.optionchar.html)(by default the dash ('-') character).

**See also:**

| [HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| --- | --- | --- |
| [GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [CheckOptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |
| [CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html) |    | Are options interpreted case sensitive or not |
| [OptionChar](../custapp/tcustomapplication.optionchar.html) |    | Command-line switch character |

---

### `GetOptionValue`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.GetOptionValue(
  const S: string
):string;function TCustomApplication.GetOptionValue(
  const C: Char;
  const S: string
):string;
```

**Arguments:**

| S |    | Long option string |
| --- | --- | --- |

**Description:**

`GetOptionValue` returns the value of an option. Values are specified in the usual GNU option format, either of

```
--longopt=Value
```

or

```
-c Value
```

is supported.

The function returns the specified value, or the empty string if none was specified.

Depending on the value of the[CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html)property, the search is performed case sensitive or case insensitive.

Options are identified as command-line parameters which start with[OptionChar](../custapp/tcustomapplication.optionchar.html)(by default the dash ('-') character).

If an option can appear multiple times, use[TCustomApplication.GetOptionValues](../custapp/tcustomapplication.getoptionvalues.html)to retrieve all values. This function only returns the value of the first occurrence of an option.

**See also:**

| [FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html) |    | Return the index of an option. |
| --- | --- | --- |
| [HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| [CheckOptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |
| [CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html) |    | Are options interpreted case sensitive or not |
| [OptionChar](../custapp/tcustomapplication.optionchar.html) |    | Command-line switch character |
| [TCustomApplication.GetOptionValues](../custapp/tcustomapplication.getoptionvalues.html) |    | Get the values for an option that may be specified multiple times |

---

### `GetOptionValues`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.GetOptionValues(
  const C: Char;
  const S: string
):TStringArray;
```

**Arguments:**

| C |    | Short form of the command-line switch |
| --- | --- | --- |
| S |    | Long form of the command-line switch |

**Description:**

`GetOptionValues` returns all values specified by command-line option switches `C` or `S` . For each occurrence of the command-line option `C` or `S` , the associated value is added to the array.

[TCustomApplication.GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html)will only return the first occurrence of a value.

**See also:**

| [TCustomApplication.GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| --- | --- | --- |

---

### `HasOption`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.HasOption(
  const S: string
):Boolean;function TCustomApplication.HasOption(
  const C: Char;
  const S: string
):Boolean;
```

**Arguments:**

| S |    | Long option string |
| --- | --- | --- |

**Description:**

`HasOption` returns `True` if the specified option was given on the command line. Either the short option character `C` or the long option `S` may be used. Note that both options (requiring a value) and switches can be specified.

Depending on the value of the[CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html)property, the search is performed case sensitive or case insensitive.

Options are identified as command-line parameters which start with[OptionChar](../custapp/tcustomapplication.optionchar.html)(by default the dash ('-') character).

**See also:**

| [FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html) |    | Return the index of an option. |
| --- | --- | --- |
| [GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [CheckOptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |
| [CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html) |    | Are options interpreted case sensitive or not |
| [OptionChar](../custapp/tcustomapplication.optionchar.html) |    | Command-line switch character |

---

### `CheckOptions`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.CheckOptions(
  const ShortOptions: string;
  const Longopts: TStrings;
  Opts: TStrings;
  NonOpts: TStrings;
  AllErrors: Boolean = False
):string;function TCustomApplication.CheckOptions(
  const ShortOptions: string;
  const Longopts: array of string;
  Opts: TStrings;
  NonOpts: TStrings;
  AllErrors: Boolean = False
):string;function TCustomApplication.CheckOptions(
  const ShortOptions: string;
  const Longopts: TStrings;
  AllErrors: Boolean = False
):string;function TCustomApplication.CheckOptions(
  const ShortOptions: string;
  const LongOpts: array of string;
  AllErrors: Boolean = False
):string;function TCustomApplication.CheckOptions(
  const ShortOptions: string;
  const LongOpts: string;
  AllErrors: Boolean = False
):string;
```

**Arguments:**

| ShortOptions |    | List of valid short options. |
| --- | --- | --- |
| Longopts |    | List of valid long options. |
| Opts |    | Valid options passed to the program. |
| NonOpts |    | Non-option strings passed to the program. |
| AllErrors |    | Should all errors be returned, or just the first one? |

**Description:**

`CheckOptions` scans the command-line and checks whether the options given are valid options. It also checks whether options that require a valued are indeed specified with a value.

The `ShortOptions` contains a string with valid short option characters. Each character in the string is a valid option character. If a character is followed by a colon (:), then a value must be specified. If it is followed by 2 colon characters (::) then the value is optional.

`LongOpts` is a list of strings (which can be specified as an array, a `TStrings` instance or a string with whitespace-separated values) of valid long options.

When the function returns, if `Opts` is non- `Nil` , the `Opts` stringlist is filled with the passed valid options. If `NonOpts` is non-nil, it is filled with any non-option strings that were passed on the command-line.

The function returns an empty string if all specified options were valid options, and whether options requiring a value have a value. If an error was found during the check, the return value is a string describing the error.

Options are identified as command-line parameters which start with[OptionChar](../custapp/tcustomapplication.optionchar.html)(by default the dash ('-') character).

if `AllErrors` is `True` then all errors are returned, separated by a[sLineBreak](../../rtl/system/slinebreak.html)character.

**See also:**

| [FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html) |    | Return the index of an option. |
| --- | --- | --- |
| [GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| [CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html) |    | Are options interpreted case sensitive or not |
| [OptionChar](../custapp/tcustomapplication.optionchar.html) |    | Command-line switch character |

---

### `GetNonOptions`

**Type:** function

**Declaration:**

```pascal
public function TCustomApplication.GetNonOptions(
  const ShortOptions: string;
  const Longopts: array of string
):TStringArray;procedure TCustomApplication.GetNonOptions(
  const ShortOptions: string;
  const Longopts: array of string;
  NonOptions: TStrings
);
```

**Arguments:**

| ShortOptions |    | List of short options |
| --- | --- | --- |
| Longopts |    | List of long options |

**Description:**

`GetNonOptions` returns the items on the command-line that are not associated with a switch. It checks the command-line for allowed switches as they are indicated by `ShortOptions` and `Longopts` . The format is identical to[TCustomApplication.Checkoptions](../custapp/tcustomapplication.checkoptions.html). This is useful for an application which accepts a command form such as `svn` :

```
svn commit [options] files
```

In the above example, "commit" and "files" would be returned by `GetNonOptions`

The non-options are returned in the form of a string array, or a stringlist instance can be passed in `NonOptions` . Either will be filled with the non-options on return.

**See also:**

| [TCustomApplication.HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| --- | --- | --- |
| [TCustomApplication.Checkoptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |
| [TCustomApplication.GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [TCustomApplication.GetOptionValues](../custapp/tcustomapplication.getoptionvalues.html) |    | Get the values for an option that may be specified multiple times |

---

### `GetEnvironmentList`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.GetEnvironmentList(
  List: TStrings;
  NamesOnly: Boolean
);procedure TCustomApplication.GetEnvironmentList(
  List: TStrings
);
```

**Arguments:**

| List |    | List to return environment strings in. |
| --- | --- | --- |
| NamesOnly |    | If `True` , only environment variable names will be returned. |

**Description:**

`GetEnvironmentList` returns a list of environment variables in `List` . They are in the form `Name=Value` , one per item in `list` . If `NamesOnly` is `True` , then only the names are returned.

**See also:**

| [EnvironmentVariable](../custapp/tcustomapplication.environmentvariable.html) |    | Environment variable access |
| --- | --- | --- |

---

### `Log`

**Type:** procedure

**Declaration:**

```pascal
public procedure TCustomApplication.Log(
  EventType: TEventType;
  const Msg: string
);procedure TCustomApplication.Log(
  EventType: TEventType;
  const Fmt: string;
  const Args: array of Const
);
```

**Arguments:**

| EventType |    | Type of event |
| --- | --- | --- |
| Msg |    | Message to log |

**Description:**

`Log` is meant for all applications to have a default logging mechanism. By default it does not do anything, descendent classes should override this method to provide appropriate logging: they should write the message `Msg` with type `EventType` to some log mechanism such as[#fcl.eventlog.TEventLog](../eventlog/teventlog.html)

The second form using `Fmt` and `Args` will format the message using the provided arguments prior to logging it.

**See also:**

| [#rtl.sysutils.TEventType](../../rtl/sysutils/teventtype.html) |
| --- |

---

## Properties

### `ExeName`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.ExeName : string  read GetExeName;
```

**Description:**

`ExeName` returns the full name of the executable binary (path+filename). This is equivalent to `Paramstr(0)`

Note that some operating systems do not return the full pathname of the binary.

**See also:**

| [ParamStr](../../rtl/system/paramstr.html) |
| --- |

---

### `HelpFile`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.HelpFile : string  read FHelpFile  write FHelpFile;
```

**Description:**

`HelpFile` is the location of the application help file. It is a simple string property which can be set by an IDE such as Lazarus, and is mainly provided for compatibility with Delphi's `TApplication` implementation.

**See also:**

| [TCustomApplication.Title](../custapp/tcustomapplication.title.html) |    | Application title |
| --- | --- | --- |

---

### `Terminated`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.Terminated : Boolean  read FTerminated;
```

**Description:**

`Terminated` indicates whether[Terminate](../custapp/tcustomapplication.terminate.html)was called or not. Descendent classes should check `Terminated` at regular intervals in their implementation of `DoRun` , and if it is set to `True` , should exit gracefully the `DoRun` method.

**See also:**

| [Terminate](../custapp/tcustomapplication.terminate.html) |    | Terminate the application. |
| --- | --- | --- |

---

### `Title`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.Title : string  read FTitle  write SetTitle;
```

**Description:**

`Title` is a simple string property which can be set to any string describing the application. It does nothing by itself, and is mainly introduced for compatibility with Delphi's `TApplication` implementation.

**See also:**

| [HelpFile](../custapp/tcustomapplication.helpfile.html) |    | Location of the application help file. |
| --- | --- | --- |

---

### `OnException`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.OnException : TExceptionEvent  read FOnException  write FOnException;
```

**Description:**

`OnException` can be set to provide custom handling of exceptions, instead of the default action, which is simply to show the exception using[ShowException](../custapp/tcustomapplication.showexception.html).

If the event is set, then it is called by the[HandleException](../custapp/tcustomapplication.handleexception.html)routine. Do not use the `OnException` event directly, instead call `HandleException` .

**See also:**

| [ShowException](../custapp/tcustomapplication.showexception.html) |    | Show an exception to the user |
| --- | --- | --- |

---

### `ConsoleApplication`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.ConsoleApplication : Boolean  read GetConsoleApplication;
```

**Description:**

`ConsoleApplication` returns `True` if the application is compiled as a console application (the default) or `False` if not. The result of this property is determined at compile-time by the settings of the compiler: it returns the value of the[IsConsole](../../rtl/system/isconsole.html)constant.

**See also:**

| [IsConsole](../../rtl/system/isconsole.html) |
| --- |

---

### `Location`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.Location : string  read GetLocation;
```

**Description:**

`Location` returns the directory part of the application binary. This property works on most platforms, although some platforms do not allow to retrieve this information (Mac OS for example has no reliable way to get this information). See the discussion of[Paramstr](../../rtl/system/paramstr.html)in the RTL documentation.

**See also:**

| [Paramstr](../../rtl/system/paramstr.html) |
| --- |
| [Params](../custapp/tcustomapplication.params.html) |    | Command-line parameters |

---

### `Params`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.Params[Index: Integer] : string  read GetParams;
```

**Description:**

`Params` gives access to the command-line parameters. They contain the value of the `Index` -th parameter, where `Index` runs from 0 to[ParamCount](../custapp/tcustomapplication.paramcount.html). It is equivalent to calling[ParamStr](../../rtl/system/paramstr.html).

**See also:**

| [ParamCount](../custapp/tcustomapplication.paramcount.html) |    | Number of command-line parameters |
| --- | --- | --- |
| [Paramstr](../../rtl/system/paramstr.html) |

---

### `ParamCount`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.ParamCount : Integer  read GetParamCount;
```

**Description:**

`ParamCount` returns the number of command-line parameters that were passed to the program. The actual parameters can be retrieved with the[Params](../custapp/tcustomapplication.params.html)property.

**See also:**

| [Params](../custapp/tcustomapplication.params.html) |    | Command-line parameters |
| --- | --- | --- |
| [Paramstr](../../rtl/system/paramstr.html) |
| [ParamCount](../../rtl/system/paramcount.html) |

---

### `EnvironmentVariable`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.EnvironmentVariable[envName: string] : string  read GetEnvironmentVar;
```

**Description:**

`EnvironmentVariable` gives access to the environment variables of the application: It returns the value of the environment variable `EnvName` , or an empty string if no such value is available.

To use this property, the name of the environment variable must be known. To get a list of available names (and values),[GetEnvironmentList](../custapp/tcustomapplication.getenvironmentlist.html)can be used.

**See also:**

| [GetEnvironmentList](../custapp/tcustomapplication.getenvironmentlist.html) |    | Return a list of environment variables. |
| --- | --- | --- |
| [TCustomApplication.Params](../custapp/tcustomapplication.params.html) |    | Command-line parameters |

---

### `OptionChar`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.OptionChar : Char  read FoptionChar  write FOptionChar;
```

**Description:**

`OptionChar` is the character used for command line switches. By default, this is the dash ('-') character, but it can be set to any other non-alphanumerical character (although no check is performed on this).

**See also:**

| [FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html) |    | Return the index of an option. |
| --- | --- | --- |
| [GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| [CaseSensitiveOptions](../custapp/tcustomapplication.casesensitiveoptions.html) |    | Are options interpreted case sensitive or not |
| [CheckOptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |

---

### `CaseSensitiveOptions`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.CaseSensitiveOptions : Boolean  read FCaseSensitiveOptions  write FCaseSensitiveOptions;
```

**Description:**

`CaseSensitiveOptions` determines whether[FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html)and[CheckOptions](../custapp/tcustomapplication.checkoptions.html)perform searches in a case sensitive manner or not. By default, the search is case-sensitive. Setting this property to `False` makes the search case-insensitive.

**See also:**

| [FindOptionIndex](../custapp/tcustomapplication.findoptionindex.html) |    | Return the index of an option. |
| --- | --- | --- |
| [GetOptionValue](../custapp/tcustomapplication.getoptionvalue.html) |    | Return the value of a command-line option. |
| [HasOption](../custapp/tcustomapplication.hasoption.html) |    | Check whether an option was specified. |
| [OptionChar](../custapp/tcustomapplication.optionchar.html) |    | Command-line switch character |
| [CheckOptions](../custapp/tcustomapplication.checkoptions.html) |    | Check whether all given options on the command-line are valid. |

---

### `StopOnException`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.StopOnException : Boolean  read FStopOnException  write FStopOnException;
```

**Description:**

`StopOnException` controls the behaviour of the[Run](../custapp/tcustomapplication.run.html)and[HandleException](../custapp/tcustomapplication.handleexception.html)procedures in case of an unhandled exception in the `DoRun` code. If `StopOnException` is `True` then[Terminate](../custapp/tcustomapplication.terminate.html)will be called after the exception was handled.

**See also:**

| [Run](../custapp/tcustomapplication.run.html) |    | Runs the application. |
| --- | --- | --- |
| [HandleException](../custapp/tcustomapplication.handleexception.html) |    | Handle an exception. |
| [Terminate](../custapp/tcustomapplication.terminate.html) |    | Terminate the application. |

---

### `ExceptionExitCode`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.ExceptionExitCode : LongInt  read FExceptionExitCode  write FExceptionExitCode;
```

**Description:**

`ExceptionExitCode` is the exit code that will be passed to[TCustomApplication.Terminate](../custapp/tcustomapplication.terminate.html)

---

### `EventLogFilter`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.EventLogFilter : TEventLogTypes  read FEventLogFilter  write FEventLogFilter;
```

**Description:**

`EventLogFilter` can be set to a set of event types that should be logged to the system log. If the set is empty, all event types are sent to the system log. If the set is non-empty, the[TCustomApplication.Log](../custapp/tcustomapplication.log.html)routine will check if the log event type is in the set, and if not, will not send the message to the system log.

**See also:**

| [TCustomApplication.Log](../custapp/tcustomapplication.log.html) |    | Write a message to the event log |
| --- | --- | --- |

---

### `SingleInstance`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.SingleInstance : TBaseSingleInstance  read GetSingleInstance;
```

**Description:**

`SingleInstance` is used when[TCustomApplication.SingleInstanceEnabled](../custapp/tcustomapplication.singleinstanceenabled.html)is set to `True` . It can be used to send a message to an already running instance, or to check for messages if the current instance is the sole ("server") instance running.

**See also:**

| [TCustomApplication.SingleInstanceClass](../custapp/tcustomapplication.singleinstanceclass.html) |    | Class to use when creating single instance |
| --- | --- | --- |
| [TCustomApplication.SingleInstanceEnabled](../custapp/tcustomapplication.singleinstanceenabled.html) |    | Enable single application instance control. |

---

### `SingleInstanceClass`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.SingleInstanceClass : TBaseSingleInstanceClass  read FSingleInstanceClass  write SetSingleInstanceClass;
```

**Description:**

`SingleInstanceClass` can be used to set the class used to instantiate[SingleInstance](../custapp/tcustomapplication.singleinstance.html). The default class is determined by the global singleinstance default class as specified in**#fcl.singleinstance.DefaultSingleInstanceClass**.

**See also:**

| [TCustomApplication.SingleInstance](../custapp/tcustomapplication.singleinstance.html) |    | Single instance used to control single application instance behaviour |
| --- | --- | --- |
| **DefaultSingleInstanceClass** |

---

### `SingleInstanceEnabled`

**Type:** property

**Declaration:**

```pascal
public property TCustomApplication.SingleInstanceEnabled : Boolean  read FSingleInstanceEnabled  write FSingleInstanceEnabled;
```

**Description:**

`SingleInstanceEnabled` can be set to `true` to start single-instance application control. This will instantiate[TCustomApplication.SingleInstance](../custapp/tcustomapplication.singleinstance.html)using[TCustomApplication.SingleInstanceClass](../custapp/tcustomapplication.singleinstanceclass.html)and starts the check to wee whether this application is a client or server instance.

**See also:**

| [TCustomApplication.SingleInstance](../custapp/tcustomapplication.singleinstance.html) |    | Single instance used to control single application instance behaviour |
| --- | --- | --- |
| [TCustomApplication.SingleInstanceClass](../custapp/tcustomapplication.singleinstanceclass.html) |    | Class to use when creating single instance |

---

