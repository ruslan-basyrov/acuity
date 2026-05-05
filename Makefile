SRC_DIR   = src
TEMPLATES = $(SRC_DIR)/templates
SCRIPTS   = $(SRC_DIR)/scripts

FIGURES   = palette

BUILD     = build/figures
SVG_DIR   = figures

.PHONY: all compile svgs

all: compile

compile: svgs
	quarto render index.qmd

plots: $(FIGURES:%=$(BUILD)/%.qmd)

$(BUILD)/%.qmd: $(TEMPLATES)/%.js.jinja $(TEMPLATES)/plot_figure.js.jinja $(TEMPLATES)/chunk.qmd.jinja
	python $(SCRIPTS)/template.py $(TEMPLATES) $(BUILD) $* $(SVG_DIR)

svgs: plots
	$(foreach fig,$(FIGURES), \
	  deno run --allow-read --allow-write $(BUILD)/svg_$(fig).js;)
