# ==============================================================================
# setup.R — Instalación de paquetes del proyecto
#
# Ejecutar UNA SOLA VEZ al clonar el repositorio.
# Los scripts de análisis solo cargan los paquetes, no los instalan.
# ==============================================================================

paquetes <- c(
  "here",       # rutas relativas a la raíz del proyecto
  "did",        # Callaway-Sant'Anna, estimador principal
  "tidyverse",  # manipulación de datos
  "data.table", # lectura rápida de archivos grandes
  "haven",      # archivos .dta y .sav del DANE
  "fixest",     # efectos fijos y TWFE, para robustez
  "janitor",    # limpieza de nombres de columnas
  "did2s"       # Sun-Abraham, para robustez
)

faltantes <- paquetes[!paquetes %in% rownames(installed.packages())]

if (length(faltantes) > 0) {
  cat("Instalando:", paste(faltantes, collapse = ", "), "\n")
  install.packages(faltantes)
} else {
  cat("Todos los paquetes ya están instalados.\n")
}
