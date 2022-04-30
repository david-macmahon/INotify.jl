module INotify

using FileWatching

export inotify_open
export inotify_close
export inotify_add_watch
export inotify_rm_watch
export inotify_read_events
export inotify_notify

include("event.jl")

# Every inotify instance has a unique "sentinal file" created for it and an OPEN
# watch is created on this sentinal file.  Events can be generated on any
# inotify instance, for example by passing its sentinal file to `touch()`.

# SENTINALS is a Dict mapping inotify instances (RawFD) to named tuples
# containing `path` and `wd` fields.
const SENTINALS = Dict{RawFD, NamedTuple{(:path, :wd), Tuple{String, Int64}}}()

function inotify_open()
    fd = @ccall inotify_init1(O_NONBLOCK::Cint)::Cint
    fd != -1 || systemerror("inotify_init1")
    inotify = RawFD(fd)

    # Create sentinal file for this inotify instance
    path, io = mktemp()
    close(io)

    # Create "OPEN" watch on the sentinal file
    wd = inotify_add_watch(inotify, path, OPEN)
    SENTINALS[inotify] = (path=path, wd=wd)

    inotify
end

function inotify_open(pathname, mask)
    fd = inotify_open()
    fd, inotify_add_watch(fd, pathname, mask)
end

function inotify_open(f::Function)
    fd = inotify_open()
    local retval
    try
        retval = f(fd)
    finally
        inotify_close(fd)
    end
    retval
end

function inotify_open(f::Function, pathname, mask)
    fd, wd = inotify_open(pathname, mask)
    local retval
    try
        retval = f(fd, wd)
    finally
        inotify_rm_watch(fd, wd)
        inotify_close(fd)
    end
    retval
end

function inotify_close(fd)
    if haskey(SENTINALS, fd)
        wd = SENTINALS[fd].wd
        delete!(SENTINALS, fd)
        try
            # Unwatch the sentinal
            inotify_rm_watch(fd, wd)
        finally
            rc = @ccall close(fd::Cint)::Cint
            rc == 0 || systemerror("close")
        end
    end
    nothing
end

function inotify_add_watch(fd, pathname, mask)
    wd = @ccall inotify_add_watch(fd::Cint, pathname::Cstring, mask::Cuint)::Cint
    wd != -1 || systemerror("inotify_add_watch")
    wd
end

function inotify_rm_watch(fd, wd)
    rc = @ccall inotify_rm_watch(fd::Cint, wd::Cint)::Cint
    rc == 0 || systemerror("inotify_rm_watch")
    nothing
end

function inotify_read_events(f::Function, fd, buf=Array{UInt8}(undef, 4096))
    wait(fd, readable=true)
    nbytes = @ccall read(fd::Cint, buf::Ptr{Cvoid}, sizeof(buf)::Csize_t)::Cint
    if nbytes == -1 && Libc.errno() != Libc.EAGAIN
        systemerror("inotify")
    end

    # Pointer to event struct(s) in buf
    pev = Ptr{Event}(pointer(buf))
    # Pointer just past end of returned data
    # Pointer arithmatic is always byte-wise in Julia!
    pend = pev + nbytes
    while pev < pend
        ev = unsafe_load(pev)
        name = ev.len > 0 ? unsafe_string(Ptr{UInt8}(pev)+sizeof(Event)) : ""

        # Ignore events on the sentinal watch
        if ev.wd != SENTINALS[fd].wd
            f(ev, name)
        end

        # Step pev past current event (and name, if any)
        # Pointer arithmatic is always byte-wise in Julia!
        pev += sizeof(Event) + ev.len
    end
end

function inotify_read_events(fd, buf=Array{UInt8}(undef, 4096))
    # Vector for returned (event, name) tuples
    events = Tuple{Event,String}[]

    inotify_read_events(fd, buf) do ev, name
        push!(events, (ev, name))
    end

    return events
end

# Generate an event on `inotify`'s sentinal file.  This will unblock tasks that
# are blocking on `inotify` in inotify_read_events().
function inotify_notify(inotify)
    open(close, SENTINALS[inotify].path)
end

# Generate an event on all sentinal file.  This will unblock tasks that are
# blocking on any inotify instance in inotify_read_events().
function inotify_notify()
    for v in values(SENTINALS)
        open(close, v.path)
    end
end

end # module INotify
