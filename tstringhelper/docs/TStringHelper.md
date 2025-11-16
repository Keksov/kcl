# TStringHelper Properties (System.SysUtils.TStringHelper)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper_Properties).

## `System.SysUtils.TStringHelper.Chars`

```pascal
property Chars[Index: Integer]: Char read GetChars;
```

## Description



Accesses individual characters in this zero-based string. The [Chars]() property is read-only. If you access a character outside the string (more than string lenght-1 or less than zero), or if the string is empty, then this function returns an undefined result. 



var
  I: Integer;
  MyString: String;

begin
  MyString := 'This is a string.';

  for I:= 0 to MyString.Length - 1 do
    Write(MyString.Chars[I]);
end.


Output:



This is a string.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Chars)

---

## `System.SysUtils.TStringHelper.Length`

```pascal
property Length: Integer read GetLength;
```

## Description



Use [Length]() in order to obtain the length of the zero-based string.



var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(MyString.Length);
end.


Output:



17



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Length)

---

# TStringHelper Methods (System.SysUtils.TStringHelper)

Automatically extracted from [Embarcadero DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper_Methods).

## `System.SysUtils.TStringHelper.Compare`

```pascal
class function Compare(const StrA: string; const StrB: string): Integer; overload; static; inline;
class function Compare(const StrA: string; const StrB: string; LocaleID: TLocaleID): Integer; overload; static; inline;
class function Compare(const StrA: string; const StrB: string; IgnoreCase: Boolean): Integer; overload; static; inline; //deprecated 'Use same with TCompareOptions';
class function Compare(const StrA: string; const StrB: string; IgnoreCase: Boolean; LocaleID: TLocaleID): Integer; overload; static; inline; //deprecated 'Use same with TCompareOptions';
class function Compare(const StrA: string; const StrB: string; Options: TCompareOptions): Integer; overload; static; inline;
class function Compare(const StrA: string; const StrB: string; Options: TCompareOptions; LocaleID: TLocaleID): Integer; overload; static; inline;
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer): Integer; overload; static; inline;
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer; LocaleID: TLocaleID): Integer; overload; static; inline;
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer; IgnoreCase: Boolean): Integer; overload; static; inline; //deprecated 'Use same with TCompareOptions';
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer; IgnoreCase: Boolean; LocaleID: TLocaleID): Integer; overload; static; inline; //deprecated 'Use same with TCompareOptions';
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer; Options: TCompareOptions): Integer; overload; static; inline;
class function Compare(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer; Options: TCompareOptions; LocaleID: TLocaleID): Integer; overload; static; inline;
```

## Description



Compares two 0-based strings for equality.



[Compare]() is a static class function (calling syntax can be String.Compare(...);) and returns:



< 0 if StrA sorts before StrB
0 if StrA is the same as StrB
> 0 if StrA sorts after StrB
var
  MyStringA, MyStringB: String;

begin
  MyStringA := 'String A';
  MyStringB := 'String B';

  Writeln(Boolean(String.Compare(MyStringA, MyStringB) = 0));
end.


Output:



FALSE


There are eight [Compare]() overloaded methods:



The first [Compare]() overloaded method compares StrA against StrB with case-sensitivity.
The second [Compare]() overloaded method compares StrA against StrB with specified language and region identifier through the LocaleID parameter. This method is case-sensitive.
The third [Compare]() overloaded method compares StrA against StrB with specifiable case-sensitivity through the IgnoreCase parameter.
The fourth [Compare]() overloaded method compares StrA against StrB with specifiable case-sensitivity through the IgnoreCase parameter and with specified language and region identifier through the LocaleID parameter.
The fifth [Compare]() overloaded method compares StrA against StrB and allows you to specify from what position in the strings (IndexA against IndexB) to start the comparison, and for what number of characters (Length). This method is case-sensitive.
The sixth [Compare]() overloaded method compares StrA against StrB and allows you to specify from what position in the strings (IndexA against IndexB) to start the comparison, and for what number of characters (Length). This method also allows you to specify the language and region identifier through the LocaleID parameter. This method is case-sensitive.
The seventh [Compare]() overloaded method compares StrA against StrB and allows you to specify from what position in the strings (IndexA against IndexB) to start the comparison, and for what number of characters (Length). This method is user specifiable case-sensitive through the IgnoreCase parameter.
The eighth [Compare]() overloaded method compares StrA against StrB and allows you to specify from what position in the strings (IndexA against IndexB) to start the comparison, and for what number of characters (Length). This method is user specifiable case-sensitive through the IgnoreCase parameter. This method also allows you to specify the language and region identifier through the LocaleID parameter.
> 
**Note:** In some circumstances, [Compare]() can unexpectedly fail on older versions of Windows (prior to Windows 7). For example, failure can result if a string contains a hyphen ("-"), or if the [System.SysUtils.TCompareOption](/Libraries/Sydney/en/System.SysUtils.TCompareOption)  **coLingIgnoreCase** or **coDigitAsNumbers** is set. 




> 
**Note:** In some circumstances, [Compare]() can fail on older versions of Windows (prior to Windows 7). For example, failure can result if a string contains a hyphen ("-"), or if the [System.SysUtils.TCompareOption](/Libraries/Sydney/en/System.SysUtils.TCompareOption)  **coLingIgnoreCase** or **coDigitAsNumbers** is set. 






