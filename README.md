# geih-empleo-formal

**Evaluación de impacto de la Jornada Única Escolar (JUE) sobre el empleo de las madres en Colombia.**
Diseño de diferencias en diferencias escalonado (*staggered DiD*) con el estimador de Callaway-Sant'Anna, implementado en R.

> El repositorio se llama `geih-empleo-formal` porque la **GEIH** del DANE es la fuente de las variables de resultado del estudio: participación laboral, informalidad, horas trabajadas e ingresos de las madres.

---

## Pregunta de investigación

**¿Qué efecto tuvo la expansión de la Jornada Única Escolar sobre la participación laboral y la calidad del empleo de las madres con hijos en edad escolar en Colombia?**

Colombia implementa desde 2015 la Jornada Única Escolar, que extiende el horario de los colegios públicos de unas 4 horas diarias a 6–7 horas. El objetivo declarado de la política es educativo: mejorar los aprendizajes. Pero tiene una consecuencia no evaluada: **libera horas de cuidado en los hogares**.

La literatura existente sobre la JUE se ha concentrado casi por completo en el rendimiento académico (pruebas Saber 11°). Nadie ha medido de forma sistemática qué le pasó al empleo, a los ingresos y a la informalidad de las madres de esos estudiantes. Ese es el vacío que aborda este trabajo.

**Hipótesis:** la extensión de la jornada escolar reduce la carga de cuidado no remunerado de las madres y les permite aumentar su participación laboral y acceder a empleos de mejor calidad (menos informales, más horas, mayores ingresos).

---

## Datos

| Fuente | Entidad | Qué aporta al estudio | Acceso |
|---|---|---|---|
| **SIMAT** | Ministerio de Educación | **Tratamiento:** matrícula por sede, municipio, año y jornada. Permite calcular qué proporción de la matrícula oficial de cada municipio está en jornada única | Datos abiertos MEN |
| **GEIH** | DANE | **Resultados:** participación laboral, formalidad/informalidad, horas trabajadas, ingresos y composición del hogar. Mensual | Microdatos públicos |
| **ENUT** | DANE | **Mecanismo:** horas de trabajo no remunerado y cuidado de menores. Solo cuatro levantamientos (2012–13, 2016–17, 2020–21, 2024–25) | Público |
| **C600** | Ministerio de Educación | Características de los establecimientos educativos | Datos abiertos MEN |

**Período de análisis:** 2012–2023. Los años 2012–2014 son período pre-tratamiento limpio (la JUE no existía) y sirven para verificar tendencias paralelas; 2015 es el año de la Ley 1753 que crea la política; de ahí en adelante se mide la expansión y sus efectos.

Los microdatos **no se versionan en este repositorio** (son archivos pesados del DANE y el MEN). El `.gitignore` los excluye junto con los archivos temporales de RStudio. Hay que descargarlos por separado desde las fuentes citadas.

---

## Método

### Diseño

**DiD escalonado.** Los municipios no adoptaron la Jornada Única todos al mismo tiempo: unos entraron en 2016, otros en 2018, otros más tarde. Esa variación en el *momento* de adopción es lo que identifica el efecto.

### Estimador

**Callaway y Sant'Anna (2021)**, paquete [`did`](https://bcallaway11.github.io/did/) de R.

El DiD tradicional de efectos fijos de dos vías (TWFE) está sesgado en diseños escalonados: usa a las unidades ya tratadas como control de las que se tratan después, y con efectos heterogéneos en el tiempo eso puede producir estimaciones con el signo equivocado. Callaway-Sant'Anna estima efectos por cohorte y período —los ATT(g,t)— y luego los agrega con ponderaciones explícitas, evitando ese problema.

**Robustez prevista:** TWFE tradicional (`fixest`) y Sun-Abraham (`did2s`) como comparación.

### Unidades y variables

- **Nivel de tratamiento:** municipio (con agregación alternativa a departamento).
- **Unidad de análisis de los resultados:** mujeres de 18 a 55 años con al menos un hijo de 6 a 17 años en el hogar, identificadas en la GEIH mediante la variable de parentesco.
- **Variable de tratamiento:** porcentaje de matrícula oficial en jornada única por municipio y año (`cobertura_ju`).
- **Año de adopción (`gname`):** primer año en que el municipio supera un umbral de cobertura. En el código el umbral está fijado en **5%**; los municipios que nunca lo superan quedan marcados con `gname = 0` (grupo de control, "nunca tratados"), como exige el paquete `did`. El umbral es una decisión metodológica y debe someterse a prueba de robustez con valores alternativos.
- **Variables de resultado (GEIH):** participación laboral (binaria), informalidad (binaria, condicional a estar ocupada), horas semanales de trabajo remunerado e ingreso laboral mensual.

### Supuestos de identificación

1. **Tendencias paralelas.** Se verifica estimando efectos dinámicos en los períodos previos a la adopción: la ausencia de efectos pre-tratamiento significativos funciona como prueba placebo temporal.
2. **No interferencia (SUTVA).** Se examina si la implementación en un municipio afecta a sus vecinos (spillovers espaciales).
3. **Ausencia de selección endógena.** Se revisa si la adopción temprana está correlacionada con características municipales previas —desarrollo económico, capacidad fiscal, demografía— que también podrían afectar el empleo femenino.

