-- Read settings, collect figure requests, render once, then replace the images.
if not (quarto.doc.is_format("html") or quarto.doc.is_format("typst")) then
	return {}
end

local document = {
	html = quarto.doc.is_format("html"),
	root = quarto.project.directory or pandoc.path.directory(quarto.doc.input_file),
	figures = {},
}

local function column(classes)
	for _, class in ipairs(classes) do
		if class == "column-margin" or class == "aside" then
			return "margin"
		end
		if class:match("^column%-page") or class:match("^column%-screen") then
			return "page"
		end
	end
	return "body"
end

-- Collect images' paths and widths into a table
local function collect(image, location)
	if not image.src:match("%.fig%.js$") then
		return
	end
	local width = image.attributes.width or "100%"
	local share = width:match("^([%d.]+)%%$")
	width = share and document.layout.columns[location] * tonumber(share) / 100 or document.layout.ems(width)
	assert(width > 0, "acuity: figure width must be positive")
	table.insert(document.figures, {
		module = pandoc.path.join({ pandoc.path.directory(quarto.doc.input_file), image.src }),
		width = width,
	})
	image.attributes.width = nil
	image.attributes["acuity-figure"] = tostring(#document.figures)
	return image
end

local function render()
	if #document.figures == 0 then
		return
	end
	local request = quarto.json.encode({
		html = document.html,
		root = document.root,
		theme = document.theme,
		small = document.layout.small,
		settings = document.layout.figures,
		figures = document.figures,
	})
	local result = pandoc.pipe(quarto.config.cli_path(), { "run", quarto.utils.resolve_path("figures.js") }, request)
	for i, figure in ipairs(quarto.json.decode(result)) do
		document.figures[i].svg = figure.svg
	end
end

local function replace(image)
	local index = image.attributes["acuity-figure"]
	if not index then
		return
	end
	local figure = document.figures[tonumber(index)]
	if document.html then
		return pandoc.RawInline("html", figure.svg)
	end
	-- Content-based names also distinguish equal basenames in different folders.
	local path = "build/figures/" .. pandoc.utils.sha1(figure.svg) .. ".svg"
	pandoc.system.make_directory(pandoc.path.join({ document.root, "build/figures" }), true)
	local file = assert(io.open(pandoc.path.join({ document.root, path }), "w"))
	file:write(figure.svg)
	file:close()
	image.src = pandoc.path.join({ quarto.project.offset or ".", path })
	image.attributes["acuity-figure"] = nil
	image.attributes.width = document.layout.pt(figure.width)
	return image
end

-- Quarto floats own their column class; ordinary images own their own.
local function in_float(float, visit)
	float.content = quarto.utils.as_blocks(float.content):walk({
		Image = function(image)
			return visit(image, column(float.classes))
		end,
	})
	return float, false
end

return {
	{
		Meta = function(meta)
			document.layout = require("./layout")(meta)
			document.theme = require("./theme")()
			return meta
		end,
	},
	{
		traverse = "topdown",
		FloatRefTarget = function(float)
			return in_float(float, collect)
		end,
		Image = function(image)
			return collect(image, column(image.classes))
		end,
	},
	{ Pandoc = render },
	{
		traverse = "topdown",
		FloatRefTarget = function(float)
			return in_float(float, replace)
		end,
		Para = function(para)
			local image = para.content[1]
			if #para.content == 1 and image.t == "Image" and image.attributes["acuity-figure"] then
				return pandoc.Div(pandoc.Plain({ replace(image) }), pandoc.Attr("", image.classes)), false
			end
		end,
		Image = replace,
	},
}