[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Compare)

---

## `System.SysUtils.TStringHelper.CompareOrdinal`

```pascal
class function CompareOrdinal(const StrA: string; const StrB: string): Integer; overload; static;
class function CompareOrdinal(const StrA: string; IndexA: Integer; const StrB: string; IndexB: Integer; Length: Integer): Integer; overload; static;
```

## Description



[CompareOrdinal]() compares two strings by evaluating the numeric values of the corresponding characters in each string.



This method is overloaded:



The first [CompareOrdinal]() overloaded method compares StrA against StrB by evaluating the numeric values of the corresponding characters in each string.
The second [CompareOrdinal]() overloaded method compares StrA against StrB and allows you to specify from what position in the strings (IndexA against IndexB) to start the comparison, and for what number of characters (Length).


[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.CompareOrdinal)

---

## `System.SysUtils.TStringHelper.CompareText`

```pascal
class function CompareText(const StrA: string; const StrB: string): Integer; static; inline;
```

## Description



Compares two strings by their ordinal value, without case sensitivity.



[CompareText]() compares StrA and StrB and returns 0 if they are equal. If StrA is greater than StrB, [CompareText]() returns an integer greater than 0. If StrA is less than StrB, [CompareText]() returns an integer less than 0. [CompareText]() is not case sensitive and is not affected by the current locale, when using the first [CompareText]() overloaded method. 





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.CompareText)

---

## `System.SysUtils.TStringHelper.CompareTo`

```pascal
function CompareTo(const strB: string): Integer;
```

## Description



Compares this 0-based string against a given string.



[CompareTo]() compares with case-sensitivity and returns:



< 0 if the string sorts before StrB
0 if the string is the same as StrB
> 0 if the string sorts after StrB
var
  MyStringA, MyStringB: String;

begin
  MyStringA := 'String A';
  MyStringB := 'String B';

  Writeln(Boolean(MyStringA.CompareTo(MyStringB) = 0));
end.


Output:



FALSE



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.CompareTo)

---

## `System.SysUtils.TStringHelper.Contains`

```pascal
function Contains(const Value: string): Boolean;
```

## Description



Returns whether this 0-based string contains the given string.



[Contains]() returns **True** if the string contains the string given through the Value parameter, **False** otherwise. This function is case-sensitive.



var
  MyString, ContainedString: String;

begin
  MyString := 'This is a string.';
  ContainedString := 'This';
  Writeln(Boolean(MyString.Contains(ContainedString)));
end.


Output:



TRUE



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Contains)

---

## `System.SysUtils.TStringHelper.Copy`

```pascal
class function Copy(const Str: string): string; inline; static;
```

## Description



Copies and returns the 0-based given string.



[Copy]() copies the 0-based string given through the Str parameter and returns it. [Copy]() is a static class function.



var
  MyString: String;

begin
  MyString := 'This is a string.';
  Writeln(String.Copy(MyString));
end.


Output:



This is a string.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Copy)

---

## `System.SysUtils.TStringHelper.CopyTo`

```pascal
procedure CopyTo(SourceIndex: Integer; var destination: array of Char; DestinationIndex: Integer; Count: Integer);
```

## Description



Copies memory allocated for several characters in the 0-based string to the memory allocated for characters in another 0-based string.



[CopyTo]() function is similar to [Move](/Libraries/Sydney/en/System.Move) function.



var
  MyString, CopyString: String;

begin
  MyString := 'This is a string.';
  CopyString := 'S';
  CopyString.CopyTo(0, MyString[11], 0, CopyString.Length);
  Writeln(MyString);
end.


Output:



This is a String.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.CopyTo)

---

## `System.SysUtils.TStringHelper.CountChar`

```pascal
function CountChar(const C: Char): Integer;
```

## Description



[CountChar]() counts the occurrences of the C character in the string.



### Example



The following code counts the "s" letters in the string:



const
  myString = 'This string contains 5 occurrences of s';
begin
  writeln(myString.CountChar('s'));
  readln;
end.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.CountChar)

---

## `System.SysUtils.TStringHelper.Create`

```pascal
class function Create(C: Char; Count: Integer): string; overload; inline; static;
class function Create(const Value: array of Char; StartIndex: Integer; Length: Integer): string; overload; static;
class function Create(const Value: array of Char): string; overload; static;
```



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Create)

---

## `System.SysUtils.TStringHelper.DeQuotedString`

```pascal
function DeQuotedString: string; overload;
function DeQuotedString(const QuoteChar: Char): string; overload;
```

## Description



This method removes the quote characters from a string.



[DeQuotedString]() removes the quote characters from the beginning and end of a quoted string, and reduces pairs of quote characters within the quoted string to a single character.



### Example


var
myString: string;

begin
  myString := '''''This function illustrates the f''''unctionality of'' the DeQuoted''String method.''';
  myString := myString.DeQuotedString;
  writeln(myString);
  readln;
end.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.DeQuotedString)

---

## `System.SysUtils.TStringHelper.EndsText`

```pascal
class function EndsText(const ASubText, AText: string): Boolean; static;
```

