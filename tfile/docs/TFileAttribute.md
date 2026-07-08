
### Description

Enumerates the possible file and directory attributes.

TFileAttribute enumerates the possible file and directory attributes. The TFileAttribute enumeration is used in file operation routines, which modify, read, or remove attributes from a file or directory.

> Note: There are different file attributes depending on the platform.

**On Windows**, the possible values of TFileAttribute are:  
| Value            | Meaning |
|------------------|---------|
| faReadOnly       | Identifies read-only files or directories. |
| faHidden         | Identifies hidden files or directories. |
| faSystem         | Identifies system files or directories. |
| faDirectory      | Identifies a directory. |
| faArchive        | Identifies Windows archived files. |
| faDevice         | Identifies Windows device files. |
| faNormal         | Identifies normal files. |
| faTemporary      | Identifies temporary files or directories. |
| faSparseFile     | Identifies a sparse file. A sparse file is a large file filled mostly with zeros. |
| faReparsePoint   | Identifies a reparse point. A reparse point is a block of user-defined data linked to a real file or directory. |
| faCompressed     | Identifies a compressed file or directory. |
| faOffline        | Identifies an offline file whose contents are unavailable. |
| faNotContentIndexed | Identifies a file that is skipped from the indexing operations. |
| faEncrypted      | Identifies an encrypted file or directory. |
| faSymLink        | Identifies a symbolic link. |

**On POSIX**, the possible values of TFileAttribute are:  
| Value              | Meaning |
|---------------------|---------|
| faNamedPipe         | Identifies a named pipe (FIFO). A named pipe can be used, for example, to transfer information from one process to another. |
| faCharacterDevice   | Identifies a character device, which is a file descriptor that offers a flow of data that must be read in order. An example of a character device is a terminal where the next character is read after a key is pressed. |
| faDirectory         | Identifies a directory. |
| faBlockDevice       | Identifies a block device. The difference between a block device and a character device is that block devices have a buffer for requests, so they can choose by which order to respond to them. |
| faNormal            | Identifies normal files. |
| faSymLink           | Identifies a symbolic link, which is a file descriptor that contains a reference to another file or directory in the form of an absolute or relative path. |
| faSocket            | Identifies a socket. |
| faWhiteout          | Identifies a whiteout file (you cannot perform any operations on it, because it does not exist.) |
| faOwnerRead         | Owner can read the file descriptor. |
| faOwnerWrite        | Owner can write the file descriptor. |
| faOwnerExecute      | Owner can execute the file descriptor. |
| faGroupRead         | All users within a group can read the file descriptor. |
| faGroupWrite        | All users within a group can write the file descriptor. |
| faGroupExecute      | All users within a group can execute the file descriptor. |
| faOthersRead        | Other users than the owner can read the file descriptor. |
| faOthersWrite       | Other users than the owner can write the file descriptor. |
| faOthersExecute     | Other users than the owner can execute the file descriptor. |
| faUserIDExecution   | User ID during execution; sometimes it may be elevated for execution. |
| faGroupIDExecution  | Group ID during execution; sometimes it may be elevated for execution. |
| faStickyBit         | Prevents any process other than the owner to delete the file. |

> Note: A symbolic link represents a reference to another file or directory in the form of an absolute or relative path.

Retrieved from “https://docwiki.embarcadero.com/Libraries/Athens/e/index.php?title=System.IOUtils.TFileAttribute&oldid=624781”  
