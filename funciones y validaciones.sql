BEGIN;                                                    -- Transacción: todo o nada
SET search_path = zap, public;                            -- Trabajar en el esquema zap

/* =======================================================
   1) UTILIDADES DE STOCK (reutilizadas en validaciones)
   ======================================================= */

-- Stock total por ARTÍCULO en una BODEGA (MP o PT base; suma todos los movimientos del artículo)
CREATE OR REPLACE FUNCTION zap.fn_stock_bodega_articulo(
  p_id_bodega   integer,
  p_id_articulo bigint
) RETURNS numeric(12,3)
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(m.cantidad),0)::numeric(12,3)
  FROM zap.movimientos m
  WHERE m.id_bodega = p_id_bodega
    AND m.id_articulo = p_id_articulo;
$$;                                                       -- Fin fn_stock_bodega_articulo


-- Stock total por VARIANTE de PT en una BODEGA (lleva talla + tipo de sandalia)
CREATE OR REPLACE FUNCTION zap.fn_stock_bodega_pt_var(
  p_id_bodega integer,
  p_id_pt_var bigint
) RETURNS numeric(12,3)
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(m.cantidad),0)::numeric(12,3)
  FROM zap.movimientos m
  WHERE m.id_bodega = p_id_bodega
    AND m.id_pt_var = p_id_pt_var;
$$;                                                       -- Fin fn_stock_bodega_pt_var


/* =======================================================
   2) MOVIMIENTOS DE MP (COMPRA / CONSUMO / AJUSTES)
   ======================================================= */
-- Registra un movimiento de MP con validaciones de:
-- - existencia de bodega y artículo
-- - bodega.tipo = 'MP' y artículo.tipo = 'MP'
-- - tipo de movimiento permitido
-- - signo de cantidad según el tipo
-- - stock suficiente para salidas (si p_permitir_stock_negativo = false)
CREATE OR REPLACE FUNCTION zap.fn_registrar_movimiento_mp(
  p_id_bodega   integer,
  p_id_articulo bigint,
  p_tipo        zap.movimiento_tipo,
  p_cantidad    numeric(12,3),
  p_doc_ref     varchar DEFAULT NULL,
  p_observacion text    DEFAULT NULL,
  p_permitir_stock_negativo boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_bodega_tipo zap.bodega_tipo;                          -- Tipo de bodega encontrada
  v_articulo_tipo zap.articulo_tipo;                      -- Tipo de artículo encontrado
  v_stock_actual numeric(12,3);                           -- Stock actual en la bodega para el artículo
  v_id_mov bigint;                                        -- ID del movimiento insertado
BEGIN
  -- 1) Validar existencia y tipo de bodega
  SELECT b.tipo INTO v_bodega_tipo
  FROM zap.bodegas b
  WHERE b.id_bodega = p_id_bodega;
  IF v_bodega_tipo IS NULL THEN
    RAISE EXCEPTION 'Bodega % no existe.', p_id_bodega
      USING HINT = 'Cree la bodega en zap.bodegas antes de registrar movimientos.';
  END IF;
  IF v_bodega_tipo <> 'MP' THEN
    RAISE EXCEPTION 'La bodega % no es de tipo MP.', p_id_bodega
      USING HINT = 'Para MP, use bodegas con tipo = MP.';
  END IF;

  -- 2) Validar existencia y tipo de artículo
  SELECT a.tipo INTO v_articulo_tipo
  FROM zap.articulos a
  WHERE a.id_articulo = p_id_articulo;
  IF v_articulo_tipo IS NULL THEN
    RAISE EXCEPTION 'Artículo % no existe.', p_id_articulo
      USING HINT = 'Cree el artículo en zap.articulos.';
  END IF;
  IF v_articulo_tipo <> 'MP' THEN
    RAISE EXCEPTION 'El artículo % no es Materia Prima (MP).', p_id_articulo
      USING HINT = 'Para esta función, el artículo debe tener tipo = MP.';
  END IF;

  -- 3) Validar tipo de movimiento permitido para MP
  IF p_tipo NOT IN ('COMPRA_MP','CONSUMO_MP','AJUSTE_ENTRADA','AJUSTE_SALIDA') THEN
    RAISE EXCEPTION 'Tipo de movimiento % no permitido para MP.', p_tipo
      USING HINT = 'Permitidos: COMPRA_MP, CONSUMO_MP, AJUSTE_ENTRADA, AJUSTE_SALIDA.';
  END IF;

  -- 4) Validar signo de cantidad según el tipo
  IF p_tipo IN ('COMPRA_MP','AJUSTE_ENTRADA') AND p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser > 0 para %.', p_tipo;
  ELSIF p_tipo IN ('CONSUMO_MP','AJUSTE_SALIDA') AND p_cantidad >= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser < 0 para %.', p_tipo;
  END IF;

  -- 5) Validar stock para salidas si no se permite negativo
  IF (NOT p_permitir_stock_negativo) AND p_cantidad < 0 THEN
    v_stock_actual := zap.fn_stock_bodega_articulo(p_id_bodega, p_id_articulo);
    IF v_stock_actual + p_cantidad < 0 THEN
      RAISE EXCEPTION 'Stock insuficiente: stock=%, intento=% (bodega %, artículo %).',
        v_stock_actual, p_cantidad, p_id_bodega, p_id_articulo
        USING HINT = 'Active p_permitir_stock_negativo=true si desea permitirlo.';
    END IF;
  END IF;

  -- 6) Insertar movimiento (en MP nunca debe ir id_pt_var)
  INSERT INTO zap.movimientos (fecha,id_bodega,id_articulo,id_pt_var,tipo,cantidad,doc_ref,observacion)
  VALUES (now(), p_id_bodega, p_id_articulo, NULL, p_tipo, p_cantidad, p_doc_ref, p_observacion)
  RETURNING id_mov INTO v_id_mov;

  RETURN v_id_mov;                                        -- OK: devuelve el id del movimiento
