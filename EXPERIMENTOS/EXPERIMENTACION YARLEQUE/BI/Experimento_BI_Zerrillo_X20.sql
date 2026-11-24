/*
 PANADERIA ZERRILLO - EXPERIMENTO INDIVIDUAL BI - ESCENARIO 20X
 Archivo independiente: crea o valida SOLO dbo.ExpBI_VentasSinteticas_20x
 Origen: dbo.FactVenta (1767 registros). No modifica FactVenta ni otras tablas.
 Objetivo: 35,340 registros, 98,980 unidades, S/ 104,010.00,
           26,440 compras sintéticas y 30 días (2026-09-01 a 2026-09-30).
 Los datos son SINTETICOS, replicados para medir rendimiento, NO ventas reales.
 Si la tabla ya existe y es válida: no duplica ni sobrescribe.
 Si la tabla existe con valores incompatibles: se detiene sin modificarla.
 IMPORTANTE: seleccionar previamente la base que contiene dbo.FactVenta en SSMS.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FactVenta',N'U') IS NULL
    THROW 52001, 'No existe dbo.FactVenta en la base seleccionada.', 1;
IF OBJECT_ID(N'dbo.DimMetodoPago',N'U') IS NULL
    THROW 52002, 'No existe dbo.DimMetodoPago en la base seleccionada.', 1;
IF (SELECT COUNT_BIG(*) FROM dbo.FactVenta) <> 1767
    THROW 52003, 'FactVenta no tiene los 1767 registros esperados. No se han creado tablas.', 1;
IF (SELECT CONVERT(BIGINT, ROUND(SUM(CONVERT(DECIMAL(19,2), importe_venta))*100,0)) FROM dbo.FactVenta) <> 520050
    THROW 52004, 'FactVenta no totaliza S/5200.50. No se han creado tablas.', 1;
IF EXISTS (SELECT 1 FROM dbo.FactVenta WHERE id_venta IS NULL OR id_fact_venta IS NULL OR id_producto IS NULL
    OR id_empleado IS NULL OR id_hora IS NULL OR cantidad_vendida IS NULL OR importe_venta IS NULL
    OR cantidad_vendida <= 0 OR importe_venta < 0)
    THROW 52005, 'FactVenta contiene nulos o valores invalidos.', 1;
IF (SELECT COUNT(*) FROM dbo.DimMetodoPago) = 0
    THROW 52006, 'DimMetodoPago no contiene metodos.', 1;

DECLARE @factor INT = 20;
    DECLARE @nombre SYSNAME = N'ExpBI_VentasSinteticas_20x';
    DECLARE @tabla NVARCHAR(260) = N'dbo.' + QUOTENAME(@nombre);
    DECLARE @filas BIGINT;
    DECLARE @centavos BIGINT;
    DECLARE @compras BIGINT;
    DECLARE @dias INT;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @esperadas BIGINT = CONVERT(BIGINT,1767) * @factor;
    DECLARE @centavosEsperados BIGINT = CONVERT(BIGINT,520050) * @factor;
    DECLARE @comprasEsperadas BIGINT = CONVERT(BIGINT,1322) * @factor;

    PRINT CONCAT('--- INICIO ', @factor, 'x en ', @tabla, ' ---');
    IF OBJECT_ID(@tabla, N'U') IS NOT NULL
    BEGIN
        IF COL_LENGTH(@tabla,N'id_registro') IS NULL OR COL_LENGTH(@tabla,N'id_venta_sintetica') IS NULL
           OR COL_LENGTH(@tabla,N'fecha') IS NULL OR COL_LENGTH(@tabla,N'importe_venta') IS NULL
           OR COL_LENGTH(@tabla,N'cantidad_vendida') IS NULL
            THROW 52007, 'La tabla de salida existe con columnas diferentes. Se detuvo sin modificar.', 1;
        SET @sql = N'SELECT @n=COUNT_BIG(*), @c=CONVERT(BIGINT,ROUND(SUM(CONVERT(DECIMAL(19,2),importe_venta))*100,0)),
              @v=COUNT_BIG(DISTINCT id_venta_sintetica), @d=COUNT(DISTINCT fecha) FROM ' + @tabla;
        EXEC sp_executesql @sql,
            N'@n BIGINT OUTPUT,@c BIGINT OUTPUT,@v BIGINT OUTPUT,@d INT OUTPUT',
            @n=@filas OUTPUT,@c=@centavos OUTPUT,@v=@compras OUTPUT,@d=@dias OUTPUT;
        IF @filas<>@esperadas OR @centavos<>@centavosEsperados OR @compras<>@comprasEsperadas OR @dias<>30
            THROW 52008, 'La tabla de salida ya existe, pero no coincide con el escenario esperado. No se altero.', 1;
        PRINT CONCAT('Tabla ', @tabla, ' existente y validada. Sin inserciones nuevas.');
    END
    ELSE
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            SET @sql=N'
              CREATE TABLE ' + @tabla + N' (
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
              ;WITH Digitos AS (
                SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(n)
              ),
              Replicas AS (
                SELECT (d1.n + d2.n * 10) AS replica
                FROM Digitos d1 CROSS JOIN Digitos d2
                WHERE (d1.n + d2.n * 10) < @multiplicador
              ),
              Ordenes AS (
                SELECT id_venta, ROW_NUMBER() OVER (ORDER BY id_venta) AS orden_n
                FROM (SELECT DISTINCT id_venta FROM dbo.FactVenta) v
              ),
              Metodos AS (
                SELECT id_metodo_pago,ROW_NUMBER() OVER (ORDER BY id_metodo_pago) AS metodo_n
                FROM dbo.DimMetodoPago
              ),
              Compras AS (
                SELECT o.id_venta, r.replica,
                   CONVERT(BIGINT,o.id_venta)*100 + r.replica AS id_venta_sintetica,
                   DATEADD(DAY,CONVERT(INT,((o.orden_n - 1)*@multiplicador + r.replica)%30),CONVERT(DATE,''20260901'',112)) AS fecha,
                   1 + CONVERT(INT, (CONVERT(BIGINT,o.orden_n)+r.replica) % @numMetodos) AS metodo_n
                FROM Ordenes o CROSS JOIN Replicas r
              )
              INSERT INTO ' + @tabla + N' (
                id_registro,id_venta_sintetica,fecha,id_producto,id_empleado,
                id_metodo_pago,id_hora,cantidad_vendida,importe_venta)
              SELECT ROW_NUMBER() OVER (ORDER BY f.id_fact_venta,c.replica),
                 c.id_venta_sintetica,c.fecha,f.id_producto,f.id_empleado,
                 m.id_metodo_pago,f.id_hora,f.cantidad_vendida,CONVERT(DECIMAL(12,2),f.importe_venta)
              FROM dbo.FactVenta f
              JOIN Compras c ON c.id_venta=f.id_venta
              JOIN Metodos m ON m.metodo_n=c.metodo_n;';
            DECLARE @numMetodos INT = (SELECT COUNT(*) FROM dbo.DimMetodoPago);
            EXEC sp_executesql @sql, N'@multiplicador INT,@numMetodos INT', @multiplicador=@factor, @numMetodos=@numMetodos;

            SET @sql=N'SELECT @n=COUNT_BIG(*),@c=CONVERT(BIGINT,ROUND(SUM(CONVERT(DECIMAL(19,2),importe_venta))*100,0)),
               @v=COUNT_BIG(DISTINCT id_venta_sintetica),@d=COUNT(DISTINCT fecha) FROM ' + @tabla;
            EXEC sp_executesql @sql,
                N'@n BIGINT OUTPUT,@c BIGINT OUTPUT,@v BIGINT OUTPUT,@d INT OUTPUT',
                @n=@filas OUTPUT,@c=@centavos OUTPUT,@v=@compras OUTPUT,@d=@dias OUTPUT;
            IF @filas<>@esperadas OR @centavos<>@centavosEsperados OR @compras<>@comprasEsperadas OR @dias<>30
                THROW 52009, 'Validacion fallida: se revertira la creacion de la tabla sintetica.', 1;
            COMMIT TRANSACTION;
            PRINT CONCAT('Tabla ', @tabla, ' creada y validada.');
        END TRY
        BEGIN CATCH
            IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END;

-- Resultado del escenario actual.
SELECT '20X' AS escenario, COUNT_BIG(*) AS registros,
       COUNT(DISTINCT id_venta_sintetica) AS compras,
       SUM(CONVERT(BIGINT,cantidad_vendida)) AS unidades,
       SUM(CONVERT(DECIMAL(19,2),importe_venta)) AS ingresos,
       MIN(fecha) AS fecha_inicial, MAX(fecha) AS fecha_final, COUNT(DISTINCT fecha) AS dias_cubiertos
FROM dbo.ExpBI_VentasSinteticas_20x;

-- Datos de muestra sin alterar la tabla.
SELECT TOP (20) * FROM dbo.ExpBI_VentasSinteticas_20x ORDER BY id_registro;