## Description



Returns whether the given 0-based string ends with the given 0-based substring.



[EndsText]() is a static function that can be called like this:



var
  MyString: String;

begin
  MyString := 'This is a string.';
  Writeln(Boolean(String.EndsText('string.', MyString)));
end.


Output:



TRUE

> 
**Tip:** [EndsText]() is case-insensitive.






[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.EndsText)

---

## `System.SysUtils.TStringHelper.EndsWith`

```pascal
function EndsWith(const Value: string): Boolean; overload; inline;
function EndsWith(const Value: string; IgnoreCase: Boolean): Boolean; overload;
```

## Description



Returns whether this 0-based string ends with the given Value substring.



[EndsWith]() returns whether this string ends with the substring passed through Value. [EndsWith]() is case-sensitive if the first overloaded function is used. 



IgnoreCase specifies whether to use case-sensitivity or not.



var
  MyString: String;

begin
  MyString := 'This is a string.';
  Writeln(Boolean(MyString.EndsWith('String.', False)));
end.


Output:



FALSE



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.EndsWith)

---

## `System.SysUtils.TStringHelper.Equals`

```pascal
function Equals(const Value: string): Boolean; overload;
class function Equals(const a: string; const b: string): Boolean; overload; static;
```

## Description



Returns whether the two given 0-based strings are identical.



[Equals]() is a a function that returns whether two 0-based strings are identical or not. There are two [Equals]() overloaded methods. The first one returns whether this string is equal to the string passed through the Value parameter. The second overloaded method is a static class function that can be called to check for equality between the two passed strings. 



var
  MyString1: String;
  MyString2: String;

begin
  MyString1 := 'This is one string.';
  MyString2 := 'This is another string.';
  Writeln(Boolean(MyString1.Equals(MyString2)));
  Writeln(Boolean(String.Equals(MyString1, MyString2)));
end.


Output:



FALSE
FALSE



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Equals)

---

## `System.SysUtils.TStringHelper.Format`

```pascal
class function Format(const Format: string; const args: array of const): string; overload; static;
```

## Description



Identical to [Format](/Libraries/Sydney/en/System.SysUtils.Format) function.



[Equals](/Libraries/Sydney/en/System.SysUtils.TStringHelper.Equals) is a class function that returns a formatted 0-based string based on the given parameters. 



var
  MyString1: String;
  MyString2: String;

begin
  MyString1 := 'This is a %s';
  MyString2 := 'string.';
  Writeln(String.Format(MyString1, [MyString2]));
end.


Output:



This is a string.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Format)

---

## `System.SysUtils.TStringHelper.GetHashCode`

```pascal
function GetHashCode: Integer;
```

## Description



Returns the hash code for this string.



**Note:**  If two strings are equal, this method returns identical values. However, there is not a unique hash code for each particular string value. Different strings can return the same hash code.

Since RAD Studio Sydney the [TStringHelper.GetHashCode]() member no longer creates an uppercase version of the string before calculating the hashcode. 



Therefore, strings that differ only in case will produce different hash codes. To illustrate:



 if 'Hello'.GetHashCode = 'HELLO'.GetHashCode then
   ShowMessage('True')
 else
   ShowMessage('False');


The above showed the '**True'** message in earlier versions. Starting RAD Studio Sydney, it shows '**False'**.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.GetHashCode)

---

## `System.SysUtils.TStringHelper.IndexOf`

```pascal
function IndexOf(value: Char): Integer; overload; inline;
function IndexOf(const Value: string): Integer; overload; inline;
function IndexOf(Value: Char; StartIndex: Integer): Integer; overload;
function IndexOf(const Value: string; StartIndex: Integer): Integer; overload;
function IndexOf(Value: Char; StartIndex: Integer; Count: Integer): Integer; overload;
function IndexOf(const Value: string; StartIndex: Integer; Count: Integer): Integer; overload;
```

## Description



Returns an integer that specifies the position of the first occurrence of a character or a substring within this 0-based string, starting the search at StartIndex.
This method returns -1 if the value is not found or StartIndex specifies an invalid value.



This method uses the following parameters:



StartIndex specifies the initial offset in this 0-based string where the search starts.
Count specifies the length of the substring to search for.
### Example


var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(MyString.IndexOf('s', 8, 4));
  Writeln(MyString.IndexOf('is', 0));
end.


Output:



10
2



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IndexOf)

---

## `System.SysUtils.TStringHelper.IndexOfAny`

```pascal
function IndexOfAny(const AnyOf: array of Char): Integer; overload;
function IndexOfAny(const AnyOf: array of Char; StartIndex: Integer): Integer; overload;
function IndexOfAny(const AnyOf: array of Char; StartIndex: Integer; Count: Integer): Integer; overload;
```

## Description



Returns an integer indicating the position of the first given character found in the 0-based string.



[IndexOfAny]() uses the following optional parameters:



StartIndex specifies the initial offset in this 0-based string where the search starts.
Count specifies the maximum length to search starting from StartIndex. It is limited by the string length.

[IndexOfAny]() returns -1 if:



The given character is not found.
StartIndex specifies a value higher than the string length minus 1 (it is 0-based).
Count is equal to or less than 0.
### Example


