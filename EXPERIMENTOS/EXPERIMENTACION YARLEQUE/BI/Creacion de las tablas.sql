-- GENERACION DE LOS CSV --
--X10
SELECT * FROM dbo.ExpBI_VentasSinteticas
ORDER BY id_registro;
--X20
SELECT * FROM dbo.ExpBI_VentasSinteticas_20x
ORDER BY id_registro ASC;
--X50
SELECT *FROM dbo.ExpBI_VentasSinteticas_50x
ORDER BY id_registro ASC;
