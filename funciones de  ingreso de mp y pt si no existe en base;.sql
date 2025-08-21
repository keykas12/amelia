BEGIN;
SET search_path = zap, public;

-- =======================================================
-- 1) CREAR MP (Materia Prima)
--    - Usa códigos de catálogo: unidad (ej. 'KG','LT','M2'), tipo MP (ej. 'CUERO','PEGANTE')
--    - Marca por nombre (opcional)
--    - Valida duplicados, existencia de catálogos y estado
-- =======================================================
CREATE OR REPLACE FUNCTION zap.fn_crear_mp(
  p_codigo           varchar,        -- Código único del MP, ej: 'MP-CUERO-2MM'
  p_nombre           varchar,        -- Nombre/descripcion del MP
  p_unidad_codigo    varchar,        -- Código de unidad: 'KG','LT','M2','UND', etc.
  p_mp_tipo_codigo   varchar,        -- Código tipo MP: 'CUERO','PEGANTE','FORRO','CERRAJES'
  p_marca_nombre     varchar DEFAULT NULL,  -- Nombre de marca (opcional; debe existir si se envía)
  p_estado           char(1) DEFAULT 'A'    -- 'A' Activo | 'I' Inactivo
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_id_unidad   integer;            -- id de la unidad
  v_id_mp_tipo  integer;            -- id del tipo MP
  v_id_marca    integer;            -- id de marca (opcional)
  v_id_existente bigint;            -- para validar duplicado de código
  v_id_articulo bigint;             -- id del nuevo artículo
BEGIN
  -- 0) Validaciones básicas de entrada
  IF p_codigo IS NULL OR btrim(p_codigo) = '' THEN
    RAISE EXCEPTION 'El código del MP es obligatorio.';
  END IF;
  IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
    RAISE EXCEPTION 'El nombre del MP es obligatorio.';
  END IF;
  IF p_estado NOT IN ('A','I') THEN
    RAISE EXCEPTION 'Estado inválido "%". Use A o I.', p_estado;
  END IF;

  -- 1) Código no duplicado
  SELECT id_articulo INTO v_id_existente
  FROM zap.articulos
  WHERE codigo = p_codigo;
  IF v_id_existente IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe un artículo con código "%".', p_codigo
      USING HINT = 'El código debe ser único en zap.articulos.';
  END IF;

  -- 2) Resolver unidad por código y validar activa
  SELECT u.id_unidad
    INTO v_id_unidad
  FROM zap.unidades u
  WHERE u.codigo = p_unidad_codigo AND u.activo = true;
  IF v_id_unidad IS NULL THEN
    RAISE EXCEPTION 'Unidad "%" no existe o está inactiva.', p_unidad_codigo;
  END IF;

  -- 3) Resolver tipo de MP por código
  SELECT t.id_mp_tipo
    INTO v_id_mp_tipo
  FROM zap.mp_tipos t
  WHERE t.codigo = p_mp_tipo_codigo;
  IF v_id_mp_tipo IS NULL THEN
    RAISE EXCEPTION 'Tipo de MP "%" no existe en zap.mp_tipos.', p_mp_tipo_codigo;
  END IF;

  -- 4) Resolver marca (opcional) por nombre y validar activa
  IF p_marca_nombre IS NOT NULL THEN
    SELECT m.id_marca
      INTO v_id_marca
    FROM zap.marcas m
    WHERE m.nombre = p_marca_nombre AND m.activo = true;
    IF v_id_marca IS NULL THEN
      RAISE EXCEPTION 'Marca "%" no existe o está inactiva.', p_marca_nombre;
    END IF;
  END IF;

  -- 5) Insertar artículo como MP
  INSERT INTO zap.articulos (
    tipo, codigo, nombre, id_unidad, id_mp_tipo, id_marca, estado
  ) VALUES (
    'MP', p_codigo, p_nombre, v_id_unidad, v_id_mp_tipo, v_id_marca, p_estado
  )
  RETURNING id_articulo INTO v_id_articulo;

  RETURN v_id_articulo;  -- OK
END;
$$;

