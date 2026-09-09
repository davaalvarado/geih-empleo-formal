# Paquetes para todo el proyecto
install.packages(c(
  "did",        # Callaway-Sant'Anna (el estimador principal)
  "tidyverse",  # manipulación de datos (dplyr, ggplot2, etc.)
  "data.table", # lectura rápida de archivos grandes
  "haven",      # leer archivos .dta y .sav del DANE
  "fixest",     # modelos de efectos fijos y TWFE (para robustez)
  "janitor",    # limpiar nombres de columnas
  "did2s"       # Sun-Abraham y otros (robustez)
))

# Verifica que el paquete clave carga bien
library(did)
library(tidyverse)
library(data.table)
library(janitor)

library(haven)
library(tidyverse)
library(data.table)
library(janitor)

carpeta <- "C:/Users/Alejandro/Downloads/"

leer_archivo <- function(ruta) {
  ext <- tolower(tools::file_ext(ruta))
  if (ext == "dta") {
    read_dta(ruta) |> clean_names()
  } else {
    fread(ruta, encoding = "Latin-1") |> clean_names()
  }
}

construir_tratamiento <- function(ruta) {
  d <- leer_archivo(ruta)
  
  # 1. Detectar la columna de matrícula (varía entre años)
  if ("sedealum_cantidad" %in% names(d)) {
    d <- d |> mutate(matricula = as.numeric(sedealum_cantidad))
  } else if (all(c("jorntra_cantidad_hombre", "jorntra_cantidad_mujer") %in% names(d))) {
    d <- d |> mutate(matricula = as.numeric(jorntra_cantidad_hombre) +
                       as.numeric(jorntra_cantidad_mujer))
  } else {
    stop("No encuentro columna de matrícula")
  }
  
  # 2. Construir tratamiento (jornada única = código 6)
  d |>
    mutate(
      cod_mpio = substr(as.character(sede_codigo), 2, 6),
      jornada_codigo = as.numeric(jornada_codigo)
    ) |>
    group_by(cod_mpio) |>
    summarise(
      matricula_total = sum(matricula, na.rm = TRUE),
      matricula_unica = sum(matricula[jornada_codigo == 6], na.rm = TRUE),
      anio = as.integer(first(periodo_anio)),
      .groups = "drop"
    ) |>
    mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))
}

# Buscar archivos SIN importar mayúsculas/minúsculas en la extensión
archivos <- list.files(carpeta, pattern = "\\.(dta|txt|csv)$",
                       full.names = TRUE, ignore.case = TRUE)
cat("=== ARCHIVOS ENCONTRADOS ===\n"); print(basename(archivos))

lista_tratamiento <- list()
for (arch in archivos) {
  cat("Procesando:", basename(arch), "... ")
  lista_tratamiento[[arch]] <- tryCatch({
    res <- construir_tratamiento(arch)
    cat("✅ OK (", nrow(res), "municipios )\n")
    res
  }, error = function(e) {
    cat("❌ ERROR:", conditionMessage(e), "\n"); NULL
  })
}

tratamiento_panel <- bind_rows(lista_tratamiento)

cat("\n=== EXPANSIÓN AÑO A AÑO ===\n")
tratamiento_panel |>
  group_by(anio) |>
  summarise(municipios = n(),
            municipios_con_ju = sum(cobertura_ju > 0),
            cobertura_promedio = round(mean(cobertura_ju), 2)) |>
  print()

saveRDS(tratamiento_panel, "tratamiento_panel.rds")

#Insumos

tratamiento_panel <- readRDS("tratamiento_panel.rds")

# Definir "adopción": primer año en que el municipio supera un umbral de cobertura
# Usamos 5% como umbral mínimo para considerar que "adoptó" de verdad
umbral <- 5

anio_adopcion <- tratamiento_panel |>
  filter(cobertura_ju >= umbral) |>
  group_by(cod_mpio) |>
  summarise(anio_adopcion = min(anio), .groups = "drop")

# Unir al panel; los municipios que nunca adoptaron quedan con NA (grupo control)
tratamiento_panel <- tratamiento_panel |>
  left_join(anio_adopcion, by = "cod_mpio")

# Para Callaway-Sant'Anna, los "nunca tratados" se marcan con 0
tratamiento_panel <- tratamiento_panel |>
  mutate(gname = ifelse(is.na(anio_adopcion), 0, anio_adopcion))

cat("=== DISTRIBUCIÓN DE COHORTES DE ADOPCIÓN ===\n")
tratamiento_panel |>
  distinct(cod_mpio, gname) |>
  count(gname) |>
  print()

saveRDS(tratamiento_panel, "tratamiento_panel.rds")


### Opcion departamental

tratamiento_panel <- readRDS("tratamiento_panel.rds")

# Agregar de municipio a departamento
tratamiento_depto <- tratamiento_panel |>
  mutate(cod_dpto = substr(cod_mpio, 1, 2)) |>
  group_by(cod_dpto, anio) |>
  summarise(
    matricula_total = sum(matricula_total, na.rm = TRUE),
    matricula_unica = sum(matricula_unica, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))

# Ver la expansión por departamento
cat("=== COBERTURA DE JU POR DEPARTAMENTO Y AÑO ===\n")
tratamiento_depto |>
  arrange(cod_dpto, anio) |>
  print(n = 40)

saveRDS(tratamiento_depto, "tratamiento_depto.rds")

## limpieza 

tratamiento_panel <- readRDS("tratamiento_panel.rds")

tratamiento_depto <- tratamiento_panel |>
  mutate(cod_dpto = substr(cod_mpio, 1, 2)) |>
  # quedarnos solo con códigos de departamento válidos (2 dígitos numéricos)
  filter(str_detect(cod_dpto, "^[0-9]{2}$")) |>
  group_by(cod_dpto, anio) |>
  summarise(
    matricula_total = sum(matricula_total, na.rm = TRUE),
    matricula_unica = sum(matricula_unica, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))

cat("=== CUÁNTOS DEPARTAMENTOS VÁLIDOS ===\n")
tratamiento_depto |> distinct(cod_dpto) |> nrow() |> print()

cat("\n=== DEPARTAMENTOS DISPONIBLES ===\n")
tratamiento_depto |> distinct(cod_dpto) |> arrange(cod_dpto) |> print(n = 40)

saveRDS(tratamiento_depto, "tratamiento_depto.rds")


#Definicion de cohorte
umbral <- 5

anio_adopcion_depto <- tratamiento_depto |>
  filter(cobertura_ju >= umbral) |>
  group_by(cod_dpto) |>
  summarise(gname = min(anio), .groups = "drop")

tratamiento_depto <- tratamiento_depto |>
  left_join(anio_adopcion_depto, by = "cod_dpto") |>
  mutate(gname = ifelse(is.na(gname), 0, gname))

cat("=== COHORTES DE ADOPCIÓN (nivel departamento) ===\n")
tratamiento_depto |> distinct(cod_dpto, gname) |> count(gname) |> print()

saveRDS(tratamiento_depto, "tratamiento_depto.rds")
