using Documenter
using June

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const DOCS_SRC = joinpath(@__DIR__, "src")
const GENERATED_ROOT = joinpath(DOCS_SRC, "generated")
const GENERATED_VIGNETTES = joinpath(GENERATED_ROOT, "vignettes")
const VIGNETTES_ROOT = joinpath(REPO_ROOT, "vignettes")

function title_case_slug(slug::AbstractString)
    parts = split(slug, "_")
    number = first(parts)
    label = join(uppercasefirst.(parts[2:end]), " ")
    return string(number, " ", label)
end

function rendered_markdown(dir::String)
    files = sort(filter(name -> endswith(name, ".md"), readdir(dir)))
    isempty(files) && error("No rendered markdown file found in $dir")
    return joinpath(dir, first(files))
end

function maybe_copy(src::String, dst::String)
    isfile(src) || return false
    cp(src, dst; force=true)
    return true
end

function stage_variant!(src_dir::String, dst_dir::String, basename::String)
    md_src = rendered_markdown(src_dir)
    md_dst = joinpath(dst_dir, basename * ".md")
    cp(md_src, md_dst; force=true)

    maybe_copy(replace(md_src, ".md" => ".html"), joinpath(dst_dir, basename * ".html"))
    maybe_copy(replace(md_src, ".md" => ".pdf"), joinpath(dst_dir, basename * ".pdf"))
end

function build_vignettes!()
    rm(GENERATED_VIGNETTES; recursive=true, force=true)
    mkpath(GENERATED_VIGNETTES)

    vignette_dirs = sort(filter(name ->
        occursin(r"^\d+_", name) && isdir(joinpath(VIGNETTES_ROOT, name)),
        readdir(VIGNETTES_ROOT),
    ))

    entries = NamedTuple[]
    for slug in vignette_dirs
        src_dir = joinpath(VIGNETTES_ROOT, slug)
        dst_dir = joinpath(GENERATED_VIGNETTES, slug)
        mkpath(dst_dir)

        stage_variant!(src_dir, dst_dir, "julia")

        python_dir = joinpath(src_dir, "python")
        if isdir(python_dir)
            stage_variant!(python_dir, dst_dir, "python")
        end

        push!(entries, (
            slug=slug,
            title=title_case_slug(slug),
            julia_page="generated/vignettes/$slug/julia.md",
            python_page="generated/vignettes/$slug/python.md",
        ))
    end

    overview_path = joinpath(GENERATED_VIGNETTES, "index.md")
    open(overview_path, "w") do io
        write(io, "# Vignettes\n\n")
        write(io, "These pages are built from the committed Quarto outputs in `vignettes/`.\n")
        write(io, "Each vignette is available as Julia and Python markdown pages, with downloadable HTML and PDF renders.\n\n")
        write(io, "| Vignette | Julia | Python | Downloads |\n")
        write(io, "| --- | --- | --- | --- |\n")
        for entry in entries
            slug = entry.slug
            write(
                io,
                "| $(entry.title) | [Page]($slug/julia.md) | [Page]($slug/python.md) | " *
                "[Julia HTML]($slug/julia.html), [Julia PDF]($slug/julia.pdf), " *
                "[Python HTML]($slug/python.html), [Python PDF]($slug/python.pdf) |\n",
            )
        end
    end

    return entries
end

vignette_entries = build_vignettes!()
vignette_pages = Any["Overview" => "generated/vignettes/index.md"]
for entry in vignette_entries
    push!(vignette_pages, entry.title => Any[
        "Julia" => entry.julia_page,
        "Python" => entry.python_page,
    ])
end

makedocs(;
    modules=[June],
    sitename="June.jl",
    remotes=nothing,
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        assets=String[],
        repolink="https://github.com/epirecipes/June.jl",
    ),
    pages=[
        "Home" => "index.md",
        "Vignettes" => vignette_pages,
        "API Reference" => "api.md",
    ],
    warnonly=[:missing_docs, :cross_references, :docs_block],
)

deploydocs(;
    repo="github.com/epirecipes/June.jl.git",
    devbranch="main",
    push_preview=true,
)