var
  MyString: String;

begin
  MyString := 'This is a string.';
  Writeln(MyString.IndexOfAny(['w'])) 
  Writeln(MyString.IndexOfAny(['w', 's', 'a'], 0)); 
  Writeln(MyString.IndexOfAny(['w', 's', 'a'], 9));
  Writeln(MyString.IndexOfAny(['w', 's', 'a'], 11, 4));
end.


Output:



-1 //  'w' is not present in MyString 
3 // The first given character found is 's' in position 3
10 // Staring at position 9, the first given character found is 's' at position 10
-1 // No given characters are found in the substring 'trin'



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IndexOfAny)

---

## `System.SysUtils.TStringHelper.IndexOfAnyUnquoted`

```pascal
function IndexOfAnyUnquoted(const AnyOf: array of Char; StartQuote, EndQuote: Char): Integer; overload;
function IndexOfAnyUnquoted(const AnyOf: array of Char; StartQuote, EndQuote: Char; StartIndex: Integer): Integer; overload;
function IndexOfAnyUnquoted(const AnyOf: array of Char; StartQuote, EndQuote: Char; StartIndex: Integer; Count: Integer): Integer; overload;
```

## Description



Returns the index of the first occurrence of any of the specified characters outside the specified type of quotes in the specified string, or -1 if there is no matching unquoted character.



[IndexOfAnyUnquoted]() follows these rules:



A character is considered to be quoted if it is located after the specified start quote and before the specified end quote.
If there is no end quote closing a start quote, any character after that start quote is considered to be quoted.
Each end quote closes a previous start quote; a single end quote cannot close multiple start quotes.

[IndexOfAnyUnquoted]() receives the following parameters:



AnyOf is an array of characters to match. [IndexOfAnyUnquoted]() looks for the first occurrence of any of these characters outside the specified quotes.
StartQuote is the start quote character.
EndQuote is the end quote character. It may be the same as the start quote character.
StartIndex (optional) is the index of the string where [IndexOfAnyUnquoted]() starts searching for a matching character. You can think of it as the number of characters at the beginning of the string to skip during the search. If you do not specify a start index, [IndexOfAnyUnquoted]() searches from the beginning of the string.
**Warning:** Quotes with an index lower than the specified StartIndex are skipped as well, and they are not taken into account to determine which characters are quoted and which characters are unquoted. See the examples with a StartIndex value in the examples table below.
Count (optional) is the number of characters of the string to search. If you do not specify a value for Count, [IndexOfAnyUnquoted]() searches until the end of the string.
### Examples



The following table shows some examples of executing [IndexOfAnyUnquoted]() with different arguments. The character that determines the returned index, if any, is displayed in bold font in the **String** column of the table.



| String | AnyOf | StartQuote | EndQuote | StartIndex | Count | Result (Index) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| "This" **i**s it | i | " | " |  |  | 7 |  |
| "This is it | i | " | " |  |  | -1 | There is no end quote, so everything after the start quote is considered quoted. |
| "This" "is" "it" | i | " | " |  |  | -1 | Only spaces are unquoted. |
| <This <is>> **i**t | i | < | > |  |  | 12 | Characters within nested quotes are ignored as well. |
| "Th**i**s" is it | i | " | " | 1 |  | 3 | [IndexOfAnyUnquoted]() skips the start quote because of the value of StartIndex, so the end quote becomes a start quote. |
| This" "is" "it | i | " | " | 5 |  | -1 | [IndexOfAnyUnquoted]() skips the first start quote because of the value of StartIndex, so end quotes become start quotes and vice versa, and the only unquoted characters are now spaces. |




[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IndexOfAnyUnquoted)

---

## `System.SysUtils.TStringHelper.Insert`

```pascal
function Insert(StartIndex: Integer; const Value: string): string;
```

## Description



Inserts a string in this 0-based string at the given position.



var
  MyString: String;

begin
  MyString := 'This a string.';

  Writeln(MyString.Insert(5, 'is '));
end.


Output:



This is a string.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Insert)

---

## `System.SysUtils.TStringHelper.IsDelimiter`

```pascal
function IsDelimiter(const Delimiters: string; Index: Integer): Boolean;
```

## Description



Indicates whether a specified character in this 0-based string matches one of a set of delimiters.



[IsDelimiter]() determines whether the character at offset Index in this 0-based string is one of the delimiters in the string Delimiters.



var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(Boolean(MyString.IsDelimiter('is', 5)));
end.


Output:



TRUE



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IsDelimiter)

---

## `System.SysUtils.TStringHelper.IsEmpty`

```pascal
function IsEmpty: Boolean;
```

## Description



Returns whether this 0-based string is empty (does not contain any characters).





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IsEmpty)

---

## `System.SysUtils.TStringHelper.IsNullOrEmpty`

```pascal
class function IsNullOrEmpty(const Value: string): Boolean; static;
```

## Description



Is a static class function that returns whether the given string is empty or not (does not contain any characters).





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IsNullOrEmpty)

---

## `System.SysUtils.TStringHelper.IsNullOrWhiteSpace`

```pascal
class function IsNullOrWhiteSpace(const Value: string): Boolean; static;
```

