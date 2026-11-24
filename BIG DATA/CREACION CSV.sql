
USE Zerrillo;
GO

SELECT
    F.id_venta,
    D.fecha,
    P.nombre_producto AS producto,
    P.categoria,
    F.cantidad_vendida AS cantidad,
    F.importe_venta AS importe,
    M.nombre_metodo AS metodo_pago
FROM FactVenta AS F
INNER JOIN DimProducto AS P
    ON F.id_producto = P.id_producto
INNER JOIN DimFecha AS D
    ON F.id_fecha = D.id_fecha
INNER JOIN DimMetodoPago AS M
    ON F.id_metodo_pago = M.id_metodo_pago
ORDER BY F.id_fact_venta;
