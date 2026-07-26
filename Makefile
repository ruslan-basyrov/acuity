PRERENDER = _extensions/acuity-figures/prerender.ts

QUARTO ?= uv run --no-project --with quarto-cli quarto
DENO    = uv run deno

.PHONY: all figures render preview clean fclean

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

clean:
	rm -rf build .quarto index_files index.typ

fclean: clean
	rm -rf _acuity