## Description



Indicates if a specified string is empty or consists only of white-space characters.



[IsNullOrWhiteSpace]() returns **True** if the Value parameter is **null** or empty, or consists only of white-space characters.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.IsNullOrWhiteSpace)

---

## `System.SysUtils.TStringHelper.Join`

```pascal
class function Join(const Separator: string; const Values: array of const): string; overload; static;
class function Join(const Separator: string; const Values: array of string): string; overload; static;
class function Join(const Separator: string; const Values: IEnumerator<string>): string; overload; static;
class function Join(const Separator: string; const Values: IEnumerable<string>): string; overload; static; inline;
class function Join(const Separator: string; const Values: array of string; StartIndex: Integer; Count: Integer): string; overload; static;
```

## Description



Joins two or more 0-based strings together separated by the given Separator.



begin
  Writeln(String.Join(',', ['String1', 'String2', 'String3']));
  Writeln(String.Join(',', ['String1', 'String2', 'String3'], 1, 2));
end.


Output:



String1,String2,String3
String2,String3


There are five [Join]() overloaded methods:



The first [Join]() overloaded method concatenates the elements of a constant array, using the specified Separator between each element.
The second [Join]() overloaded method concatenates all the elements of a string array, using the specified Separator between each element.
The third [Join]() overloaded method concatenates the elements of an object array, using the specified Separator between each element.
The fourth [Join]() overloaded method concatenates the elements of a [IEnumerable](/Libraries/Sydney/en/System.IEnumerable), using the specified Separator between each member.
The fifth [Join]() overloaded method concatenates the specified elements of a string array, using the specified Separator between each element.


[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Join)

---

## `System.SysUtils.TStringHelper.LastDelimiter`

```pascal
function LastDelimiter(const Delims: string): Integer; overload;
function LastDelimiter(const Delims: TSysCharSet): Integer; overload;
```

## Description



Returns the string index in this 0-based string of the rightmost whole character that matches any character in Delims (except null = #0).





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.LastDelimiter)

---

## `System.SysUtils.TStringHelper.LastIndexOf`

```pascal
function LastIndexOf(Value: Char): Integer; overload;
function LastIndexOf(const Value: string): Integer; overload;
function LastIndexOf(Value: Char; StartIndex: Integer): Integer; overload;
function LastIndexOf(const Value: string; StartIndex: Integer): Integer; overload;
function LastIndexOf(Value: Char; StartIndex: Integer; Count: Integer): Integer; overload;
function LastIndexOf(const Value: string; StartIndex: Integer; Count: Integer): Integer; overload;
```

## Description



Returns the last index of the Value string in the current 0-based string.



StartIndex specifies the offset in this 0-based string where the [LastIndexOf]() method begins the search, and Count specifies the end offset where the search ends.



There are six [LastIndexOf]() overloaded methods, each one allowing you to specify various options in order to obtain the last index of the given string in this 0-based string.



When the Value argument (Char or String), passed to [ LastIndexOf](),  is not found in the 0-based string, [ LastIndexOf]() function returns -1.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.LastIndexOf)

---

## `System.SysUtils.TStringHelper.LastIndexOfAny`

```pascal
function LastIndexOfAny(const AnyOf: array of Char): Integer; overload;
function LastIndexOfAny(const AnyOf: array of Char; StartIndex: Integer): Integer; overload;
function LastIndexOfAny(const AnyOf: array of Char; StartIndex: Integer; Count: Integer): Integer; overload;
```

## Description



Returns the last index of any character of the AnyOf character array, in the current 0-based string.



var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(MyString.LastIndexOfAny(['T'], 0));
end.


There are three [LastIndexOfAny]() overloaded methods, each one allowing you to specify various options in order to obtain the last index of the given characters in this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.LastIndexOfAny)

---

## `System.SysUtils.TStringHelper.LowerCase`

```pascal
class function LowerCase(const S: string): string; overload; static; inline;
class function LowerCase(const S: string; LocaleOptions: TLocaleOptions): string; overload; static; inline;
```

## Description



Converts an ASCII string to lowercase.



[LowerCase]() returns a string with the same text as the string passed in S, but with all letters converted to lowercase. The conversion affects only 7-bit ASCII characters between 'A' and 'Z'. To convert 8-bit international characters, use [ToLower](/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToLower).



The LocaleOptions parameter of the second [LowerCase]() overloaded method is of type [TLocaleOptions](/Libraries/Sydney/en/System.SysUtils.TLocaleOptions) and defines a choice of dependent and independent locale options. For more information, please refer to the [TLocaleOptions](/Libraries/Sydney/en/System.SysUtils.TLocaleOptions) topic.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.LowerCase)

---

## `System.SysUtils.TStringHelper.PadLeft`

```pascal
function PadLeft(TotalWidth: Integer): string; overload; inline;
function PadLeft(TotalWidth: Integer; PaddingChar: Char): string; overload; inline;
```

## Description



Left-aligns a 0-based string into a fixed length text space.



var
  MyString1: String;
  MyString2: String;

begin
  MyString1 := '12345';
  MyString2 := '123';
  Writeln(MyString1.PadLeft(5));
  Writeln(MyString2.PadLeft(5));
end.


