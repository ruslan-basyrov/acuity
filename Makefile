PRERENDER = _extensions/acuity-figures/prerender.ts

QUARTO ?= uv run --no-project --with quarto-cli quarto
DENO    = uv run --no-project --with "deno>=2.7.14" deno

WORDCOUNT = _extensions/acuity/wordcount.lua

# Override on the command line: `make word_count WORDS_MAX=40000`.
INPUT      ?= index.qmd
WORDS_MIN  ?= 20000
WORDS_MAX  ?= 30000
WORDS_FILE ?= build/wordcount.txt

.PHONY: all figures render preview word_count clean fclean

all: render

# Normally the extension runs this as a pre-render script. It is bootstrapped
# here because Quarto resolves `{{< include >}}` while scanning input files,
# before pre-render runs, so a clean checkout has nothing to include yet.
figures:
	$(DENO) run -A $(PRERENDER)

render: figures
	$(QUARTO) render

preview: figures
	$(QUARTO) preview

# The throwaway render is what gives the filter the includes and the floats.
# Plain `html`, not `acuity-html`: the Acuity filters move captions and
# references into the margin, which would count them as margin text.
word_count: figures
	@mkdir -p $(dir $(WORDS_FILE))
	@$(QUARTO) render $(INPUT) --to html --quiet \
		-M "filters:[$(WORDCOUNT)]" \
		-M "wordcount-min:$(WORDS_MIN)" \
		-M "wordcount-max:$(WORDS_MAX)" \
		-M "wordcount-report:$(WORDS_FILE)" \
		-o wordcount.html
	@cat $(WORDS_FILE)

clean:
	rm -rf build .quarto index_files index.typ

fclean: clean
	rm -rf _acuity