-- Wrapper: registrar movimiento de PT usando NOMBRE de bodega, CÓDIGO de PT y CÓDIGO de variante
CREATE OR REPLACE FUNCTION zap.fn_registrar_movimiento_pt_por_codigo(
  p_bodega_nombre       text,                 -- ej: 'I2-PT'
  p_articulo_pt_codigo  text,                 -- ej: 'PT-SAND-BASIC' (PT base)
  p_pt_var_codigo       text,                 -- ej: 'SAND-PLANA-36' (SKU variante)
  p_tipo                zap.movimiento_tipo,  -- 'PRODUCCION_PT' | 'VENTA_PT' | 'AJUSTE_ENTRADA' | 'AJUSTE_SALIDA'
  p_cantidad            numeric(12,3),        -- pares (la función oficial exige enteros)
  p_doc_ref             varchar DEFAULT NULL,
  p_observacion         text    DEFAULT NULL,
  p_permitir_stock_negativo boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_id_bodega      integer;
  v_id_articulo_pt bigint;
  v_id_pt_var      bigint;
BEGIN
  -- Resolver bodega por nombre
  SELECT id_bodega INTO v_id_bodega
  FROM zap.bodegas
  WHERE nombre = p_bodega_nombre;
  IF v_id_bodega IS NULL THEN
    RAISE EXCEPTION 'Bodega "%" no existe.', p_bodega_nombre;
  END IF;

  -- Resolver artículo PT por código (y opcionalmente confirmar que sea PT)
  SELECT id_articulo INTO v_id_articulo_pt
  FROM zap.articulos
  WHERE codigo = p_articulo_pt_codigo;
  IF v_id_articulo_pt IS NULL THEN
    RAISE EXCEPTION 'Artículo PT con código "%" no existe.', p_articulo_pt_codigo;
  END IF;

  -- Resolver variante por código (SKU)
  SELECT id_pt_var INTO v_id_pt_var
  FROM zap.pt_variantes
  WHERE codigo_variante = p_pt_var_codigo;
  IF v_id_pt_var IS NULL THEN
    RAISE EXCEPTION 'Variante PT con código "%" no existe.', p_pt_var_codigo;
  END IF;

  -- Delegar en la función oficial (valida tipo bodega=PT, tipo artículo=PT, variante pertenece al PT,
  -- tipo permitido, signo, pares enteros y stock por variante)
  RETURN zap.fn_registrar_movimiento_pt(
    p_id_bodega      := v_id_bodega,
    p_id_articulo_pt := v_id_articulo_pt,
    p_id_pt_var      := v_id_pt_var,
    p_tipo           := p_tipo,
    p_cantidad       := p_cantidad,
    p_doc_ref        := p_doc_ref,
    p_observacion    := p_observacion,
    p_permitir_stock_negativo := p_permitir_stock_negativo
  );
END;
$$;
