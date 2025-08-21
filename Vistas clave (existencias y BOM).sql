-- Existencias por ARTÍCULO y BODEGA (MP o PT base)
CREATE OR REPLACE VIEW zap.v_existencias_articulo_bodega AS
SELECT
  m.id_bodega,
  m.id_articulo,
  SUM(m.cantidad)::numeric(12,3) AS stock
FROM zap.movimientos m
GROUP BY m.id_bodega, m.id_articulo;

-- Existencias totales por ARTÍCULO (todas las bodegas)
CREATE OR REPLACE VIEW zap.v_existencias_articulo_total AS
SELECT
  a.id_articulo,
  a.tipo,
  a.codigo,
  a.nombre,
  COALESCE(SUM(m.cantidad),0)::numeric(12,3) AS stock_total
FROM zap.articulos a
LEFT JOIN zap.movimientos m ON m.id_articulo = a.id_articulo
GROUP BY a.id_articulo, a.tipo, a.codigo, a.nombre;

-- Existencias por VARIANTE de PT y BODEGA (lleva talla + tipo sandalia)
CREATE OR REPLACE VIEW zap.v_existencias_pt_var_bodega AS
SELECT
  m.id_bodega,
  m.id_pt_var,
  v.id_articulo_pt,
  SUM(m.cantidad)::numeric(12,3) AS stock
FROM zap.movimientos m
JOIN zap.pt_variantes v ON v.id_pt_var = m.id_pt_var
GROUP BY m.id_bodega, m.id_pt_var, v.id_articulo_pt;

-- Existencias totales por VARIANTE de PT (todas las bodegas)
CREATE OR REPLACE VIEW zap.v_existencias_pt_var_total AS
SELECT
  v.id_pt_var,
  v.id_articulo_pt,
  a.codigo  AS pt_codigo,
  a.nombre  AS pt_nombre,
  t.valor   AS talla,
  ts.codigo AS tipo_sandalia,
  v.codigo_variante,
  COALESCE(SUM(m.cantidad),0)::numeric(12,3) AS stock_total
FROM zap.pt_variantes v
JOIN zap.articulos a   ON a.id_articulo = v.id_articulo_pt
JOIN zap.tallas t      ON t.id_talla    = v.id_talla
JOIN zap.tipos_sandalia ts ON ts.id_tipo_sandalia = v.id_tipo_sandalia
LEFT JOIN zap.movimientos m ON m.id_pt_var = v.id_pt_var
GROUP BY v.id_pt_var, v.id_articulo_pt, a.codigo, a.nombre, t.valor, ts.codigo, v.codigo_variante;

-- Detalle de BOM (MP por par de PT)
CREATE OR REPLACE VIEW zap.v_bom_detalle AS
SELECT
  pt.id_articulo      AS pt_id,
  pt.codigo           AS pt_codigo,
  pt.nombre           AS pt_nombre,
  mp.id_articulo      AS mp_id,
  mp.codigo           AS mp_codigo,
  mp.nombre           AS mp_nombre,
  b.cantidad          AS mp_por_par,
  u.codigo            AS unidad_mp
FROM zap.bom b
JOIN zap.articulos pt ON pt.id_articulo = b.producto_pt_id
JOIN zap.articulos mp ON mp.id_articulo = b.insumo_mp_id
JOIN zap.unidades  u  ON u.id_unidad    = mp.id_unidad;

-- Requerimientos de MP por OP (expande BOM * cantidad de la OP)
CREATE OR REPLACE VIEW zap.v_op_requerimientos_mp AS
SELECT
  op.id_op,
  op.cantidad::numeric(12,3)                       AS pares_programados,
  b.insumo_mp_id                                    AS mp_id,
  a_mp.codigo                                       AS mp_codigo,
  a_mp.nombre                                       AS mp_nombre,
  (b.cantidad * op.cantidad)::numeric(12,3)         AS mp_requerido,
  u.codigo                                          AS unidad_mp
FROM zap.ordenes_produccion op
JOIN zap.bom b                 ON b.producto_pt_id = op.producto_pt_id
JOIN zap.articulos a_mp        ON a_mp.id_articulo = b.insumo_mp_id
JOIN zap.unidades  u           ON u.id_unidad      = a_mp.id_unidad;
