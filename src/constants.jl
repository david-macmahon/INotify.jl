# Constants compatible with those defined in inotify.h (on Ubuntu 16.04)

# the following are legal, implemented events that user-space can watch for
const ACCESS         = 0x00000001  # File was accessed
const MODIFY         = 0x00000002  # File was modified
const ATTRIB         = 0x00000004  # Metadata changed
const CLOSE_WRITE    = 0x00000008  # Writtable file was closed
const CLOSE_NOWRITE  = 0x00000010  # Unwrittable file closed
const OPEN           = 0x00000020  # File was opened
const MOVED_FROM     = 0x00000040  # File was moved from X
const MOVED_TO       = 0x00000080  # File was moved to Y
const CREATE         = 0x00000100  # Subfile was created
const DELETE         = 0x00000200  # Subfile was deleted
const DELETE_SELF    = 0x00000400  # Self was deleted
const MOVE_SELF      = 0x00000800  # Self was moved

# the following are legal events.  they are sent as needed to any watch
const UNMOUNT        = 0x00002000  # Backing fs was unmounted
const Q_OVERFLOW     = 0x00004000  # Event queued overflowed
const IGNORED        = 0x00008000  # File was ignored

# helper events
const CLOSE = (CLOSE_WRITE | CLOSE_NOWRITE) # close
const MOVE  = (MOVED_FROM | MOVED_TO)       # moves

# special flags
const ONLYDIR        = 0x01000000  # only watch the path if it is a directory
const DONT_FOLLOW    = 0x02000000  # don't follow a sym link
const EXCL_UNLINK    = 0x04000000  # exclude events on unlinked objects
const MASK_ADD       = 0x20000000  # add to the mask of an already existing watch
const ISDIR          = 0x40000000  # event occurred against dir
const ONESHOT        = 0x80000000  # only send event once

# INotify special flag
const CREATE_DIR = (CREATE | ISDIR)

# All of the events - we build the list by hand so that we can add flags in
# the future and not break backward compatibility.  Apps will get only the
# events that they originally wanted.  Be sure to add new events here!

const ALL_EVENTS = (
        ACCESS | MODIFY | ATTRIB | CLOSE_WRITE | CLOSE_NOWRITE | OPEN |
        MOVED_FROM | MOVED_TO | DELETE | CREATE | DELETE_SELF | MOVE_SELF
    )

const O_NONBLOCK = 0o4000
