using INotify
using Test

@testset "INotify.jl" begin
    mktempdir() do dir
        inotify_open() do inotify
            wd = inotify_add_watch(inotify, dir, INotify.CREATE|INotify.DELETE)
            fname = joinpath(dir, "foo")
            open(fname, "w") do f
                print(f, "hello, world")
            end

            evs = inotify_read_events(inotify)
            @test length(evs) == 1

            ev, name = evs[1]
            @test ev.mask == INotify.CREATE
            @test name == "foo"
            @show ev

            rm(fname)

            evs = inotify_read_events(inotify)
            @test length(evs) == 1

            ev, name = evs[1]
            @test ev.mask == INotify.DELETE
            @test name == "foo"
            @show ev

            @test inotify_rm_watch(inotify, wd) === nothing
        end
    end
end
