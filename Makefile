SRC_DIR   = src
TEMPLATES = $(SRC_DIR)/templates
SCRIPTS   = $(SRC_DIR)/scripts

FIGURES   = palette

BUILD     = build/figures
SVG_DIR   = $(BUILD)/svgs

QUARTO    = quarto
PYTHON    = uv run python

.PHONY: all compile svgs install-deno clean preview

all: compile

compile: svgs
	$(QUARTO) render index.qmd

plots: $(FIGURES:%=$(BUILD)/%.qmd)

$(BUILD)/%.qmd: $(TEMPLATES)/%.js.jinja $(TEMPLATES)/plot_figure.js.jinja $(TEMPLATES)/chunk.qmd.jinja
	$(PYTHON) $(SCRIPTS)/template.py $(TEMPLATES) $(BUILD) $* $(SVG_DIR)

svgs: plots
	$(foreach fig,$(FIGURES), \
	  deno run --allow-read --allow-write $(BUILD)/svg_$(fig).js;)

preview: svgs
	$(QUARTO) preview

clean:
	rm -rf build _acuity .quarto site_libs
