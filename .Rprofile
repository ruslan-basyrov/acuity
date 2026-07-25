source("renv/activate.R")

# Restore the full renv environment if there are missing libraries in the current one
if (requireNamespace("renv", quietly = TRUE) &&
    !all(names(renv::lockfile_read()$Packages) %in% list.files(renv::paths$library()))) {
  renv::restore(prompt = FALSE)
}
