QUARTO ?= uv run --no-project --with quarto-cli quarto

.PHONY: render preview clean

render:
	$(QUARTO) render

preview:
	$(QUARTO) preview

clean:
	rm -rf .quarto _acuity site_libs index_files index.typ
