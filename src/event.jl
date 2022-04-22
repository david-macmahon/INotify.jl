include("constants.jl")

struct Event
    wd::Int32
    mask::UInt32
    cookie::UInt32
    len::UInt32
end

FUNCFLAGS = (
    (:isaccess,       :ACCESS),
    (:ismodify,       :MODIFY),
    (:isattrib,       :ATTRIB),
    (:isclosewrite,   :CLOSE_WRITE),
    (:isclosenowrite, :CLOSE_NOWRITE),
    (:isclose,        :CLOSE),
    (:isopen,         :OPEN),
    (:ismovedfrom,    :MOVED_FROM),
    (:ismovedto,      :MOVED_TO),
    (:ismove,         :MOVE),
    (:iscreate,       :CREATE),
    (:isdelete,       :DELETE),
    (:isdeleteself,   :DELETE_SELF),
    (:ismoveself,     :MOVE_SELF),
    (:isdirevent,     :ISDIR)
)

for (m,c) in FUNCFLAGS
    @eval $m(ev) = ev.mask & $c != 0
end

function Base.show(io::IO, ev::Event)
    flags = filter(FUNCFLAGS) do (_,c)
        c != :CLOSE && c != :MOVE && ev.mask & getproperty(INotify, c) != 0
    end
    print(io, "Event(wd=", ev.wd, ", mask=")

    if isempty(flags)
        print(io, "0")
    else
        print(io, join((f[2] for f in flags), '|'))
    end

    print(io, ", cookie=", ev.cookie, ")")
end
