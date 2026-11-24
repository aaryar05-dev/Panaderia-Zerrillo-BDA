CREATE TABLE DimFecha (
    id_fecha INT PRIMARY KEY,
    fecha DATE,
    dia INT,
    mes INT,
    nombre_mes VARCHAR(20),
    trimestre INT,
    anio INT
)
CREATE TABLE DimProducto (
    id_producto INT PRIMARY KEY,
    nombre_producto VARCHAR(50),
    categoria VARCHAR(50),
    precio DECIMAL(5,2),
    estado VARCHAR(13)
)
CREATE TABLE DimEmpleado (
    id_empleado INT PRIMARY KEY,
    nombre VARCHAR(50),
    apellido VARCHAR(50),
    cargo VARCHAR(30)
)
CREATE TABLE DimMetodoPago (
    id_metodo_pago INT PRIMARY KEY,
    nombre_metodo VARCHAR(30)
)
CREATE TABLE DimHora (
    id_hora INT PRIMARY KEY,
    hora_numero INT,
    turno VARCHAR(20)
)
CREATE TABLE FactVenta (
    id_fact_venta INT IDENTITY(1,1) PRIMARY KEY,

    id_venta INT,
    id_fecha INT,
    id_producto INT,
    id_empleado INT,
    id_metodo_pago INT,
    id_hora INT,

    cantidad_vendida INT,
    importe_venta DECIMAL(10,2),

    FOREIGN KEY (id_fecha)
        REFERENCES DimFecha(id_fecha),

    FOREIGN KEY (id_producto)
        REFERENCES DimProducto(id_producto),

    FOREIGN KEY (id_empleado)
        REFERENCES DimEmpleado(id_empleado),

    FOREIGN KEY (id_metodo_pago)
        REFERENCES DimMetodoPago(id_metodo_pago),

    FOREIGN KEY (id_hora)
        REFERENCES DimHora(id_hora)
)
-----------CARGAR DIMENSIONES CON LIMPIEZA DE DATOS-----------

-- 1. DIMENSION PRODUCTO
-- Quita espacios, evita IDs repetidos y no carga campos obligatorios nulos.
;WITH ProductosLimpios AS
(
    SELECT
        p.id_producto,
        NULLIF(LTRIM(RTRIM(p.nombre_producto)), '') AS nombre_producto,
        COALESCE(NULLIF(LTRIM(RTRIM(c.nombre_categoria)), ''), 'No especificado') AS categoria,
        p.precio,
        COALESCE(NULLIF(LTRIM(RTRIM(p.estado)), ''), 'No especificado') AS estado,
        ROW_NUMBER() OVER
        (
            PARTITION BY p.id_producto
            ORDER BY p.id_producto
        ) AS fila
    FROM Zerrillo.dbo.Producto p
    LEFT JOIN Zerrillo.dbo.Categoria c
        ON p.id_categoria = c.id_categoria
)
INSERT INTO DimProducto
(
    id_producto, nombre_producto, categoria, precio, estado
)
SELECT
    id_producto, nombre_producto, categoria, precio, estado
FROM ProductosLimpios
WHERE fila = 1
  AND id_producto IS NOT NULL
  AND nombre_producto IS NOT NULL
  AND precio IS NOT NULL
  AND precio >= 0;

-----------------------------------------
-- 2. DIMENSION EMPLEADO
-- Limpia espacios, reemplaza datos opcionales vacíos y evita IDs repetidos.
;WITH EmpleadosLimpios AS
(
    SELECT
        id_empleado,
        NULLIF(LTRIM(RTRIM(nombre)), '') AS nombre,
        COALESCE(NULLIF(LTRIM(RTRIM(apellido)), ''), 'No especificado') AS apellido,
        COALESCE(NULLIF(LTRIM(RTRIM(cargo)), ''), 'No especificado') AS cargo,
        ROW_NUMBER() OVER
        (
            PARTITION BY id_empleado
            ORDER BY id_empleado
        ) AS fila
    FROM Zerrillo.dbo.Empleado
)
INSERT INTO DimEmpleado
(
    id_empleado, nombre, apellido, cargo
)
SELECT
    id_empleado, nombre, apellido, cargo
FROM EmpleadosLimpios
WHERE fila = 1
  AND id_empleado IS NOT NULL
  AND nombre IS NOT NULL;

--------------------------------------
-- 3. DIMENSION METODO DE PAGO
-- Quita espacios, evita IDs repetidos y excluye nombres vacíos.
;WITH MetodosLimpios AS
(
    SELECT
        id_metodo_pago,
        NULLIF(LTRIM(RTRIM(nombre_metodo)), '') AS nombre_metodo,
        ROW_NUMBER() OVER
        (
            PARTITION BY id_metodo_pago
            ORDER BY id_metodo_pago
        ) AS fila
    FROM Zerrillo.dbo.MetodoPago
)
INSERT INTO DimMetodoPago
(
    id_metodo_pago, nombre_metodo
)
SELECT
    id_metodo_pago, nombre_metodo
FROM MetodosLimpios
WHERE fila = 1
  AND id_metodo_pago IS NOT NULL
  AND nombre_metodo IS NOT NULL;

---------------------------
-- 4. DIMENSION FECHA
-- DISTINCT evita fechas repetidas y se excluyen fechas nulas.
INSERT INTO DimFecha
(
    id_fecha, fecha, dia, mes, nombre_mes, trimestre, anio
)
SELECT DISTINCT
    CONVERT(INT, CONVERT(CHAR(8), fecha, 112)),
    fecha,
    DAY(fecha),
    MONTH(fecha),
    DATENAME(MONTH, fecha),
    DATEPART(QUARTER, fecha),
    YEAR(fecha)
