# ==============================================================================
# Paso 2 — Construcción de la variable de tratamiento (Jornada Única Escolar)
#
# Proyecto : Evaluación de impacto de la JUE sobre el empleo de las madres
# Fuente   : Educación Formal (DANE) — microdatos.dane.gov.co, EDU-MICRODATOS
#            Un catálogo por año (2018 = 615, 2023 = 834)
# Salidas  : salidas/tratamiento_panel.rds  (municipio-año)
#            salidas/tratamiento_depto.rds  (departamento-año)
#
# Requisitos: ejecutar setup.R una sola vez para instalar los paquetes.
#             Dejar los archivos anuales del DANE en datos/simat/
# ==============================================================================

library(here)
library(haven)
library(tidyverse)
library(data.table)
library(janitor)

# ------------------------------------------------------------------------------
# Rutas del proyecto (relativas a la raíz del repositorio)
# ------------------------------------------------------------------------------

carpeta_datos   <- here("datos", "simat")
carpeta_salidas <- here("salidas")

if (!dir.exists(carpeta_datos)) {
  stop("No existe la carpeta datos/simat/. Crearla y dejar allí los archivos ",
       "anuales de Educación Formal del DANE. Ver el README.")
}

if (!dir.exists(carpeta_salidas)) dir.create(carpeta_salidas, recursive = TRUE)

# Umbral de cobertura a partir del cual se considera que un municipio adoptó la
# política. Decisión metodológica: someter a prueba de robustez con otros valores.
umbral <- 5

# ------------------------------------------------------------------------------
# 1. Lectura de archivos
#    El formato cambia entre años: unos vienen en .dta, otros en .txt o .csv
# ------------------------------------------------------------------------------

leer_archivo <- function(ruta) {
  ext <- tolower(tools::file_ext(ruta))
  if (ext == "dta") {
    read_dta(ruta) |> clean_names()
  } else {
    fread(ruta, encoding = "Latin-1") |> clean_names()
  }
}

# Algunos años traen sede_codigo como número. as.character() lo pasa a notación
# científica cuando el código termina en ceros ("1.08001e+11"), y entonces la
# extracción del municipio devuelve basura ("​.0800" en vez de "08001").
# Esto fuerza siempre la forma de 12 dígitos.
cod_a_texto <- function(x) {
  if (is.character(x)) x else sprintf("%.0f", as.numeric(x))
}
# ------------------------------------------------------------------------------
# 2. Construcción del panel municipio-año
#    La columna de matrícula también cambia de nombre entre años, por eso se
#    detecta en vez de asumirse. La jornada única corresponde al código 6.
# ------------------------------------------------------------------------------

construir_tratamiento <- function(ruta) {
  d <- leer_archivo(ruta)

  if ("sedealum_cantidad" %in% names(d)) {
    d <- d |> mutate(matricula = as.numeric(sedealum_cantidad))
  } else if (all(c("jorntra_cantidad_hombre", "jorntra_cantidad_mujer") %in% names(d))) {
    d <- d |> mutate(matricula = as.numeric(jorntra_cantidad_hombre) +
                                 as.numeric(jorntra_cantidad_mujer))
  } else {
    stop("No encuentro columna de matrícula")
  }

  codigo_txt <- cod_a_texto(d$sede_codigo)
  if (!all(nchar(codigo_txt) == 12)) {
    stop("Códigos de sede con longitud distinta de 12 en ", basename(ruta), ": ",
         paste(unique(nchar(codigo_txt)), collapse = ", "))
  }
  
  d |>
    mutate(
      cod_mpio       = substr(codigo_txt, 2, 6),
      jornada_codigo = as.numeric(jornada_codigo),
      anio           = as.integer(periodo_anio)
    ) |>
    group_by(cod_mpio, anio) |>
    summarise(
      matricula_total = sum(matricula, na.rm = TRUE),
      matricula_unica = sum(matricula[jornada_codigo == 6], na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))
}

