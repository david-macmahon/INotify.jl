module INotify

using FileWatching

export inotify_open
export inotify_close
export inotify_add_watch
export inotify_rm_watch
export inotify_read_events

include("event.jl")

function inotify_open()
    fd = @ccall inotify_init1(O_NONBLOCK::Cint)::Cint
    fd != -1 || systemerror("inotify_init1")
    RawFD(fd)
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
    rc = @ccall close(fd::Cint)::Cint
    rc == 0 || systemerror("close")
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

function inotify_read_events(f::Function, fd, buf=Array{UInt8}(undef, 4096); loopwhile=()->true)
    while true
        wait(fd, readable=true)
        len = @ccall read(fd::Cint, buf::Ptr{Cvoid}, sizeof(buf)::Csize_t)::Cint
        if len == -1 && Libc.errno() != Libc.EAGAIN
            systemerror("inotify")
        end

        # Pointer to event struct(s) in buf
        pev = Ptr{Event}(pointer(buf))
        # Pointer just past end of returned data
        # Pointer arithmatic is always byte-wise in Julia!
        pend = pev + len
        while pev < pend
            ev = unsafe_load(pev)
            name = ev.len > 0 ? unsafe_string(Ptr{UInt8}(pev)+sizeof(Event)) : ""

            f(ev, name)

            # Step pev past current event (and name, if any)
            # Pointer arithmatic is always byte-wise in Julia!
            pev += sizeof(Event) + ev.len
        end

        # Break out of loop if loopwhile() returns false
        loopwhile() || break
    end
end

function inotify_read_events(fd, buf=Array{UInt8}(undef, 4096))
    # Vector for returned (event, name) tuples
    events = Tuple{Event,String}[]

    # Call inotify_read_events with looping disabled so it will only perform one
    # read (which may return multiple events).
    inotify_read_events(fd, buf, loopwhile=()->false) do ev, name
        push!(events, (ev, name))
    end

    return events
end

end # module INotify
