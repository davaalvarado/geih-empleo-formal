# 2026-10-07 — ¿La caída de matrícula de Guainía en 2018 viene de la fuente? ¿Se repite en otros departamentos o años?
# Hallazgo: (por llenar)
# Decisión: (por llenar)

library(tidyverse)
library(here)

panel    <- readRDS(here("salidas", "tratamiento_panel.rds"))
depto    <- readRDS(here("salidas", "tratamiento_depto.rds"))
divipola <- readr::read_csv(here("referencias", "divipola_municipios.csv"),
                            col_types = readr::cols(.default = "c")) |>
  janitor::clean_names()

# Razón entre la matrícula de un año y el promedio de los años vecinos de la misma
# unidad (el anterior y el siguiente disponibles). Cerca de 1 es lo normal; muy por
# debajo de 1 es una caída que se recupera después.
razon_vecinos <- function(datos, unidad) {
  datos |>
    arrange({{ unidad }}, anio) |>
    group_by({{ unidad }}) |>
    mutate(vecinos = rowMeans(cbind(dplyr::lag(matricula_total),
                                    dplyr::lead(matricula_total)), na.rm = TRUE),
           razon   = round(matricula_total / vecinos, 2)) |>
    ungroup()
}

depto_r <- razon_vecinos(depto, cod_dpto) |>
  left_join(distinct(divipola, cod_dpto, dpto), by = "cod_dpto")
panel_r <- razon_vecinos(panel, cod_mpio) |>
  left_join(select(divipola, cod_mpio, nom_mpio, dpto), by = "cod_mpio")

# A. Razón por departamento y año
depto_r |>
  select(cod_dpto, dpto, anio, razon) |>
  pivot_wider(names_from = anio, values_from = razon, names_sort = TRUE) |>
  print(n = 40)

# B. Departamentos-año que se alejan más de 10% de sus vecinos
depto_r |>
  filter(razon < 0.90 | razon > 1.10) |>
  select(cod_dpto, dpto, anio, matricula_total, vecinos, razon, cobertura_ju) |>
  arrange(razon) |>
  print(n = 40, width = Inf)

# C. ¿Cuántos municipios caen o suben más de 30% frente a sus vecinos en cada año?
panel_r |>
  group_by(anio) |>
  summarise(municipios = n(),
            caen_30    = sum(razon < 0.70, na.rm = TRUE),
            suben_30   = sum(razon > 1.30, na.rm = TRUE),
            alumnos_que_faltan = round(sum((vecinos - matricula_total)[razon < 0.70], na.rm = TRUE)),
            .groups = "drop") |>
  print()

# D. Las 25 caídas municipales más grandes en número de alumnos
panel_r |>
  filter(razon < 0.70) |>
  mutate(faltan = round(vecinos - matricula_total)) |>
  arrange(desc(faltan)) |>
  select(cod_mpio, nom_mpio, dpto, anio, matricula_total, vecinos, razon, cobertura_ju, faltan) |>
  print(n = 25, width = Inf)

# E. ¿La caída de Guainía está en el archivo de matrícula o la produjo el cruce con la carátula?
#    Matrícula de las sedes que traen el 94 embebido en su código, leída del archivo crudo.
crudo_dpto <- function(ruta, dpto) {
  d <- if (grepl("\\.dta$", ruta, ignore.case = TRUE)) {
    haven::read_dta(ruta)
  } else {
    data.table::fread(ruta, encoding = "Latin-1")
  }
  d <- janitor::clean_names(d)

  codigo <- if (is.character(d$sede_codigo)) d$sede_codigo else sprintf("%.0f", as.numeric(d$sede_codigo))

  if ("sedealum_cantidad" %in% names(d)) {
    matricula <- as.numeric(d$sedealum_cantidad)
  } else if (all(c("jorntra_cantidad_hombre", "jorntra_cantidad_mujer") %in% names(d))) {
    matricula <- as.numeric(d$jorntra_cantidad_hombre) + as.numeric(d$jorntra_cantidad_mujer)
  } else {
    stop("No encuentro columna de matrícula en ", basename(ruta))
  }

  del_dpto <- substr(codigo, 2, 3) == dpto
  tibble(archivo   = basename(ruta),
         sedes     = n_distinct(codigo[del_dpto]),
         matricula = sum(matricula[del_dpto], na.rm = TRUE))
}

list.files(here("datos", "simat"), pattern = "\\.(dta|txt|csv)$",
           full.names = TRUE, ignore.case = TRUE) |>
  map(crudo_dpto, dpto = "94") |>
  bind_rows() |>
  print()