archivos <- list.files(carpeta_datos, pattern = "\\.(dta|txt|csv)$",
                       full.names = TRUE, ignore.case = TRUE)

if (length(archivos) == 0) {
  stop("No hay archivos en datos/simat/. Descargar Educación Formal del DANE ",
       "para los años 2012-2023. Ver el README.")
}

cat("=== ARCHIVOS ENCONTRADOS ===\n"); print(basename(archivos))

# Un archivo con estructura inesperada avisa del error sin abortar el proceso
lista_tratamiento <- list()
for (arch in archivos) {
  cat("Procesando:", basename(arch), "... ")
  lista_tratamiento[[arch]] <- tryCatch({
    res <- construir_tratamiento(arch)
    cat("OK (", nrow(res), "municipios )\n")
    res
  }, error = function(e) {
    cat("ERROR:", conditionMessage(e), "\n"); NULL
  })
}

tratamiento_panel <- bind_rows(lista_tratamiento)

cat("\n=== EXPANSIÓN AÑO A AÑO ===\n")
tratamiento_panel |>
  group_by(anio) |>
  summarise(
    municipios         = n(),
    municipios_con_ju  = sum(cobertura_ju > 0),
    cobertura_promedio = round(mean(cobertura_ju), 2),
    .groups = "drop"
  ) |>
  print()

# ------------------------------------------------------------------------------
# 3. Cohortes de adopción (nivel municipal)
#    gname = primer año en que el municipio supera el umbral.
#    Los nunca tratados se marcan con 0, como exige el paquete did.
# ------------------------------------------------------------------------------

anio_adopcion <- tratamiento_panel |>
  filter(cobertura_ju >= umbral) |>
  group_by(cod_mpio) |>
  summarise(anio_adopcion = min(anio), .groups = "drop")

tratamiento_panel <- tratamiento_panel |>
  left_join(anio_adopcion, by = "cod_mpio") |>
  mutate(gname = ifelse(is.na(anio_adopcion), 0, anio_adopcion))

cat("\n=== DISTRIBUCIÓN DE COHORTES DE ADOPCIÓN (municipio) ===\n")
tratamiento_panel |>
  distinct(cod_mpio, gname) |>
  count(gname) |>
  print()

saveRDS(tratamiento_panel, here("salidas", "tratamiento_panel.rds"))

# ------------------------------------------------------------------------------
# 4. Agregación departamental (especificación alternativa)
#    Útil si el nivel municipal resulta demasiado ruidoso.
# ------------------------------------------------------------------------------

tratamiento_depto <- tratamiento_panel |>
  mutate(cod_dpto = substr(cod_mpio, 1, 2)) |>
  filter(str_detect(cod_dpto, "^[0-9]{2}$")) |>   # solo códigos válidos
  group_by(cod_dpto, anio) |>
  summarise(
    matricula_total = sum(matricula_total, na.rm = TRUE),
    matricula_unica = sum(matricula_unica, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))

anio_adopcion_depto <- tratamiento_depto |>
  filter(cobertura_ju >= umbral) |>
  group_by(cod_dpto) |>
  summarise(gname = min(anio), .groups = "drop")

tratamiento_depto <- tratamiento_depto |>
  left_join(anio_adopcion_depto, by = "cod_dpto") |>
  mutate(gname = ifelse(is.na(gname), 0, gname))

cat("\n=== DEPARTAMENTOS VÁLIDOS ===\n")
tratamiento_depto |> distinct(cod_dpto) |> nrow() |> print()

cat("\n=== COHORTES DE ADOPCIÓN (departamento) ===\n")
tratamiento_depto |> distinct(cod_dpto, gname) |> count(gname) |> print()

saveRDS(tratamiento_depto, here("salidas", "tratamiento_depto.rds"))

cat("\nListo. Salidas en salidas/tratamiento_panel.rds y salidas/tratamiento_depto.rds\n")
