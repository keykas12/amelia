BEGIN; -- Carga de catálogos base

-- Unidades (incluye PAR para PT, y decimales para MP tipo LT/KG/M2)
INSERT INTO zap.unidades (codigo,nombre,activo) VALUES
('PAR','Par',true),
('UND','Unidad',true),
('KG','Kilogramo',true),
('LT','Litro',true),
('M2','Metro cuadrado',true)
ON CONFLICT (codigo) DO NOTHING;

-- Bodegas
INSERT INTO zap.bodegas (nombre,tipo,activo) VALUES
('I1-MP','MP',true),
('I2-PT','PT',true)
ON CONFLICT (nombre) DO NOTHING;

-- Tipos de Materia Prima
INSERT INTO zap.mp_tipos (codigo,nombre) VALUES
('PEGANTE','Pegante'),
('FORRO','Forros'),
('CUERO','Cuero'),
('CERRAJES','Cerrajes')
ON CONFLICT (codigo) DO NOTHING;

-- Tallas (ajusta el rango a tu operación)
INSERT INTO zap.tallas (valor,etiqueta) VALUES
(34,'34'),(35,'35'),(36,'36'),(37,'37'),(38,'38'),(39,'39'),(40,'40')
ON CONFLICT (valor) DO NOTHING;

-- Tipos de sandalia
INSERT INTO zap.tipos_sandalia (codigo,nombre) VALUES
('PLANA','Sandalia plana'),
('PLATAFORMA','Sandalia de plataforma')
ON CONFLICT (codigo) DO NOTHING;

-- Marcas
INSERT INTO zap.marcas (nombre,activo) VALUES ('Genérica',true)
ON CONFLICT (nombre) DO NOTHING;

-- Categorías PT
INSERT INTO zap.categorias_pt (nombre,activo) VALUES ('Sandalia',true)
ON CONFLICT (nombre) DO NOTHING;

-- Subcategorías PT (ligadas a "Sandalia")
INSERT INTO zap.subcategorias_pt (id_categoria_pt, id_subcategoria_pt, nombre, activo)
SELECT c.id_categoria_pt, 1, 'Plana', true FROM zap.categorias_pt c WHERE c.nombre='Sandalia'
UNION ALL
SELECT c.id_categoria_pt, 2, 'Plataforma', true FROM zap.categorias_pt c WHERE c.nombre='Sandalia'
ON CONFLICT DO NOTHING;

-- Geografía mínima
INSERT INTO zap.departamentos (codigo,nombre,activo) VALUES
(NULL,'Antioquia',true),(NULL,'Cundinamarca',true)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO zap.ciudades (id_departamento,codigo,nombre,activo)
SELECT d.id_departamento,NULL,'Medellín',true FROM zap.departamentos d WHERE d.nombre='Antioquia'
UNION ALL
SELECT d.id_departamento,NULL,'Bogotá D.C.',true FROM zap.departamentos d WHERE d.nombre='Cundinamarca'
ON CONFLICT DO NOTHING;

-- Roles base (para tu login)
INSERT INTO zap.roles (codigo,nombre,descripcion) VALUES
('ADMIN','Administrador','Acceso total'),
('ENCARGADO','Encargado de Operaciones','Inventario/Producción/Pedidos')
ON CONFLICT (codigo) DO NOTHING;

COMMIT;
