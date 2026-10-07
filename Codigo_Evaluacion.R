# ==============================================================================
# Paso 2 — Construcción de la variable de tratamiento (Jornada Única Escolar)
#
# Proyecto : Evaluación de impacto de la JUE sobre el empleo de las madres
# Fuente   : Educación Formal (DANE) — microdatos.dane.gov.co, EDU-MICRODATOS
#            Un catálogo por año. De cada año se usan dos archivos, ambos con el
#            año al inicio del nombre (2018_..., 2019_...):
#              - Alumnos matriculados por jornada     -> datos/simat/
#              - Carátula única de la sede educativa  -> datos/simat_sedes/
# Referencias (carpeta referencias/, versionada):
#            divipola_municipios.csv       lista vigente de municipios (DIVIPOLA)
#            equivalencias_municipios.csv  códigos que ya no existen en la DIVIPOLA
#                                          y el código vigente que les corresponde
# Salidas  : salidas/tratamiento_panel.rds    (municipio-año)
#            salidas/tratamiento_depto.rds    (departamento-año)
#            salidas/auditoria_caratula.csv   (control del cruce, una fila por año)
#            salidas/sedes_sin_municipio.csv  (solo si alguna sede queda sin municipio)
#            salidas/recodificados.csv        (solo si se aplicó alguna equivalencia)
#
# Requisitos: ejecutar setup.R una sola vez para instalar los paquetes.
# Ejecución : con el botón Source, en una sesión nueva de R. Línea por línea
#             (Ctrl+Enter) un error no detiene las líneas que siguen.
# ==============================================================================

library(here)
library(haven)
library(tidyverse)
library(data.table)
library(janitor)

# ------------------------------------------------------------------------------
# Rutas del proyecto (relativas a la raíz del repositorio)
# ------------------------------------------------------------------------------

carpeta_datos     <- here("datos", "simat")
carpeta_caratulas <- here("datos", "simat_sedes")
carpeta_salidas   <- here("salidas")

ruta_divipola      <- here("referencias", "divipola_municipios.csv")
ruta_equivalencias <- here("referencias", "equivalencias_municipios.csv")

if (!dir.exists(carpeta_datos)) {
  stop("No existe la carpeta datos/simat/. Crearla y dejar allí los archivos ",
       "anuales de Educación Formal del DANE. Ver el README.")
}

if (!dir.exists(carpeta_caratulas)) {
  stop("No existe la carpeta datos/simat_sedes/. Crearla y dejar allí la ",
       "carátula de la sede de cada año. Ver el README.")
}

if (!file.exists(ruta_divipola)) {
  stop("Falta referencias/divipola_municipios.csv. Se genera una sola vez con ",
       "exploracion/2026-10-07_validacion_divipola.R")
}

if (!file.exists(ruta_equivalencias)) {
  stop("Falta referencias/equivalencias_municipios.csv, la tabla de códigos de ",
       "municipio que ya no existen en la DIVIPOLA.")
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
# extracción del municipio devuelve basura (".0800" en vez de "08001").
# Esto fuerza siempre la forma completa, sin notación científica, y conserva
# los faltantes como NA.
cod_a_texto <- function(x) {
  if (is.character(x)) return(as.character(x))
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_, sprintf("%.0f", x))
}

# Año al que corresponde un archivo: los cuatro primeros caracteres de su nombre
anio_de_archivo <- function(rutas) {
  suppressWarnings(as.integer(substr(basename(rutas), 1, 4)))
}

# ------------------------------------------------------------------------------
# 2. Tablas de referencia
#    DIVIPOLA: lista vigente de municipios, bajada de datos.gov.co (gdxc-w37w).
#    Equivalencias: códigos que traen las carátulas y que ya no existen en la
#    DIVIPOLA, con el código vigente que les corresponde y la razón del cambio.
#    Las dos se leen como texto para no perder el cero inicial de Antioquia y
#    Atlántico. Ver exploracion/2026-10-07_validacion_divipola.R
# ------------------------------------------------------------------------------

divipola      <- read_csv(ruta_divipola, col_types = cols(.default = "c")) |>
  clean_names()
equivalencias <- read_csv(ruta_equivalencias, col_types = cols(.default = "c")) |>
  clean_names()

if (!"cod_mpio" %in% names(divipola)) {
  stop("referencias/divipola_municipios.csv no trae la columna cod_mpio")
}

mpios_validos <- unique(divipola$cod_mpio)

faltan <- setdiff(c("cod_original", "cod_vigente"), names(equivalencias))
if (length(faltan) > 0) {
  stop("A referencias/equivalencias_municipios.csv le faltan columnas: ",
       paste(faltan, collapse = ", "))
}

