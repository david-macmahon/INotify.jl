module INotify

export inotify_open
export inotify_close
export inotify_add_watch
export inotify_rm_watch
export inotify_read_events

include("event.jl")

function inotify_open()
    @ccall inotify_init()::Cint
end

function inotify_open(pathname, mask)
    inotify = inotify_open()
    inotify, inotify_add_watch(inotify, pathname, mask)
end

function inotify_open(f::Function)
    inotify = inotify_open()
    local retval
    try
        retval = f(inotify)
    finally
        inotify_close(inotify)
    end
    retval
end

function inotify_open(f::Function, pathname, mask)
    inotify, wd = inotify_open(pathname, mask)
    local retval
    try
        retval = f(inotify, wd)
    finally
        inotify_rm_watch(inotify, wd)
        inotify_close(inotify)
    end
    retval
end

function inotify_close(inotify)
    rc = @ccall close(inotify::Cint)::Cint
    rc == 0 || systemerror("close")
    nothing
end

function inotify_add_watch(inotify, pathname, mask)
    wd = @ccall inotify_add_watch(inotify::Cint, pathname::Cstring, mask::Cuint)::Cint
    wd != -1 || systemerror("inotify_add_watch")
    wd
end

function inotify_rm_watch(inotify, wd)
    rc = @ccall inotify_rm_watch(inotify::Cint, wd::Cint)::Cint
    rc == 0 || systemerror("inotify_rm_watch")
    nothing
end

function inotify_read_events(f::Function, inotify, buf=Array{UInt8}(undef, 4096); loopwhile=()->true)
    while true
        len = @ccall read(inotify::Cint, buf::Ptr{Cvoid}, sizeof(buf)::Csize_t)::Cint
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

function inotify_read_events(inotify, buf=Array{UInt8}(undef, 4096))
    # Vector for returned (event, name) tuples
    events = Tuple{Event,String}[]

    # Call inotify with looping disabled so it will only perform one read (which
    # may return multiple events).
    inotify_read_events(inotify, buf, loopwhile=()->false) do ev, name
        push!(events, (ev, name))
    end

    return events
end

end # module INotify
