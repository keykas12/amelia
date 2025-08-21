-- Wrapper: registrar movimiento de MP usando NOMBRE de bodega y CÓDIGO de artículo
CREATE OR REPLACE FUNCTION zap.fn_registrar_movimiento_mp_por_codigo(
  p_bodega_nombre text,                            -- Ej: 'I1-MP'
  p_articulo_codigo text,                          -- Ej: 'MP-CUERO'
  p_tipo zap.movimiento_tipo,                      -- 'COMPRA_MP' | 'CONSUMO_MP' | 'AJUSTE_ENTRADA' | 'AJUSTE_SALIDA'
  p_cantidad numeric(12,3),                        -- Positivo para entradas; negativo para salidas
  p_doc_ref varchar DEFAULT NULL,                  -- Referencia (OC, OP, REM, etc.)
  p_observacion text DEFAULT NULL,                 -- Observación libre
  p_permitir_stock_negativo boolean DEFAULT false  -- Controla si permites salidas dejando stock < 0
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_id_bodega   integer;                           -- Guardará el id_bodega encontrado por nombre
  v_id_articulo bigint;                            -- Guardará el id_articulo encontrado por código
BEGIN
  -- 1) Resolver id_bodega a partir del nombre
  SELECT id_bodega INTO v_id_bodega
  FROM zap.bodegas
  WHERE nombre = p_bodega_nombre;
  IF v_id_bodega IS NULL THEN
    RAISE EXCEPTION 'Bodega "%" no existe.', p_bodega_nombre;
  END IF;

  -- 2) Resolver id_articulo a partir del código
  SELECT id_articulo INTO v_id_articulo
  FROM zap.articulos
  WHERE codigo = p_articulo_codigo;
  IF v_id_articulo IS NULL THEN
    RAISE EXCEPTION 'Artículo con código "%" no existe.', p_articulo_codigo;
  END IF;

  -- 3) Delegar en la función “oficial” que valida todo y hace el INSERT
  RETURN zap.fn_registrar_movimiento_mp(
    p_id_bodega   := v_id_bodega,
    p_id_articulo := v_id_articulo,
    p_tipo        := p_tipo,
    p_cantidad    := p_cantidad,
    p_doc_ref     := p_doc_ref,
    p_observacion := p_observacion,
    p_permitir_stock_negativo := p_permitir_stock_negativo
  );
END;
$$;