END;
$$;                                                       -- Fin fn_registrar_movimiento_mp


/* =======================================================
   3) MOVIMIENTOS DE PT (PRODUCCIÓN / VENTA / AJUSTES)
   ======================================================= */
-- Registra un movimiento de PT con validaciones de:
-- - existencia de bodega/artículo/variante y coherencia entre ellos
-- - bodega.tipo = 'PT' y artículo.tipo = 'PT'
-- - variante pertenece al artículo PT
-- - tipo de movimiento permitido
-- - signo de cantidad según el tipo
-- - pares enteros (sin decimales) para PT
-- - stock suficiente por VARIANTE para salidas (si p_permitir_stock_negativo = false)
CREATE OR REPLACE FUNCTION zap.fn_registrar_movimiento_pt(
  p_id_bodega      integer,
  p_id_articulo_pt bigint,
  p_id_pt_var      bigint,
  p_tipo           zap.movimiento_tipo,
  p_cantidad       numeric(12,3),
  p_doc_ref        varchar DEFAULT NULL,
  p_observacion    text    DEFAULT NULL,
  p_permitir_stock_negativo boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_bodega_tipo zap.bodega_tipo;                          -- Tipo de bodega
  v_articulo_tipo zap.articulo_tipo;                      -- Tipo de artículo
  v_var_ok boolean;                                       -- ¿La variante pertenece al artículo?
  v_stock_var numeric(12,3);                              -- Stock actual por variante en la bodega
  v_id_mov bigint;                                        -- ID del movimiento insertado
BEGIN
  -- 1) Validar bodega
  SELECT b.tipo INTO v_bodega_tipo
  FROM zap.bodegas b
  WHERE b.id_bodega = p_id_bodega;
  IF v_bodega_tipo IS NULL THEN
    RAISE EXCEPTION 'Bodega % no existe.', p_id_bodega;
  END IF;
  IF v_bodega_tipo <> 'PT' THEN
    RAISE EXCEPTION 'La bodega % no es de tipo PT.', p_id_bodega
      USING HINT = 'Para PT, use bodegas con tipo = PT.';
  END IF;

  -- 2) Validar artículo PT
  SELECT a.tipo INTO v_articulo_tipo
  FROM zap.articulos a
  WHERE a.id_articulo = p_id_articulo_pt;
  IF v_articulo_tipo IS NULL THEN
    RAISE EXCEPTION 'Artículo PT % no existe.', p_id_articulo_pt;
  END IF;
  IF v_articulo_tipo <> 'PT' THEN
    RAISE EXCEPTION 'El artículo % no es Producto Terminado (PT).', p_id_articulo_pt;
  END IF;

  -- 3) Validar variante y pertenencia al artículo
  SELECT EXISTS(
           SELECT 1
           FROM zap.pt_variantes v
           WHERE v.id_pt_var = p_id_pt_var
             AND v.id_articulo_pt = p_id_articulo_pt
         )
  INTO v_var_ok;
  IF NOT v_var_ok THEN
    RAISE EXCEPTION 'La variante % no pertenece al artículo PT %.', p_id_pt_var, p_id_articulo_pt
      USING HINT = 'Revise zap.pt_variantes.id_articulo_pt.';
  END IF;

  -- 4) Validar tipo de movimiento permitido para PT
  IF p_tipo NOT IN ('PRODUCCION_PT','VENTA_PT','AJUSTE_ENTRADA','AJUSTE_SALIDA') THEN
    RAISE EXCEPTION 'Tipo de movimiento % no permitido para PT.', p_tipo
      USING HINT = 'Permitidos: PRODUCCION_PT, VENTA_PT, AJUSTE_ENTRADA, AJUSTE_SALIDA.';
  END IF;

  -- 5) Validar signo de cantidad según el tipo
  IF p_tipo IN ('PRODUCCION_PT','AJUSTE_ENTRADA') AND p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser > 0 para %.', p_tipo;
  ELSIF p_tipo IN ('VENTA_PT','AJUSTE_SALIDA') AND p_cantidad >= 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser < 0 para %.', p_tipo;
  END IF;

  -- 6) Validar que PT sean pares enteros (sin decimales)
  IF p_cantidad <> ROUND(p_cantidad, 0) THEN
    RAISE EXCEPTION 'PT se gestiona en pares enteros. Cantidad % no es entera.', p_cantidad
      USING HINT = 'Envíe cantidades como 1, 2, 3 ...';
  END IF;

  -- 7) Validar stock por VARIANTE para salidas si no se permite negativo
  IF (NOT p_permitir_stock_negativo) AND p_cantidad < 0 THEN
    v_stock_var := zap.fn_stock_bodega_pt_var(p_id_bodega, p_id_pt_var);
    IF v_stock_var + p_cantidad < 0 THEN
      RAISE EXCEPTION 'Stock de variante insuficiente: stock=%, intento=% (bodega %, pt_var %).',
        v_stock_var, p_cantidad, p_id_bodega, p_id_pt_var
        USING HINT = 'Active p_permitir_stock_negativo=true si desea permitirlo.';
    END IF;
  END IF;

  -- 8) Insertar movimiento (en PT siempre se registra la variante)
  INSERT INTO zap.movimientos (fecha,id_bodega,id_articulo,id_pt_var,tipo,cantidad,doc_ref,observacion)
  VALUES (now(), p_id_bodega, p_id_articulo_pt, p_id_pt_var, p_tipo, p_cantidad, p_doc_ref, p_observacion)
  RETURNING id_mov INTO v_id_mov;

  RETURN v_id_mov;                                        -- OK
END;
$$;                                                       -- Fin fn_registrar_movimiento_pt

COMMIT;                                                   -- Cierra la transacción
