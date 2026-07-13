-- Acceso ilimitado (founder / staff): bypass trial y suscripción.
-- Solo se asigna por SQL (service role / dashboard); el cliente no puede auto-otorgárselo.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS acceso_ilimitado boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.acceso_ilimitado IS
  'Si true: organizador sin trial ni paywall. Solo editable fuera de rol authenticated.';

-- Proteger columna en self-update / update de organizador sobre jugadores.
CREATE OR REPLACE FUNCTION public.trg_profiles_protect_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS DISTINCT FROM OLD.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role
       OR NEW.saldo_acumulado IS DISTINCT FROM OLD.saldo_acumulado
       OR NEW.acceso_ilimitado IS DISTINCT FROM OLD.acceso_ilimitado THEN
      RAISE EXCEPTION
        'permission_denied: no puedes cambiar role, saldo ni acceso_ilimitado de otro perfil'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION
      'permission_denied: usa promover_a_organizador() para cambiar rol'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.saldo_acumulado IS DISTINCT FROM OLD.saldo_acumulado THEN
    RAISE EXCEPTION
      'permission_denied: no puedes modificar tu saldo acumulado'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.acceso_ilimitado IS DISTINCT FROM OLD.acceso_ilimitado THEN
    RAISE EXCEPTION
      'permission_denied: no puedes modificar acceso_ilimitado'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

-- Founder: Francisco (cuenta de desarrollo / dueño).
UPDATE public.profiles
SET acceso_ilimitado = true
WHERE lower(trim(email)) = 'fparram13@gmail.com';