Output:



12345
  123


There are two [PadLeft]() overloaded methods. The first one assumes the pad character is the empty space, while the second one allows you to specify the padding character.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.PadLeft)

---

## `System.SysUtils.TStringHelper.PadRight`

```pascal
function PadRight(TotalWidth: Integer): string; overload; inline;
function PadRight(TotalWidth: Integer; PaddingChar: Char): string; overload; inline;
```

## Description



Right aligns this 0-based string into a fixed length text space.



var
  MyString1: String;
  MyString2: String;

begin
  MyString1 := '12345';
  MyString2 := '123';
  Writeln(MyString1.PadRight(5));
  Writeln(MyString2.PadRight(5));
end.


Output:



12345
123


There are two [PadRight]() overloaded methods. The first one assumes the pad character is the empty space, while the second one allows you to specify the padding character.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.PadRight)

---

## `System.SysUtils.TStringHelper.Parse`

```pascal
class function Parse(const Value: Integer): string; overload; static; inline;
class function Parse(const Value: Int64): string; overload; static; inline;
class function Parse(const Value: Boolean): string; overload; static; inline;
class function Parse(const Value: Extended): string; overload; static;inline;
```

## Description



[Parse]() converts **Integer**, **Boolean** and **Extended** types to their string representations.



This method is overloaded: 



Converts an integer value into a string.
Converts a boolean value into a string.
Converts a floating-point value into a string.


[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Parse)

---

## `System.SysUtils.TStringHelper.QuotedString`

```pascal
function QuotedString: string; overload;
function QuotedString(const QuoteChar: Char): string; overload;
```

## Description



[QuotedString]() doubles all the occurrences of a character and also adds it to the edges of the string.



This method is overloaded:



If the QuoteChar parameter is given, the method doubles all the occurrences of the letter specified in the parameter and also adds it to the edges of the string. Then, this method returns a new instance of the string.
If a parameter is not given, the method adds apostrophes to the beginning and end of the string. Then, this method returns a new instance of the string.
### Example



The following code adds apostrophes at the edges of the string and, afterwards, doubles all the occurrences of the letter specified in the parameter:



var
myString: string;

begin
  myString := 'This function illustrates the functionality of the QuotedString method.';
  myString := myString.QuotedString;
  myString := myString.QuotedString('f');
  writeln(myString);
  readln;
end.



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.QuotedString)

---

## `System.SysUtils.TStringHelper.Remove`

```pascal
function Remove(StartIndex: Integer): string; overload; inline;
function Remove(StartIndex: Integer; Count: Integer): string; overload; inline;
```

## Description



Removes the substring at the position StartIndex and optionally until the position StartIndex + Count, if specified, from this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Remove)

---

## `System.SysUtils.TStringHelper.Replace`

```pascal
function Replace(OldChar: Char; NewChar: Char): string; overload;
function Replace(OldChar: Char; NewChar: Char; ReplaceFlags: TReplaceFlags): string; overload;
function Replace(const OldValue: string; const NewValue: string): string; overload;
function Replace(const OldValue: string; const NewValue: string; ReplaceFlags: TReplaceFlags): string; overload;
```

## Description



Replaces an old character or string with a new given character or string.



var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(MyString.Replace('a', 'one'));
  Writeln(MyString.Replace('a', '1'));
end.


Output:



This is one string.
This is 1 string.


There are four [Replace]() overloaded methods. The first two of them replace only characters while the third and fourth ones replace strings. The ReplaceFlags parameter is introduced in order for you to use flags such as rfIgnoreCase or rfReplaceAll.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Replace)

---

## `System.SysUtils.TStringHelper.Split`

```pascal
function Split(const Separator: array of Char): TArray<string>; overload;
function Split(const Separator: array of Char; Count: Integer): TArray<string>; overload;
function Split(const Separator: array of Char; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of Char; Count: Integer; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of string): TArray<string>; overload;
function Split(const Separator: array of string; Count: Integer): TArray<string>; overload;
function Split(const Separator: array of string; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of string; Count: Integer; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of Char; Quote: Char): TArray<string>; overload;
function Split(const Separator: array of Char; QuoteStart, QuoteEnd: Char): TArray<string>; overload;
function Split(const Separator: array of Char; QuoteStart, QuoteEnd: Char; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of Char; QuoteStart, QuoteEnd: Char; Count: Integer): TArray<string>; overload;
function Split(const Separator: array of Char; QuoteStart, QuoteEnd: Char; Count: Integer; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of string; Quote: Char): TArray<string>; overload;
function Split(const Separator: array of string; QuoteStart, QuoteEnd: Char): TArray<string>; overload;
function Split(const Separator: array of string; QuoteStart, QuoteEnd: Char; Options: TStringSplitOptions): TArray<string>; overload;
function Split(const Separator: array of string; QuoteStart, QuoteEnd: Char; Count: Integer): TArray<string>; overload;
function Split(const Separator: array of string; QuoteStart, QuoteEnd: Char; Count: Integer; Options: TStringSplitOptions): TArray<string>; overload;
```

## Description



Splits this 0-based string into substrings, using the given Separator.



var
  MyString: String;
  Splitted: TArray<String>;

