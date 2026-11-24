
USE Zerrillo;
GO
SELECT @@VERSION AS version_sql_server;
SELECT COUNT(*) AS ventas_originales   FROM Venta;
SELECT COUNT(*) AS detalles_originales FROM DetalleVenta;
GO

--   1. AMPLIACION DE DATOS (volumen simulado)

DROP TABLE IF EXISTS DetalleVenta_Exp;
DROP TABLE IF EXISTS Venta_Exp;
GO

DECLARE @copias INT = 500;

;WITH numeros AS (
    SELECT TOP (@copias) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT
    v.id_venta + (n.n - 1) * 100000 AS id_venta,
    DATEADD(DAY, (n.n - 1) % 365, v.fecha) AS fecha,   -- reparte fechas en ~1 anio
    v.hora,
    v.id_empleado,
    v.id_metodo_pago,
    v.total
INTO Venta_Exp
FROM Venta v CROSS JOIN numeros n;

;WITH numeros AS (
    SELECT TOP (@copias) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT
    d.id_detalle + (n.n - 1) * 100000 AS id_detalle,
    d.id_venta   + (n.n - 1) * 100000 AS id_venta,
    d.id_producto,
    d.cantidad,
    d.precio_venta,
    d.subtotal
INTO DetalleVenta_Exp
FROM DetalleVenta d CROSS JOIN numeros n;
GO

-- Llaves primarias (indice agrupado), igual que las tablas originales
ALTER TABLE Venta_Exp        ALTER COLUMN id_venta   INT NOT NULL;
ALTER TABLE DetalleVenta_Exp ALTER COLUMN id_detalle INT NOT NULL;
ALTER TABLE Venta_Exp        ADD CONSTRAINT PK_Venta_Exp        PRIMARY KEY (id_venta);
ALTER TABLE DetalleVenta_Exp ADD CONSTRAINT PK_DetalleVenta_Exp PRIMARY KEY (id_detalle);
GO

SELECT COUNT(*) AS ventas_exp   FROM Venta_Exp;
SELECT COUNT(*) AS detalles_exp FROM DetalleVenta_Exp;
EXEC sp_helpindex 'Venta_Exp';
EXEC sp_helpindex 'DetalleVenta_Exp';
GO

  -- 2. MEDICION ANTES: SOLO INDICES DE LLAVE PRIMARIA
     -- (Activar "Incluir plan de ejecucion real": Ctrl+M)
  --    Ejecutar cada bloque 3 veces y anotar el promedio.
CHECKPOINT;
DBCC DROPCLEANBUFFERS;   -- solo en entorno de pruebas
DBCC FREEPROCCACHE;
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

-- CONSULTA 1: ventas por producto y mes
SELECT
    p.nombre_producto,
    YEAR(v.fecha)  AS anio,
    MONTH(v.fecha) AS mes,
    SUM(d.cantidad) AS total_cantidad,
    SUM(d.subtotal) AS total_importe
FROM DetalleVenta_Exp d
JOIN Venta_Exp v ON d.id_venta    = v.id_venta
JOIN Producto  p ON d.id_producto = p.id_producto
GROUP BY p.nombre_producto, YEAR(v.fecha), MONTH(v.fecha)
ORDER BY anio, mes, total_importe DESC;
GO

-- CONSULTA 2: ventas por categoria y metodo de pago
SELECT
    c.nombre_categoria,
    mp.nombre_metodo,
    SUM(d.subtotal)         AS total_importe,
    COUNT(DISTINCT v.id_venta) AS num_ventas
FROM DetalleVenta_Exp d
JOIN Venta_Exp    v  ON d.id_venta        = v.id_venta
JOIN Producto     p  ON d.id_producto     = p.id_producto
JOIN Categoria    c  ON p.id_categoria    = c.id_categoria
JOIN MetodoPago   mp ON v.id_metodo_pago  = mp.id_metodo_pago
GROUP BY c.nombre_categoria, mp.nombre_metodo
ORDER BY total_importe DESC;
GO

-- CONSULTA 3: filtro selectivo (rango de fechas + metodo de pago)
SELECT
    v.fecha,
    COUNT(*)     AS num_ventas,
    SUM(v.total) AS total_dia
FROM Venta_Exp v
JOIN MetodoPago mp ON v.id_metodo_pago = mp.id_metodo_pago
WHERE v.fecha BETWEEN '2026-09-03' AND '2026-09-09'
  AND mp.nombre_metodo = 'Yape'
GROUP BY v.fecha
ORDER BY v.fecha;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

 --  3. CREACION DE INDICES

CREATE NONCLUSTERED INDEX IX_DetalleExp_Venta
    ON DetalleVenta_Exp (id_venta)
    INCLUDE (id_producto, cantidad, subtotal);

CREATE NONCLUSTERED INDEX IX_DetalleExp_Producto
    ON DetalleVenta_Exp (id_producto)
    INCLUDE (id_venta, cantidad, subtotal);

CREATE NONCLUSTERED INDEX IX_VentaExp_Fecha
    ON Venta_Exp (fecha)
    INCLUDE (id_metodo_pago, total);

CREATE NONCLUSTERED INDEX IX_VentaExp_MetodoPago
    ON Venta_Exp (id_metodo_pago, fecha)
    INCLUDE (total);
GO

--Opcional

EXEC sp_helpindex 'Venta_Exp';
EXEC sp_helpindex 'DetalleVenta_Exp';
GO

  -- 4. MEDICION DESPUES (mismas 3 consultas)

CHECKPOINT;
DBCC DROPCLEANBUFFERS;
DBCC FREEPROCCACHE;
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

-- CONSULTA 1
SELECT
    p.nombre_producto,
    YEAR(v.fecha)  AS anio,
    MONTH(v.fecha) AS mes,
    SUM(d.cantidad) AS total_cantidad,
    SUM(d.subtotal) AS total_importe
FROM DetalleVenta_Exp d
JOIN Venta_Exp v ON d.id_venta    = v.id_venta
JOIN Producto  p ON d.id_producto = p.id_producto
GROUP BY p.nombre_producto, YEAR(v.fecha), MONTH(v.fecha)
ORDER BY anio, mes, total_importe DESC;
GO

-- CONSULTA 2
SELECT
    c.nombre_categoria,
    mp.nombre_metodo,
    SUM(d.subtotal)         AS total_importe,
    COUNT(DISTINCT v.id_venta) AS num_ventas
FROM DetalleVenta_Exp d
JOIN Venta_Exp    v  ON d.id_venta        = v.id_venta
JOIN Producto     p  ON d.id_producto     = p.id_producto
JOIN Categoria    c  ON p.id_categoria    = c.id_categoria
JOIN MetodoPago   mp ON v.id_metodo_pago  = mp.id_metodo_pago
GROUP BY c.nombre_categoria, mp.nombre_metodo
ORDER BY total_importe DESC;
GO

-- CONSULTA 3
SELECT
    v.fecha,
    COUNT(*)     AS num_ventas,
    SUM(v.total) AS total_dia
FROM Venta_Exp v
JOIN MetodoPago mp ON v.id_metodo_pago = mp.id_metodo_pago
WHERE v.fecha BETWEEN '2026-09-03' AND '2026-09-09'
  AND mp.nombre_metodo = 'Yape'
GROUP BY v.fecha
ORDER BY v.fecha;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

   --5. LIMPIEZA (opcional, al terminar las capturas)
-- DROP TABLE IF EXISTS DetalleVenta_Exp;
-- DROP TABLE IF EXISTS Venta_Exp;

--Extra para desactivar los indices

ALTER INDEX IX_DetalleExp_Venta    ON DetalleVenta_Exp DISABLE;
ALTER INDEX IX_DetalleExp_Producto ON DetalleVenta_Exp DISABLE;
ALTER INDEX IX_VentaExp_Fecha      ON Venta_Exp DISABLE;
ALTER INDEX IX_VentaExp_MetodoPago ON Venta_Exp DISABLE;