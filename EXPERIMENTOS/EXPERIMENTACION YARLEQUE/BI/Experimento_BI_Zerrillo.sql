/*
 PANADERIA ZERRILLO - EXPERIMENTO INDIVIDUAL BI - VERSION 3 (SEGURA)
 Fuente verificada: ETL_Panaderia_Estrella.sql, tabla dbo.FactVenta.
 OBJETIVO: 10x registros (17,670), ingresos x10 (S/ 52,005.00), 30 dias.

 IMPORTANTE:
  1) En SSMS selecciona ARRIBA la base que contiene dbo.FactVenta.
     NO ejecutes de nuevo los scripts de creacion del Data Mart ni del origen.
  2) Ejecuta ESTE archivo completo, de principio a fin.
  3) El script NO modifica FactVenta ni ninguna tabla original.
  4) Los datos experimentales se crean SOLO en dbo.ExpBI_VentasSinteticas.
  5) Si una ejecucion anterior ya creo la tabla correcta, valida sus cifras
     y no vuelve a insertar ni duplicar datos.
  6) Si existe una tabla experimental incorrecta, SE DETIENE, sin borrarla:
     revisa primero su contenido. No uses DROP sobre tablas originales.

 METODO SINTETICO: se replican 10 veces los detalles de FactVenta;
 las compras sinteticas tienen identificadores nuevos, se distribuyen
 entre 2026-09-01 y 2026-09-30, y se asignan medios de pago variados.
 Se preservan cantidad e importe de cada linea para conservar coherencia
 entre productos, unidades e ingresos (no son nuevas ventas reales).
 Las fechas y pagos son simulados; se reutilizan productos, empleados y horas.

*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '=== EXPERIMENTO BI ZERRILLO / VERSION 3 ===';
PRINT 'Base seleccionada: ' + DB_NAME();

-- 1. VERIFICACIONES PREVIAS
IF OBJECT_ID(N'dbo.FactVenta', N'U') IS NULL
    THROW 51001, 'No existe dbo.FactVenta en la base actual. Selecciona la base que contiene el Data Mart.', 1;

IF OBJECT_ID(N'dbo.DimMetodoPago', N'U') IS NULL
    THROW 51002, 'No existe dbo.DimMetodoPago en la base actual. Revisa la seleccion de base de datos.', 1;

IF EXISTS (SELECT 1 FROM dbo.FactVenta WHERE id_venta IS NULL OR id_fact_venta IS NULL
           OR cantidad_vendida IS NULL OR importe_venta IS NULL)
    THROW 51003, 'FactVenta contiene valores nulos en campos obligatorios para este experimento.', 1;

IF EXISTS (SELECT 1 FROM dbo.FactVenta WHERE importe_venta < 0 OR cantidad_vendida <= 0)
    THROW 51004, 'FactVenta tiene importes negativos o cantidades no positivas. Revisa antes de replicar.', 1;

DECLARE @OriginalRegistros BIGINT;
DECLARE @OriginalCompras BIGINT;
DECLARE @CentavosOriginales BIGINT;
DECLARE @Pagos INT;
DECLARE @RegistrosEsperados BIGINT;
DECLARE @CentavosEsperados BIGINT;

SELECT
    @OriginalRegistros = COUNT_BIG(*),
    @OriginalCompras = COUNT_BIG(DISTINCT id_venta),
    @CentavosOriginales = CONVERT(BIGINT, ROUND(SUM(CONVERT(DECIMAL(19, 2), importe_venta)) * 100, 0))
FROM dbo.FactVenta;

SELECT @Pagos = COUNT(*) FROM dbo.DimMetodoPago;

IF @OriginalRegistros = 0 OR @CentavosOriginales IS NULL OR @Pagos = 0
    THROW 51005, 'FactVenta esta vacia o faltan metodos de pago.', 1;

-- Verificacion estricta de la fuente conocida del proyecto.
-- No replicar por error una version diferente o ya ampliada del Data Mart.
IF @OriginalRegistros <> 1767 OR @CentavosOriginales <> 520050
    THROW 51006, 'Los datos de FactVenta no coinciden con 1767 registros y S/5200.50. Revisa la base seleccionada.', 1;

SET @RegistrosEsperados = @OriginalRegistros * 10;
SET @CentavosEsperados = @CentavosOriginales * 10;

PRINT 'Fuente validada: 1767 registros, S/5200.50.';

-- 2. EJECUCION REPETIBLE SIN SOBREESCRIBIR TRABAJO ANTERIOR.
IF OBJECT_ID(N'dbo.ExpBI_VentasSinteticas', N'U') IS NOT NULL
BEGIN
    PRINT 'La tabla experimental YA EXISTE. Se verifica; no se sobreescribe.';
    IF COL_LENGTH(N'dbo.ExpBI_VentasSinteticas', N'id_registro') IS NULL
       OR COL_LENGTH(N'dbo.ExpBI_VentasSinteticas', N'fecha') IS NULL
       OR COL_LENGTH(N'dbo.ExpBI_VentasSinteticas', N'importe_venta') IS NULL
       OR COL_LENGTH(N'dbo.ExpBI_VentasSinteticas', N'id_venta_sintetica') IS NULL
       THROW 51007, 'La tabla experimental existente no tiene la estructura esperada; revisala manualmente.', 1;

    DECLARE @FilasExistentes BIGINT;
    DECLARE @CentavosExistentes BIGINT;
    DECLARE @DiasExistentes INT;

    SELECT @FilasExistentes = COUNT_BIG(*),
           @CentavosExistentes = CONVERT(BIGINT, ROUND(SUM(CONVERT(DECIMAL(19,2), importe_venta)) * 100, 0)),
           @DiasExistentes = COUNT(DISTINCT fecha)
    FROM dbo.ExpBI_VentasSinteticas;

    IF @FilasExistentes <> @RegistrosEsperados
       OR @CentavosExistentes <> @CentavosEsperados
       OR @DiasExistentes <> 30
       THROW 51008, 'La tabla experimental EXISTE pero sus datos no coinciden. No se modifico; revisa antes de regenerar.', 1;

    PRINT 'Tabla existente validada. No se insertaron registros duplicados.';
END
ELSE
BEGIN
    -- 3. GENERACION EN TABLA AISLADA Y TRANSACCION CONTROLADA
    DECLARE @Semilla INT = CHECKSUM(NEWID());

    BEGIN TRY
        BEGIN TRANSACTION;

        CREATE TABLE dbo.ExpBI_VentasSinteticas (
            id_registro BIGINT NOT NULL PRIMARY KEY,
            id_venta_sintetica BIGINT NOT NULL,
            fecha DATE NOT NULL,
            id_producto INT NOT NULL,
            id_empleado INT NOT NULL,
            id_metodo_pago INT NOT NULL,
            id_hora INT NOT NULL,
            cantidad_vendida INT NOT NULL,
            importe_venta DECIMAL(12,2) NOT NULL
        );

        ;WITH Copias AS (
            SELECT replica FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) C(replica)
        ),
        Ordenes AS (
            SELECT id_venta,
                   ROW_NUMBER() OVER (ORDER BY id_venta) AS orden_n
            FROM (SELECT DISTINCT id_venta FROM dbo.FactVenta) V
        ),
        Metodos AS (
            SELECT id_metodo_pago,
                   ROW_NUMBER() OVER (ORDER BY id_metodo_pago) AS metodo_n
            FROM dbo.DimMetodoPago
        ),
        ComprasSimuladas AS (
            SELECT o.id_venta, c.replica,
                   CONVERT(BIGINT, o.id_venta) * 10 + c.replica AS id_venta_sintetica,
                   DATEADD(DAY, CONVERT(INT, ((o.orden_n - 1) * 10 + c.replica) % 30),
                           CONVERT(DATE, '20260901', 112)) AS fecha,
                   1 + ((CHECKSUM(CONCAT(o.id_venta, '-', c.replica, '-', @Semilla))
                         & 2147483647) % @Pagos) AS metodo_n
            FROM Ordenes o CROSS JOIN Copias c
        )
        INSERT INTO dbo.ExpBI_VentasSinteticas (
            id_registro, id_venta_sintetica, fecha, id_producto,
            id_empleado, id_metodo_pago, id_hora, cantidad_vendida, importe_venta
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY f.id_fact_venta, cs.replica) AS id_registro,
            cs.id_venta_sintetica,
            cs.fecha,
            f.id_producto,
            f.id_empleado,
            m.id_metodo_pago,
            f.id_hora,
            f.cantidad_vendida,
            CONVERT(DECIMAL(12,2), f.importe_venta)
        FROM dbo.FactVenta f
        INNER JOIN ComprasSimuladas cs ON cs.id_venta = f.id_venta
        INNER JOIN Metodos m ON m.metodo_n = cs.metodo_n;

        -- 4. COMPROBACION ANTES DE CONFIRMAR LA CREACION
        IF (SELECT COUNT_BIG(*) FROM dbo.ExpBI_VentasSinteticas) <> @RegistrosEsperados
           OR (SELECT CONVERT(BIGINT, ROUND(SUM(CONVERT(DECIMAL(19,2), importe_venta)) * 100, 0))
               FROM dbo.ExpBI_VentasSinteticas) <> @CentavosEsperados
           OR (SELECT COUNT(DISTINCT fecha) FROM dbo.ExpBI_VentasSinteticas) <> 30
           OR (SELECT COUNT_BIG(DISTINCT id_venta_sintetica)
               FROM dbo.ExpBI_VentasSinteticas) <> @OriginalCompras * 10
        BEGIN
            THROW 51009, 'No coinciden registros, ingresos, fechas o compras. Se revertira la creacion.', 1;
        END;

        COMMIT TRANSACTION;
        PRINT 'DATOS SINTETICOS CREADOS CORRECTAMENTE.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;

-- 5. RESULTADOS FINALES: CAPTURAR PARA EL INFORME
SELECT 'ORIGINAL' AS conjunto,
       COUNT_BIG(*) AS registros,
       COUNT(DISTINCT id_venta) AS compras,
       SUM(CONVERT(BIGINT, cantidad_vendida)) AS unidades,
       SUM(CONVERT(DECIMAL(19,2), importe_venta)) AS ingresos
FROM dbo.FactVenta
UNION ALL
SELECT 'SINTETICO_10X_30_DIAS',
       COUNT_BIG(*), COUNT(DISTINCT id_venta_sintetica),
       SUM(CONVERT(BIGINT, cantidad_vendida)),
       SUM(CONVERT(DECIMAL(19,2), importe_venta))
FROM dbo.ExpBI_VentasSinteticas;

SELECT MIN(fecha) AS fecha_inicial,
       MAX(fecha) AS fecha_final,
       COUNT(DISTINCT fecha) AS dias_cubiertos
FROM dbo.ExpBI_VentasSinteticas;

SELECT fecha,
       COUNT_BIG(*) AS registros,
       COUNT(DISTINCT id_venta_sintetica) AS compras,
       SUM(CONVERT(BIGINT, cantidad_vendida)) AS unidades,
       SUM(CONVERT(DECIMAL(19,2), importe_venta)) AS ingresos
FROM dbo.ExpBI_VentasSinteticas
GROUP BY fecha
ORDER BY fecha;

PRINT 'FIN. Tabla fuente sin cambios: dbo.FactVenta.';
