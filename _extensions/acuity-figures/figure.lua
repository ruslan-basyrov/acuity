-- {{< figure name >}} places figures/<name>.fig.js, as prerendered by prerender.ts.
return {
  figure = function(args)
    local name = pandoc.utils.stringify(args[1])
    local base = "/build/figures/" .. name
    if quarto.doc.is_format("typst") then
      return pandoc.Image({}, quarto.project.offset .. base .. ".svg", "",
        pandoc.Attr("", {}, { width = "100%" }))
    end
    local file = assert(io.open(quarto.project.directory .. base .. ".html"),
      "figure not prerendered: " .. name)
    local html = file:read("a")
    file:close()
    return pandoc.RawBlock("html", html)
  end,
}