FROM Zerrillo.dbo.Venta
WHERE fecha IS NOT NULL;

----------------------------
-- 5. DIMENSION HORA
-- Excluye horas nulas y evita horas repetidas.
INSERT INTO DimHora
(
    id_hora, hora_numero, turno
)
SELECT DISTINCT
    DATEPART(HOUR, hora),
    DATEPART(HOUR, hora),
    CASE
        WHEN DATEPART(HOUR, hora) < 12 THEN 'Mañana'
        WHEN DATEPART(HOUR, hora) < 18 THEN 'Tarde'
        ELSE 'Noche'
    END
FROM Zerrillo.dbo.Venta
WHERE hora IS NOT NULL;

----------------------------
-- 6. TABLA DE HECHOS
-- Carga solo ventas relacionadas con todas las dimensiones.
-- Recalcula el subtotal si viene nulo; excluye cantidades inválidas.
-- DISTINCT evita duplicados exactos en las columnas cargadas.
INSERT INTO FactVenta
(
    id_venta, id_fecha, id_producto, id_empleado,
    id_metodo_pago, id_hora, cantidad_vendida, importe_venta
)
SELECT DISTINCT
    v.id_venta,
    CONVERT(INT, CONVERT(CHAR(8), v.fecha, 112)) AS id_fecha,
    dv.id_producto,
    v.id_empleado,
    v.id_metodo_pago,
    DATEPART(HOUR, v.hora) AS id_hora,
    dv.cantidad,
    COALESCE(dv.subtotal, dv.cantidad * dv.precio_venta) AS importe_venta
FROM Zerrillo.dbo.Venta v
INNER JOIN Zerrillo.dbo.DetalleVenta dv
    ON v.id_venta = dv.id_venta
INNER JOIN DimFecha df
    ON df.id_fecha = CONVERT(INT, CONVERT(CHAR(8), v.fecha, 112))
INNER JOIN DimProducto dp
    ON dp.id_producto = dv.id_producto
INNER JOIN DimEmpleado de
    ON de.id_empleado = v.id_empleado
INNER JOIN DimMetodoPago dm
    ON dm.id_metodo_pago = v.id_metodo_pago
INNER JOIN DimHora dh
    ON dh.id_hora = DATEPART(HOUR, v.hora)
WHERE v.id_venta IS NOT NULL
  AND v.fecha IS NOT NULL
  AND v.hora IS NOT NULL
  AND dv.cantidad IS NOT NULL
  AND dv.cantidad > 0
  AND dv.precio_venta IS NOT NULL
  AND dv.precio_venta >= 0
  AND COALESCE(dv.subtotal, dv.cantidad * dv.precio_venta) >= 0;

-----------------------------------------
-- 7. CONSULTAS PARA COMPROBAR LA LIMPIEZA
-- Estos SELECT muestran posibles nulos y duplicados en las tablas destino.

SELECT 'DimProducto' AS tabla, COUNT(*) AS registros FROM DimProducto
UNION ALL
SELECT 'DimEmpleado', COUNT(*) FROM DimEmpleado
UNION ALL
SELECT 'DimMetodoPago', COUNT(*) FROM DimMetodoPago
UNION ALL
SELECT 'DimFecha', COUNT(*) FROM DimFecha
UNION ALL
SELECT 'DimHora', COUNT(*) FROM DimHora
UNION ALL
SELECT 'FactVenta', COUNT(*) FROM FactVenta;

-- Comprobar si hay valores nulos en columnas obligatorias.
SELECT * FROM DimProducto
WHERE nombre_producto IS NULL OR precio IS NULL;

SELECT * FROM DimEmpleado
WHERE nombre IS NULL;

SELECT * FROM DimMetodoPago
WHERE nombre_metodo IS NULL;

SELECT * FROM FactVenta
WHERE id_venta IS NULL
   OR id_fecha IS NULL
   OR id_producto IS NULL
   OR id_empleado IS NULL
   OR id_metodo_pago IS NULL
   OR id_hora IS NULL
   OR cantidad_vendida IS NULL
   OR importe_venta IS NULL;

-- Comprobar duplicados por clave de cada dimensión.
SELECT id_producto, COUNT(*) AS repeticiones
FROM DimProducto
GROUP BY id_producto
HAVING COUNT(*) > 1;

SELECT id_empleado, COUNT(*) AS repeticiones
FROM DimEmpleado
GROUP BY id_empleado
HAVING COUNT(*) > 1;

SELECT id_metodo_pago, COUNT(*) AS repeticiones
FROM DimMetodoPago
GROUP BY id_metodo_pago
HAVING COUNT(*) > 1;

SELECT id_fecha, COUNT(*) AS repeticiones
FROM DimFecha
GROUP BY id_fecha
HAVING COUNT(*) > 1;

SELECT id_hora, COUNT(*) AS repeticiones
FROM DimHora
GROUP BY id_hora
HAVING COUNT(*) > 1;

-------------
SELECT * FROM Producto

SELECT * FROM Venta

SELECT *FROM DetalleVenta

SELECT * FROM Categoria

SELECT * FROM MetodoPago

SELECT * FROM Empleado
-------------
SELECT
    COUNT(*) AS registros_factventa,
    SUM(cantidad_vendida) AS productos_vendidos,
    SUM(importe_venta) AS importe_total
FROM FactVenta;