-- =======================================================
-- 2) CREAR PT BASE (Producto Terminado)
--    - Siempre en unidad PAR (debe existir en zap.unidades)
--    - Requiere categoría y subcategoría por NOMBRE
--    - Marca opcional por NOMBRE
-- =======================================================
CREATE OR REPLACE FUNCTION zap.fn_crear_pt_base(
  p_codigo               varchar,        -- Código único PT base, ej: 'PT-SAND-BASIC'
  p_nombre               varchar,        -- Nombre/descripcion del PT
  p_categoria_nombre     varchar,        -- Nombre categoría PT, ej: 'Sandalia'
  p_subcategoria_nombre  varchar,        -- Nombre subcategoría PT, ej: 'Plana'
  p_marca_nombre         varchar DEFAULT NULL,  -- Marca opcional
  p_estado               char(1) DEFAULT 'A'    -- 'A'|'I'
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_id_unidad_par   integer;       -- id de unidad 'PAR'
  v_id_marca        integer;       -- id de marca (opcional)
  v_id_categoria    integer;       -- id de categoría PT
  v_id_subcategoria integer;       -- id de subcategoría PT (componente de PK compuesta)
  v_id_existente    bigint;        -- para validar duplicado de código
  v_id_articulo     bigint;        -- id PT creado
BEGIN
  -- 0) Validaciones básicas
  IF p_codigo IS NULL OR btrim(p_codigo) = '' THEN
    RAISE EXCEPTION 'El código del PT es obligatorio.';
  END IF;
  IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
    RAISE EXCEPTION 'El nombre del PT es obligatorio.';
  END IF;
  IF p_estado NOT IN ('A','I') THEN
    RAISE EXCEPTION 'Estado inválido "%". Use A o I.', p_estado;
  END IF;

  -- 1) Código no duplicado
  SELECT id_articulo INTO v_id_existente
  FROM zap.articulos
  WHERE codigo = p_codigo;
  IF v_id_existente IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe un artículo con código "%".', p_codigo;
  END IF;

  -- 2) Unidad PAR debe existir y estar activa
  SELECT u.id_unidad INTO v_id_unidad_par
  FROM zap.unidades u
  WHERE u.codigo = 'PAR' AND u.activo = true;
  IF v_id_unidad_par IS NULL THEN
    RAISE EXCEPTION 'No existe unidad "PAR" activa. Insértala en zap.unidades.';
  END IF;

  -- 3) Resolver categoría y subcategoría por nombre
  SELECT c.id_categoria_pt INTO v_id_categoria
  FROM zap.categorias_pt c
  WHERE c.nombre = p_categoria_nombre AND c.activo = true;
  IF v_id_categoria IS NULL THEN
    RAISE EXCEPTION 'Categoría PT "%" no existe o está inactiva.', p_categoria_nombre;
  END IF;

  SELECT s.id_subcategoria_pt INTO v_id_subcategoria
  FROM zap.subcategorias_pt s
  WHERE s.id_categoria_pt = v_id_categoria
    AND s.nombre = p_subcategoria_nombre
    AND s.activo = true;
  IF v_id_subcategoria IS NULL THEN
    RAISE EXCEPTION 'Subcategoría "%" no existe/inactiva para la categoría "%".',
      p_subcategoria_nombre, p_categoria_nombre;
  END IF;

  -- 4) Marca (opcional)
  IF p_marca_nombre IS NOT NULL THEN
    SELECT m.id_marca INTO v_id_marca
    FROM zap.marcas m
    WHERE m.nombre = p_marca_nombre AND m.activo = true;
    IF v_id_marca IS NULL THEN
      RAISE EXCEPTION 'Marca "%" no existe o está inactiva.', p_marca_nombre;
    END IF;
  END IF;

  -- 5) Insertar PT base
  INSERT INTO zap.articulos (
    tipo, codigo, nombre, id_unidad, id_marca, id_categoria_pt, id_subcategoria_pt, estado
  ) VALUES (
    'PT', p_codigo, p_nombre, v_id_unidad_par, v_id_marca, v_id_categoria, v_id_subcategoria, p_estado
  )
  RETURNING id_articulo INTO v_id_articulo;

  RETURN v_id_articulo;  -- OK
END;
$$;

-- =======================================================
-- 3) CREAR VARIANTE DE PT (talla + tipo sandalia)
--    - Recibe códigos: PT base (codigo), tipo sandalia (codigo), y valor de talla
--    - Código de variante (SKU) debe ser único
--    - Valida que la variante no exista (por combinación y por código)
-- =======================================================
CREATE OR REPLACE FUNCTION zap.fn_crear_pt_variante(
  p_articulo_pt_codigo   varchar,  -- Código PT base, ej: 'PT-SAND-BASIC'
  p_talla_valor          integer,  -- Valor talla, ej: 36
  p_tipo_sandalia_codigo varchar,  -- Código tipo sandalia, ej: 'PLANA'/'PLATAFORMA'
  p_codigo_variante      varchar,  -- Código SKU variante, ej: 'SAND-PLANA-36'
  p_activo               boolean DEFAULT true
) RETURNS bigint
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
  v_id_articulo_pt   bigint;    -- id del PT base
  v_tipo_articulo    zap.articulo_tipo; -- para validar que es PT
  v_id_talla         integer;   -- id de talla
  v_id_tipo_sandalia integer;   -- id de tipo sandalia
  v_id_existente     bigint;    -- para validar duplicado de código variante
  v_ptvar_existente  bigint;    -- para validar combinación duplicada
  v_id_pt_var        bigint;    -- id de la variante creada