---

## Qué hay en cada archivo

### `Codigo_Evaluacion.R`

Construcción de la **variable de tratamiento** a partir del SIMAT. Es el Paso 2 del proyecto y produce los insumos que alimentan la estimación. Va en cuatro bloques:

**1. Configuración e insumos**
Instala y carga los paquetes del proyecto. Define `carpeta`, la ruta local donde están los archivos anuales del SIMAT.

**2. Lectura y construcción del panel municipal**
- `leer_archivo()` — lee indistintamente `.dta`, `.txt` y `.csv`, porque el formato del SIMAT cambia entre años, y normaliza los nombres de columna con `janitor::clean_names()`.
- `construir_tratamiento()` — detecta la columna de matrícula (que también cambia de nombre entre años: `sedealum_cantidad` en unos, la suma de hombres y mujeres en otros), extrae el código de municipio del código de sede, e identifica la jornada única por su **código 6**. Agrega por municipio y calcula `cobertura_ju = 100 × matrícula en jornada única / matrícula total`.
- Un bucle recorre todos los archivos de la carpeta con `tryCatch()`, de modo que un archivo con estructura inesperada avisa del error sin abortar el proceso completo.
- Resultado: `tratamiento_panel.rds`, un panel municipio-año, más una tabla de expansión año a año como validación.

**3. Definición de cohortes de adopción**
Aplica el umbral del 5% para calcular el primer año de adopción de cada municipio y crea `gname` en el formato que espera el paquete `did`. Imprime la distribución de cohortes, que es literalmente la estructura del experimento natural.

**4. Agregación departamental**
Repite la lógica a nivel de departamento (`cod_dpto`, los dos primeros dígitos del código municipal), filtrando códigos inválidos. Produce `tratamiento_depto.rds` como especificación alternativa, útil si el nivel municipal resulta demasiado ruidoso.

**Salidas:** `tratamiento_panel.rds` (municipio-año) y `tratamiento_depto.rds` (departamento-año). Ninguna se versiona.

### `.gitignore`

Plantilla estándar de R. Excluye `.Rhistory`, `.RData`, `.Rproj.user/` y demás archivos de sesión de RStudio, además de los microdatos.

---

## Cómo reproducir

**Requisitos:** R (≥ 4.1, por el uso del pipe nativo `|>`) y RStudio.

```r
install.packages(c(
  "did",        # Callaway-Sant'Anna, estimador principal
  "tidyverse",  # manipulación de datos
  "data.table", # lectura rápida de archivos grandes
  "haven",      # archivos .dta y .sav del DANE
  "fixest",     # efectos fijos y TWFE, para robustez
  "janitor",    # limpieza de nombres de columnas
  "did2s"       # Sun-Abraham, para robustez
))
```

**Pasos:**

1. Descargar los archivos anuales del SIMAT desde los datos abiertos del MEN (`MEN_ESTADISTICAS-MATRICULA-POR-MUNICIPIOS`) y dejarlos todos en una misma carpeta.
2. Abrir `Codigo_Evaluacion.R` y **ajustar la variable `carpeta`** a la ruta de esa carpeta en tu equipo. La ruta que viene en el script es local y no funcionará en otra máquina.
3. Ejecutar el script. Deja `tratamiento_panel.rds` y `tratamiento_depto.rds` en el directorio de trabajo.

---

## Estado del proyecto

- [x] **Paso 1** — Configuración del entorno en R
- [x] **Paso 2** — Variable de tratamiento desde el SIMAT: panel municipio-año, cohortes de adopción y grupo de control definidos
- [ ] **Paso 3** — Descarga y unión de módulos de la GEIH
- [ ] **Paso 4** — Identificación de madres con hijos en edad escolar y construcción de variables de resultado
- [ ] **Paso 5** — Panel municipio-año con resultados
- [ ] **Paso 6** — Estimación Callaway-Sant'Anna
- [ ] **Paso 7** — Efectos dinámicos, gráficos y tablas
- [ ] **Paso 8** — Canal de cuidado con la ENUT

El repositorio contiene, por ahora, el código del Paso 2. Los resultados aún no están estimados.

---

## Limitaciones conocidas

- **Error de medición en el tratamiento.** La cobertura municipal de JUE es una aproximación a la exposición real de cada hogar: no se observa si los hijos de una madre concreta asistían a una sede con jornada única.
- **Cohortes tardías.** Las cohortes de adopción de 2021 y 2022 son pequeñas y coinciden con el período pos-pandemia, así que sus estimaciones serán más ruidosas y probablemente convenga examinarlas por separado.
- **Umbral de adopción.** El 5% es un punto medio defendible, no un valor derivado de la teoría. Requiere prueba de robustez.
- **La ENUT no es continua**, así que el análisis del mecanismo de cuidado es más grueso que el de empleo.

---

## Autor

David Alvarado — [@davaalvarado](https://github.com/davaalvarado)
Trabajo de especialización en evaluación de impacto de políticas públicas.
