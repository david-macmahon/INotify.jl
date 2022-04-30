# INotify

A Julia interface to the Linux `inotify` API.

# Why

Julia includes a FileWatching package in its standard library which provides
platform independent access to some of the same functionality that the Linux
`inotify` API provides.  If that meets your needs then you should use so that
your code will be able to run on as many platforms as possible.  If that doesn't
meet your needs and you are running on Linux, the `INotify` package might be a
better fit.

# How to use it

`INotify` includes low level functionality and high level functionality.  The
low level functionality closely parallels the Linux `inotify` API.  The high
level functionality is a more convenient interface for recursively watching a
directory tree for file events.

## High level interface

The high level interface is primarily through the `INotify.DirWatcher`
structure.  Creating a `DirWatcher` structure also creates an asynchronous Task
that waits for inotify events and then either passes them to a user supplied
function or `put!`s them into a user supplied `Channel`.  The other parameters
required to create a DirWatcher structure are the name of the directory to watch
and a bit mask that specifies which events should be watched for.  See
`src/constants.jl` for a complete list of events.  Multiple event types may be
specified by bitwise OR'ing their constants together.  If the event mask is not
given, `DirWatcher` will watch for all events.

When a file system event occurs, a named tuple will be passed to the user
supplied function or `put!` on the user supplied `Channel`.  The named tuple has
these fields:

- `dir` Name of the directory in which the event occured
- `event` `INotify.Event` structure for the event
- `name` Name associated with the event

The `INotify.Event` structure contains these fields:

- `wd` The inotify watch descriptor for this event
- `mask` Bitmask indicating type/features of this event
- `cookie` Number to match up certain types of events
- `len` Length of the name associated with this event

Generally, the `mask` field will be the most useful.

`DirWatcher` will automatically add watches for newly created directories.  It
is possible for file events to occur in the new directory before the watch gets
added.  This race condition in inherent in the underlying inotify system.  See
`man inotify` for on your Linux system for more information.

For use with a `Channel`, one can use the generic `Channel{Any}` that can hold any
type or the more type specific `Channel{Inotify.DirEventNameTuple}` type that
holds the specific type of named tuple used by DirWatcher.

The `DirWatcher` instance can be passed to `close()` to stop watching and to end
the asynchronous Task.

### Example

```julia
julia> using INotify

julia> chan = Channel{INotify.DirEventNameTuple}(100);

julia> dir = mktempdir();

julia> dw = INotify.DirWatcher(chan, dir);

julia> isready(chan)
false

julia> touch(joinpath(dir, "foo"));

julia> isready(chan)
true

julia> while isready(chan)
       dir, event, name = take!(chan)
       @show dir, event, name
       end
(dir, event, name) = ("/tmp/jl_YURiqm", Event(wd=2, mask=CREATE, cookie=0), "foo")
(dir, event, name) = ("/tmp/jl_YURiqm", Event(wd=2, mask=OPEN, cookie=0), "foo")
(dir, event, name) = ("/tmp/jl_YURiqm", Event(wd=2, mask=ATTRIB, cookie=0), "foo")
(dir, event, name) = ("/tmp/jl_YURiqm", Event(wd=2, mask=CLOSE_WRITE, cookie=0), "foo")

julia> close(dw) # Stop watching and end the async Task
```

# TODO

Add more documentation and tests.
