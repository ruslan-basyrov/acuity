QUARTO ?= uv run --no-project --with quarto-cli quarto

.PHONY: render preview check clean

render:
	$(QUARTO) render

preview:
	$(QUARTO) preview

check: render
	$(QUARTO) run tests/figures.js

clean:
	rm -rf .quarto _acuity site_libs index_files index.typ build