if (anyDuplicated(equivalencias$cod_original) > 0) {
  stop("En referencias/equivalencias_municipios.csv hay códigos originales ",
       "repetidos: ",
       paste(unique(equivalencias$cod_original[duplicated(equivalencias$cod_original)]),
             collapse = ", "))
}

if (!all(equivalencias$cod_vigente %in% mpios_validos)) {
  stop("En referencias/equivalencias_municipios.csv hay códigos vigentes que no ",
       "existen en la DIVIPOLA: ",
       paste(setdiff(equivalencias$cod_vigente, mpios_validos), collapse = ", "))
}

# Cambia un código por su equivalente vigente; los demás quedan igual
aplicar_equivalencias <- function(cod) {
  i <- match(cod, equivalencias$cod_original)
  ifelse(is.na(i), cod, equivalencias$cod_vigente[i])
}

# ------------------------------------------------------------------------------
# 3. Carátula de la sede: de ahí sale el municipio real
#    El código de municipio embebido en sede_codigo (posiciones 2 a 6) no
#    siempre es el municipio donde está la sede: en la carátula de 2018 difiere
#    en 3.040 de 58.860 sedes, repartidas en 32 departamentos. El municipio
#    real viene en la columna codigointernomuni de la carátula, que trae una
#    fila por sede. Ver exploracion/2026-10-07_alcance_caratula.R
# ------------------------------------------------------------------------------

leer_caratula <- function(ruta, anio_esperado) {
  car <- leer_archivo(ruta)

  faltan <- setdiff(c("sede_codigo", "codigointernomuni"), names(car))
  if (length(faltan) > 0) {
    stop("A la carátula ", basename(ruta), " le faltan columnas: ",
         paste(faltan, collapse = ", "))
  }

  # Protege contra una carátula guardada con el año equivocado en el nombre
  if ("periodo_anio" %in% names(car)) {
    anios <- unique(as.integer(car$periodo_anio))
    anios <- anios[!is.na(anios)]
    if (!identical(anios, anio_esperado)) {
      stop("La carátula ", basename(ruta), " trae el año ",
           paste(anios, collapse = ", "), " y se esperaba ", anio_esperado)
    }
  }

  # cod_caratula es el código tal como viene en la carátula; cod_mpio es el
  # mismo después de aplicar la tabla de equivalencias
  car <- tibble(
    sede_codigo  = str_trim(cod_a_texto(car$sede_codigo)),
    cod_caratula = str_trim(cod_a_texto(car$codigointernomuni)),
    en_caratula  = TRUE
  ) |>
    filter(!is.na(sede_codigo), sede_codigo != "") |>
    mutate(cod_caratula = str_pad(na_if(cod_caratula, ""), 5, pad = "0"),
           cod_mpio     = aplicar_equivalencias(cod_caratula))

  if (anyDuplicated(car$sede_codigo) > 0) {
    stop("La carátula ", basename(ruta), " trae ", sum(duplicated(car$sede_codigo)),
         " sedes repetidas. Unirla así duplicaría la matrícula de esas sedes.")
  }

  mal <- !is.na(car$cod_caratula) & !str_detect(car$cod_caratula, "^[0-9]{5}$")
  if (any(mal)) {
    stop("La carátula ", basename(ruta), " trae códigos de municipio que no son ",
         "de 5 dígitos: ",
         paste(head(unique(car$cod_caratula[mal]), 5), collapse = ", "))
  }

  car
}

# ------------------------------------------------------------------------------
# 4. Construcción del panel municipio-año
#    La columna de matrícula también cambia de nombre entre años, por eso se
#    detecta en vez de asumirse. La jornada única corresponde al código 6.
#    Cada archivo de matrícula se une por sede_codigo con la carátula de su
#    mismo año, y la matrícula se agrupa por el municipio de la carátula.
# ------------------------------------------------------------------------------

