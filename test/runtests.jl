using INotify
using Test

@testset "inotify" begin
    mktempdir() do dir
        inotify_open() do inotify
            # Add watch
            wd = inotify_add_watch(inotify, dir, INotify.CREATE|INotify.DELETE)

            # Add two levels of subdirectories
            subdirpath = joinpath(dir, "subdir1", "subdir2")
            mkpath(subdirpath)

            # Read inotify events
            evs = inotify_read_events(inotify)
            @test_broken length(evs) == 2

            # Validate events
            for (i, (ev, name)) in enumerate(evs)
                @debug "got event" ev
                @test ev.mask == INotify.CREATE_DIR
                @test name == "subdir$i"
            end

            # Add file
            fname = joinpath(dir, "foo")
            open(fname, "w") do f
                print(f, "hello, world")
            end

            # Read inotify events
            evs = inotify_read_events(inotify)
            @test length(evs) == 1

            # Validate event
            ev, name = evs[1]
            @debug "got event" ev
            @test ev.mask == INotify.CREATE
            @test name == "foo"

            # Remove file
            rm(fname)

            # Read inotify events
            evs = inotify_read_events(inotify)
            @test length(evs) == 1

            # Validate event
            ev, name = evs[1]
            @debug "got event" ev
            @test ev.mask == INotify.DELETE
            @test name == "foo"

        end # inotify_open
    end # mktempdir
end # testset inotify

@testset "dirwatcher" begin
    mktempdir() do dir

        evcount = Ref{Int}(0)

        function incr(den; evc)
            @debug "in incr" den evc
            evc[] += 1
        end

        # Create DirWatcher for `dir`
        dw = INotify.DirWatcher(incr, dir, INotify.CREATE|INotify.DELETE; evc=evcount)

        # Add two levels of subdirectories
        subdirpath = joinpath(dir, "subdir1", "subdir2")
        mkpath(subdirpath)

        # Verify that event counter got three events
        sleep(2.0) # Give dw some time to work (a bit longer due to compilation)
        @test evcount[] == 3

        # Verify that dw is watching all three directories
        expected = [dir, joinpath(dir, "subdir1"), joinpath(dir, "subdir1/subdir2")]
        @test sort(collect(values(dw.watches))) == expected
        @test sort(collect(keys(dw.dirs))) == expected

        # Reset evcount
        evcount[] = 0

        # Add file
        fname = joinpath(dir, "subdir1/subdir2/foo")
        open(fname, "w") do f
            print(f, "hello, world")
        end

        # Verify that event counter got 1 event
        sleep(0.1) # Give dw some time to work
        @test evcount[] == 1

        # Reset evcount
        evcount[] = 0

        # Remove subdir1 recursively
        rm(joinpath(dir, "subdir1"), recursive=true)

        # Verify that event counter got 5 events (3 DELETEs + 2 IGNOREDs)
        sleep(0.1) # Give dw some time to work
        @test evcount[] == 5

        close(dw)

    end # mktempdir
end # testset dirwatcher