BEGIN
  -- 0) Validaciones básicas
  IF p_codigo_variante IS NULL OR btrim(p_codigo_variante) = '' THEN
    RAISE EXCEPTION 'El código de la variante (SKU) es obligatorio.';
  END IF;

  -- 1) Resolver PT base por código y validar tipo
  SELECT a.id_articulo, a.tipo
    INTO v_id_articulo_pt, v_tipo_articulo
  FROM zap.articulos a
  WHERE a.codigo = p_articulo_pt_codigo;
  IF v_id_articulo_pt IS NULL THEN
    RAISE EXCEPTION 'PT base con código "%" no existe.', p_articulo_pt_codigo;
  END IF;
  IF v_tipo_articulo <> 'PT' THEN
    RAISE EXCEPTION 'El artículo con código "%" no es PT.', p_articulo_pt_codigo;
  END IF;

  -- 2) Resolver talla por valor
  SELECT t.id_talla INTO v_id_talla
  FROM zap.tallas t
  WHERE t.valor = p_talla_valor;
  IF v_id_talla IS NULL THEN
    RAISE EXCEPTION 'La talla % no existe en zap.tallas.', p_talla_valor;
  END IF;

  -- 3) Resolver tipo sandalia por código
  SELECT ts.id_tipo_sandalia INTO v_id_tipo_sandalia
  FROM zap.tipos_sandalia ts
  WHERE ts.codigo = p_tipo_sandalia_codigo;
  IF v_id_tipo_sandalia IS NULL THEN
    RAISE EXCEPTION 'Tipo de sandalia "%" no existe.', p_tipo_sandalia_codigo;
  END IF;

  -- 4) Código de variante único
  SELECT v.id_pt_var INTO v_id_existente
  FROM zap.pt_variantes v
  WHERE v.codigo_variante = p_codigo_variante;
  IF v_id_existente IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe una variante con código "%".', p_codigo_variante;
  END IF;

  -- 5) Combinación (PT + talla + tipo) no debe existir
  SELECT v.id_pt_var INTO v_ptvar_existente
  FROM zap.pt_variantes v
  WHERE v.id_articulo_pt = v_id_articulo_pt
    AND v.id_talla = v_id_talla
    AND v.id_tipo_sandalia = v_id_tipo_sandalia;
  IF v_ptvar_existente IS NOT NULL THEN
    RAISE EXCEPTION 'Ya existe una variante para % / talla % / tipo %.',
      p_articulo_pt_codigo, p_talla_valor, p_tipo_sandalia_codigo;
  END IF;

  -- 6) Insertar variante
  INSERT INTO zap.pt_variantes (
    id_articulo_pt, id_talla, id_tipo_sandalia, codigo_variante, activo
  ) VALUES (
    v_id_articulo_pt, v_id_talla, v_id_tipo_sandalia, p_codigo_variante, p_activo
  )
  RETURNING id_pt_var INTO v_id_pt_var;

  RETURN v_id_pt_var;  -- OK
END;
$$;

COMMIT;



-- -- Crear MP nuevo (cuero en m²)
-- SELECT zap.fn_crear_mp(
--   p_codigo         := 'MP-CUERO-2MM',
--   p_nombre         := 'Cuero 2mm',
--   p_unidad_codigo  := 'M2',
--   p_mp_tipo_codigo := 'CUERO',
--   p_marca_nombre   := 'Genérica'
-- );

-- -- Crear PT base (unidad PAR) en categoría/subcategoría existentes
-- SELECT zap.fn_crear_pt_base(
--   p_codigo              := 'PT-SAND-BASIC',
--   p_nombre              := 'Sandalia básica',
--   p_categoria_nombre    := 'Sandalia',
--   p_subcategoria_nombre := 'Plana',
--   p_marca_nombre        := 'Genérica'
-- );

-- -- Crear variante de PT (talla 36, tipo PLANA)
-- SELECT zap.fn_crear_pt_variante(
--   p_articulo_pt_codigo   := 'PT-SAND-BASIC',
--   p_talla_valor          := 36,
--   p_tipo_sandalia_codigo := 'PLANA',
--   p_codigo_variante      := 'SAND-PLANA-36'
-- );