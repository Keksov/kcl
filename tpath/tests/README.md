# TPath Test Suite

Comprehensive test suite for the TPath class implementation, covering all path manipulation and analysis methods.

## Test Files

The test suite consists of the following test files:

### Path Manipulation Tests
- **001_combine_paths.sh** - Tests for `TPath.combine()` method
  - Path combination with separators
  - Handling absolute/relative paths
  - Empty path handling
  
- **002_change_extension.sh** - Tests for `TPath.changeExtension()` method
  - Adding extensions
  - Changing existing extensions
  - Removing extensions
  - Multiple dot handling

- **003_get_directory_name.sh** - Tests for `TPath.getDirectoryName()` method
  - Extracting directory paths
  - Handling trailing separators
  - Root and relative paths

- **004_get_extension.sh** - Tests for `TPath.getExtension()` method
  - Extracting file extensions
  - Multiple dots in filenames
  - Files without extensions

- **005_get_filename.sh** - Tests for filename extraction methods
  - `TPath.getFileName()` - Extract filename with extension
  - `TPath.getFileNameWithoutExtension()` - Extract filename without extension

### Path Analysis Tests
- **006_path_analysis.sh** - Tests for path analysis methods
  - `TPath.hasExtension()` - Check if path has extension
  - `TPath.isPathRooted()` - Check if path is absolute
  - `TPath.isRelativePath()` - Check if path is relative
  - `TPath.isUNCPath()` - Check for UNC paths
  - `TPath.isDriveRooted()` - Check for Windows drive paths
  - `TPath.isExtendedPrefixed()` - Check for extended prefix

- **007_get_path_root.sh** - Tests for `TPath.getPathRoot()` method
  - Unix root paths
  - Windows drive paths
  - UNC paths
  - Relative paths

- **009_get_full_path.sh** - Tests for `TPath.getFullPath()` method
  - Converting relative to absolute paths
  - Handling current directory
  - Already absolute paths

### System Path Tests
- **008_system_paths.sh** - Tests for system path methods
  - `TPath.getTempPath()` - Get temp directory
  - `TPath.getHomePath()` - Get home directory
  - `TPath.getDocumentsPath()` - Get documents directory
  - `TPath.getDownloadsPath()` - Get downloads directory
  - `TPath.getTempFileName()` - Generate temp file
  - `TPath.getGUIDFileName()` - Generate GUID filename
  - `TPath.getRandomFileName()` - Generate random filename

### Properties Tests
- **010_properties.sh** - Tests for platform-specific constants
  - `TPath.getAltDirectorySeparatorChar()` - Get alternate directory separator
  - `TPath.getDirectorySeparatorChar()` - Get primary directory separator
  - `TPath.getExtensionSeparatorChar()` - Get extension separator
  - `TPath.getPathSeparator()` - Get path separator
  - `TPath.getVolumeSeparatorChar()` - Get volume separator

### Additional Method Tests
- **011_drive_exists.sh** - Tests for `TPath.driveExists()` method
  - Platform-specific drive checking
  - Invalid drive handling

- **012_get_attributes.sh** - Tests for `TPath.getAttributes()` method
  - File attribute detection
  - Directory vs file attributes
  - Read-only and hidden file detection

- **013_valid_chars.sh** - Tests for character validation methods
  - `TPath.hasValidFileNameChars()` - Filename character validation
  - `TPath.hasValidPathChars()` - Path character validation
  - `TPath.isValidFileNameChar()` - Single filename character validation
  - `TPath.isValidPathChar()` - Single path character validation

- **014_matches_pattern.sh** - Tests for `TPath.matchesPattern()` method
  - Pattern matching with wildcards
  - Case-sensitive and case-insensitive matching
  - Complex pattern support

## Running Tests

### Run All Tests

Run all tests with default settings (error verbosity, threaded mode with 8 workers):

```bash
bash kcl/tests/test_tpath.sh
```

### Run with Verbose Output

Run tests with detailed output:

```bash
bash kcl/tests/test_tpath.sh --verbosity info
# or
bash kcl/tests/test_tpath.sh -v info
```

### Run Specific Tests

Run specific test files by number:

```bash
# Run a single test
bash kcl/tests/test_tpath.sh -n 1

# Run multiple tests
bash kcl/tests/test_tpath.sh -n 1,3,5

# Run a range of tests
bash kcl/tests/test_tpath.sh -n 1-5

# Combine ranges and individual tests
bash kcl/tests/test_tpath.sh -n 1-3,5,7-9
```

### Execution Modes

#### Threaded Mode (Default)
Run tests in parallel using multiple workers:

```bash
bash kcl/tests/test_tpath.sh -m threaded -w 8
```

#### Single Mode
Run tests sequentially:

```bash
bash kcl/tests/test_tpath.sh -m single
```

### Command Line Options

```
-v, --verbosity [info|error]  Set verbosity level (default: error)
-n, --tests SELECTION         Run specific tests (e.g., 1, 1-3, 1,3,5-7)
-m, --mode [threaded|single]  Execution mode (default: threaded)
-w WORKERS                    Number of workers for threaded mode (default: 8)
```

## Examples

```bash
# Run all tests with verbose output
bash kcl/tests/test_tpath.sh -v info

# Run tests 1-5 in single mode
bash kcl/tests/test_tpath.sh -n 1-5 -m single

# Run specific tests with 4 workers
bash kcl/tests/test_tpath.sh -n 1,3,6 -w 4

# Quick test run with minimal output
bash kcl/tests/test_tpath.sh -v error
```

## Test Structure

Each test file follows this structure:

1. **Initialization**: Source `common.sh` and parse arguments
2. **Test Cases**: Multiple test cases using helper functions:
   - `test_start(description)` - Start a new test
   - `test_pass(description)` - Mark test as passed
   - `test_fail(description)` - Mark test as failed
3. **Output**: Test counters exported via `__COUNTS__` format

## Test Result Format

When running in error verbosity mode, only failed tests and summary are shown:
```
[FAIL] Test description (expected: X, got: Y)
Total tests: N
Passed: M
Failed: K
```

When running in info verbosity mode, all test progress is shown:
```
[TEST] Test description
[PASS] Test description
...
Total tests: N
Passed: M
Failed: K
✓ All tests passed!
```

## Adding New Tests

To add new test files:

1. Create a new file following the naming pattern: `NNN_test_name.sh`
2. Use the template:

```bash
#!/bin/bash
# NNN_test_name.sh - Test description

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Your tests here using test_start, test_pass, test_fail
```

3. The test runner will automatically detect and run new tests

## Requirements

- Bash 4.0+
- TPath implementation (`kcl/tpath/tpath.sh`)
- kklass system (`kklass/kklass.sh`)

## Notes

- Tests are isolated and run in separate bash instances
- Temporary files are automatically cleaned up
- Test counters are aggregated across all test files
- Failed tests always show output regardless of verbosity setting