begin
  MyString := String.Join(',', ['String1', 'String2', 'String3']);
  Splitted := MyString.Split([','], 2);
end.


There are many [Split]() overloaded methods each one allowing for various splitting options.



The Count parameter represents the maximum number of strings to be added to the array.



| Parameter | Description |
| --- | --- |
| Separator | The characters or strings to be used as separator. |
| Count | Maximum number of splits to return; defaults to MaxInt if not specified. |
| QuoteStart/QuoteEnd | Start and end characters of a quoted part of the string where the separator is ignored. |
| Options | Controls if any empty matches, or if trailing empty matches are included. |




[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Split)

---

## `System.SysUtils.TStringHelper.StartsText`

```pascal
class function StartsText(const ASubText, AText: string): Boolean; static;
```



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.StartsText)

---

## `System.SysUtils.TStringHelper.StartsWith`

```pascal
function StartsWith(const Value: string): Boolean; overload; inline;
function StartsWith(const Value: string; IgnoreCase: Boolean): Boolean; overload;
```

## Description



Returns whether this 0-based string starts with the given string.



The string you want to test whether it is the start string for this 0-based string, is passed through the Value parameter. The IgnoreCase parameter of the second overloaded [StartsWith]() function allows you to compare without case-sensitivity.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.StartsWith)

---

## `System.SysUtils.TStringHelper.Substring`

```pascal
function Substring(StartIndex: Integer): string; overload; inline;
function Substring(StartIndex: Integer; Length: Integer): string; overload; inline;
```

## Description



Returns the substring starting at the position StartIndex and optionally ending at the position StartIndex + Length, if specified, from this 0-based string.



var
  MyString: String;

begin
  MyString := 'This is a string.';

  Writeln(MyString.Substring(5));
  Writeln(MyString.Substring(5, 2));
end.


Output:



is a string.
is



[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Substring)

---

## `System.SysUtils.TStringHelper.ToBoolean`

```pascal
class function ToBoolean(const S: string): Boolean; overload; static; inline;
function ToBoolean: Boolean; overload; inline;
```

## Description



Converts a string to a Boolean value.



This method is overloaded.



[ToBoolean]() converts the string specified by S to a Boolean.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToBoolean)

---

## `System.SysUtils.TStringHelper.ToCharArray`

```pascal
function ToCharArray: TArray<Char>; overload;
function ToCharArray(StartIndex: Integer; Length: Integer): TArray<Char>; overload;
```

## Description



Transforms this 0-based string into a TArray<Char> (a character array) and returns it.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToCharArray)

---

## `System.SysUtils.TStringHelper.ToDouble`

```pascal
class function ToDouble(const S: string): Double; overload; static; inline;
function ToDouble: Double; overload; inline;
```

## Description



Converts a given string to a floating-point value.



This method is overloaded.



Use [ToDouble]() to convert a string S to a floating-point value. S must consist of an optional sign (+ or -), a string of digits with an optional decimal point, and an optional mantissa. The mantissa consists of 'E' or 'e' followed by an optional sign (+ or -) and a whole number. Leading and trailing blanks are ignored.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToDouble)

---

## `System.SysUtils.TStringHelper.ToExtended`

```pascal
class function ToExtended(const S: string): Extended; overload; static; inline;
function ToExtended: Extended; overload; inline;
```

## Description



Converts a given string to a floating-point value.



This method is overloaded.



Use [ToExtended]() to convert a string S to a floating-point value. S must consist of an optional sign (+ or -), a string of digits with an optional decimal point, and an optional mantissa. The mantissa consists of 'E' or 'e' followed by an optional sign (+ or -) and a whole number. Leading and trailing blanks are ignored.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToExtended)

---

## `System.SysUtils.TStringHelper.ToInt64`

```pascal
class function ToInt64(const S: string): Int64; overload; static; inline;
function ToInt64: Int64; overload; inline;
```

## Description



Returns the integer value of the specified string as an [Int64](/Libraries/Sydney/en/System.Int64) value.



For information about the supported input notations, see [Val](/Libraries/Sydney/en/System.Val).





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToInt64)

---

## `System.SysUtils.TStringHelper.ToInteger`

```pascal
class function ToInteger(const S: string): Integer; overload; static; inline;
function ToInteger: Integer; overload; inline;
```

## Description



Converts a string that represents an integer (decimal or hex notation) into a number.



This method is overloaded.



[ToInteger]() converts the string S, which represents an integer-type number in either decimal or hexadecimal notation, into a number. If S does not represent a valid number, [ToInteger]() raises an [EConvertError](/Libraries/Sydney/en/System.SysUtils.EConvertError) exception.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToInteger)

---

## `System.SysUtils.TStringHelper.ToLower`

```pascal
function ToLower: string; overload; inline;
function ToLower(LocaleID: TLocaleID): string; overload;
```

## Description



Transforms this 0-based string into an all lowercase characters 0-based string and returns it.



The LocaleID parameter of the second [ToLower]() overloaded method is of type [TLocaleID](/Libraries/Sydney/en/System.SysUtils.TLocaleID) and defines a choice of language and region identifiers. For more information, please refer to the [TLocaleID](/Libraries/Sydney/en/System.SysUtils.TLocaleID) topic.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToLower)

