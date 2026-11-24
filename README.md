Este proyecto desarrolla y evalúa dos soluciones complementarias para analizar las ventas de la Panadería Zerrillo:
- Business Intelligence (BI): base de datos operacional en Microsoft SQL Server, transformación ETL, Data Mart con esquema estrella (tabla de hechos FactVenta y cinco dimensiones) y tablero interactivo en Power BI.
- Big Data: ingesta, limpieza, transformación, análisis exploratorio (EDA), agregaciones, almacenamiento y visualizaciones en Databricks mediante Apache Spark y PySpark.
El objetivo es facilitar el análisis de ingresos, ventas, cantidades, productos, categorías, horarios y medios de pago, así como documentar experimentos de rendimiento y calidad realizados individualmente por el equipo.
Alcance: el proyecto estudia registros comerciales y su procesamiento analítico. No implementa un sistema de punto de venta ni un control integral de inventarios. Los datasets ampliados de experimentación son sintéticos y no representan nuevas ventas reales.

**Integrantes**
- Adrian Antonio Erazo Garcia
- Victor Manuelle Garrido Reyes
- Brayan Jhossep Martinez Zeta
- Aaron Enrique Yarleque Ramos
- Diego Aaron Zeña Paredes
  
**Tecnologías**
Componente	Tecnología	Propósito
Base operacional y Data Mart	Microsoft SQL Server / SSMS	Tablas, consultas, ETL y validaciones
BI	Microsoft Power BI Desktop	KPIs, reportes y filtros
Big Data	Databricks / Apache Spark / PySpark	DataFrames, transformaciones, agregaciones y persistencia
Experimentación	T-SQL, notebooks Python/PySpark	Medición de rendimiento, índices, particiones, formatos y calidad


**Estructura y archivos del repositorio**

Panaderia-Zerrillo-BDA/
- ├── Capturas/                   # Imágenes y evidencias publicadas
- ├── ETL_Panaderia_Estrella.sql  # Script del modelo analítico y ETL
- ├── Zerillo BD.sql              # Script de base de datos operacional
- ├── Zerrillo_Excel.xlsx         # Dataset de referencia en Excel
- ├── proyecto_bd_T2.pbix         # Dashboard Power BI
- └── README.md                   # Documentación general (este archivo)
