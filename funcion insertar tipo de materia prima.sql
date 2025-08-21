BEGIN;

-- MP: CUERO en m² (usa unidad M2 del bloque de semillas)
INSERT INTO zap.articulos (tipo,codigo,nombre,id_unidad,id_mp_tipo,id_marca,estado)
SELECT 'MP','MP-CUERO','Cuero 2mm',
       (SELECT id_unidad  FROM zap.unidades WHERE codigo='M2'),
       (SELECT id_mp_tipo FROM zap.mp_tipos WHERE codigo='CUERO'),
       (SELECT id_marca   FROM zap.marcas   WHERE nombre='Genérica'),
       'A'
ON CONFLICT (codigo) DO NOTHING;

-- (Opcional) MP: PEGANTE en litros
INSERT INTO zap.articulos (tipo,codigo,nombre,id_unidad,id_mp_tipo,id_marca,estado)
SELECT 'MP','MP-PEGANTE','Pegante base',
       (SELECT id_unidad  FROM zap.unidades WHERE codigo='LT'),
       (SELECT id_mp_tipo FROM zap.mp_tipos WHERE codigo='PEGANTE'),
       (SELECT id_marca   FROM zap.marcas   WHERE nombre='Genérica'),
       'A'
ON CONFLICT (codigo) DO NOTHING;

COMMIT;