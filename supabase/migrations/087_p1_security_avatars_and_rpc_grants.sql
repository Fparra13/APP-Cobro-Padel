-- P1 hardening (pre–Google Play): avatars privados, grants mínimos, policy DELETE convocatoria.
-- No cambia contratos Flutter de tablas/RPC de negocio ni nombres legacy.

-- =============================================================================
-- 1) Bucket avatars → privado + SELECT acotado (sin listado global público)
-- =============================================================================
UPDATE storage.buckets
SET public = false
WHERE id = 'avatars';

DROP POLICY IF EXISTS "Lectura pública avatares" ON storage.objects;

DROP POLICY IF EXISTS "Leer avatar propio" ON storage.objects;
CREATE POLICY "Leer avatar propio"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Organizador lee avatares de su roster" ON storage.objects;
CREATE POLICY "Organizador lee avatares de su roster"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND public.is_organizer()
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
  );

-- Compañeros del mismo encuentro (convocatoria o detalles) + organizador vinculado.
DROP POLICY IF EXISTS "Leer avatar de compañero de encuentro" ON storage.objects;
CREATE POLICY "Leer avatar de compañero de encuentro"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND (
      EXISTS (
        SELECT 1
        FROM public.convocatoria_jugadores me
        JOIN public.convocatoria_jugadores other
          ON other.partido_id = me.partido_id
        WHERE me.jugador_id = auth.uid()
          AND other.jugador_id = ((storage.foldername(name))[1])::uuid
      )
      OR EXISTS (
        SELECT 1
        FROM public.detalles_partido me
        JOIN public.detalles_partido other
          ON other.partido_id = me.partido_id
        WHERE me.jugador_id = auth.uid()
          AND other.jugador_id = ((storage.foldername(name))[1])::uuid
      )
      OR EXISTS (
        SELECT 1
        FROM public.organizador_jugadores oj
        WHERE oj.jugador_id = auth.uid()
          AND oj.organizador_id = ((storage.foldername(name))[1])::uuid
      )
    )
  );

-- =============================================================================
-- 2) Worker / helpers internos: solo service_role (A)
-- =============================================================================
REVOKE ALL ON FUNCTION public.completar_cobro_recordatorio_envio(bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.completar_cobro_recordatorio_envio(bigint, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.completar_cobro_recordatorio_envio(bigint, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.reintentar_cobro_recordatorio_backoff(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reintentar_cobro_recordatorio_backoff(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reintentar_cobro_recordatorio_backoff(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.diferir_cobro_recordatorio_sin_token(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.diferir_cobro_recordatorio_sin_token(bigint, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.diferir_cobro_recordatorio_sin_token(bigint, boolean) TO service_role;

REVOKE ALL ON FUNCTION public.liberar_cobro_recordatorio_ineligible(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.liberar_cobro_recordatorio_ineligible(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.liberar_cobro_recordatorio_ineligible(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.detalle_monto_pendiente_recordatorio(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.detalle_monto_pendiente_recordatorio(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.detalle_monto_pendiente_recordatorio(bigint) TO service_role;

-- Helpers internos (trigger / definer): no exponer a API cliente.
REVOKE ALL ON FUNCTION public.marcar_comprobante_pago_estado(bigint, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marcar_comprobante_pago_estado(bigint, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marcar_comprobante_pago_estado(bigint, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.asegurar_fila_saldo_cuenta(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.asegurar_fila_saldo_cuenta(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.asegurar_fila_saldo_cuenta(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.reparar_saltos_cargo_cadena_saldo(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reparar_saltos_cargo_cadena_saldo(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reparar_saltos_cargo_cadena_saldo(uuid, uuid) TO service_role;

-- Deprecadas (solo raise): cerrar superficie.
REVOKE ALL ON FUNCTION public.recalcular_saldo_jugador(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalcular_saldo_jugador(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldo_jugador(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.recalcular_saldos_jugadores(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalcular_saldos_jugadores(uuid[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldos_jugadores(uuid[]) TO service_role;

-- Usadas por Flutter autenticado (B): quitar anon/PUBLIC; mantener authenticated.
REVOKE ALL ON FUNCTION public.recalcular_saldo_cuenta(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalcular_saldo_cuenta(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.recalcular_saldo_cuenta(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldo_cuenta(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.recalcular_saldos_cuentas(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalcular_saldos_cuentas(uuid, uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.recalcular_saldos_cuentas(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldos_cuentas(uuid, uuid[]) TO service_role;

-- =============================================================================
-- 3) convocatoria_jugadores DELETE: quitar is_organizer() global
--    Se mantiene "Organizador borra convocatoria de sus partidos" (owns_partido).
-- =============================================================================
DROP POLICY IF EXISTS "Organizador elimina convocatoria"
  ON public.convocatoria_jugadores;
