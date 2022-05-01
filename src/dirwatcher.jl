struct DirWatcher
    fd::RawFD
    mask::UInt32
    watches::Dict{Int32, String}
    run::Ref{Bool}
    task::Ref{Task}

    function DirWatcher(f::Function, dir, mask=ALL_EVENTS; kwargs...)
        # Have to watch for CREATE to watch new subdirs
        mask |= CREATE

        fd = inotify_open()

        watches = Dict{Int32, String}()
        for (root, dirs, files) in walkdir(dir, topdown=false)
            @debug "adding watch for $root mask $mask"
            wd = inotify_add_watch(fd, root, mask)
            watches[wd] = root
        end

        run = Ref(true)

        dirwatcher = new(fd, mask, watches, run, Ref{Task}())
        dirwatcher.task[] = @async begin
            @debug "watcher task for $fd starting"
            disable_sigint() do
                watch_dir_loop($f, $dirwatcher; $kwargs...)
            end
            @debug "watcher task for $fd ending"
        end

        dirwatcher
    end
end

const DirEventNameTuple = NamedTuple{(:dir, :event, :name),
                               Tuple{AbstractString, INotify.Event, AbstractString}}

function DirWatcher(channel::AbstractChannel, dir, mask=ALL_EVENTS)
    DirWatcher((den)->put!(channel, den), dir, mask)
end

function watch_dir_loop(f::Function, dirwatcher::DirWatcher; kwargs...)
    buf=Array{UInt8}(undef, 4096)
    while dirwatcher.run[]
        @debug "watch_dir_loop for $fd calling inotify_read_events"
        inotify_read_events(dirwatcher.fd, buf) do (ev, name)
            dir = get(dirwatcher.watches, ev.wd, nothing)

            # When a subdir is created in a watched directory, we have to call
            # inotify_add_watch to add a new watch to the new subdir.  We use
            # the new watch descriptor to store the subdir name in
            # `dirwatcher.watches`.
            if iscreatedir(ev)
                subdir = joinpath(dir, name)
                @debug "watch_dir_loop calling inotify_add_watch" dirwatcher.fd subdir dirwatcher.mask
                wd = inotify_add_watch(dirwatcher.fd, subdir, dirwatcher.mask)
                dirwatcher.watches[wd] = subdir
            end

            @debug "calling DirWatcher client function"
            f((dir=dir, event=ev, name=name); kwargs...)
            @debug "back from DirWatcher client function"

            # When a subdir is deleted, we do not have to call inotify_rm_watch
            # in response to DELETE_SELF because the watch is automatically
            # removed.  The automatic removal of the watch results in an IGNORED
            # event, which we use to delete the old watch descriptor from
            # `dirwatcher.watches`.
            isignored(ev) && delete!(dirwatcher.watches, ev.wd)
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