---

## `System.SysUtils.TStringHelper.ToLowerInvariant`

```pascal
function ToLowerInvariant: string; {$IF Defined(USE_LIBICU) and not Defined(Linux)}inline;{$ENDIF}
```

## Description



Transforms this 0-based string into an all-lowercase characters 0-based string and returns it. The conversion is done using the UTF-16 character representation, according to Unicode specification.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToLowerInvariant)

---

## `System.SysUtils.TStringHelper.ToSingle`

```pascal
class function ToSingle(const S: string): Single; overload; static; inline;
function ToSingle: Single; overload; inline;
```

## Description



Converts a given string to a floating-point value.



This method is overloaded.



Use [ToSingle]() to convert a string S, to a floating-point value. S must consist of an optional sign (+ or -), a string of digits with an optional decimal point, and an optional mantissa. The mantissa consists of 'E' or 'e' followed by an optional sign (+ or -) and a whole number. Leading and trailing blanks are ignored.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToSingle)

---

## `System.SysUtils.TStringHelper.ToUpper`

```pascal
function ToUpper: string; overload; inline;
function ToUpper(LocaleID: TLocaleID): string; overload;
```

## Description



Transforms this 0-based string into an all-uppercase characters 0-based string and returns it.



The LocaleID parameter of the second [ToUpper]() overloaded method is of type [TLocaleID](/Libraries/Sydney/en/System.SysUtils.TLocaleID) and defines a choice of language and region identifiers. For more information, please refer to the [TLocaleID](/Libraries/Sydney/en/System.SysUtils.TLocaleID) topic.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToUpper)

---

## `System.SysUtils.TStringHelper.ToUpperInvariant`

```pascal
function ToUpperInvariant: string; {$IF Defined(USE_LIBICU) and not Defined(Linux)}inline;{$ENDIF}
```

## Description



Transforms this zero-based string into an all-uppercase characters zero-based string and returns it. The conversion is done using the UTF-16 character representation, according to the Unicode specification.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToUpperInvariant)

---

## `System.SysUtils.TStringHelper.Trim`

```pascal
function Trim: string; overload;
function Trim(const TrimChars: array of Char): string; overload;
```

## Description



Trims leading and trailing spaces and control characters from this 0-based string.



There are two [Trim]() overloaded methods. The first one takes no parameters while the second one allows you to specify which characters (in the form of an array of characters) to trim from this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.Trim)

---

## `System.SysUtils.TStringHelper.TrimEnd`

```pascal
function TrimEnd(const TrimChars: array of Char): string; deprecated 'Use TrimRight';
```

## Description




**Warning:** [TrimEnd]() is deprecated. Please use [TrimRight](/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimRight). 





Trims the given trailing characters from this 0-based string.



The TrimChars parameter allows you specify which characters (in the form of an array of characters) to trim from the end of this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimEnd)

---

## `System.SysUtils.TStringHelper.TrimLeft`

```pascal
function TrimLeft: string; overload;
function TrimLeft(const TrimChars: array of Char): string; overload;
```

## Description



Trims the given leading characters from this 0-based string.



This method is overloaded.



The TrimChars parameter allows you to specify which characters (in the form of an array of characters) to trim from the start of this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimLeft)

---

## `System.SysUtils.TStringHelper.TrimRight`

```pascal
function TrimRight: string; overload;
function TrimRight(const TrimChars: array of Char): string; overload;
```

## Description



Trims the given trailing characters from a 0-based string.



This method is overloaded.



The TrimChars parameter allows you to specify the characters (in the form of an array of characters) to trim from the end of a 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimRight)

---

## `System.SysUtils.TStringHelper.TrimStart`

```pascal
function TrimStart(const TrimChars: array of Char): string; deprecated 'Use TrimLeft';
```

## Description




**Warning:** [TrimStart]() is deprecated. Please use [TrimLeft](/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimLeft). 





Trims the given leading characters from this 0-based string.



The TrimChars parameter allows you to specify which characters (in the form of an array of characters) to trim from the start of this 0-based string.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.TrimStart)

---

## `System.SysUtils.TStringHelper.UpperCase`

```pascal
class function UpperCase(const S: string): string; overload; static; inline;
class function UpperCase(const S: string; LocaleOptions: TLocaleOptions): string; overload; static; inline;
```

## Description



Converts an ASCII string to uppercase.



[UpperCase]() returns a string with the same text as the string passed in S, but with all letters converted to uppercase. The conversion affects only 7-bit ASCII characters between 'a' and 'z'. To convert 8-bit international characters, use [ToUpper](/Libraries/Sydney/en/System.SysUtils.TStringHelper.ToUpper).



The LocaleOptions parameter of the second [UpperCase]() overloaded method is of type [TLocaleOptions](/Libraries/Sydney/en/System.SysUtils.TLocaleOptions) and defines a choice of dependent and independent locale options. For more information, please refer to the [TLocaleOptions](/Libraries/Sydney/en/System.SysUtils.TLocaleOptions) topic.





[View on DocWiki](https://docwiki.embarcadero.com/Libraries/Sydney/en/System.SysUtils.TStringHelper.UpperCase)

---

