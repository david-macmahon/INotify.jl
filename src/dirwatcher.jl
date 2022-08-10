struct DirWatcher
    fd::RawFD
    mask::UInt32
    watches::Dict{Int32, String} # watch_descriptor=>name
    dirs::Dict{String, Int32} # absdirname=>watch_descritor
    run::Ref{Bool}
    task::Ref{Task}

    function DirWatcher(f::Function, dir, mask=ALL_EVENTS; kwargs...)
        # Have to watch for CREATE to watch new subdirs
        mask |= CREATE

        fd = inotify_open()

        watches = Dict{Int32, String}()
        dirs = Dict{String, Int32}()
        run = Ref(true)

        dirwatcher = new(fd, mask, watches, dirs, run, Ref{Task}())

        # Use add_watch() to add dir and all subdirs recursively
        add_watch(f, dirwatcher, dir; kwargs...)

        dirwatcher.task[] = @async begin
            @info "watcher task for $fd starting"
            try
                watch_dir_loop($f, $dirwatcher; $kwargs...)
            catch ex
                @error "async DirWatcher task caught exception" ex
                if !(ex isa InterruptException)
                    for (exc, bt) in Base.catch_stack()
                        showerror(stderr, exc, bt)
                        println(stderr)
                    end
                end
            finally
                @info "watcher task for $fd ending"
            end
        end

        dirwatcher
    end
end

const DirEventNameTuple = NamedTuple{(:dir, :event, :name),
                               Tuple{AbstractString, INotify.Event, AbstractString}}

function DirWatcher(channel::AbstractChannel, dir, mask=ALL_EVENTS)
    DirWatcher((den)->put!(channel, den), dir, mask)
end

"""
    add_watch(f, dirwatcher::DirWatcher, dir::AbstractString; kwargs...)
Add an `inotify` watch on `dir` to `dirwatcher`.  `f` is passed a
`DirEventNameTuple` for `dir` and every file and subdir that exists in/under
`dir` after the watch is added.  The `event` field of the passed
`DirEventNameTuple` instances will be `CREATE_DIR` for directories and `CREATE`
for files.
"""
function add_watch(f, dirwatcher::DirWatcher, dir::AbstractString; kwargs...)
    @debug "add_watch" dirwatcher.fd dir

    # If we are already watching subdir then return
    haskey(dirwatcher.dirs, dir) && return

    # Call inotify_add_watch for this dirwatcher and dir
    @debug "add_watch calling inotify_add_watch" dirwatcher.fd dir dirwatcher.mask
    wd = inotify_add_watch(dirwatcher.fd, dir, dirwatcher.mask)
    dirwatcher.watches[wd] = dir
    dirwatcher.dirs[dir] = wd

    @debug "calling DirWatcher client function" dir
    f((dir=dirname(dir), event=CREATE_DIR, name=basename(dir)); kwargs...)
    @debug "back from DirWatcher client function"

    # Now that we've called inotify_add_watch, handle existing content (either
    # pre-existing or newly created but prior to adding the watch)

    # Call client function for all files in `dir`
    for file in readdir(dir; join=true)
        isfile(file) || continue
        @debug "calling DirWatcher client function" file
        f((dir=dirname(file), event=CREATE, name=basename(file)); kwargs...)
        @debug "back from DirWatcher client function"
    end

    # walk dir and add call add_watch recursively for all encountered
    # directories.
    for (subdir, _, _) in walkdir(dir)
        subdir == dir && continue
        haskey(dirwatcher.dirs, subdir) || add_watch(f, dirwatcher, subdir; kwargs...)
    end
end

function watch_dir_loop(f::Function, dirwatcher::DirWatcher; kwargs...)
    buf=Array{UInt8}(undef, 4096)
    while dirwatcher.run[]
        @debug "watch_dir_loop for $fd calling inotify_read_events"
        inotify_read_events(dirwatcher.fd, buf) do (ev, name)
            # Find directory corresponding to this event
            dir = get(dirwatcher.watches, ev.wd, nothing)

            # When a subdir is created in a watched directory, we have to call
            # inotify_add_watch to add a new watch to the new subdir.  We use
            # the new watch descriptor to store the subdir name in
            # `dirwatcher.watches`.
            if iscreatedir(ev)
                # Add watch for new dir to dirwatcher
                subdir = joinpath(dir, name)
                haskey(dirwatcher.dirs, subdir) || add_watch(f, dirwatcher, subdir; kwargs...)
            else # otherwise just call `f`
                @debug "calling DirWatcher client function"
                f((dir=dir, event=ev, name=name); kwargs...)
                @debug "back from DirWatcher client function"
            end

            # When a subdir is deleted, we do not have to call inotify_rm_watch
            # in response to DELETE_SELF because the watch is automatically
            # removed.  The automatic removal of the watch results in an IGNORED
            # event, which we use to delete the old watch descriptor from
            # `dirwatcher.watches`.
            if isignored(ev) && haskey(dirwatcher.watches, ev.wd)
                # Delete dirwatcher.dirs entry
                delete!(dirwatcher.dirs, dir)
                delete!(dirwatcher.watches, ev.wd)
            end
        end
        @debug "watch_dir_loop for $fd back from inotify_read_events"
    end
    @debug "watch_dir_loop for $fd ending"
end

function Base.close(dirwatcher::DirWatcher)
    dirwatcher.run[] = false
    inotify_notify(dirwatcher.fd)
    wait(dirwatcher.task[])
    inotify_close(dirwatcher.fd)
end