construir_tratamiento <- function(ruta, ruta_caratula) {
  anio_archivo <- anio_de_archivo(ruta)

  d   <- leer_archivo(ruta)
  car <- leer_caratula(ruta_caratula, anio_archivo)

  if ("sedealum_cantidad" %in% names(d)) {
    d <- d |> mutate(matricula = as.numeric(sedealum_cantidad))
  } else if (all(c("jorntra_cantidad_hombre", "jorntra_cantidad_mujer") %in% names(d))) {
    d <- d |> mutate(matricula = as.numeric(jorntra_cantidad_hombre) +
                                 as.numeric(jorntra_cantidad_mujer))
  } else {
    stop("No encuentro columna de matrícula")
  }

  codigo_txt <- cod_a_texto(d$sede_codigo)
  if (!isTRUE(all(nchar(codigo_txt) == 12))) {
    stop("Códigos de sede con longitud distinta de 12 en ", basename(ruta), ": ",
         paste(unique(nchar(codigo_txt)), collapse = ", "))
  }

  anios <- unique(as.integer(d$periodo_anio))
  if (!identical(anios, anio_archivo)) {
    stop("El archivo ", basename(ruta), " trae el año ",
         paste(anios, collapse = ", "), " y se esperaba ", anio_archivo)
  }

  d <- d |>
    mutate(
      sede_codigo    = codigo_txt,
      cod_embebido   = substr(codigo_txt, 2, 6),
      jornada_codigo = as.numeric(jornada_codigo),
      anio           = as.integer(periodo_anio)
    ) |>
    left_join(car, by = "sede_codigo")

  # Control del cruce: cuánto queda sin municipio y cuánto cambia de lugar la
  # carátula frente al código embebido en sede_codigo
  fila_sin_mpio    <- is.na(d$cod_mpio)
  fila_reasignada  <- !fila_sin_mpio & d$cod_caratula != d$cod_embebido
  fila_cambia_dpto <- !fila_sin_mpio &
    substr(d$cod_caratula, 1, 2) != substr(d$cod_embebido, 1, 2)

  auditoria <- tibble(
    anio             = anio_archivo,
    sedes            = n_distinct(d$sede_codigo),
    sin_mpio         = n_distinct(d$sede_codigo[fila_sin_mpio]),
    reasignadas      = n_distinct(d$sede_codigo[fila_reasignada]),
    cambian_dpto     = n_distinct(d$sede_codigo[fila_cambia_dpto]),
    matricula        = sum(d$matricula, na.rm = TRUE),
    matr_sin_mpio    = sum(d$matricula[fila_sin_mpio], na.rm = TRUE),
    matr_reasignada  = sum(d$matricula[fila_reasignada], na.rm = TRUE),
    matr_cambia_dpto = sum(d$matricula[fila_cambia_dpto], na.rm = TRUE)
  )

  sedes_sin_mpio <- d |>
    filter(is.na(cod_mpio)) |>
    group_by(anio, sede_codigo) |>
    summarise(
      matricula = sum(matricula, na.rm = TRUE),
      motivo    = if_else(is.na(en_caratula[1]), "sede_ausente_de_la_caratula",
                          "caratula_sin_municipio"),
      .groups   = "drop"
    )

  # Qué movió la tabla de equivalencias en este año
  recodificados <- d |>
    filter(!is.na(cod_mpio), cod_mpio != cod_caratula) |>
    group_by(anio, cod_original = cod_caratula, cod_vigente = cod_mpio) |>
    summarise(
      sedes     = n_distinct(sede_codigo),
      matricula = sum(matricula, na.rm = TRUE),
      .groups   = "drop"
    )

  panel <- d |>
    filter(!is.na(cod_mpio)) |>
    group_by(cod_mpio, anio) |>
    summarise(
      matricula_total = sum(matricula, na.rm = TRUE),
      matricula_unica = sum(matricula[jornada_codigo == 6], na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(cobertura_ju = round(100 * matricula_unica / matricula_total, 2))

  # En el cruce no se pierde ni se duplica ningún alumno
  if (!isTRUE(all.equal(sum(panel$matricula_total) + auditoria$matr_sin_mpio,
                        auditoria$matricula))) {
    stop("La matrícula del panel no cuadra con la del archivo ", basename(ruta))
  }

  list(panel = panel, auditoria = auditoria, sedes_sin_mpio = sedes_sin_mpio,
       recodificados = recodificados)
}

patron    <- "\\.(dta|txt|csv)$"
archivos  <- list.files(carpeta_datos, pattern = patron,
                        full.names = TRUE, ignore.case = TRUE)
caratulas <- list.files(carpeta_caratulas, pattern = patron,
                        full.names = TRUE, ignore.case = TRUE)

if (length(archivos) == 0) {
  stop("No hay archivos en datos/simat/. Descargar Educación Formal del DANE ",
       "para 2014, 2015, 2016, 2018, 2019, 2021 y 2022. Ver el README.")
}

# Cada archivo de matrícula necesita la carátula de su mismo año
revisar_anios <- function(anios, rutas, carpeta) {
  if (anyNA(anios)) {
    stop("En ", carpeta, " hay archivos cuyo nombre no empieza con el año: ",
         paste(basename(rutas)[is.na(anios)], collapse = ", "))
  }
  if (anyDuplicated(anios) > 0) {
    stop("En ", carpeta, " hay más de un archivo para el año ",
         paste(unique(anios[duplicated(anios)]), collapse = ", "))
  }
}

anios_matricula <- anio_de_archivo(archivos)
anios_caratula  <- anio_de_archivo(caratulas)

revisar_anios(anios_matricula, archivos,  "datos/simat/")
revisar_anios(anios_caratula,  caratulas, "datos/simat_sedes/")

sin_caratula <- setdiff(anios_matricula, anios_caratula)
if (length(sin_caratula) > 0) {
  stop("Falta la carátula de ", paste(sort(sin_caratula), collapse = ", "),
       " en datos/simat_sedes/. El nombre del archivo debe empezar con el año.")
}

caratulas <- caratulas[match(anios_matricula, anios_caratula)]

cat("=== ARCHIVOS ENCONTRADOS ===\n")
print(tibble(anio      = anios_matricula,
             matricula = basename(archivos),
             caratula  = basename(caratulas)))

# Se procesan todos los años y, si alguno falla, el script termina aquí con la
# lista de errores: un panel al que le falta un año no sirve.
resultados <- list()
errores    <- character()

for (i in seq_along(archivos)) {
  cat("Procesando:", basename(archivos[i]), "... ")
  res <- tryCatch(construir_tratamiento(archivos[i], caratulas[i]),
                  error = function(e) conditionMessage(e))
  if (is.character(res)) {
    cat("ERROR\n")
    errores <- c(errores, paste0(basename(archivos[i]), ": ", res))
  } else {
    cat("OK (", nrow(res$panel), "municipios )\n")
    resultados[[length(resultados) + 1]] <- res
  }
}

if (length(errores) > 0) {
  stop("No se construyó el panel. Archivos con error:\n  ",
       paste(errores, collapse = "\n  "))
}

tratamiento_panel <- map(resultados, "panel")          |> bind_rows()
auditoria         <- map(resultados, "auditoria")      |> bind_rows()
sedes_sin_mpio    <- map(resultados, "sedes_sin_mpio") |> bind_rows()
recodificados     <- map(resultados, "recodificados")  |> bind_rows()

# Después de aplicar las equivalencias, todos los municipios del panel deben
# existir en la DIVIPOLA. Si aparece un código nuevo, el script termina aquí:
# hay que decidir qué hacer con él y registrarlo en la tabla de equivalencias.
invalidos <- tratamiento_panel |>
  filter(!cod_mpio %in% mpios_validos) |>
  group_by(cod_mpio) |>
  summarise(anios           = paste(anio, collapse = " "),
            matricula_media = round(mean(matricula_total)),
            .groups = "drop")

if (nrow(invalidos) > 0) {
  stop("Códigos de municipio que no existen en la DIVIPOLA ni tienen equivalencia ",
       "en referencias/equivalencias_municipios.csv:\n  ",
       paste0(invalidos$cod_mpio, " (años ", invalidos$anios, "; matrícula media ",
              invalidos$matricula_media, ")", collapse = "\n  "))
}

cat("\n=== CONTROL DEL CRUCE CON LA CARÁTULA ===\n")
print(auditoria, width = Inf)
write_csv(auditoria, here("salidas", "auditoria_caratula.csv"))

ruta_sin_mpio <- here("salidas", "sedes_sin_municipio.csv")
if (nrow(sedes_sin_mpio) > 0) {
  write_csv(sedes_sin_mpio, ruta_sin_mpio)
  cat("\nAVISO:", nrow(sedes_sin_mpio), "registros sede-año quedaron fuera del",
      "panel por no tener municipio. Detalle en salidas/sedes_sin_municipio.csv\n")
} else if (file.exists(ruta_sin_mpio)) {
  file.remove(ruta_sin_mpio)
}

ruta_recodificados <- here("salidas", "recodificados.csv")
if (nrow(recodificados) > 0) {
  cat("\n=== RECODIFICADOS POR LA TABLA DE EQUIVALENCIAS ===\n")
  print(recodificados)
  write_csv(recodificados, ruta_recodificados)
} else if (file.exists(ruta_recodificados)) {
  file.remove(ruta_recodificados)
}

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
# 5. Cohortes de adopción (nivel municipal)
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
# 6. Agregación departamental (especificación alternativa)
#    Útil si el nivel municipal resulta demasiado ruidoso. El departamento son
#    los dos primeros dígitos del municipio, ya validado contra la DIVIPOLA.
# ------------------------------------------------------------------------------

tratamiento_depto <- tratamiento_panel |>
  mutate(cod_dpto = substr(cod_mpio, 1, 2)) |>
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

cat("\n=== DEPARTAMENTOS ===\n")
tratamiento_depto |> distinct(cod_dpto) |> nrow() |> print()

cat("\n=== COHORTES DE ADOPCIÓN (departamento) ===\n")
tratamiento_depto |> distinct(cod_dpto, gname) |> count(gname) |> print()

saveRDS(tratamiento_depto, here("salidas", "tratamiento_depto.rds"))

cat("\nListo. Salidas en salidas/tratamiento_panel.rds y salidas/tratamiento_depto.rds\n")
